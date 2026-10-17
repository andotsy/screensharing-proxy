import CoreFoundation
import Foundation

/// Names are selection hints, never proof of Apple's identity or an active role.
enum PerformanceComponent {
    static let knownExecutables = [
        "/System/Applications/Utilities/Screen Sharing.app/Contents/MacOS/Screen Sharing",
        "/System/Library/CoreServices/Screen Sharing.app/Contents/MacOS/Screen Sharing",
        "/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd",
        "/System/Library/CoreServices/RemoteManagement/ScreensharingAgent.bundle/Contents/MacOS/ScreensharingAgent",
        "/usr/libexec/avconferenced",
    ]

    static func role(_ path: String) -> String? {
        switch URL(fileURLWithPath: path).lastPathComponent.lowercased() {
        case "screen sharing", "screen sharing.app": "viewerClient"
        case "screensharingd", "screensharingd.bundle": "serverControl"
        case "screensharingagent", "screensharingagent.bundle": "sessionAgent"
        case "avconferenced": "mediaServiceCandidate"
        default: nil
        }
    }

    static func enclosingBundle(_ path: String) -> String? {
        let components = path.split(separator: "/")
        guard path.hasPrefix("/"), let index = components.lastIndex(where: {
            $0.hasSuffix(".app") || $0.hasSuffix(".bundle")
        }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }

    static func relevantService(_ label: String) -> Bool {
        ["com.apple.screensharing", "com.apple.screensharing.agent", "com.apple.avconferenced"].contains(label.lowercased())
    }
}

enum PerformanceEvidence {
    static func addressKind(_ address: String) -> String {
        let host = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        if ["*", "0.0.0.0", "::"].contains(host) { return "wildcard" }
        if host == "::1" || host.hasPrefix("127.") || host.hasPrefix("::ffff:127.") { return "loopback" }
        return "nonLoopback"
    }

    static func portMatches(_ socket: SocketObservation, base: UInt16) -> Bool {
        let ports = (0..<(socket.transport == "UDP" ? 3 : 1)).compactMap { UInt16(exactly: Int(base) + $0) }
        return ports.contains(socket.local.port ?? 0) || ports.contains(socket.remote?.port ?? 0)
    }

    // `defaults read` emits an OpenStep dictionary. It represents numbers as
    // decimal atoms; also accept typed numbers from XML/binary test fixtures.
    // No other host settings are retained in the report.
    static func portBase(_ data: Data) -> UInt16? {
        guard data.count <= 65_536,
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = dictionary["portBase"] else { return nil }
        let value: UInt16?
        if let number = raw as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == number.doubleValue.rounded() else { return nil }
            value = UInt16(exactly: number.doubleValue)
        } else if let text = raw as? String, !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) {
            value = UInt16(text)
        } else { value = nil }
        guard let value, value >= 1_024 else { return nil }
        return value
    }

    static func socketDelegationEntitlement(_ data: Data) -> Bool? {
        guard data.count <= 65_536,
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        guard let raw = dictionary["com.apple.private.network.socket-delegate"] else { return false }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

/// Reuse only within one explicitly paired capture. The mapping stays in memory;
/// reports contain opaque tokens and an ID identifying their comparison scope.
public final class DiagnosticRedactionScope: @unchecked Sendable {
    public let id = UUID().uuidString
    private let lock = NSLock()
    private var redactor = ReportRedactor(includePrivate: false)
    public init() {}
    func address(_ value: String) -> String { lock.withLock { redactor.address(value) } }
    func path(_ value: String) -> String { lock.withLock { redactor.path(value) } }
}

struct ScopedReportRedactor {
    let scope: DiagnosticRedactionScope
    let includePrivate: Bool
    func address(_ value: String) -> String { includePrivate ? value : scope.address(value) }
    func path(_ value: String) -> String { includePrivate ? value : scope.path(value) }
}
