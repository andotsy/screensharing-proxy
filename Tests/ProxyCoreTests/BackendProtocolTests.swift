import Foundation
import Testing
@testable import ProxyCore

@Suite("Bounded backend protocol and session generations")
struct BackendProtocolTests {
    @Test func socketFailurePortIsBoundedAndOlderContextStillDecodes() throws {
        let id = UUID()
        let prefix = "{\"version\":1,\"sessionID\":\"\(id)\",\"event\":{\"failureContext\":{\"operation\":\"tcpListenerBind\",\"systemError\":\"addressInUse\""
        var decoder = BackendLineDecoder()
        let withPort = try decoder.feed(Data((prefix + ",\"port\":5900}}}\n").utf8))
        #expect(withPort.first?.event == .failureContext(operation: .tcpListenerBind, systemError: .addressInUse, port: 5900))
        let older = try decoder.feed(Data((prefix + "}}}\n").utf8))
        #expect(older.first?.event == .failureContext(operation: .tcpListenerBind, systemError: .addressInUse))
        #expect(throws: BackendProtocolError.invalidMessage) {
            try decoder.feed(Data((prefix + ",\"port\":65536}}}\n").utf8))
        }
    }

    @Test func splitAndCoalescedFramesDecodeInOrder() throws {
        let id = UUID()
        let messages = [BackendEnvelope(sessionID: id, event: .ready),
                        BackendEnvelope(sessionID: id, event: .traffic(receivedBytes: 80, sentBytes: 90)),
                        BackendEnvelope(sessionID: id, event: .controlConnections(accepted: 2, connected: 2, completed: 1))]
        var data = Data()
        for message in messages { data.append(try message.encodedLine()) }
        var decoder = BackendLineDecoder()
        var decoded: [BackendEnvelope] = []
        for byte in data.prefix(17) { decoded += try decoder.feed(Data([byte])) }
        decoded += try decoder.feed(data.dropFirst(17))
        try decoder.finish()
        #expect(decoded == messages)
        #expect(throws: BackendProtocolError.streamClosed) { try decoder.feed(Data()) }
    }

    @Test func oversizedFramesPoisonDecoderWithoutRetainingStream() throws {
        var decoder = BackendLineDecoder()
        #expect(throws: BackendProtocolError.frameTooLarge) {
            try decoder.feed(Data(repeating: 65, count: BackendLineDecoder.maximumFrameBytes + 1))
        }
        #expect(throws: BackendProtocolError.decoderFailed) {
            try decoder.feed(BackendEnvelope(sessionID: UUID(), event: .ready).encodedLine())
        }
    }

    @Test func rejectsInvalidUTF8VersionAndPartialEOF() throws {
        var invalid = BackendLineDecoder()
        #expect(throws: BackendProtocolError.invalidEncoding) { try invalid.feed(Data([0xff, 10])) }
        var version = BackendLineDecoder()
        #expect(throws: BackendProtocolError.unsupportedVersion) {
            try version.feed(BackendEnvelope(sessionID: UUID(), event: .ready, version: 2).encodedLine())
        }
        var partial = BackendLineDecoder()
        _ = try partial.feed(Data("{\"version\":".utf8))
        #expect(throws: BackendProtocolError.truncatedFrame) { try partial.finish() }
    }

    @Test func staleMessagesCannotChangeNewSession() throws {
        var lifecycle = SessionLifecycle()
        let old = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: old, available: true)
        lifecycle.requestStop()
        lifecycle.processExited(session: old)
        let current = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: current, available: true)
        try lifecycle.accept(.init(sessionID: old, event: .failed(code: .connectFailed)))
        try lifecycle.accept(.init(sessionID: old, event: .ready))
        lifecycle.processExited(session: old)
        #expect(lifecycle.phase == .starting)
        #expect(lifecycle.sessionID == current)
        #expect(lifecycle.failure == nil)
    }

    @Test func stopWinsOverReadyAndWaitsForProcessExit() throws {
        var lifecycle = SessionLifecycle()
        let id = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: id, available: true)
        lifecycle.requestStop()
        try lifecycle.accept(.init(sessionID: id, event: .ready))
        #expect(lifecycle.phase == .stopping)
        try lifecycle.accept(.init(sessionID: id, event: .stopped))
        #expect(lifecycle.stopAcknowledged)
        #expect(lifecycle.phase == .stopping)
        #expect(throws: SessionLifecycle.TransitionError.alreadyActive) { try lifecycle.begin() }
        lifecycle.processExited(session: id)
        #expect(lifecycle.phase == .off)
    }

    @Test func requiresHandshakeAndMonotonicCounters() throws {
        var lifecycle = SessionLifecycle()
        let id = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: id, available: true)
        #expect(throws: SessionLifecycle.TransitionError.handshakeRequired) {
            try lifecycle.accept(.init(sessionID: id, event: .traffic(receivedBytes: 5, sentBytes: 5)))
        }
        try lifecycle.accept(.init(sessionID: id, event: .ready))
        try lifecycle.accept(.init(sessionID: id, event: .traffic(receivedBytes: 5, sentBytes: 5)))
        #expect(lifecycle.phase == .relaying)
        #expect(throws: SessionLifecycle.TransitionError.countersRegressed) {
            try lifecycle.accept(.init(sessionID: id, event: .traffic(receivedBytes: 4, sentBytes: 6)))
        }
        lifecycle.processExited(session: id)
        #expect(lifecycle.phase == .interrupted)
    }

    @Test func failedBackendKeepsSlotUntilReaped() throws {
        var lifecycle = SessionLifecycle()
        let id = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: id, available: true)
        try lifecycle.accept(.init(sessionID: id, event: .failed(code: .addressInUse)))
        #expect(throws: SessionLifecycle.TransitionError.alreadyActive) { try lifecycle.begin() }
        lifecycle.processExited(session: id)
        #expect(lifecycle.phase == .blocked)
        #expect(lifecycle.failure == .addressInUse)
    }

    @Test func cancelledPreflightCannotStartLater() throws {
        var lifecycle = SessionLifecycle()
        let id = try lifecycle.begin()
        lifecycle.requestStop()
        try lifecycle.preflightCompleted(session: id, available: true)
        #expect(lifecycle.phase == .off)
        #expect(lifecycle.sessionID == nil)
    }

    @Test func failedSpawnDoesNotWaitForNonexistentProcess() throws {
        var lifecycle = SessionLifecycle()
        let id = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: id, available: true)
        try lifecycle.launchFailed(session: id, code: .unavailable)
        #expect(lifecycle.phase == .blocked)
        #expect(lifecycle.sessionID == nil)
        let next = try lifecycle.begin()
        try lifecycle.preflightCompleted(session: next, available: true)
        lifecycle.requestStop()
        try lifecycle.launchFailed(session: next, code: .unavailable)
        #expect(lifecycle.phase == .off)
    }

    @Test func rejectsUnboundedReadChunksAndBlankFrames() {
        var large = BackendLineDecoder()
        #expect(throws: BackendProtocolError.chunkTooLarge) {
            try large.feed(Data(repeating: 10, count: BackendLineDecoder.maximumReadBytes + 1))
        }
        var blank = BackendLineDecoder()
        #expect(throws: BackendProtocolError.invalidMessage) { try blank.feed(Data([10])) }
    }
}
