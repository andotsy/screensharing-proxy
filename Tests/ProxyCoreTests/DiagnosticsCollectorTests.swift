import Foundation
import Testing
@testable import ProxyCore

private actor FixtureRunner: CommandRunning {
    var processCalls = 0
    let changeIdentity: Bool
    let failedFirewall: Bool
    let truncatedSockets: Bool
    let proxyPath: String
    let listHasProxy: Bool
    var commands: [CommandSpec] = []
    init(changeIdentity: Bool = false, failedFirewall: Bool = false, truncatedSockets: Bool = false,
         proxyPath: String = "/usr/libexec/proxyd", listHasProxy: Bool = true) {
        self.changeIdentity = changeIdentity; self.failedFirewall = failedFirewall; self.truncatedSockets = truncatedSockets
        self.proxyPath = proxyPath; self.listHasProxy = listHasProxy
    }
    func run(_ spec: CommandSpec) async -> CommandResult {
        commands.append(spec)
        var text = "", error = "", code: Int32 = 0, truncated = false
        switch spec.executable {
        case "/bin/ps":
            processCalls += 1
            let start = changeIdentity && processCalls > 1 ? "11:00:00" : "10:00:00"
            text = "42 Sat Oct 17 \(start) 2026 \(proxyPath)\n43 Sat Oct 17 10:00:00 2026 /Users/alice/private/receiver\n"
        case "/usr/sbin/lsof":
            text = "p42\0cproxyd\0\nf3\0tIPv4\0PUDP\0n192.0.2.4:5901->192.0.2.5:5902\0\n"
                + "p43\0creceiver\0\nf4\0tIPv4\0PUDP\0n*:5903\0\n"
            truncated = truncatedSockets
        case "/usr/libexec/ApplicationFirewall/socketfilterfw":
            if failedFirewall { code = 1; error = "permission denied /Users/alice/private" }
            else if spec.arguments == ["--listapps"] { text = listHasProxy ? "1 : \(proxyPath)\n(Allow incoming connections)\n" : "ALF: total number of apps = 0\n" }
            else if spec.arguments == ["--getglobalstate"] { text = "Firewall is enabled. (State = 1)" }
            else if spec.arguments == ["--getblockall"] { text = "Block all DISABLED!" }
            else if spec.arguments.first == "--getappblocked" { text = "The application is not blocked." }
        case "/usr/bin/codesign":
            if spec.arguments.first == "--display" { error = "Executable=/usr/libexec/proxyd\nIdentifier=com.apple.proxyd\nTeamIdentifier=not set\n" }
        case "/usr/bin/sw_vers": text = "ProductName: macOS\nProductVersion: 26.0\nBuildVersion: fixture\n"
        case "/usr/bin/uname": text = "arm64\n"
        default: code = 1
        }
        return CommandResult(outcome: .exited, exitCode: code, terminationSignal: nil,
            output: Data(text.utf8), errorOutput: Data(error.utf8), outputTruncated: truncated,
            errorTruncated: false, durationMilliseconds: 1, systemError: nil)
    }
}

private struct FixtureExecutableInspector: ExecutableInspecting {
    func inspect(_ path: String) -> ExecutableInspection { .init(resolvedPath: path, accessible: true) }
}

