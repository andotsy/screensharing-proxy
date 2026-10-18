import Foundation
import Testing
@testable import ProxyAppSupport
import ProxyCore

private actor TestRelay: RelayRunning {
    var configuration: RubyRelayConfiguration?
    var callback: (@Sendable (BackendEnvelope) -> Void)?
    var stopped = false
    func run(configuration: RubyRelayConfiguration, onEvent: @escaping @Sendable (BackendEnvelope) -> Void) async -> RubyRelayRunResult {
        self.configuration = configuration; callback = onEvent
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        onEvent(.init(sessionID: configuration.sessionID, event: .traffic(receivedBytes: 900, sentBytes: 100)))
        onEvent(.init(sessionID: configuration.sessionID, event: .stopped)); stopped = true
        return .cancelled
    }
    func emit(_ event: BackendEvent, stale: Bool = false) {
        if let configuration { callback?(.init(sessionID: stale ? UUID() : configuration.sessionID, event: event)) }
    }
}
private actor TestViewer: ViewerLaunching {
    var ports: [UInt16] = []
    func open(port: UInt16) async -> Bool { ports.append(port); return true }
}
@MainActor private final class ReportSaver: DiagnosticArchiveSaving {
    var data: Data?
    func save(_ data: Data) async -> DiagnosticSaveResult { self.data = data; return .saved }
    func cancel() {}
}
@Suite @MainActor struct RelayModelTests {
    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for model event")
    }
    @Test func readyLaunchesOnceAndStopDrainsFinalEvents() async throws {
        let runner = TestRelay(), viewer = TestViewer(), saver = ReportSaver()
        let model = RelayModel(saver: saver, runner: runner, launcher: viewer)
        model.remoteAddress = "192.0.2.10"
        #expect(model.canConnect)
        model.connect(); model.connect()
        try await wait { await runner.configuration != nil }
        #expect(await runner.configuration?.maximumDurationSeconds == 0)
        #expect(await runner.configuration?.mode == .loopback)
        #expect(await viewer.ports.isEmpty)
        await runner.emit(.ready, stale: true)
        await runner.emit(.ready)
        try await wait { await viewer.ports == [15900] }
        await runner.emit(.controlConnections(accepted: 2, connected: 2, completed: 1))
        try await wait { model.activity == .forwarding }
        #expect(!model.canConnect)
        model.disconnect()
        #expect(model.activity == .stopping)
        await model.stop()
        #expect(await runner.stopped)
        #expect(!model.isRunning)
        #expect(model.report?.relayStopAcknowledged == true)
        #expect(model.report?.forwardedToNativeBytes == 900)
        #expect(model.report?.termination == "stopped")
        #expect(model.report?.transport == "TCP only")
        model.saveReport()
        try await wait { !model.saving }
        let json = String(decoding: try #require(saver.data), as: UTF8.self)
        #expect(!json.contains("192.0.2.10"))
        #expect(json.contains("unverified"))
    }
    @Test func rejectsInvalidPortsAndAddressesBeforeStarting() {
        let model = RelayModel(saver: ReportSaver(), runner: TestRelay(), launcher: TestViewer())
        for address in ["", "127.0.0.1", "hostname.local", "192.0.2.10;id"] {
            model.remoteAddress = address; #expect(!model.canConnect)
            model.connect(); #expect(!model.isRunning)
        }
        model.remoteAddress = "192.0.2.10"; model.mediaBase = 65534
        #expect(!model.canConnect)
        model.mediaBase = 5900; model.remotePort = -1; #expect(!model.canConnect)
        model.remotePort = 5900; model.listenerPort = 65536; #expect(!model.canConnect)
    }
    @Test func mediaCountersDoNotClaimDecodedHighPerformance() async throws {
        let runner = TestRelay(), model = RelayModel(saver: ReportSaver(), runner: TestRelay(), launcher: TestViewer())
        #expect(model.report == nil)
        let active = RelayModel(saver: ReportSaver(), runner: runner, launcher: TestViewer())
        active.remoteAddress = "192.0.2.10"; active.connect()
        try await wait { await runner.configuration != nil }
        await runner.emit(.ready)
        await runner.emit(.media(receivedDatagrams: 10, sentDatagrams: 2, droppedDatagrams: 1))
        try await wait { active.report?.forwardedToNativeDatagrams == 10 }
        #expect(active.report?.transport == "TCP + UDP")
        #expect(active.report?.highPerformanceSession == "unverified")
        await active.stop()
    }
    @Test func stopBeforeReadinessNeverLaunchesViewer() async throws {
        let runner = TestRelay(), viewer = TestViewer()
        let model = RelayModel(saver: ReportSaver(), runner: runner, launcher: viewer)
        model.remoteAddress = "192.0.2.10"; model.connect()
        try await wait { await runner.configuration != nil }
        model.disconnect(); await runner.emit(.ready)
        await model.stop()
        #expect(await viewer.ports.isEmpty)
    }
}
