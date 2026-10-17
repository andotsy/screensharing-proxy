import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct DiagnosticOptions: Sendable {
    public let remote: IPAddress?
    public let samples: Int
    public let interval: TimeInterval
    public let includePrivate: Bool
    public let capturePhase: String
    public let redactionScope: DiagnosticRedactionScope

    public enum ValidationError: Error { case invalidSampling, invalidPhase }
    public init(remote: IPAddress? = nil, samples: Int = 3, interval: TimeInterval = 1,
                includePrivate: Bool = false, capturePhase: String = "snapshot",
                redactionScope: DiagnosticRedactionScope? = nil) throws {
        guard (1...10).contains(samples), interval.isFinite, (0.2...5).contains(interval) else {
            throw ValidationError.invalidSampling
        }
        guard ["snapshot", "baseline", "duringSession"].contains(capturePhase) else { throw ValidationError.invalidPhase }
        self.remote = remote; self.samples = samples; self.interval = interval
        self.includePrivate = includePrivate
        self.capturePhase = capturePhase; self.redactionScope = redactionScope ?? DiagnosticRedactionScope()
    }
}

public protocol DiagnosticCollecting: Sendable {
    func inspect(_ options: DiagnosticOptions) async -> DiagnosticCollection
}

public struct DiagnosticsCollector: DiagnosticCollecting {
    private let runner: any CommandRunning
    private let platform: String
    private let scanManifests: Bool
    private let executableInspector: any ExecutableInspecting

    public init(runner: any CommandRunning = BoundedCommandRunner()) {
        self.runner = runner
        #if os(macOS)
        platform = "macOS"
        #else
        platform = "unsupported"
        #endif
        scanManifests = true
        executableInspector = LocalExecutableInspector()
    }

    // Tests inject macOS-shaped evidence without executing platform commands.
    init(runner: any CommandRunning, platform: String, scanManifests: Bool,
         executableInspector: any ExecutableInspecting = LocalExecutableInspector()) {
        self.runner = runner; self.platform = platform; self.scanManifests = scanManifests
        self.executableInspector = executableInspector
    }

    public func collect(_ options: DiagnosticOptions) async -> DiagnosticReport {
        await inspect(options).report
    }

