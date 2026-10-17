import Foundation

/// Control-plane messages for an app-owned backend adapter. This is not an
/// invented proxyd protocol and carries no Screen Sharing payloads.
public struct BackendEnvelope: Codable, Sendable, Equatable {
    public let version: Int
    public let sessionID: UUID
    public let event: BackendEvent

    public init(sessionID: UUID, event: BackendEvent, version: Int = 1) {
        self.version = version; self.sessionID = sessionID; self.event = event
    }

    public func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        guard data.count <= BackendLineDecoder.maximumFrameBytes else { throw BackendProtocolError.frameTooLarge }
        data.append(10)
        return data
    }
}

public enum BackendEvent: Codable, Sendable, Equatable {
    case ready
    case traffic(receivedBytes: UInt64, sentBytes: UInt64)
    case media(receivedDatagrams: UInt64, sentDatagrams: UInt64, droppedDatagrams: UInt64)
    case control(nativeAccepted: Bool, remoteConnected: Bool, nativeReadClosed: Bool, remoteReadClosed: Bool)
    case failureContext(operation: BackendOperation, systemError: BackendSystemError?)
    case stopped
    case failed(code: BackendFailureCode)
}

/// Fixed labels only; no socket addresses, exception strings or payloads.
public enum BackendOperation: String, Codable, Sendable {
    case configuration, socketReservation, routeCheck, viewerAccept, hostBind, hostConnect
    case tcpRead, tcpWrite, udpReceive, udpSend, tcpShutdown, parentInput, eventOutput, waiting
}

public enum BackendSystemError: String, Codable, Sendable {
    case addressUnavailable, addressInUse, connectionRefused, connectionReset
    case networkUnreachable, hostUnreachable, permissionDenied, other
}

public enum BackendFailureCode: String, Codable, Sendable {
    case unavailable, permissionUnknown, addressInUse, connectFailed, incompatibleProtocol, internalFailure
    case invalidConfiguration, localAddressUnavailable, nativeSourceMismatch, connectionTimedOut, routeChanged
}

public enum BackendProtocolError: Error, Equatable {
    case frameTooLarge, chunkTooLarge, invalidEncoding, invalidMessage, unsupportedVersion, truncatedFrame, decoderFailed, streamClosed
}

/// Incremental bounded framing for arbitrarily split/coalesced pipe reads.
/// An invalid stream stays failed; never resynchronize past a protocol error.
public struct BackendLineDecoder: Sendable {
    public static let maximumFrameBytes = 16_384
    public static let maximumReadBytes = 65_536
    private var buffer = Data()
    private var failed = false
    private var finished = false
    public init() {}

    public mutating func feed(_ bytes: Data) throws -> [BackendEnvelope] {
        guard !failed else { throw BackendProtocolError.decoderFailed }
        guard !finished else { throw BackendProtocolError.streamClosed }
        do {
            guard bytes.count <= Self.maximumReadBytes else { throw BackendProtocolError.chunkTooLarge }
            var messages: [BackendEnvelope] = []
            for byte in bytes {
                if byte == 10 {
                    guard !buffer.isEmpty else { throw BackendProtocolError.invalidMessage }
                    guard String(data: buffer, encoding: .utf8) != nil else { throw BackendProtocolError.invalidEncoding }
                    let message: BackendEnvelope
                    do { message = try JSONDecoder().decode(BackendEnvelope.self, from: buffer) }
                    catch { throw BackendProtocolError.invalidMessage }
                    guard message.version == 1 else { throw BackendProtocolError.unsupportedVersion }
                    messages.append(message)
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    guard buffer.count < Self.maximumFrameBytes else { throw BackendProtocolError.frameTooLarge }
                    buffer.append(byte)
                }
            }
            return messages
        } catch {
            failed = true
            buffer.removeAll(keepingCapacity: false)
            throw error
        }
    }

    public mutating func finish() throws {
        guard !failed else { throw BackendProtocolError.decoderFailed }
        guard buffer.isEmpty else {
            failed = true; buffer.removeAll()
            throw BackendProtocolError.truncatedFrame
        }
        finished = true
    }
}

