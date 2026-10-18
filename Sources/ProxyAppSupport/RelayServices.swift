import Foundation
import ProxyCore

public protocol RelayRunning: Sendable {
    func run(configuration: RubyRelayConfiguration,
             onEvent: @escaping @Sendable (BackendEnvelope) -> Void) async -> RubyRelayRunResult
}
extension RubyRelayRunner: RelayRunning {}

public protocol ViewerLaunching: Sendable {
    func open(port: UInt16) async -> Bool
}
public struct ScreenSharingLauncher: ViewerLaunching {
    public init() {}
    public func open(port: UInt16) async -> Bool {
        let result = await BoundedCommandRunner().run(.init("/usr/bin/open",
            ["-b", "com.apple.ScreenSharing", "vnc://127.0.0.1:\(port)"],
            timeout: 5, outputLimit: 4096))
        return result.succeeded
    }
}

