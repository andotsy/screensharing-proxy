import AppKit
import ProxyAppSupport
import ProxyCore
import SwiftUI

private enum AppPane: String, CaseIterable {
    case proxy = "Proxy", settings = "Settings", diagnostics = "Diagnostics"
    var symbol: String {
        switch self {
        case .proxy: "network"
        case .diagnostics: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

struct MainPanel: View {
    @Bindable var model: DiagnosticsModel
    @Bindable var relay: RelayModel
    @State private var pane = AppPane.proxy

    var body: some View {
        VStack(spacing: 0) {
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
                    }
                    .buttonStyle(.plain)
                    .help(item.rawValue)
                    .accessibilityAddTraits(pane == item ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollView {
                Group {
                    switch pane {
                    case .proxy: ProxyPane(relay: relay)
                    case .settings: RelaySettingsPane(relay: relay)
                    case .diagnostics: diagnostics
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("v\(ProxyBuild.version)")
                Spacer()
                Text("Experimental relay")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background { WindowMaterial().allowsHitTesting(false).accessibilityHidden(true) }
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
