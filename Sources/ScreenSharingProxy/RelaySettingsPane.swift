import SwiftUI
import ProxyAppSupport

struct RelaySettingsPane: View {
    @Bindable var relay: RelayModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connection Settings").font(.title2.weight(.semibold))
            Text("Keep the defaults unless the remote Mac uses different ports. Stop the relay before changing them.")
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 16) {
                GridRow { Text("Remote TCP port"); TextField("5900", value: $relay.remotePort, format: .number.grouping(.never)).accessibilityLabel("Remote TCP port") }
                GridRow { Text("Local TCP port"); TextField("15900", value: $relay.listenerPort, format: .number.grouping(.never)).accessibilityLabel("Local TCP port") }
                GridRow { Text("UDP media base"); TextField("5900", value: $relay.mediaBase, format: .number.grouping(.never)).accessibilityLabel("UDP media base") }
            }
            .textFieldStyle(.roundedBorder).disabled(relay.isRunning)
            Text("TCP ports: 1024–65535. Media base: 1024–65533; the next two ports are also reserved.")
                .font(.caption).foregroundStyle(.secondary)
            Label("Firewall, network interfaces and display settings stay under your control.", systemImage: "lock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