    /// Native startup can call this to discover/select the allowed executable
    /// automatically. The raw selection stays out of the redacted report.
    public func inspect(_ options: DiagnosticOptions) async -> DiagnosticCollection {
        let redactor = ScopedReportRedactor(scope: options.redactionScope, includePrivate: options.includePrivate)
        var report = DiagnosticReport(schemaVersion: 2, collectedAt: Self.timestamp(), platform: platform,
            privateDetailsIncluded: options.includePrivate,
            remoteFilter: options.remote.map { redactor.address($0.value) })
        report.capturePhase = options.capturePhase
        report.redactionScopeID = options.redactionScope.id
        guard platform == "macOS" else {
            report.limitations = ["macOS is required to inspect proxyd, Apple's firewall and Screen Sharing sockets."]
            let discovery = ProxydDiscoveryResult(status: .unsupportedPlatform, candidates: [], selected: nil,
                reason: "Automatic discovery requires macOS.")
            report.proxyDiscovery = .init(status: discovery.status, selectedExecutable: nil, reason: discovery.reason)
            return .init(report: report, discovery: discovery)
        }
        report.limitations = [
            "Read-only snapshots are not atomic. Some processes/sockets may be hidden without administrative access.",
            "Listed firewall rules do not prove effective permission, socket attribution or another filter's behavior.",
            "A manifest is configuration evidence, not proof that its service is running or supports forwarding.",
            "UDP purpose, media negotiation and successful presentation require a separate two-Mac experiment.",
            "Unconnected UDP sockets have no known peer; they are included as unattributed listeners, not identified session traffic.",
            "Process names, port hints and entitlements are candidates, not proof of media use. Socket delegation can make firewall attribution differ from lsof's owner.",
            "Local host preferences are not the remote Mac's settings or a measurement of the active session's UDP base. No packet contents are collected.",
        ]
        if options.remote == nil {
            report.limitations.append("No remote IP filter supplied: unknown process names may own unreported session sockets.")
        }
        let firewall = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        let initial: [(String, CommandSpec)] = [
            ("osVersion", CommandSpec("/usr/bin/sw_vers")),
            ("architecture", CommandSpec("/usr/bin/uname", ["-m"])),
            ("firewallState", CommandSpec(firewall, ["--getglobalstate"])),
            ("firewallBlockAll", CommandSpec(firewall, ["--getblockall"])),
            ("firewallSignedApps", CommandSpec(firewall, ["--getallowsigned"])),
            ("firewallApplications", CommandSpec(firewall, ["--listapps"])),
            ("proxydManualLocation", CommandSpec("/usr/bin/man", ["-w", "proxyd"])),
            ("hostMediaPreference", CommandSpec("/usr/bin/defaults", ["read", "com.apple.ScreenSharingServer", "hostSettings"], outputLimit: 65_536)),
        ]
        var firewallEntries: [FirewallEntry] = []
        var candidates: [String: Set<String>] = [:]
        var components = Dictionary(uniqueKeysWithValues: PerformanceComponent.knownExecutables.map { ($0, Set(["knownSystemLocation"])) })
        var blockAll = "unknown"
        for (name, spec) in initial {
            if Task.isCancelled { break }
            let result = await runner.run(spec)
            var value: String?
            if result.complete {
                switch name {
                case "osVersion":
                    // Only Apple's known public version fields, not arbitrary output.
                    value = result.text.split(separator: "\n").filter {
                        ["ProductName:", "ProductVersion:", "BuildVersion:"].contains(where: $0.hasPrefix)
                    }.joined(separator: "\n")
                case "architecture":
                    let arch = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    value = ["arm64", "x86_64"].contains(arch) ? arch : "unknown"
                case "firewallState": report.firewallState = FirewallParser.globalState(result.text)
                case "firewallApplications":
                    firewallEntries = FirewallParser.parse(result.text)
                    // Keep all entries (with private paths redacted): the recalled
                    // daemon name may be mistaken, and another system entry can
                    // resolve it without guessing that two services are equivalent.
                    for entry in firewallEntries {
                        report.firewallEntries.append(.init(executable: redactor.path(entry.path), listedRule: entry.rule.rawValue))
                        if CandidateNames.isProxyd(entry.path) { candidates[entry.path, default: []].insert("firewallList") }
                        if PerformanceComponent.role(entry.path) != nil && PerformanceComponent.enclosingBundle(entry.path) != entry.path {
                            components[entry.path, default: []].insert("firewallList")
                        }
                    }
                case "firewallBlockAll":
                    blockAll = FirewallParser.blockAll(result.text)
                    value = blockAll
                case "firewallSignedApps":
                    // Preserve just normalized known booleans. Do not infer permission for proxyd.
                    value = result.text.split(separator: "\n").filter {
                        $0.hasPrefix("Automatically allow") && ($0.hasSuffix("ENABLED") || $0.hasSuffix("DISABLED"))
                    }.joined(separator: "\n")
                case "proxydManualLocation":
                    let paths = result.text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") }
                    value = paths.map { redactor.path($0) }.joined(separator: "\n")
                case "hostMediaPreference":
                    report.mediaPortConfiguration.observedHostPreferenceUDPBase = PerformanceEvidence.portBase(result.output)
                    report.mediaPortConfiguration.preferenceStatus = report.mediaPortConfiguration.observedHostPreferenceUDPBase == nil
                        ? "noValidPortBaseInVisibleValue" : "observed"
                default: break
                }
            }
            if name == "hostMediaPreference" && !result.complete { report.mediaPortConfiguration.preferenceStatus = "unavailableOrIncomplete" }
            report.probes.append(Self.summary(name, result, value: value))
        }

        let processSpec = CommandSpec("/bin/ps", ["-axo", "pid=,lstart=,comm="], outputLimit: 524_288)
        for index in 0..<options.samples {
            if Task.isCancelled { break }
            let started = Self.timestamp()
            let before = await runner.run(processSpec)
            let sockets = await runner.run(CommandSpec("/usr/sbin/lsof", ["-nP", "-iTCP", "-iUDP", "-F0pcftPnT"], outputLimit: 524_288))
            let after = await runner.run(processSpec)
            report.probes += [Self.summary("sample\(index).processesBefore", before),
                              Self.summary("sample\(index).sockets", sockets),
                              Self.summary("sample\(index).processesAfter", after)]
            let beforeMap = before.complete ? ProcessParser.parse(before.text) : [:]
            let afterMap = after.complete ? ProcessParser.parse(after.text) : [:]
            for identity in afterMap.values where CandidateNames.isProxyd(identity.executable) {
                candidates[identity.executable, default: []].insert("processSnapshot")
            }
            var processes: [DiagnosticReport.ProcessSummary] = []
            for pid in Set(beforeMap.keys).union(afterMap.keys).sorted() {
                // Retain transitions as well as stable identities, including processes
                // without visible sockets. PID reuse never becomes stable ownership.
                let identities = [beforeMap[pid], afterMap[pid]].compactMap { $0 }
                for (offset, identity) in identities.enumerated() {
                    let stable = beforeMap[pid] != nil && beforeMap[pid] == afterMap[pid]
                    if stable && offset > 0 { continue }
                    guard let role = PerformanceComponent.role(identity.executable)
                        ?? (CandidateNames.isProxyd(identity.executable) ? "proxyCandidate" : nil) else { continue }
                    if role != "proxyCandidate" { components[identity.executable, default: []].insert("processSnapshot") }
                    let observation = stable ? "beforeAndAfter" : (beforeMap[pid] == identity ? "beforeOnly" : "afterOnly")
                    processes.append(.init(pid: pid, executable: redactor.path(identity.executable), startedAt: identity.started,
                        roleHint: role, observation: observation))
                }
            }
            // lsof exit 1 can mean no matches OR an error. Preserve it as an
            // incomplete observation, never as proof that no sockets exist.
            let parsed = LsofParser.parse(sockets.output)
            var selected: [DiagnosticReport.SocketSummary] = []
            for socket in parsed.sockets {
                let identity = beforeMap[socket.pid]
                let stable = identity != nil && identity == afterMap[socket.pid]
                let path = stable ? identity?.executable : nil
                var hints: [String] = []
                if PerformanceEvidence.portMatches(socket, base: 5900) { hints.append("documentedDefaultPortRange") }
                if let base = report.mediaPortConfiguration.observedHostPreferenceUDPBase,
                   socket.transport == "UDP", PerformanceEvidence.portMatches(socket, base: base) { hints.append("localHostPreferencePortRange") }
                let selection: String
                if CandidateNames.relevant(path ?? socket.command) { selection = "namedCandidate" }
                else if options.remote.map({ socket.remote?.address == $0.value }) == true { selection = "remotePeerMatch" }
                else if !hints.isEmpty { selection = "portHint" }
                else if socket.transport == "UDP" && socket.remote == nil { selection = "unattributedUDPListener" }
                else { continue }
                selected.append(.init(pid: socket.pid, executable: path.map { redactor.path($0) },
                    ownershipEvidence: stable ? "consistentProcessSnapshots" : "unresolved",
                    selectionReason: selection,
                    descriptor: socket.descriptor, transport: socket.transport, family: socket.family,
                    localAddress: redactor.address(socket.local.address), localPort: socket.local.port,
                    remoteAddress: socket.remote.map { redactor.address($0.address) },
                    remotePort: socket.remote?.port, state: socket.state,
                    localAddressKind: PerformanceEvidence.addressKind(socket.local.address),
                    remoteAddressKind: socket.remote.map { PerformanceEvidence.addressKind($0.address) }, portHints: hints))
            }
            report.samples.append(.init(index: index, startedAt: started,
                complete: before.complete && sockets.complete && after.complete && parsed.unparsedRecords == 0
                    && before.errorOutput.isEmpty && sockets.errorOutput.isEmpty && after.errorOutput.isEmpty,
                unparsedRecords: parsed.unparsedRecords, sockets: selected, processes: processes))
            if index + 1 < options.samples {
                do { try await Task.sleep(for: .seconds(options.interval)) } catch { break }
            }
        }

        if scanManifests && !Task.isCancelled {
            let manifests = Self.manifests(candidatePaths: Set(candidates.keys))
            for item in manifests.items {
                if let program = item.program, program.hasPrefix("/") {
                    if CandidateNames.isProxyd(program) { candidates[program, default: []].insert("serviceManifest") }
                    if PerformanceComponent.role(program) != nil { components[program, default: []].insert("serviceManifest") }
                } else if item.program != nil {
                    report.limitations.append("A candidate service has a relative program name; its executable path remains unresolved.")
                }
                report.services.append(.init(manifest: redactor.path(item.path), label: item.label,
                    program: item.program.map { redactor.path($0) }, machServices: item.machServices, socketNames: item.socketNames))
            }
            if !manifests.complete { report.limitations.append("Some launchd manifests were unreadable, oversized or beyond the scan limit.") }
        }
        if components.count > 16 { report.limitations.append("Only the first sixteen performance component paths were inspected.") }
        for path in components.keys.sorted().prefix(16) {
            if Task.isCancelled { break }
            let executable = executableInspector.inspect(path)
            var checks: [DiagnosticReport.ComponentFirewallCheck] = []
            var targets = [(path, "executable")]
            if let bundle = PerformanceComponent.enclosingBundle(path) { targets.append((bundle, "enclosingBundle")) }
            for (target, kind) in targets {
                let rules = Set(firewallEntries.filter { $0.path == target }.map(\.rule))
                let listed = rules.count == 1 ? rules.first! : .unknown
                var queried = FirewallRule.unknown
                if executable.accessible && !Task.isCancelled {
                    let result = await runner.run(CommandSpec(firewall, ["--getappblocked", target]))
                    report.probes.append(Self.summary("component.\(redactor.path(target)).incomingRule", result))
                    if result.complete { queried = FirewallParser.queriedRule(result.text) }
                }
                checks.append(.init(target: redactor.path(target), targetKind: kind, listedRule: listed.rawValue, queriedRule: queried.rawValue))
            }
            var signingIdentifier: String?, signatureVerified: Bool?, delegated: Bool?
            if executable.accessible && !Task.isCancelled {
                let verify = await runner.run(CommandSpec("/usr/bin/codesign", ["--verify", "--strict", path]))
                let identity = await runner.run(CommandSpec("/usr/bin/codesign", ["--display", "--verbose=2", path]))
                let entitlements = await runner.run(CommandSpec("/usr/bin/codesign", ["--display", "--entitlements", ":-", path], outputLimit: 65_536))
                report.probes += [Self.summary("component.\(redactor.path(path)).signature", verify),
                                  Self.summary("component.\(redactor.path(path)).identity", identity),
                                  Self.summary("component.\(redactor.path(path)).entitlements", entitlements)]
                signatureVerified = verify.outcome == .exited ? verify.succeeded : nil
                if identity.complete {
                    signingIdentifier = String(decoding: identity.errorOutput, as: UTF8.self).split(separator: "\n")
                        .first { $0.hasPrefix("Identifier=") }.map { String($0.dropFirst("Identifier=".count)) }
                }
                if entitlements.complete { delegated = PerformanceEvidence.socketDelegationEntitlement(entitlements.output) }
            }
            report.components.append(.init(executable: redactor.path(path), roleHint: PerformanceComponent.role(path) ?? "unknown",
                sources: components[path]!.sorted(), executableAccessible: executable.accessible, firewallChecks: checks,
                signingIdentifier: signingIdentifier, signatureVerified: signatureVerified, socketDelegationEntitlement: delegated))
        }
        if candidates.count > 8 { report.limitations.append("Only the first eight candidate executables were inspected.") }
        var inspected: [ProxyCandidate] = []
        for path in candidates.keys.sorted().prefix(8) {
            if Task.isCancelled { break }
            guard path.hasPrefix("/") else { continue }
            let executable = executableInspector.inspect(path)
            let listedRules = Set(firewallEntries.filter { $0.path == path }.map(\.rule))
            var incomingRule = listedRules.count == 1 ? listedRules.first! : .unknown
            var ruleSource = incomingRule == .unknown ? "unknown" : "firewallList"
            if incomingRule == .unknown {
                let query = await runner.run(CommandSpec(firewall, ["--getappblocked", path]))
                report.probes.append(Self.summary("candidate.incomingRule", query))
                if query.complete {
                    incomingRule = FirewallParser.queriedRule(query.text)
                    if incomingRule != .unknown { ruleSource = "getappblocked" }
                }
            }
            let verification = await runner.run(CommandSpec("/usr/bin/codesign", ["--verify", "--strict", path]))
            let identity = await runner.run(CommandSpec("/usr/bin/codesign", ["--display", "--verbose=2", path]))
            report.probes += [Self.summary("candidate.signature", verification), Self.summary("candidate.identity", identity)]
            let metadata = identity.complete ? String(decoding: identity.errorOutput, as: UTF8.self).split(separator: "\n") : []
            func field(_ key: String) -> String? {
                metadata.first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
            }
            report.candidates.append(.init(executable: redactor.path(path), sources: candidates[path]!.sorted(),
                listedFirewallRule: firewallEntries.first { $0.path == path }?.rule.rawValue ?? "unknown",
                signatureVerified: verification.outcome == .exited ? verification.succeeded : nil,
                signingIdentifier: field("Identifier"), teamIdentifier: field("TeamIdentifier"),
                incomingRule: incomingRule.rawValue, ruleSource: ruleSource, executableAccessible: executable.accessible))
            inspected.append(.init(executable: path, resolvedExecutable: executable.resolvedPath,
                sources: candidates[path]!.sorted(), incomingRule: incomingRule, ruleSource: ruleSource,
                runningObserved: candidates[path]!.contains("processSnapshot"), executableAccessible: executable.accessible))
        }
        if candidates.isEmpty { report.limitations.append("No exact proxyd executable was identified; the recalled name remains unconfirmed.") }
        if Task.isCancelled { report.limitations.append("Collection was cancelled; this report is partial.") }
        // A truncated candidate scan cannot establish uniqueness, and a cancelled
        // preflight must never return a usable selection to an app's startup path.
        let discovery: ProxydDiscoveryResult
        if Task.isCancelled || candidates.count > 8 {
            discovery = .init(status: .permissionUnknown, candidates: inspected, selected: nil,
                reason: "Discovery is incomplete; no executable was selected.")
        } else {
            discovery = .evaluate(candidates: inspected, firewallState: report.firewallState, blockAll: blockAll)
        }
        report.proxyDiscovery = .init(status: discovery.status,
            selectedExecutable: discovery.selected.map { redactor.path($0.executable) }, reason: discovery.reason)
        return .init(report: report, discovery: discovery)
    }

