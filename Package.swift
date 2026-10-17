// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScreenSharingProxy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProxyCore", targets: ["ProxyCore"]),
        .executable(name: "screensharing-proxy-diagnose", targets: ["ProxyDiagnostics"]),
    ],
    targets: [
        .target(name: "CProcessSupport", publicHeadersPath: "include"),
        .target(name: "ProxyCore", dependencies: ["CProcessSupport"]),
        .executableTarget(name: "ProxyDiagnostics", dependencies: ["ProxyCore"]),
        .testTarget(name: "ProxyCoreTests", dependencies: ["ProxyCore"]),
    ]
)
