import Foundation
import Testing
@testable import ProxyCore
@testable import ProxyAppSupport

private actor CollectorFixture: DiagnosticCollecting {
    let delay: Duration
    var calls: [DiagnosticOptions] = []
    var started = false
    init(delay: Duration = .zero) { self.delay = delay }
    func inspect(_ options: DiagnosticOptions) async -> DiagnosticCollection {
        calls.append(options); started = true
        if delay != .zero { try? await Task.sleep(for: delay) }
        var report = DiagnosticReport(schemaVersion: 2, collectedAt: "fixture", platform: "macOS",
            privateDetailsIncluded: options.includePrivate, remoteFilter: options.remote?.value)
        report.capturePhase = options.capturePhase
        report.redactionScopeID = options.redactionScope.id
        return .init(report: report, discovery: .init(status: .notFound, candidates: [], selected: nil, reason: "fixture"))
    }
    func hasStarted() -> Bool { started }
}

@MainActor @Suite("Native app collection state")
struct DiagnosticsModelTests {
    @Test func pairedCaptureLocksOptionsAndExportsBothWithOneRedactionScope() async throws {
        let fixture = CollectorFixture()
        let model = DiagnosticsModel(collector: fixture)
        model.remoteAddress = "192.0.2.5"
        model.captureSession()
        #expect(await fixture.calls.isEmpty)
        model.captureBaseline()
        await model.waitForCompletion()
        #expect(model.hasBaseline)
        model.remoteAddress = "invalid.example"
        model.includePrivate = true
        model.captureSession()
        await model.waitForCompletion()
        let calls = await fixture.calls
        #expect(calls.count == 2)
        #expect(calls[1].samples == 10)
        #expect(calls[1].remote == calls[0].remote)
        #expect(!calls[1].includePrivate)
        #expect(calls[0].redactionScope.id == calls[1].redactionScope.id)
        let data = try #require(model.reportData)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["kind"] as? String == "screenSharingCapturePair")
        #expect((json["baseline"] as? [String: Any])?["capturePhase"] as? String == "baseline")
        #expect((json["duringSession"] as? [String: Any])?["capturePhase"] as? String == "duringSession")
        model.discover()
        await model.waitForCompletion()
        #expect(model.reportData == data)
        model.resetPair()
        #expect(!model.hasBaseline && model.reportData == nil)
    }

    @Test func cancellingSecondCapturePreservesBaselineExport() async throws {
        let fixture = CollectorFixture()
        let model = DiagnosticsModel(collector: fixture)
        model.captureBaseline()
        await model.waitForCompletion()
        let data = try #require(model.reportData)
        model.captureSession()
        model.cancel()
        await model.waitForCompletion()
        #expect(model.reportData == data)
        #expect(model.hasBaseline && model.sessionReport == nil)
    }

    @Test func discoveryNeedsNoManualPathOrRemoteAddress() async {
        let fixture = CollectorFixture()
        let model = DiagnosticsModel(collector: fixture)
        model.remoteAddress = "invalid.example"
        model.discover()
        await model.waitForCompletion()
        #expect(model.activity == .idle)
        #expect(model.reportData != nil)
        #expect(await fixture.calls.first?.remote == nil)
        #expect(await fixture.calls.first?.samples == 1)
    }

    @Test func invalidRemoteDoesNotStartCollection() async {
        let fixture = CollectorFixture()
        let model = DiagnosticsModel(collector: fixture)
        model.remoteAddress = "invalid.example"
        model.collect()
        #expect(model.message != nil)
        #expect(!model.isBusy)
        #expect(await fixture.calls.isEmpty)
    }

    @Test func serializesCollectionAndWaitsForCancellation() async {
        let fixture = CollectorFixture(delay: .seconds(30))
        let model = DiagnosticsModel(collector: fixture)
        model.discover()
        while !(await fixture.hasStarted()) { await Task.yield() }
        model.collect()
        #expect(await fixture.calls.count == 1)
        model.cancel()
        #expect(model.activity == .cancelling)
        await model.waitForCompletion()
        #expect(model.activity == .idle)
        #expect(model.collection == nil)
        #expect(model.message?.contains("cancelled") == true)
    }

    @Test func reportsAreRedactedUnlessExplicitlyRequested() async {
        let fixture = CollectorFixture()
        let model = DiagnosticsModel(collector: fixture)
        model.collect()
        await model.waitForCompletion()
        #expect(model.collection?.report.privateDetailsIncluded == false)
        model.includePrivate = true
        model.remoteAddress = "192.0.2.5"
        model.collect()
        await model.waitForCompletion()
        #expect(model.collection?.report.privateDetailsIncluded == true)
        #expect(await fixture.calls.last?.remote?.value == "192.0.2.5")
    }
}
