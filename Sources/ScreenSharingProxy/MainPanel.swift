import AppKit
import ProxyAppSupport
import ProxyCore
import SwiftUI

private enum AppPane: String, CaseIterable {
    case proxy = "Proxy", diagnostics = "Diagnostics", settings = "Settings"
    var symbol: String {
        switch self {
        case .proxy: "network"
        case .diagnostics: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
    var isAvailable: Bool { self == .diagnostics }
}

struct MainPanel: View {
    @Bindable var model: DiagnosticsModel
    @State private var pane = AppPane.diagnostics

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 8) {
                ForEach(AppPane.allCases, id: \.self) { item in
                    Button { pane = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 18))
                            Text(item.rawValue).font(.system(size: 12))
                        }
                        .frame(width: 110, height: 48).contentShape(.rect)
                        .foregroundStyle(pane == item ? Color.accentColor : .secondary)
                        .background(pane == item ? Color.primary.opacity(0.07) : .clear,
                                    in: .rect(cornerRadius: 8))
                        .opacity(item.isAvailable ? 1 : 0.4)
                    }
                    .buttonStyle(.plain).disabled(!item.isAvailable)
                    .help(item.isAvailable ? "Collect and save a diagnostic report" : "Coming in a future version")
                    .accessibilityAddTraits(pane == item ? [.isSelected] : [])
                }
            }
            .padding(.bottom, 12).frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollView {
                diagnostics.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("v\(ProxyBuild.version)")
                Spacer()
                Text("Proxy and settings are coming soon.")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background { WindowMaterial().allowsHitTesting(false).accessibilityHidden(true) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Screen Sharing Proxy").font(.title3.weight(.semibold))
                Text("Screen Sharing tools for macOS").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("ALPHA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.primary.opacity(0.06), in: .capsule)
        }
        .padding(20).background(Color(nsColor: .windowBackgroundColor))
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Diagnostics").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Keep the Screen Sharing connection attempt open on this viewer Mac.")
                step(2, "Collect diagnostics, then choose where to save the ZIP.")
                step(3, "Send the ZIP to the person helping you.")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: .rect(cornerRadius: 12))
            HStack(spacing: 12) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Text(model.activity == .choosingDestination ? "Choose where to save your ZIP…" :
                         model.activity == .cancelling ? "Cancelling…" : "Collecting diagnostics…")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancel() }.disabled(model.activity == .cancelling)
                } else {
                    Button("Collect Diagnostics") { model.collect() }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    if model.archiveData != nil {
                        Button("Save ZIP Again…") { model.saveAgain() }
                    }
                }
            }
            if let message = model.message {
                Text(message).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Private addresses and paths are hidden in the report.", systemImage: "lock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
