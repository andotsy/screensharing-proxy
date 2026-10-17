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
        let report = DiagnosticReport(schemaVersion: 1, collectedAt: "fixture", platform: "macOS",
            privateDetailsIncluded: options.includePrivate, remoteFilter: options.remote?.value)
        return .init(report: report, discovery: .init(status: .notFound, candidates: [], selected: nil, reason: "fixture"))
    }
    func hasStarted() -> Bool { started }
}

@MainActor @Suite("Native app collection state")
struct DiagnosticsModelTests {
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
