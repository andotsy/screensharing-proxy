import AppKit
import ProxyAppSupport
import ProxyCore
import SwiftUI

struct MainPanel: View {
    @Bindable var rubyfier: RubyfierModel

    var body: some View {
        VStack(spacing: 0) {
            RubyfierPane(model: rubyfier)
            Divider()
            Text("Version \(ProxyBuild.version)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background { WindowMaterial().allowsHitTesting(false).accessibilityHidden(true) }
        .frame(minWidth: RubyfierWindow.minimumContentSize.width, minHeight: RubyfierWindow.minimumContentSize.height)
    }
}
