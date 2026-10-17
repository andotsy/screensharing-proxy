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
    public var remoteAddress = ""
    public var includePrivate = false
    #if os(macOS)
    @ObservationIgnored
    #endif
    private let collector: any DiagnosticCollecting
    #if os(macOS)
    @ObservationIgnored
    #endif
    private var task: Task<Void, Never>?
    #if os(macOS)
    @ObservationIgnored
    #endif
    private var operationID: UUID?

    public init(collector: any DiagnosticCollecting = DiagnosticsCollector()) { self.collector = collector }

    public var isBusy: Bool { activity != .idle }
    public var remoteIsValid: Bool {
        let value = remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || IPAddress(value) != nil
    }

    public func discover() { start(samples: 1, useRemote: false) }
    public func collect() { start(samples: 3, useRemote: true) }

    public func cancel() {
        guard let task else { return }
        activity = .cancelling
        task.cancel()
    }

    public func waitForCompletion() async { await task?.value }

    public func stop() async {
        cancel()
        await task?.value
    }

    public func showError(_ text: String) { message = text }
    public func dismissMessage() { message = nil }

    private func start(samples: Int, useRemote: Bool) {
        guard task == nil else { return }
        let text = remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if useRemote && !remoteIsValid { message = "Enter a numeric IPv4 or IPv6 address, or leave the field empty."; return }
        let remote = useRemote && !text.isEmpty ? IPAddress(text) : nil
        guard let options = try? DiagnosticOptions(remote: remote, samples: samples, includePrivate: includePrivate) else {
            message = "The collection options could not be prepared."; return
        }
        message = nil
        activity = useRemote ? .collecting : .discovering
        let id = UUID()
        operationID = id
        task = Task { [weak self, collector] in
            let result = await collector.inspect(options)
            guard let self, operationID == id else { return }
            if Task.isCancelled {
                message = "Collection cancelled. Your previous report is unchanged."
            } else {
                do {
                    let encoded = try result.report.json()
                    collection = result
                    reportData = encoded
                } catch { message = "The report could not be prepared for export." }
            }
            operationID = nil
            task = nil
            activity = .idle
        }
    }
}
