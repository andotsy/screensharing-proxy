import Foundation
// Observation is needed by SwiftUI only; the portable model is also tested on Linux.
#if os(macOS)
import Observation
#endif
import ProxyCore

@MainActor
#if os(macOS)
@Observable
#endif
public final class DiagnosticsModel {
    public enum Activity: Equatable { case idle, discovering, collecting, cancelling }
    public private(set) var activity = Activity.idle
    public private(set) var collection: DiagnosticCollection?
    public private(set) var message: String?
    public private(set) var reportData: Data?
    public private(set) var baselineReport: DiagnosticReport?
    public private(set) var sessionReport: DiagnosticReport?
    public var remoteAddress = ""
    public var includePrivate = false
    private let collector: any DiagnosticCollecting
    private let operation = Operation()

    // Immutable storage is excluded from Observation. Keeping the owned task
    // here also avoids observing bookkeeping changes as UI state.
    @MainActor private final class Operation {
        var task: Task<Void, Never>?
        var id: UUID?
        var pairOptions: DiagnosticOptions?
    }

    public init(collector: any DiagnosticCollecting = DiagnosticsCollector()) { self.collector = collector }

    public var isBusy: Bool { activity != .idle }
    public var remoteIsValid: Bool {
        let value = remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || IPAddress(value) != nil
    }

    public var hasBaseline: Bool { baselineReport != nil }
    public func discover() { start(mode: .discovery) }
    public func collect() { start(mode: hasBaseline ? .session : .single) }
    public func captureBaseline() { start(mode: .baseline) }
    public func captureSession() {
        guard hasBaseline else { message = "Capture a baseline before connecting first."; return }
        start(mode: .session)
    }
    public func resetPair() {
        guard !isBusy else { return }
        baselineReport = nil; sessionReport = nil; operation.pairOptions = nil
        reportData = nil; collection = nil; message = nil
    }

    public func cancel() {
        guard let task = operation.task else { return }
        activity = .cancelling
        task.cancel()
    }

    public func waitForCompletion() async { await operation.task?.value }

    public func stop() async {
        cancel()
        await operation.task?.value
    }

    public func showError(_ text: String) { message = text }
    public func dismissMessage() { message = nil }

    private enum CaptureMode { case discovery, single, baseline, session }

    private func start(mode: CaptureMode) {
        guard operation.task == nil else { return }
        let useRemote = mode != .discovery
        let text = remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if useRemote && mode != .session && !remoteIsValid { message = "Enter a numeric IPv4 or IPv6 address, or leave the field empty."; return }
        let paired = mode == .session ? operation.pairOptions : nil
        let remote = mode == .session ? paired?.remote : (useRemote && !text.isEmpty ? IPAddress(text) : nil)
        let phase = mode == .baseline ? "baseline" : (mode == .session ? "duringSession" : "snapshot")
        guard let options = try? DiagnosticOptions(remote: remote, samples: mode == .discovery ? 1 : (mode == .session ? 10 : 3),
            includePrivate: paired?.includePrivate ?? includePrivate, capturePhase: phase, redactionScope: paired?.redactionScope) else {
            message = "The collection options could not be prepared."; return
        }
        message = nil
        activity = useRemote ? .collecting : .discovering
        let id = UUID()
        operation.id = id
        operation.task = Task { [weak self, collector] in
            let result = await collector.inspect(options)
            guard let self, operation.id == id else { return }
            if Task.isCancelled {
                message = "Collection cancelled. Your previous report is unchanged."
            } else {
                do {
                    let encoded: Data
                    switch mode {
                    case .baseline:
                        encoded = try CapturePair(baseline: result.report, duringSession: nil).json()
                    case .session:
                        guard let baselineReport else { throw CocoaError(.coderInvalidValue) }
                        encoded = try CapturePair(baseline: baselineReport, duringSession: result.report).json()
                    case .discovery, .single:
                        encoded = try result.report.json()
                    }
                    collection = result
                    if mode != .discovery || !hasBaseline { reportData = encoded }
                    if mode == .baseline {
                        baselineReport = result.report; sessionReport = nil; operation.pairOptions = options
                        message = "Baseline saved. Start High Performance Screen Sharing, then capture during the connection attempt."
                    } else if mode == .session {
                        sessionReport = result.report
                        message = "Both captures are ready. Save or copy the report to share them together."
                    }
                } catch { message = "The report could not be prepared for export." }
            }
            operation.id = nil
            operation.task = nil
            activity = .idle
        }
    }
}

private struct CapturePair: Encodable {
    let kind = "screenSharingCapturePair"
    let schemaVersion = 1
    let toolVersion = ProxyBuild.version
    let baseline: DiagnosticReport
    let duringSession: DiagnosticReport?
    let comparisonScope = "Address and path tokens are comparable only when redactionScopeID matches. Snapshots do not measure packet delivery."
    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
