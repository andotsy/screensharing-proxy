import AppKit
import ProxyAppSupport
import ProxyCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum Pane: String, CaseIterable {
    case connection = "Connection", general = "General", diagnostics = "Diagnostics"
    var symbol: String {
        switch self { case .connection: "network"; case .general: "gearshape"; case .diagnostics: "waveform.path.ecg" }
    }
}

struct MainPanel: View {
    @Bindable var model: DiagnosticsModel
    @State private var pane = Pane.connection

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 8) {
                ForEach(Pane.allCases, id: \.self) { item in
                    Button { pane = item } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol).font(.system(size: 18))
                            Text(item.rawValue).font(.system(size: 12))
                        }.frame(width: 102, height: 44)
                            .contentShape(.rect)
                            .foregroundStyle(pane == item ? Color.accentColor : .secondary)
                            .background(pane == item ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(pane == item ? [.isSelected] : [])
                }
            }.padding(.bottom, 12).frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message = model.message {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle")
                            Text(message).textSelection(.enabled)
                            Spacer()
                            Button { model.dismissMessage() } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                        }.padding(12).background(.yellow.opacity(0.12), in: .rect(cornerRadius: 10))
                    }
                    switch pane {
                    case .connection: connectionPane
                    case .general: GeneralPane()
                    case .diagnostics: diagnosticsPane
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().padding(.horizontal, 20)
            footer
        }.background { WindowMaterial().allowsHitTesting(false).accessibilityHidden(true) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Screen Sharing Proxy").font(.title3.weight(.semibold))
                Text("Service discovery & diagnostics").foregroundStyle(.secondary)
            }
            Spacer()
            Text("ALPHA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.primary.opacity(0.06), in: .capsule)
        }.padding(20).background(Color(nsColor: .windowBackgroundColor))
    }

    private var connectionPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Incoming Service") {
                LabeledContent("Status") {
                    HStack(spacing: 7) {
                        if model.isBusy { ProgressView().controlSize(.small) }
                        Text(discoveryTitle).multilineTextAlignment(.trailing)
                    }
                }
                Divider()
                Text("The allowed service is found automatically. You don’t need to enter its path.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Proxy Connection") {
                Label("Proxy connections are not available in this alpha.", systemImage: "info.circle")
                Text("You can find the incoming service and collect a report. Traffic forwarding is still under development.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Session Diagnostics") {
                LabeledContent("Remote Mac IP") {
                    TextField("Optional IPv4 or IPv6 address", text: $model.remoteAddress)
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                        .accessibilityLabel("Optional remote Mac IP address")
                        .disabled(model.isBusy || model.hasBaseline)
                }
                if !model.remoteIsValid {
                    Text("Enter a numeric IP address, or leave this empty.").font(.callout).foregroundStyle(.red)
                }
                Divider()
                Text("On this viewer Mac, enter the remote IP if known. In Diagnostics, capture a baseline before connecting, then capture during the High Performance connection attempt.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Report Privacy") {
                Toggle("Include private addresses and paths", isOn: $model.includePrivate).disabled(model.isBusy || model.hasBaseline)
                Text("Reports are redacted by default. No packet contents, passwords or process environments are collected.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Before and During Connection") {
                Text("1. Before connecting, capture a baseline.\n2. Start the High Performance connection and capture during the attempt.\n3. Save one report containing both captures.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Capture Baseline") { model.captureBaseline() }
                        .disabled(model.isBusy || model.hasBaseline || !model.remoteIsValid)
                    Button("Capture During Session") { model.captureSession() }
                        .disabled(model.isBusy || !model.hasBaseline)
                }
                if model.hasBaseline {
                    Divider()
                    LabeledContent("Baseline", value: "Captured")
                    LabeledContent("During session", value: model.sessionReport == nil ? "Waiting" : "Captured")
                    Text("Remote IP and privacy settings are kept the same for both captures. The second capture takes ten socket snapshots; keep the attempt open while it runs.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Clear Captures") { model.resetPair() }.disabled(model.isBusy)
                }
            }
            group("Last Completed Report") {
                if let collection = model.collection {
                    LabeledContent("Collected", value: collection.report.collectedAt)
                    Divider()
                    LabeledContent("Private details", value: collection.report.privateDetailsIncluded ? "Included" : "Redacted")
                    Divider()
                    LabeledContent("Socket snapshots", value: "\(collection.report.samples.count)")
                    Divider()
                    LabeledContent("Performance component paths", value: "\(collection.report.components.count)")
                    if let selected = collection.report.proxyDiscovery?.selectedExecutable {
                        Divider()
                        LabeledContent("Selected executable") { Text(selected).textSelection(.enabled).multilineTextAlignment(.trailing) }
                    }
                    Divider()
                    Text(collection.discovery.reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Text("No completed report yet.").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Copy Report", action: copyReport).disabled(model.reportData == nil)
                Button("Save Report…", action: saveReport).disabled(model.reportData == nil)
            }.buttonStyle(.bordered)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("v\(ProxyBuild.version)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.isBusy {
                Button(model.activity == .cancelling ? "Cancelling…" : "Cancel") { model.cancel() }
                    .disabled(model.activity == .cancelling)
            } else {
                Button("Find Service") { model.discover() }
                Button(model.hasBaseline ? "Capture During Session" : "Collect Diagnostics") { model.collect(); pane = .diagnostics }
                    .buttonStyle(.borderedProminent).disabled(!model.remoteIsValid)
            }
        }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
    }

    private var discoveryTitle: String {
        if model.activity == .discovering { return "Finding allowed service…" }
        if model.activity == .collecting { return "Collecting diagnostics…" }
        if model.activity == .cancelling { return "Cancelling…" }
        switch model.collection?.discovery.status {
        case .selected: return "Allowed service found"
        case .notFound: return "Service not found"
        case .unavailable: return "Service unavailable"
        case .blocked: return "Incoming connections blocked"
        case .ambiguous: return "Several allowed services found"
        case .permissionUnknown: return "Permission could not be confirmed"
        case .firewallDisabled: return "Application firewall is off"
        case .unsupportedPlatform: return "Unsupported platform"
        case nil: return "Not checked"
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: .rect(cornerRadius: 12))
        }
    }

    private func copyReport() {
        guard let data = model.reportData else { return }
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string) {
            model.showError("The report could not be copied. Use Save Report instead.")
        }
    }

    private func saveReport() {
        guard let data = model.reportData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ScreenSharingProxy-report.json"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try PrivateReportWriter.write(data, to: url, replaceExisting: true) }
            catch { model.showError("The report could not be saved. Choose another location and try again.") }
        }
    }
}

private struct GeneralPane: View {
    @AppStorage("showInDock") private var showInDock = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behavior").font(.headline)
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, value in NSApp.setActivationPolicy(value ? .regular : .accessory) }
                Divider()
                Toggle("Launch at login", isOn: Binding(get: {
                    loginStatus == .enabled || loginStatus == .requiresApproval
                }, set: { value in
                    do {
                        if value { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginStatus = SMAppService.mainApp.status
                    } catch { self.error = "Login startup could not be changed. Install the app in Applications and try again." }
                }))
                if loginStatus == .requiresApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("The menu bar icon remains available when the window is closed. Launching at login checks the service without opening the window.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: .rect(cornerRadius: 12))
        }
    }
}
