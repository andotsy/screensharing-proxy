import Foundation

/// Explicit, bounded options for the separate native relay experiments.
/// This does not establish transport readiness or enable the application's UI.
public struct IncomingExperimentOptions: Sendable {
    public let mode: RubyRelayConfiguration.Mode
    public let remoteAddress: String
    public let mediaBase: UInt16
    public let duration: Int
    public let output: String
    public let listenerPort: UInt16
    public let remoteControlPort: UInt16

    public struct InvalidInvocation: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    public init(arguments: [String]) throws {
        guard let verb = arguments.first, ["incoming", "loopback"].contains(verb) else {
            throw InvalidInvocation(description: "Expected the 'incoming' or 'loopback' experiment.")
        }
        mode = verb == "loopback" ? .loopback : .incoming
        var remote: String?, output: String?, base: UInt16 = 5900, duration = 600
        var listenerPort: UInt16 = 15900, remoteControlPort: UInt16 = 5900
        var seen = Set<String>()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted, index + 1 < arguments.count else {
                throw InvalidInvocation(description: "Every option requires one value and may appear only once.")
            }
            let value = arguments[index + 1]
            switch flag {
            case "--listen-port", "--remote-control-port":
                guard mode == .loopback, let port = UInt16(value), port >= 1024 else {
                    throw InvalidInvocation(description: "TCP port options require loopback mode and ports 1024...65535.")
                }
                if flag == "--listen-port" { listenerPort = port } else { remoteControlPort = port }
            case "--remote":
                guard RubyRelayConfiguration.validRemoteAddress(value) else {
                    throw InvalidInvocation(description: "--remote requires a numeric unicast IPv4 address on another Mac.")
                }
                remote = value
            case "--media-base":
                guard let number = UInt16(value), (1024...65533).contains(number) else {
                    throw InvalidInvocation(description: "--media-base must be 1024...65533.")
                }
                base = number
            case "--duration":
                guard let number = Int(value), (10...1200).contains(number) else {
                    throw InvalidInvocation(description: "--duration must be 10...1200 seconds.")
                }
                duration = number
            case "--output":
                guard !value.isEmpty, !value.utf8.contains(0) else {
                    throw InvalidInvocation(description: "--output requires a new report path.")
                }
                output = value
            default:
                throw InvalidInvocation(description: "Unknown option. Use --help for usage.")
            }
            index += 2
        }
        guard let remote, let output else {
            throw InvalidInvocation(description: "Both --remote and --output are required.")
        }
        self.remoteAddress = remote
        self.mediaBase = base
        self.duration = duration
        self.output = output
        self.listenerPort = listenerPort
        self.remoteControlPort = remoteControlPort
    }

    public func configuration(sessionID: UUID = UUID()) -> RubyRelayConfiguration {
        var configuration = RubyRelayConfiguration(sessionID: sessionID, remoteAddress: remoteAddress)
        configuration.mode = mode
        configuration.mediaBase = mediaBase
        if mode == .loopback {
            configuration.listenerAddress = "127.0.0.1"
            configuration.nativeAddress = "127.0.0.1"
            configuration.listenerPort = listenerPort
            configuration.remoteControlPort = remoteControlPort
        }
        return configuration
    }
}
