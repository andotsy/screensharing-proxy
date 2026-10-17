import Foundation
import Testing
@testable import ProxyCore

private actor PerformanceRunner: CommandRunning {
    var processCalls = 0
    var commands: [CommandSpec] = []
    let failed: Bool
    init(failed: Bool = false) { self.failed = failed }
    func run(_ spec: CommandSpec) async -> CommandResult {
        commands.append(spec)
        var text = "", error = "", code: Int32 = 0
        switch spec.executable {
        case "/bin/ps":
            processCalls += 1
            text = "42 Sat Oct 17 10:00:00 2026 /usr/libexec/avconferenced\n"
                + "43 Sat Oct 17 10:00:00 2026 /Users/alice/Screen Sharing.app/Contents/MacOS/Screen Sharing\n"
                + "44 Sat Oct 17 10:00:00 2026 /Users/alice/unknown\n"
            if processCalls == 1 { text += "45 Sat Oct 17 10:00:00 2026 /usr/libexec/screensharingd\n" }
        case "/usr/sbin/lsof":
            text = "p43\0cScreen Sharing\0\nf3\0tIPv4\0PUDP\0n127.0.0.2:5901\0\n"
                + "p44\0cunknown\0\nf4\0tIPv4\0PUDP\0n192.0.2.4:6101->192.0.2.5:6101\0\n"
                + "f5\0tIPv4\0PTCP\0n192.0.2.4:40000->192.0.2.5:5900\0TST=ESTABLISHED\0\n"
                + "f6\0tIPv4\0PUDP\0n192.0.2.4:6109->192.0.2.5:6109\0\n"
        case "/usr/bin/defaults": text = "{ portBase = 6100; credential = \"secret-value\"; }"
        case "/usr/libexec/ApplicationFirewall/socketfilterfw":
            if spec.arguments == ["--listapps"] {
                text = "1 : /Users/alice/Screen Sharing.app\n(Block incoming connections)\n"
                    + "2 : /usr/libexec/avconferenced\n(Allow incoming connections)\n"
            } else if spec.arguments.first == "--getappblocked" { text = "The application is not blocked." }
        case "/usr/bin/codesign":
            if spec.arguments.contains("--entitlements") {
                text = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>com.apple.private.network.socket-delegate</key><true/></dict></plist>"
            } else if spec.arguments.first == "--display" { error = "Identifier=com.apple.fixture\n" }
        default: code = 1
        }
        return .init(outcome: .exited, exitCode: failed ? 1 : code, terminationSignal: nil,
            output: Data(text.utf8), errorOutput: Data(error.utf8), outputTruncated: failed,
            errorTruncated: false, durationMilliseconds: 1, systemError: nil)
    }
}

private struct PerformanceInspector: ExecutableInspecting {
    func inspect(_ path: String) -> ExecutableInspection { .init(resolvedPath: path, accessible: true) }
}

