import Foundation
import Testing
@testable import ProxyCore

private actor RuntimeRunner: CommandRunning {
    var commands: [CommandSpec] = []
    func run(_ spec: CommandSpec) async -> CommandResult {
        commands.append(spec)
        let listing = """
        1 : /usr/bin/python3
        (Allow incoming connections)
        2 : /Users/example/.pyenv/versions/3.12.12/bin/python3.12
        (Allow incoming connections)
        3 : /usr/bin/ruby
        (Block incoming connections)
        4 : /Applications/Python.app
        (Allow incoming connections)
        5 : /usr/bin/python3
        (Block incoming connections)
        """
        return .init(outcome: .exited, exitCode: spec.arguments == ["--listapps"] ? 0 : 1, terminationSignal: nil,
            output: Data((spec.arguments == ["--listapps"] ? listing : "").utf8), errorOutput: Data(),
            outputTruncated: false, errorTruncated: false, durationMilliseconds: 1, systemError: nil)
    }
}

@Suite("Allowed runtime evidence")
struct RuntimeEvidenceTests {
    @Test func identifiesVersionedInterpretersWithoutFalseMatches() {
        for name in ["python", "python3", "python3.12", "Python.app", "ruby", "ruby3.4"] {
            #expect(RuntimeEvidence.family("/usr/bin/" + name) != nil)
        }
        for name in ["python-helper", "python3evil", "notruby", "RubyMine.app", "Python Launcher.app"] {
            #expect(RuntimeEvidence.family(name) == nil)
        }
    }
    @Test func reportsRuntimesSeparatelyWithoutExecutingOrSelectingThem() async throws {
        let runner = RuntimeRunner()
        let report = await DiagnosticsCollector(runner: runner, platform: "macOS", scanManifests: false)
            .collect(try DiagnosticOptions(samples: 1))
        #expect(report.candidates.isEmpty && report.proxyDiscovery?.status == .notFound)
        #expect(report.runtimeCandidates.count == 4)
        #expect(report.runtimeCandidates.first { $0.firewallTarget == "/usr/bin/python3" }?.listedRule == "unknown")
        #expect(report.runtimeCandidates.first { $0.name == "python3.12" }?.listedRule == "allow")
        #expect(report.runtimeCandidates.first { $0.name == "ruby" }?.listedRule == "block")
        #expect(report.runtimeCandidates.allSatisfy { !$0.executionTested && !$0.forwardingVerified })
        #expect(!(await runner.commands).contains { RuntimeEvidence.family($0.executable) != nil })
        #expect(!String(decoding: try report.json(), as: UTF8.self).contains("/Users/example"))
    }
    @Test func bundleMetadataCannotEscapeItsExecutableDirectory() throws {
        for name in ["../python", "/usr/bin/python", "..", ".", "python\0suffix", ""] {
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": name], format: .binary, options: 0)
            #expect(RuntimeEvidence.bundleExecutable(data) == nil)
        }
        let valid = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Python"], format: .binary, options: 0)
        #expect(RuntimeEvidence.bundleExecutable(valid) == "Python")
    }
}
