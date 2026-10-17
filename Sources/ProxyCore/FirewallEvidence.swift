import Foundation

public enum FirewallRule: String, Codable, Sendable { case allow, block, unknown }
struct FirewallEntry: Sendable, Equatable {
    let path: String
    let rule: FirewallRule
}

enum FirewallParser {
    static func parse(_ text: String) -> [FirewallEntry] {
        var entries: [FirewallEntry] = []
        var path: String?, rule = FirewallRule.unknown
        func flush() { if let path { entries.append(FirewallEntry(path: path, rule: rule)) } }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colon = line.firstIndex(of: ":"),
               Int(line[..<colon].trimmingCharacters(in: .whitespaces)) != nil {
                flush()
                let candidate = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                path = candidate.hasPrefix("/") ? candidate : nil
                rule = .unknown
            } else if line == "(Allow incoming connections)" { rule = .allow }
            else if line == "(Block incoming connections)" { rule = .block }
        }
        flush()
        return entries
    }

    static func globalState(_ text: String) -> String {
        if text.contains("Firewall is enabled. (State = 1)") { return "enabled" }
        if text.contains("Firewall is disabled. (State = 0)") { return "disabled" }
        return "unknown"
    }

    static func blockAll(_ text: String) -> String {
        let normalized = text.lowercased()
        let enabled = normalized.contains("block all enabled") || normalized.contains("block all state set to enabled")
        let disabled = normalized.contains("block all disabled") || normalized.contains("block all state set to disabled")
        if enabled == disabled { return "unknown" }
        return enabled ? "enabled" : "disabled"
    }

    static func queriedRule(_ text: String) -> FirewallRule {
        let lines = text.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        }
        let allow = lines.contains("the application is not blocked")
        let block = lines.contains("the application is blocked")
        guard allow != block else { return .unknown }
        return allow ? .allow : .block
    }
}

struct ServiceManifest: Sendable {
    let path: String
    let label: String
    let program: String?
    let machServices: [String]
    let socketNames: [String]
}

enum ServiceManifestParser {
    static func parse(_ data: Data, path: String, candidatePaths: Set<String>) -> ServiceManifest? {
        guard data.count <= 262_144,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }
        let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
        let matches = label.lowercased().split(separator: ".").contains("proxyd")
            || program.map { CandidateNames.isProxyd($0) || candidatePaths.contains($0) } == true
        guard matches else { return nil }
        return ServiceManifest(path: path, label: label, program: program,
            machServices: (plist["MachServices"] as? [String: Any])?.keys.sorted() ?? [],
            socketNames: (plist["Sockets"] as? [String: Any])?.keys.sorted() ?? [])
    }
}
