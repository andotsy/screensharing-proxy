import AppKit
import ProxyAppSupport
import SwiftUI

struct RubyfierPane: View {
    @Bindable var model: RubyfierModel
    @State private var copyConfirmation = 0
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Screen Sharing, Rubyfied.").font(.title2.weight(.semibold))
                Text("Adds our Ruby relay to a separate copy of Screen Sharing. Your original app stays untouched.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Creating your app…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: model.cancel)
                } else {
                    Button("Create Rubyfied App…", action: chooseDestination)
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                        .disabled(!model.payloadAvailable)
                    if model.createdApp != nil {
                        Button("Open App", action: openCreatedApp)
                        Button("Show in Finder", action: revealCreatedApp)
                    }
                }
            }
            Text(model.message).font(.callout).textSelection(.enabled)
            VStack(spacing: 0) {
                HStack {
                    Label("Console", systemImage: "terminal")
                    Spacer()
                    Button(action: copyConsole) {
                        HStack(spacing: 5) {
                            Text("Copy All")
                            Image(systemName: "checkmark").opacity(copied ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                    }
                    .disabled(model.consoleText.isEmpty)
                    .buttonStyle(ConsoleCopyButtonStyle())
                    .accessibilityLabel(copied ? "Copy All, copied" : "Copy All")
                    .task(id: copyConfirmation) {
                        guard copyConfirmation > 0 else { return }
                        do { try await Task.sleep(for: .seconds(2)) }
                        catch { return }
                        copied = false
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
                PatchConsole(text: model.consoleText.isEmpty ? "Patch activity will appear here.\n" : model.consoleText)
                    .frame(minHeight: 190, maxHeight: .infinity)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 10))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.5)))
            Text("High Performance video, audio, and control through Ruby.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Where should Rubyfied be created?"
        panel.prompt = "Create Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        panel.begin { response in
            if response == .OK, let url = panel.url { model.create(in: url) }
        }
    }
    private func copyConsole() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(model.consoleText, forType: .string) {
            copied = true
            copyConfirmation += 1
        }
    }
    private func openCreatedApp() {
        guard let url = model.createdApp else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    private func revealCreatedApp() {
        guard let url = model.createdApp else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
