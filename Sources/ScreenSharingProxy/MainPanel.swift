import AppKit
import ProxyAppSupport
import ProxyCore
import SwiftUI

struct MainPanel: View {
    @Bindable var model: DiagnosticsModel
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 82, height: 82)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Screen Sharing Diagnostics").font(.title2.weight(.semibold))
                Text("Keep the Screen Sharing connection attempt open on this Mac, then collect a report to send for help.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.activity == .choosingDestination ? "Choose where to save your ZIP…" :
                     model.activity == .cancelling ? "Cancelling…" : "Collecting diagnostics…")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Cancel") { model.cancel() }.disabled(model.activity == .cancelling)
            } else {
                Button("Collect Diagnostics") { model.collect() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                if model.archiveData != nil {
                    Button("Save ZIP Again…") { model.saveAgain() }.buttonStyle(.link)
                }
            }
            if let message = model.message {
                Text(message).font(.callout).multilineTextAlignment(.center).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Private addresses and paths are hidden in the report.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("v\(ProxyBuild.version)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WindowMaterial().allowsHitTesting(false).accessibilityHidden(true) }
    }
}
