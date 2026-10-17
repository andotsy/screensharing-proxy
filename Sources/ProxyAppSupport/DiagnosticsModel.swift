import Foundation
#if os(macOS)
import Observation
#endif
import ProxyCore

public enum DiagnosticSaveResult: Sendable { case saved, cancelled, failed }

@MainActor public protocol DiagnosticArchiveSaving {
    func save(_ data: Data) async -> DiagnosticSaveResult
    func cancel()
}

@MainActor
#if os(macOS)
@Observable
#endif
public final class DiagnosticsModel {
    public enum Activity: Equatable { case idle, collecting, choosingDestination, cancelling }
    public private(set) var activity = Activity.idle
    public private(set) var collection: DiagnosticCollection?
    public private(set) var message: String?
    public private(set) var archiveData: Data?
    private let collector: any DiagnosticCollecting
    private let saver: any DiagnosticArchiveSaving
    private let operation = Operation()

    @MainActor private final class Operation { var task: Task<Void, Never>? }

    public init(saver: any DiagnosticArchiveSaving, collector: any DiagnosticCollecting = DiagnosticsCollector()) {
        self.saver = saver; self.collector = collector
    }
    public var isBusy: Bool { activity != .idle }

    public func collect() {
        guard operation.task == nil else { return }
        message = nil; activity = .collecting
        operation.task = Task { [weak self, collector] in
            let result = await collector.inspect(try! DiagnosticOptions(samples: 10))
            guard let self else { return }
            if Task.isCancelled {
                message = "Collection cancelled."
            } else {
                do {
                    let archive = try DiagnosticArchive.make(report: result.report)
                    collection = result; archiveData = archive
                    await saveArchive(archive)
                } catch { message = "Couldn’t prepare the ZIP. Please collect again." }
            }
            operation.task = nil; activity = .idle
        }
    }

    public func saveAgain() {
        guard operation.task == nil, let archiveData else { return }
        message = nil; activity = .choosingDestination
        operation.task = Task { [weak self] in
            guard let self else { return }
            await saveArchive(archiveData)
            operation.task = nil; activity = .idle
        }
    }

    public func cancel() {
        guard let task = operation.task else { return }
        activity = .cancelling
        task.cancel(); saver.cancel()
    }
    public func waitForCompletion() async { await operation.task?.value }
    public func stop() async { cancel(); await operation.task?.value }
    public func showError(_ text: String) { message = text }

    private func saveArchive(_ data: Data) async {
        guard !Task.isCancelled else { return }
        activity = .choosingDestination
        switch await saver.save(data) {
        case .saved: message = "Saved. Send the ZIP to the person helping you."
        case .cancelled: message = "Not saved. You can save the ZIP when you’re ready."
        case .failed: message = "Couldn’t save the ZIP. Try another location."
        }
    }
}