@Suite("High Performance diagnostic evidence")
struct PerformanceEvidenceTests {
    @Test func componentsAreNotProxyCandidatesAndKeepConflictingRulesSeparate() async throws {
        let report = await DiagnosticsCollector(runner: PerformanceRunner(), platform: "macOS", scanManifests: false,
            executableInspector: PerformanceInspector()).collect(try DiagnosticOptions(samples: 1, capturePhase: "baseline"))
        #expect(report.schemaVersion == 2)
        #expect(report.capturePhase == "baseline")
        #expect(report.candidates.isEmpty)
        #expect(report.proxyDiscovery?.status == .notFound)
        let app = try #require(report.components.first { $0.sources.contains("processSnapshot") && $0.roleHint == "viewerClient" })
        let bundle = try #require(app.firewallChecks.first { $0.targetKind == "enclosingBundle" })
        #expect(bundle.listedRule == "block")
        #expect(bundle.queriedRule == "allow")
        let av = try #require(report.components.first { $0.executable == "/usr/libexec/avconferenced" })
        #expect(av.socketDelegationEntitlement == true)
        #expect(av.signingIdentifier == "com.apple.fixture")
        #expect(report.samples[0].processes.contains { $0.pid == 42 && $0.observation == "beforeAndAfter" })
        #expect(!report.samples[0].sockets.contains { $0.pid == 42 })
        #expect(report.samples[0].processes.contains { $0.pid == 45 && $0.observation == "beforeOnly" })
        #expect(report.samples[0].sockets[0].localAddressKind == "loopback")
        #expect(report.samples[0].sockets[1].selectionReason == "portHint")
        #expect(report.samples[0].sockets[1].portHints == ["localHostPreferencePortRange"])
        #expect(report.samples[0].sockets[2].portHints == ["documentedDefaultPortRange"])
        #expect(report.samples[0].sockets[3].selectionReason == "unattributedUDPSocket")
        #expect(report.mediaPortConfiguration.observedHostPreferenceUDPBase == 6100)
        #expect(report.mediaPortConfiguration.activeSessionUDPBase == "unknown")
        let json = String(decoding: try report.json(), as: UTF8.self)
        for secret in ["/Users/alice", "192.0.2.", "127.0.0.2", "secret-value", "credential"] { #expect(!json.contains(secret)) }
    }

    @Test func failedOrTruncatedProbesCannotEstablishPreferencesOrEntitlements() async throws {
        let report = await DiagnosticsCollector(runner: PerformanceRunner(failed: true), platform: "macOS", scanManifests: false,
            executableInspector: PerformanceInspector()).collect(try DiagnosticOptions(samples: 1))
        #expect(report.mediaPortConfiguration.observedHostPreferenceUDPBase == nil)
        #expect(report.mediaPortConfiguration.preferenceStatus == "unavailableOrIncomplete")
        #expect(report.components.allSatisfy { $0.socketDelegationEntitlement == nil && $0.signingIdentifier == nil })
        #expect(report.samples[0].processes.isEmpty)
        #expect(!report.samples[0].complete)
    }

    @Test func validatesOnlyPortBaseAndNeverWrapsPortRange() throws {
        for raw: Any in [true, 1023, 65536, 6100.5, "6100 trailing", [6100]] {
            let data = try PropertyListSerialization.data(fromPropertyList: ["portBase": raw], format: .xml, options: 0)
            #expect(PerformanceEvidence.portBase(data) == nil)
        }
        #expect(PerformanceEvidence.portBase(Data("{ portBase = 65535; }".utf8)) == 65535)
        let parsed = LsofParser.parse(Data("p42\0cx\0\nf3\0tIPv4\0PUDP\0n*:1\0\n".utf8))
        #expect(!PerformanceEvidence.portMatches(try #require(parsed.sockets.first), base: 65535))
        #expect(throws: DiagnosticOptions.ValidationError.self) { try DiagnosticOptions(capturePhase: "invalid") }
    }

    @Test func classifiesWildcardAndLoopbackBindingsWithoutPrivateAddresses() {
        for address in ["*", "::", "0.0.0.0"] { #expect(PerformanceEvidence.addressKind(address) == "wildcard") }
        for address in ["127.0.0.2", "::1", "::1%lo0", "::ffff:127.0.0.1"] { #expect(PerformanceEvidence.addressKind(address) == "loopback") }
        #expect(PerformanceEvidence.addressKind("fe80::123%en0") == "nonLoopback")
    }

    @Test func redactionScopeKeepsPairedIdentitiesButDoesNotLinkUnrelatedCaptures() {
        let scope = DiagnosticRedactionScope()
        let first = ScopedReportRedactor(scope: scope, includePrivate: false)
        let second = ScopedReportRedactor(scope: scope, includePrivate: false)
        let token = first.address("192.0.2.1")
        _ = second.address("192.0.2.2")
        #expect(second.address("192.0.2.1") == token)
        #expect(first.path("/Users/alice/tool") == second.path("/Users/alice/tool"))
        #expect(scope.id != DiagnosticRedactionScope().id)
        #expect(ScopedReportRedactor(scope: scope, includePrivate: true).address("192.0.2.1") == "192.0.2.1")
    }

    @Test func sessionAgentManifestIncludesOnlySafeFields() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "Label": "com.apple.screensharing.agent", "ProgramArguments": ["/usr/libexec/ScreensharingAgent", "secret"],
            "EnvironmentVariables": ["TOKEN": "secret"], "MachServices": ["com.apple.screensharing.agent": true],
        ], format: .binary, options: 0)
        let manifest = try #require(ServiceManifestParser.parse(data, path: "/private/etc/com.apple.screensharing.agent.launchd", candidatePaths: []))
        #expect(manifest.program == "/usr/libexec/ScreensharingAgent")
        #expect(manifest.machServices == ["com.apple.screensharing.agent"])
        #expect(PerformanceComponent.role(manifest.program!) == "sessionAgent")
    }
}
