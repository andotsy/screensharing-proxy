import Foundation

public struct DiagnosticReport: Sendable, Encodable {
    public let toolVersion = ProxyBuild.version
    public let schemaVersion: Int
    public let collectedAt: String
    public let platform: String
    public let privateDetailsIncluded: Bool
    public let remoteFilter: String?
    public var redactionScopeID: String?
    public var capturePhase = "snapshot"
    public var probes: [ProbeSummary] = []
    public var firewallState = "unknown"
    public var firewallEntries: [FirewallSummary] = []
    public var candidates: [CandidateSummary] = []
    public var proxyDiscovery: DiscoverySummary?
    public var services: [ServiceSummary] = []
    public var components: [ComponentSummary] = []
    public var runtimeCandidates: [RuntimeCandidateSummary] = []
    public var mediaPortConfiguration = MediaPortConfiguration()
    public var samples: [SocketSample] = []
    public var limitations: [String] = []
    // Deliberately cannot be promoted by traffic counts or an allow entry.
    public let highPerformanceRelay = "notVerified"

    public struct ProbeSummary: Sendable, Codable {
        public let name: String
        public let outcome: CommandResult.Outcome
        public let exitCode: Int32?
        public let terminationSignal: Int32?
        public let truncated: Bool
        public let durationMilliseconds: Int
        public let systemError: Int32?
        public let hadStandardError: Bool
        public let value: String?
    }
    public struct FirewallSummary: Sendable, Codable {
        public let executable: String
        public let listedRule: String
    }
    public struct CandidateSummary: Sendable, Codable {
        public let executable: String
        public let sources: [String]
        public let listedFirewallRule: String
        public let signatureVerified: Bool?
        public let signingIdentifier: String?
        public let teamIdentifier: String?
        public let incomingRule: String
        public let ruleSource: String
        public let executableAccessible: Bool
    }
    public struct DiscoverySummary: Sendable, Codable {
        public let status: ProxydDiscoveryResult.Status
        public let selectedExecutable: String?
        public let reason: String
    }
    public struct ServiceSummary: Sendable, Codable {
        public let manifest: String
        public let label: String
        public let program: String?
        public let machServices: [String]
        public let socketNames: [String]
    }
    public struct MediaPortConfiguration: Sendable, Encodable {
        public let documentedDefaultUDPBase = 5900
        public var observedHostPreferenceUDPBase: UInt16?
        public var preferenceStatus = "notChecked"
        public let preferenceDomain = "com.apple.ScreenSharingServer"
        public let preferenceKey = "hostSettings.portBase"
        public let preferenceScope = "localPreferencesVisibleToCollectingUser"
        public let activeSessionUDPBase = "unknown"
    }
    public struct ComponentSummary: Sendable, Codable {
        public let executable: String
        public let roleHint: String
        public let sources: [String]
        public let executableAccessible: Bool
        public let firewallChecks: [ComponentFirewallCheck]
        public let signingIdentifier: String?
        public let signatureVerified: Bool?
        public let socketDelegationEntitlement: Bool?
    }
    public struct RuntimeCandidateSummary: Sendable, Encodable {
        public let family: String
        public let name: String
        public let firewallTarget: String
        public let targetKind: String
        public let listedRule: String
        public let executable: String?
        public let resolvedExecutable: String?
        public let executableAccessible: Bool?
        public let signatureVerified: Bool?
        public let signingIdentifier: String?
        public let executionTested = false
        public let forwardingVerified = false
    }
    public struct ComponentFirewallCheck: Sendable, Codable {
        public let target: String
        public let targetKind: String
        public let listedRule: String
        public let queriedRule: String
    }
    public struct ProcessSummary: Sendable, Codable {
        public let pid: Int32
        public let executable: String
        public let startedAt: String
        public let roleHint: String
        public let observation: String
    }
    public struct SocketSample: Sendable, Codable {
        public let index: Int
        public let startedAt: String
        public let complete: Bool
        public let unparsedRecords: Int
        public let sockets: [SocketSummary]
        public var processes: [ProcessSummary] = []
    }
    public struct SocketSummary: Sendable, Codable {
        public let pid: Int32
        public let executable: String?
        public let ownershipEvidence: String
        public let selectionReason: String
        public let descriptor: String
        public let transport: String
        public let family: String
        public let localAddress: String
        public let localPort: UInt16?
        public let remoteAddress: String?
        public let remotePort: UInt16?
        public let state: String?
        public var localAddressKind = "unknown"
        public var remoteAddressKind: String?
        public var portHints: [String] = []
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

struct ReportRedactor {
    let includePrivate: Bool
    private var addresses: [String: String] = [:]
    private var paths: [String: String] = [:]

    init(includePrivate: Bool) { self.includePrivate = includePrivate }
    mutating func address(_ value: String) -> String {
        if includePrivate || ["*", "127.0.0.1", "::1", "0.0.0.0", "::"].contains(value) { return value }
        if let token = addresses[value] { return token }
        let token = "address-\(addresses.count + 1)"
        addresses[value] = token
        return token
    }
    mutating func path(_ value: String) -> String {
        let canonical = value.hasPrefix("/") ? URL(fileURLWithPath: value).standardizedFileURL.path : value
        let systemRoots = ["/System/", "/usr/libexec/", "/usr/bin/", "/usr/sbin/", "/usr/share/man/", "/bin/", "/sbin/"]
        if includePrivate || systemRoots.contains(where: canonical.hasPrefix) { return canonical }
        if let token = paths[value] { return token }
        let token = "private-path-\(paths.count + 1)"
        paths[value] = token
        return token
    }
}
