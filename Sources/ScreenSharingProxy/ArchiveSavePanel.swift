import AppKit
import ProxyAppSupport
import ProxyCore
import UniformTypeIdentifiers

final class ArchiveSavePanel: DiagnosticArchiveSaving {
    weak var parentWindow: NSWindow?
    var smokeDestination: URL?
    private(set) var presented = false
    private var activePanel: NSSavePanel?

    func save(_ data: Data) async -> DiagnosticSaveResult {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.title = "Save Diagnostics"
        panel.nameFieldStringValue = "ScreenSharingProxy-Diagnostics.zip"
        if let smokeDestination {
            panel.directoryURL = smokeDestination.deletingLastPathComponent()
            panel.nameFieldStringValue = smokeDestination.lastPathComponent
        }
        activePanel = panel
        return await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                self?.activePanel = nil
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: .cancelled); return
                }
                do {
                    try PrivateReportWriter.write(data, to: url, replaceExisting: true)
                    continuation.resume(returning: .saved)
                } catch { continuation.resume(returning: .failed) }
            }
            if let parentWindow { panel.beginSheetModal(for: parentWindow, completionHandler: completion) }
            else { panel.begin(completionHandler: completion) }
            presented = true
            // Exercise the actual sheet and its normal OK action in hosted CI.
            // The test supplies a fresh path inside its own temporary directory.
            if smokeDestination != nil {
                Task {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                    while !panel.isVisible && ContinuousClock.now < deadline {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if panel.isVisible { panel.ok(nil) }
                    else { panel.cancel(nil) }
                }
            }
        }
    }
    func cancel() { activePanel?.cancel(nil) }
}
