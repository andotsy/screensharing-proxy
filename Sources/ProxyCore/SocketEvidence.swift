import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct IPAddress: Hashable, Sendable, Codable {
    public let value: String
    public init?(_ text: String) {
        guard !text.utf8.contains(0) else { return nil }
        let parts = text.split(separator: "%", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        let address = String(parts[0])
        let scope = parts.count == 2 ? String(parts[1]) : nil
        if let scope, scope.isEmpty || scope.contains(where: { !$0.isASCII || !($0.isLetter || $0.isNumber || "_.-".contains($0)) }) {
            return nil
        }
        var v4 = in_addr(), v6 = in6_addr()
        var formatted = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if scope == nil, inet_pton(AF_INET, address, &v4) == 1 {
            guard inet_ntop(AF_INET, &v4, &formatted, socklen_t(formatted.count)) != nil else { return nil }
        } else if inet_pton(AF_INET6, address, &v6) == 1 {
            guard inet_ntop(AF_INET6, &v6, &formatted, socklen_t(formatted.count)) != nil else { return nil }
        } else { return nil }
        let canonical = String(decoding: formatted.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        value = canonical + (scope.map { "%" + $0 } ?? "")
    }
}

struct SocketEndpoint: Equatable, Sendable {
    let address: String
    let port: UInt16?

    init?(_ text: String) {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let portText = String(text[text.index(after: colon)...])
        guard portText == "*" || UInt16(portText) != nil else { return nil }
        var host = String(text[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard host == "*" || IPAddress(host) != nil else { return nil }
        address = IPAddress(host)?.value ?? "*"
        port = UInt16(portText)
    }
}

struct SocketObservation: Equatable, Sendable {
    let pid: Int32
    let command: String
    let descriptor: String
    let transport: String
    let family: String
    let local: SocketEndpoint
    let remote: SocketEndpoint?
    let state: String?
}

struct SocketParseResult: Sendable {
    var sockets: [SocketObservation] = []
    var unparsedRecords = 0
}

enum LsofParser {
    // lsof -F0 emits NUL-delimited fields plus newlines between process/file
    // sets. Parsing human-aligned output loses spaces and IPv6 addresses.
    static func parse(_ data: Data) -> SocketParseResult {
        var result = SocketParseResult()
        var pid: Int32?, command = "", descriptor: String?, transport = "", family = "", name = "", state: String?
        func finishFile() {
            guard let descriptor else { return }
            guard let pid, ["TCP", "UDP"].contains(transport) else { result.unparsedRecords += 1; return }
            let ends = name.components(separatedBy: "->")
            guard (1...2).contains(ends.count), let local = SocketEndpoint(ends[0]),
                  ends.count == 1 || SocketEndpoint(ends[1]) != nil else {
                result.unparsedRecords += 1; return
            }
            result.sockets.append(SocketObservation(pid: pid, command: command, descriptor: descriptor,
                transport: transport, family: family, local: local,
                remote: ends.count == 2 ? SocketEndpoint(ends[1]) : nil, state: state))
        }
        for raw in data.split(separator: 0) {
            let field = String(decoding: raw.drop(while: { $0 == 10 || $0 == 13 }), as: UTF8.self)
            guard let tag = field.first else { continue }
            let value = String(field.dropFirst())
            switch tag {
            case "p":
                finishFile(); descriptor = nil; pid = Int32(value); command = ""
            case "c": command = value
            case "f":
                finishFile(); descriptor = value; transport = ""; family = ""; name = ""; state = nil
            case "P": transport = value
            case "t": family = value
            case "n": name = value
            case "T": if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: break
            }
        }
        finishFile()
        return result
    }
}

struct ProcessIdentity: Equatable, Sendable {
    let pid: Int32
    let started: String
    let executable: String
}

enum ProcessParser {
    // ps -axo pid=,lstart=,comm=; comm contains no process arguments.
    static func parse(_ text: String) -> [Int32: ProcessIdentity] {
        var result: [Int32: ProcessIdentity] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 6, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 7, let pid = Int32(fields[0]), pid > 0 else { continue }
            let path = String(fields[6]).trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/") else { continue }
            result[pid] = ProcessIdentity(pid: pid, started: fields[1...5].joined(separator: " "), executable: path)
        }
        return result
    }
}

enum CandidateNames {
    static func relevant(_ value: String) -> Bool {
        let name = URL(fileURLWithPath: value).lastPathComponent.lowercased()
        return name == "proxyd" || name == "avconferenced"
            || name.contains("screensharing") || name == "screen sharing"
    }
    static func isProxyd(_ path: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent.lowercased() == "proxyd"
    }
}
