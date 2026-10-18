import SwiftUI
import ProxyAppSupport

struct ProxyPane: View {
    @Bindable var relay: RelayModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect to a Mac").font(.title2.weight(.semibold))
            Text("Run this app on the Mac you use to view and control the remote screen.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Host IPv4 address").font(.headline)
                TextField("192.168.1.20", text: $relay.remoteAddress)
                    .textFieldStyle(.roundedBorder).disabled(relay.isRunning)
                    .onSubmit(relay.connect)
                    .accessibilityLabel("Host IPv4 address")
            }
            HStack(spacing: 12) {
                if relay.isRunning {
                    Button("Stop Relay", action: relay.disconnect)
                        .buttonStyle(.borderedProminent).disabled(relay.activity == .stopping)
                    if relay.activity == .starting || relay.activity == .stopping { ProgressView().controlSize(.small) }
                } else {
                    Button("Connect", action: relay.connect)
                        .buttonStyle(.borderedProminent).disabled(!relay.canConnect).keyboardShortcut(.defaultAction)
                }
                if relay.report != nil {
                    Button("Save Session Report…", action: relay.saveReport).disabled(relay.saving)
                }
            }
            Text(relay.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("relay-status")
            if let report = relay.report {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("Transport observed"); Text(report.transport).monospacedDigit() }
                    GridRow { Text("Receiving"); Text(relay.megabitsPerSecond, format: .number.precision(.fractionLength(1))) + Text(" Mbit/s") }
                    GridRow { Text("Received"); Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: report.forwardedToNativeBytes), countStyle: .file)) }
                    GridRow { Text("UDP sent / received"); Text("\(report.forwardedToRemoteDatagrams) / \(report.forwardedToNativeDatagrams)").monospacedDigit() }
                    GridRow { Text("Relay drops"); Text("\(report.droppedDatagrams)").monospacedDigit() }
                }
                .font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
                if report.transport == "TCP only" {
                    Text("No UDP traffic observed. The native high-performance media path is not confirmed and this connection may be slower.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Quit any existing Screen Sharing session before connecting. Sign in and select the sharing mode in Apple’s Screen Sharing window.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
