import Foundation
import Testing
@testable import ProxyCore

@Suite("Owned subprocess lifecycle")
struct BoundedCommandTests {
    let runner = BoundedCommandRunner()

    @Test func preservesExitAndBothStreams() async {
        let result = await runner.run(CommandSpec("/bin/sh", ["-c", "printf out; printf err >&2; exit 7"]))
        #expect(result.outcome == .exited)
        #expect(result.exitCode == 7)
        #expect(result.text == "out")
        #expect(String(decoding: result.errorOutput, as: UTF8.self) == "err")
        #expect(!result.succeeded)
    }

    @Test func drainsBothFloodedPipesAndKillsProcessGroup() async {
        let result = await runner.run(CommandSpec("/bin/sh", ["-c", "yes output & yes error >&2 & wait"], timeout: 0.2, outputLimit: 128))
        #expect(result.outcome == .timedOut)
        #expect(result.output.count == 128)
        #expect(result.errorOutput.count == 128)
        #expect(result.outputTruncated && result.errorTruncated)
        #expect(result.durationMilliseconds < 4_000)
    }

    @Test func escalatesWhenTerminationIgnored() async {
        let result = await runner.run(CommandSpec("/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.15))
        #expect(result.outcome == .timedOut)
        #expect(result.terminationSignal == 9)
        #expect(result.durationMilliseconds < 4_000)
    }

    @Test func cleansUpDescendantHoldingPipesAfterRootExits() async {
        let result = await runner.run(CommandSpec("/bin/sh", ["-c", "sleep 30 & printf spawned; exit 9"], timeout: 2))
        #expect(result.outcome == .exited)
        #expect(result.exitCode == 9)
        #expect(result.text == "spawned")
        #expect(result.durationMilliseconds < 1_500)
        #expect(!result.outputTruncated)
    }

    @Test func cancellationWaitsForCleanup() async throws {
        let task = Task { await runner.run(CommandSpec("/bin/sh", ["-c", "sleep 30 & wait"], timeout: 30)) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.value
        #expect(result.outcome == .cancelled)
        #expect(result.durationMilliseconds < 4_000)
    }

    @Test func launchFailureIsNotAnExit() async {
        let result = await runner.run(CommandSpec("/this/executable/does/not/exist"))
        #expect(result.outcome == .launchFailed)
        #expect(result.exitCode == nil)
        #expect(result.systemError != nil)
    }

    @Test func argumentsAreLiteral() async {
        let result = await runner.run(CommandSpec("/usr/bin/printf", ["%s", "$(touch should-not-exist); `id` a b"]))
        #expect(result.text == "$(touch should-not-exist); `id` a b")
        #expect(result.complete)
    }

    @Test(arguments: [Double.nan, Double.infinity, 0, -1, 301])
    func rejectsInvalidDeadlines(timeout: Double) async {
        let result = await runner.run(CommandSpec("/bin/sh", timeout: timeout))
        #expect(result.outcome == .launchFailed)
    }

    @Test func rejectsNulArgumentsAndRelativeExecutables() async {
        #expect(await runner.run(CommandSpec("/bin/sh", ["bad\0argument"])).outcome == .launchFailed)
        #expect(await runner.run(CommandSpec("sh")).outcome == .launchFailed)
    }
}
