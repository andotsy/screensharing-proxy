import Foundation
import Testing
@testable import ProxyCore
@testable import ProxyAppSupport

private actor CollectorFixture: DiagnosticCollecting {
    var delay = Duration.zero
    var calls: [DiagnosticOptions] = []
    func setDelay(_ delay: Duration) { self.delay = delay }
    func inspect(_ options: DiagnosticOptions) async -> DiagnosticCollection {
        calls.append(options)
        if delay != .zero { try? await Task.sleep(for: delay) }
        let report = DiagnosticReport(schemaVersion: 2, collectedAt: "fixture", platform: "macOS",
            privateDetailsIncluded: options.includePrivate, remoteFilter: nil)
        return .init(report: report, discovery: .init(status: .notFound, candidates: [], selected: nil, reason: "fixture"))
    }
}

@MainActor private final class SaverFixture: DiagnosticArchiveSaving {
    var calls: [Data] = []
    var result = DiagnosticSaveResult.saved
    var cancelled = false
    func save(_ data: Data) async -> DiagnosticSaveResult { calls.append(data); return result }
    func cancel() { cancelled = true }
}

@MainActor @Suite("One-click diagnostics")
struct DiagnosticsModelTests {
    @Test func opensSaveAutomaticallyAfterOneCollection() async {
        let collector = CollectorFixture(), saver = SaverFixture()
        let model = DiagnosticsModel(saver: saver, collector: collector)
        #expect(await collector.calls.isEmpty)
        #expect(saver.calls.isEmpty)
        model.collect()
        await model.waitForCompletion()
        #expect(await collector.calls.count == 1)
        #expect(await collector.calls[0].samples == 10)
        #expect(await collector.calls[0].includePrivate == false)
        #expect(await collector.calls[0].remote == nil)
        #expect(saver.calls.count == 1)
        #expect(saver.calls[0].prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        #expect(model.activity == .idle)
        #expect(model.message?.hasPrefix("Saved.") == true)
    }

    @Test func cancelledSaveCanBeRetriedWithoutCollectingAgain() async {
        let collector = CollectorFixture(), saver = SaverFixture()
        saver.result = .cancelled
        let model = DiagnosticsModel(saver: saver, collector: collector)
        model.collect(); await model.waitForCompletion()
        #expect(model.archiveData != nil)
        #expect(model.message?.hasPrefix("Not saved.") == true)
        saver.result = .saved
        model.saveAgain(); await model.waitForCompletion()
        #expect(await collector.calls.count == 1)
        #expect(saver.calls.count == 2 && saver.calls[0] == saver.calls[1])
    }

    @Test func failedSaveKeepsArchiveForRetry() async {
        let saver = SaverFixture(); saver.result = .failed
        let model = DiagnosticsModel(saver: saver, collector: CollectorFixture())
        model.collect(); await model.waitForCompletion()
        #expect(model.archiveData != nil)
        #expect(model.message?.contains("another location") == true)
    }

    @Test func cancellationAndDuplicateClicksDoNotOpenSaveOrReplacePreviousArchive() async throws {
        let collector = CollectorFixture(), saver = SaverFixture()
        let model = DiagnosticsModel(saver: saver, collector: collector)
        model.collect(); await model.waitForCompletion()
        let previous = try #require(model.archiveData)
        await collector.setDelay(.seconds(30))
        model.collect()
        while await collector.calls.count < 2 { await Task.yield() }
        model.collect(); model.saveAgain()
        model.cancel(); await model.waitForCompletion()
        #expect(await collector.calls.count == 2)
        #expect(saver.calls.count == 1)
        #expect(model.archiveData == previous)
        #expect(saver.cancelled && !model.isBusy)
        #expect(model.message == "Collection cancelled.")
    }
}
