import Foundation
import Testing
@testable import ProxyCore

@Suite struct IncomingExperimentOptionsTests {
    @Test func explicitInvocationSelectsOnlyTheIncomingResource() throws {
        let options = try IncomingExperimentOptions(arguments: [
            "incoming", "--remote", "192.0.2.1", "--output", "result.json",
            "--media-base", "6200", "--duration", "60",
        ])
        let config = options.configuration()
        #expect(config.mode == .incoming)
        #expect(config.remoteAddress == "192.0.2.1")
        #expect(config.mediaBase == 6200)
        #expect(options.duration == 60)
        #expect(options.output == "result.json")
    }

    @Test func missingDuplicateAndUnsupportedOptionsFailBeforeSpawning() {
        let required = ["incoming", "--remote", "192.0.2.1", "--output", "result.json"]
        for arguments in [
            [], ["incoming"], ["incoming", "--remote", "192.0.2.1"],
            required + ["--duration"], required + ["--remote", "192.0.2.2"],
            required + ["--ruby", "/tmp/other-ruby"], required + ["--include-private", "true"],
            ["collect", "--remote", "192.0.2.1", "--output", "result.json"],
        ] {
            #expect(throws: IncomingExperimentOptions.InvalidInvocation.self) {
                try IncomingExperimentOptions(arguments: arguments)
            }
        }
    }

    @Test func rejectsUnsafeTargetsAndUnboundedDurations() {
        for remote in ["localhost", "127.0.0.1", "0.0.0.0", "224.0.0.1", "192.0.2.255", "192.0.2.1;id", "::1"] {
            #expect(throws: IncomingExperimentOptions.InvalidInvocation.self) {
                try IncomingExperimentOptions(arguments: ["incoming", "--remote", remote, "--output", "result.json"])
            }
        }
        let required = ["incoming", "--remote", "192.0.2.1", "--output", "result.json"]
        for value in ["-1", "0", "9", "1201", "inf", "1.5"] {
            #expect(throws: IncomingExperimentOptions.InvalidInvocation.self) {
                try IncomingExperimentOptions(arguments: required + ["--duration", value])
            }
        }
        for value in ["0", "1023", "65534", "65535"] {
            #expect(throws: IncomingExperimentOptions.InvalidInvocation.self) {
                try IncomingExperimentOptions(arguments: required + ["--media-base", value])
            }
        }
    }
}
