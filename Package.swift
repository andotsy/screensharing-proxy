// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .library(name: "ProxyCore", targets: ["ProxyCore"]),
    .executable(name: "screensharing-proxy-diagnose", targets: ["ProxyDiagnostics"]),
]
var targets: [Target] = [
    .target(name: "CProcessSupport", publicHeadersPath: "include"),
    .target(name: "ProxyCore", dependencies: ["CProcessSupport"], resources: [.copy("Resources/relay.rb")]),
    .target(name: "ProxyAppSupport", dependencies: ["ProxyCore"]),
    .executableTarget(name: "ProxyDiagnostics", dependencies: ["ProxyCore"]),
    .testTarget(name: "ProxyCoreTests", dependencies: ["ProxyCore"]),
    .testTarget(name: "ProxyAppSupportTests", dependencies: ["ProxyAppSupport", "ProxyCore"]),
]
#if os(macOS)
products.append(.executable(name: "ScreenSharingProxy", targets: ["ScreenSharingProxy"]))
targets.append(.executableTarget(name: "ScreenSharingProxy", dependencies: ["ProxyCore", "ProxyAppSupport"],
    swiftSettings: [.defaultIsolation(MainActor.self)]))
#endif

let package = Package(
    name: "ScreenSharingProxy",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
