import Foundation

public struct ProxyCandidate: Sendable, Equatable {
    public let executable: String
    public let resolvedExecutable: String
    public let sources: [String]
    public let incomingRule: FirewallRule
    public let ruleSource: String
    public let runningObserved: Bool
    public let executableAccessible: Bool
}

/// Raw executable paths remain in memory for the native app. The shareable
/// DiagnosticReport contains a separately redacted projection of this result.
public struct ProxydDiscoveryResult: Sendable {
    public enum Status: String, Sendable, Codable {
        case selected, notFound, unavailable, blocked, ambiguous, permissionUnknown, firewallDisabled, unsupportedPlatform
    }
    public let status: Status
    public let candidates: [ProxyCandidate]
    public let selected: ProxyCandidate?
    public let reason: String

    static func evaluate(candidates: [ProxyCandidate], firewallState: String, blockAll: String) -> Self {
        func result(_ status: Status, _ reason: String, selected: ProxyCandidate? = nil) -> Self {
            .init(status: status, candidates: candidates, selected: selected, reason: reason)
        }
        guard !candidates.isEmpty else { return result(.notFound, "No exact proxyd executable was discovered.") }
        if firewallState == "disabled" {
            return result(.firewallDisabled, "Apple's application firewall is disabled; its rules cannot establish the reported restriction.")
        }
        if blockAll == "enabled" {
            return result(.blocked, "Block-all is enabled; a listed application allow rule is insufficient.")
        }
        guard firewallState == "enabled", blockAll == "disabled" else {
            return result(.permissionUnknown, "The firewall's global and block-all settings could not both be established.")
        }
        let accessible = candidates.filter(\.executableAccessible)
        guard !accessible.isEmpty else { return result(.unavailable, "Discovered entries do not identify an accessible executable.") }
        let grouped = Dictionary(grouping: accessible, by: \.resolvedExecutable)
        var allowed: [ProxyCandidate] = []
        for aliases in grouped.values {
            let rules = Set(aliases.map(\.incomingRule))
            if rules.contains(.allow) && rules.contains(.block) {
                return result(.permissionUnknown, "Conflicting rules refer to the same executable through different paths.")
            }
            if let candidate = aliases.filter({ $0.incomingRule == .allow }).sorted(by: {
                if $0.runningObserved != $1.runningObserved { return $0.runningObserved }
                return $0.executable < $1.executable
            }).first { allowed.append(candidate) }
        }
        if allowed.count == 1 {
            return result(.selected, "One accessible proxyd has an explicit incoming-connection allow rule.", selected: allowed[0])
        }
        let running = allowed.filter(\.runningObserved)
        if running.count == 1 {
            return result(.selected, "The sole running proxyd with an explicit allow rule was selected.", selected: running[0])
        }
        if allowed.count > 1 { return result(.ambiguous, "Multiple distinct allowed proxyd executables were found.") }
        if accessible.allSatisfy({ $0.incomingRule == .block }) {
            return result(.blocked, "All accessible proxyd candidates are explicitly blocked.")
        }
        return result(.permissionUnknown, "No accessible proxyd has a confirmed explicit allow rule. Signed-app defaults are not proof.")
    }
}

struct ExecutableInspection: Sendable {
    let resolvedPath: String
    let accessible: Bool
}

protocol ExecutableInspecting: Sendable {
    func inspect(_ path: String) -> ExecutableInspection
}

struct LocalExecutableInspector: ExecutableInspecting {
    func inspect(_ path: String) -> ExecutableInspection {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        let manager = FileManager.default
        let attributes = try? manager.attributesOfItem(atPath: resolved)
        let regular = attributes?[.type] as? FileAttributeType == .typeRegular
        return .init(resolvedPath: resolved, accessible: regular && manager.isExecutableFile(atPath: resolved))
    }
}

public struct DiagnosticCollection: Sendable {
    public let report: DiagnosticReport
    public let discovery: ProxydDiscoveryResult
}