public struct SessionLifecycle: Sendable {
    public enum Phase: String, Codable, Sendable { case off, checking, starting, listening, relaying, stopping, interrupted, blocked }
    public enum TransitionError: Error, Equatable { case alreadyActive, invalidTransition, handshakeRequired, countersRegressed }
    public private(set) var sessionID: UUID?
    public private(set) var phase = Phase.off
    public private(set) var failure: BackendFailureCode?
    public private(set) var receivedBytes: UInt64 = 0
    public private(set) var sentBytes: UInt64 = 0
    public private(set) var receivedDatagrams: UInt64 = 0
    public private(set) var sentDatagrams: UInt64 = 0
    public private(set) var droppedDatagrams: UInt64 = 0
    private var receivedStopAcknowledgement = false
    public init() {}

    /// A new identifier is required even when retrying the same destination.
    @discardableResult public mutating func begin() throws -> UUID {
        guard [.off, .blocked, .interrupted].contains(phase) else { throw TransitionError.alreadyActive }
        let id = UUID()
        sessionID = id; phase = .checking; failure = nil
        receivedBytes = 0; sentBytes = 0; receivedStopAcknowledgement = false
        receivedDatagrams = 0; sentDatagrams = 0; droppedDatagrams = 0
        explicitStop = false
        return id
    }

    /// The caller must establish a supported backend before spawning it.
    /// This lifecycle never promotes transport feasibility or decoded video.
    public mutating func preflightCompleted(session: UUID, available: Bool) throws {
        guard session == sessionID else { return }
        guard phase == .checking else { throw TransitionError.invalidTransition }
        phase = available ? .starting : .blocked
        failure = available ? nil : .unavailable
    }

    public mutating func accept(_ envelope: BackendEnvelope) throws {
        // Stale traffic/failure/ready events have no effect on a newer generation.
        guard envelope.sessionID == sessionID else { return }
        guard envelope.version == 1 else { throw BackendProtocolError.unsupportedVersion }
        if phase == .stopping {
            if envelope.event == .stopped { receivedStopAcknowledgement = true }
            return // Including a late ready or failure racing with explicit stop.
        }
        switch envelope.event {
        case .ready:
            guard phase == .starting else { throw TransitionError.invalidTransition }
            phase = .listening
        case let .traffic(received, sent):
            guard [.listening, .relaying].contains(phase) else { throw TransitionError.handshakeRequired }
            guard received >= receivedBytes, sent >= sentBytes else { throw TransitionError.countersRegressed }
            receivedBytes = received; sentBytes = sent
            if received > 0 || sent > 0 { phase = .relaying }
        case .stopped:
            // Unexpected stop is still an interruption; the process must be reaped.
            guard [.starting, .listening, .relaying].contains(phase) else { throw TransitionError.invalidTransition }
            phase = .stopping; receivedStopAcknowledgement = false
        case let .media(received, sent, dropped):
            guard [.listening, .relaying].contains(phase) else { throw TransitionError.handshakeRequired }
            guard received >= receivedDatagrams, sent >= sentDatagrams, dropped >= droppedDatagrams else {
                throw TransitionError.countersRegressed
            }
            receivedDatagrams = received; sentDatagrams = sent; droppedDatagrams = dropped
        case let .failed(code):
            guard [.starting, .listening, .relaying].contains(phase) else { throw TransitionError.invalidTransition }
            failure = code
            phase = .stopping // Keep the slot occupied until actual process exit.
        case .control, .failureContext:
            break // Experiment evidence does not promote native-session validity.
        }
    }

    private var explicitStop = false
    public mutating func requestStop() {
        guard ![.off, .blocked, .interrupted].contains(phase) else { return }
        if phase == .checking {
            phase = .off; sessionID = nil
            return // No process has been requested; invalidate the pending probe.
        }
        explicitStop = true
        phase = .stopping
    }

    /// A failed spawn produces no exit callback. This closes that lifecycle gap.
    public mutating func launchFailed(session: UUID, code: BackendFailureCode) throws {
        guard session == sessionID else { return }
        guard phase == .starting || phase == .stopping else { throw TransitionError.invalidTransition }
        phase = explicitStop ? .off : .blocked
        failure = explicitStop ? nil : code
        sessionID = nil; explicitStop = false
    }

    /// Called after the process exit observer, not just a JSON "stopped" event.
    public mutating func processExited(session: UUID) {
        guard session == sessionID else { return }
        if explicitStop { phase = .off }
        else if failure != nil { phase = .blocked }
        else { phase = .interrupted }
        sessionID = nil
        explicitStop = false
        receivedStopAcknowledgement = false
    }

    public var stopAcknowledged: Bool { receivedStopAcknowledgement }
}
