// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .library(name: "ProxyCore", targets: ["ProxyCore"]),
]
var targets: [Target] = [
    .target(name: "CProcessSupport", publicHeadersPath: "include"),
    .target(name: "ProxyCore", dependencies: ["CProcessSupport"]),
    .target(name: "ProxyAppSupport", dependencies: ["ProxyCore"]),
    .testTarget(name: "ProxyCoreTests", dependencies: ["ProxyCore"]),
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