    private static func summary(_ name: String, _ result: CommandResult, value: String? = nil) -> DiagnosticReport.ProbeSummary {
        .init(name: name, outcome: result.outcome, exitCode: result.exitCode,
              terminationSignal: result.terminationSignal,
              truncated: result.outputTruncated || result.errorTruncated,
              durationMilliseconds: result.durationMilliseconds, systemError: result.systemError,
              hadStandardError: !result.errorOutput.isEmpty, value: value)
    }

    private static func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    private static func manifests(candidatePaths: Set<String>) -> (items: [ServiceManifest], complete: Bool) {
        let manager = FileManager.default
        let directories = ["/System/Library/LaunchDaemons", "/System/Library/LaunchAgents",
                           "/Library/LaunchDaemons", "/Library/LaunchAgents",
                           manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path]
        var items: [ServiceManifest] = [], complete = true
        for directory in directories {
            if Task.isCancelled { return (items, false) }
            guard manager.fileExists(atPath: directory) else { continue }
            guard let entries = try? manager.contentsOfDirectory(atPath: directory) else { complete = false; continue }
            if entries.count > 4_096 { complete = false }
            for entry in entries.sorted().prefix(4_096) where entry.hasSuffix(".plist") {
                if Task.isCancelled { return (items, false) }
                let url = URL(fileURLWithPath: directory).appendingPathComponent(entry)
                guard let data = readManifest(url.path) else { complete = false; continue }
                if let item = ServiceManifestParser.parse(data, path: url.path, candidatePaths: candidatePaths) {
                    items.append(item)
                }
            }
        }
        // This agent's manifest is outside the normal *.plist directories in the
        // researched server binary. Absence is expected on some macOS versions.
        let agentPath = "/private/etc/com.apple.screensharing.agent.launchd"
        if manager.fileExists(atPath: agentPath) {
            if let data = readManifest(agentPath), let item = ServiceManifestParser.parse(data, path: agentPath, candidatePaths: candidatePaths) {
                items.append(item)
            } else { complete = false }
        }
        return (items, complete)
    }

    private static func readManifest(_ path: String) -> Data? {
        // Open before checking the type/size: avoid a stat/read race that could
        // turn a replaced plist into a blocking FIFO or an unbounded read.
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size >= 0, info.st_size <= 262_144,
              let data = try? handle.read(upToCount: 262_145), data.count <= 262_144 else { return nil }
        return data
    }
}