@Suite("Read-only collection")
struct DiagnosticsCollectorTests {
    @Test func cancelledDiscoveryNeverSelectsAnExecutable() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await DiagnosticsCollector(runner: FixtureRunner(), platform: "macOS", scanManifests: false,
                executableInspector: FixtureExecutableInspector()).inspect(try DiagnosticOptions(samples: 1))
        }
        let collected = try await task.value
        #expect(collected.discovery.selected == nil)
        #expect(collected.discovery.status == .permissionUnknown)
    }

    @Test func automaticallySelectsAllowedProxyWithoutPathInput() async throws {
        let collected = await DiagnosticsCollector(runner: FixtureRunner(), platform: "macOS", scanManifests: false,
            executableInspector: FixtureExecutableInspector()).inspect(try DiagnosticOptions(samples: 1))
        #expect(collected.discovery.status == .selected)
        #expect(collected.discovery.selected?.executable == "/usr/libexec/proxyd")
        #expect(collected.report.proxyDiscovery?.selectedExecutable == "/usr/libexec/proxyd")
        #expect(collected.report.highPerformanceRelay == "notVerified")
    }

    @Test func discoversRunningProxyThenQueriesItsIncomingRule() async throws {
        let runner = FixtureRunner(proxyPath: "/Users/alice/tools/proxyd", listHasProxy: false)
        let collected = await DiagnosticsCollector(runner: runner, platform: "macOS", scanManifests: false,
            executableInspector: FixtureExecutableInspector()).inspect(try DiagnosticOptions(samples: 1))
        #expect(collected.discovery.status == .selected)
        #expect(collected.discovery.selected?.executable == "/Users/alice/tools/proxyd")
        #expect(collected.discovery.selected?.ruleSource == "getappblocked")
        #expect(collected.report.proxyDiscovery?.selectedExecutable?.hasPrefix("private-path-") == true)
        #expect(collected.report.proxyDiscovery?.selectedExecutable == collected.report.candidates.first?.executable)
        #expect(!String(decoding: try collected.report.json(), as: UTF8.self).contains("/Users/alice"))
        #expect(await runner.commands.contains { $0.arguments == ["--getappblocked", "/Users/alice/tools/proxyd"] })
    }

    @Test func reportRedactsPrivateDataAndNeverClaimsRelayReadiness() async throws {
        let runner = FixtureRunner()
        let report = await DiagnosticsCollector(runner: runner, platform: "macOS", scanManifests: false)
            .collect(try DiagnosticOptions(remote: IPAddress("192.0.2.5"), samples: 1))
        #expect(report.candidates.count == 1)
        #expect(report.candidates.first?.listedFirewallRule == "allow")
        #expect(report.candidates.first?.signatureVerified == true)
        #expect(report.highPerformanceRelay == "notVerified")
        #expect(report.samples.first?.sockets.first?.ownershipEvidence == "consistentProcessSnapshots")
        #expect(report.samples.first?.sockets.last?.selectionReason == "unattributedUDPListener")
        let json = String(decoding: try report.json(), as: UTF8.self)
        #expect(!json.contains("192.0.2."))
        #expect(!json.contains("/Users/alice"))
        #expect(json.contains("address-1"))
        let commands = await runner.commands
        #expect(commands.filter { $0.executable.hasSuffix("socketfilterfw") }.allSatisfy {
            ["--getglobalstate", "--getblockall", "--getallowsigned", "--listapps"].contains($0.arguments[0])
        })
    }

    @Test func changingProcessIdentityIsUnresolved() async throws {
        let report = await DiagnosticsCollector(runner: FixtureRunner(changeIdentity: true), platform: "macOS", scanManifests: false)
            .collect(try DiagnosticOptions(samples: 1))
        #expect(report.samples[0].sockets[0].ownershipEvidence == "unresolved")
        #expect(report.samples[0].sockets[0].executable == nil)
    }

    @Test func failedFirewallAndTruncatedSocketsStayUnknown() async throws {
        let report = await DiagnosticsCollector(runner: FixtureRunner(failedFirewall: true, truncatedSockets: true), platform: "macOS", scanManifests: false)
            .collect(try DiagnosticOptions(samples: 1))
        #expect(report.firewallState == "unknown")
        #expect(report.candidates.first?.listedFirewallRule == "unknown")
        #expect(report.samples[0].complete == false)
        #expect(report.highPerformanceRelay == "notVerified")
    }

    @Test func unsupportedPlatformRunsNoCommands() async throws {
        let runner = FixtureRunner()
        let report = await DiagnosticsCollector(runner: runner, platform: "unsupported", scanManifests: false)
            .collect(try DiagnosticOptions())
        #expect(await runner.commands.isEmpty)
        #expect(report.samples.isEmpty)
        #expect(!report.limitations.isEmpty)
    }

    @Test func privateDetailsRequireExplicitOption() async throws {
        let report = await DiagnosticsCollector(runner: FixtureRunner(), platform: "macOS", scanManifests: false)
            .collect(try DiagnosticOptions(samples: 1, includePrivate: true))
        let json = String(decoding: try report.json(), as: UTF8.self)
        #expect(json.contains("192.0.2.5"))
        #expect(json.contains("/Users/alice/private/receiver"))
    }
}
