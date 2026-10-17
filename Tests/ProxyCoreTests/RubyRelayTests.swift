import Foundation
import Testing
@testable import ProxyCore

private final class RelayEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BackendEnvelope] = []
    func append(_ event: BackendEnvelope) { lock.withLock { values.append(event) } }
    var events: [BackendEnvelope] { lock.withLock { values } }
}

@Suite struct RubyRelayTests {
    private var ruby: String? {
        let path = ProcessInfo.processInfo.environment["SSP_TEST_RUBY"] ?? "/usr/bin/ruby"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    @Test func remoteAddressValidationAndPackagedResource() throws {
        for value in ["192.168.1.20", "10.0.0.2", "172.16.4.5"] {
            #expect(RubyRelayConfiguration.validRemoteAddress(value))
        }
        for value in ["", "localhost", "127.0.0.1", "224.0.0.1", "0.0.0.0", "1.2.3.256", "01.2.3.4", "1.2.3.4\n", "1.2.3.4;id"] {
            #expect(!RubyRelayConfiguration.validRemoteAddress(value))
        }
        #expect(FileManager.default.fileExists(atPath: RubyRelayResources.script.path))
        #expect(FileManager.default.fileExists(atPath: RubyRelayResources.incomingScript.path))
        let config = RubyRelayConfiguration(sessionID: UUID(), remoteAddress: "192.0.2.1")
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(json["externalAddress"] == nil)
    }

    @Test func mediaCountersRequireReadyAndNeverRegress() throws {
        var state = SessionLifecycle()
        let id = try state.begin()
        try state.preflightCompleted(session: id, available: true)
        let media = BackendEnvelope(sessionID: id, event: .media(receivedDatagrams: 4, sentDatagrams: 2, droppedDatagrams: 1))
        #expect(throws: SessionLifecycle.TransitionError.handshakeRequired) { try state.accept(media) }
        try state.accept(.init(sessionID: id, event: .ready))
        try state.accept(media)
        #expect(state.receivedDatagrams == 4)
        #expect(state.sentDatagrams == 2)
        #expect(state.droppedDatagrams == 1)
        #expect(throws: SessionLifecycle.TransitionError.countersRegressed) {
            try state.accept(.init(sessionID: id, event: .media(receivedDatagrams: 3, sentDatagrams: 2, droppedDatagrams: 1)))
        }
    }

    private func fixture(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssp-relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let path = directory.appendingPathComponent("fixture.rb")
        let script = """
        require 'json'
        STDOUT.sync = true
        config = JSON.parse(STDIN.gets)
        def emit(config, name, values = {})
          puts JSON.generate('version' => 1, 'sessionID' => config['sessionID'], 'event' => {name => values})
        end
        \(body)
        """
        try script.write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func runnerStreamsEventsAndClosesStdinOnCancellation() async throws {
        guard let ruby else { return }
        let script = try fixture("""
        abort if ENV.key?('RUBYOPT') || ENV.key?('RUBYLIB')
        abort unless config['remoteAddress'] == '192.0.2.1'
        emit(config, 'ready')
        STDIN.read
        emit(config, 'stopped')
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let events = RelayEvents()
        let task = Task {
            await RubyRelayRunner(executable: ruby, script: script.path).run(
                configuration: .init(sessionID: UUID(), remoteAddress: "192.0.2.1"),
                onEvent: { events.append($0) })
        }
        for _ in 0..<100 {
            if !events.events.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(events.events.first?.event == .ready)
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(events.events.last?.event == .stopped)
    }

    @Test func runnerKillsUnresponsiveChildAfterStopDeadline() async throws {
        guard let ruby else { return }
        let script = try fixture("""
        Signal.trap('TERM', 'IGNORE')
        emit(config, 'ready')
        loop { sleep 1 }
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let events = RelayEvents()
        let task = Task {
            await RubyRelayRunner(executable: ruby, script: script.path).run(
                configuration: .init(sessionID: UUID(), remoteAddress: "192.0.2.1"),
                onEvent: { events.append($0) })
        }
        for _ in 0..<100 {
            if !events.events.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(events.events.first?.event == .ready)
        let started = ContinuousClock.now
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(started.duration(to: .now) < .seconds(4))
    }

    @Test func runnerPreservesStartupFailure() async throws {
        guard let ruby else { return }
        let script = try fixture("emit(config, 'failed', 'code' => 'addressInUse'); exit 1")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let result = await RubyRelayRunner(executable: ruby, script: script.path).run(
            configuration: .init(sessionID: UUID(), remoteAddress: "192.0.2.1"), onEvent: { _ in })
        #expect(result == .failed(.addressInUse))
    }

    @Test func runnerRejectsInvalidFramesAndStopsTheChild() async throws {
        guard let ruby else { return }
        let script = try fixture("puts 'not-json'; loop { sleep 1 }")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let result = await RubyRelayRunner(executable: ruby, script: script.path).run(
            configuration: .init(sessionID: UUID(), remoteAddress: "192.0.2.1"), onEvent: { _ in })
        #expect(result == .failed(.incompatibleProtocol))
    }
}
