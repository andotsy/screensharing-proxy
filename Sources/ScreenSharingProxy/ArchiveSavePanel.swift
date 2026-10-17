import AppKit
import ProxyAppSupport
import ProxyCore
import UniformTypeIdentifiers

final class ArchiveSavePanel: NSObject, DiagnosticArchiveSaving {
    weak var parentWindow: NSWindow?
    var smokeDestination: URL?
    private(set) var presented = false
    private(set) var smokePanelWasVisible = false
    private var activePanel: NSSavePanel?
    private var smokeTimer: Timer?
    private var smokeDeadline: ContinuousClock.Instant?

    func save(_ data: Data) async -> DiagnosticSaveResult {
        smokeLog("Save requested")
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
                self?.smokeLog(response == .OK ? "Save confirmed" : "Save cancelled")
                self?.smokeTimer?.invalidate()
                self?.smokeTimer = nil
                self?.activePanel = nil
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: .cancelled); return
                }
                do {
                    try PrivateReportWriter.write(data, to: url, replaceExisting: true)
                    self?.smokeLog("ZIP written")
                    continuation.resume(returning: .saved)
                } catch { continuation.resume(returning: .failed) }
            }
            if let parentWindow { panel.beginSheetModal(for: parentWindow, completionHandler: completion) }
            else { panel.begin(completionHandler: completion) }
            presented = true
            smokeLog("Save sheet presented")
            // Since macOS 10.15, NSSavePanel.ok(_:) cannot be called
            // programmatically. Exercise presentation and the supported Cancel
            // action; the smoke driver verifies ZIP writing separately.
            // https://developer.apple.com/documentation/appkit/nssavepanel/ok(_:)
            if smokeDestination != nil {
                smokeDeadline = ContinuousClock.now.advanced(by: .seconds(20))
                let timer = Timer(timeInterval: 0.5, target: self,
                                  selector: #selector(cancelSmokePanel(_:)), userInfo: nil, repeats: true)
                smokeTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    @objc private func cancelSmokePanel(_ timer: Timer) {
        guard let panel = activePanel else { timer.invalidate(); return }
        if let smokeDeadline, ContinuousClock.now >= smokeDeadline {
            timer.invalidate(); smokeLog("Save sheet timed out"); panel.cancel(nil)
        } else if panel.isVisible {
            timer.invalidate()
            smokePanelWasVisible = true
            smokeLog("Cancelling visible save sheet")
            panel.cancel(nil)
        }
    }
    func cancel() { activePanel?.cancel(nil) }
    private func smokeLog(_ text: String) {
        if smokeDestination != nil { FileHandle.standardError.write(Data((text + "\n").utf8)) }
    }
}
