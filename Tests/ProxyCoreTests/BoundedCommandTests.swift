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

    @Test func cancellationEscalatesAfterChildInstallsTermHandler() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssp-term-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("ready")
        // A short wall-clock deadline can fire before /bin/sh installs its
        // handler on a busy runner. Synchronize with the child before testing
        // escalation; cancellation uses the same TERM/KILL path as timeout.
        let task = Task {
            await runner.run(CommandSpec("/bin/sh", ["-c",
                "trap '' TERM; printf ready > \"$1\"; while :; do :; done", "ssp-fixture", marker.path], timeout: 10))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var ready = false
        while ContinuousClock.now < deadline {
            if (try? Data(contentsOf: marker)) == Data("ready".utf8) { ready = true; break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let cancelledAt = ContinuousClock.now
        task.cancel()
        let result = await task.value // Always reap before asserting readiness.
        try #require(ready)
        #expect(result.outcome == .cancelled)
        #expect(result.terminationSignal == 9)
        #expect(cancelledAt.duration(to: .now) < .seconds(4))
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
