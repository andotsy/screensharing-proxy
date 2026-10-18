import CProcessSupport
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct CommandSpec: Sendable {
    public let executable: String
    public let arguments: [String]
    public let timeout: TimeInterval
    public let outputLimit: Int

    public init(_ executable: String, _ arguments: [String] = [],
                timeout: TimeInterval = 3, outputLimit: Int = 131_072) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.outputLimit = outputLimit
    }
}

public struct CommandResult: Sendable, Codable, Equatable {
    public enum Outcome: String, Sendable, Codable { case exited, timedOut, cancelled, launchFailed, supervisionFailed }
    public let outcome: Outcome
    public let exitCode: Int32?
    public let terminationSignal: Int32?
    public let output: Data
    public let errorOutput: Data
    public let outputTruncated: Bool
    public let errorTruncated: Bool
    public let durationMilliseconds: Int
    public let systemError: Int32?

    public var succeeded: Bool { outcome == .exited && exitCode == 0 }
    public var complete: Bool { succeeded && !outputTruncated && !errorTruncated }
    public var text: String { String(decoding: output, as: UTF8.self) }
}

public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async -> CommandResult
}

// The sole shared mutable value is protected by this lock. The worker never
// shares child descriptors or PID ownership with the cancellation callback.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.withLock { value = true } }
    var isCancelled: Bool { lock.withLock { value } }
}

public struct BoundedCommandRunner: CommandRunning {
    private let outputHandler: (@Sendable (Data, Bool) -> Void)?
    public init(outputHandler: (@Sendable (Data, Bool) -> Void)? = nil) { self.outputHandler = outputHandler }

    public func run(_ spec: CommandSpec) async -> CommandResult {
        let flag = CancellationFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.execute(spec, cancellation: flag, outputHandler: outputHandler))
                }
            }
        } onCancel: { flag.cancel() }
    }

    private static func execute(_ spec: CommandSpec, cancellation: CancellationFlag,
                                outputHandler: (@Sendable (Data, Bool) -> Void)?) -> CommandResult {
        let started = ProcessInfo.processInfo.systemUptime
        var output = Data(), errors = Data()
        var outputTruncated = false, errorTruncated = false
        func result(_ outcome: CommandResult.Outcome, exit: Int32? = nil,
                    signal: Int32? = nil, systemError: Int32? = nil) -> CommandResult {
            CommandResult(outcome: outcome, exitCode: exit, terminationSignal: signal,
                          output: output, errorOutput: errors, outputTruncated: outputTruncated,
                          errorTruncated: errorTruncated,
                          durationMilliseconds: Int((ProcessInfo.processInfo.systemUptime - started) * 1_000),
                          systemError: systemError)
        }
        guard spec.executable.hasPrefix("/"), !spec.executable.utf8.contains(0),
              spec.arguments.allSatisfy({ !$0.utf8.contains(0) }),
              spec.timeout.isFinite, spec.timeout > 0, spec.timeout <= 300,
              (1...4_194_304).contains(spec.outputLimit) else {
            return result(.launchFailed, systemError: EINVAL)
        }
        if cancellation.isCancelled { return result(.cancelled) }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        let argv = ([spec.executable] + spec.arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else {
            return result(.launchFailed, systemError: ENOMEM)
        }
        var child = ssp_child()
        let spawnError = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                ssp_spawn(spec.executable, args.baseAddress, env.baseAddress, &child)
            }
        }
        guard spawnError == 0 else { return result(.launchFailed, systemError: spawnError) }
        defer { close(child.output_fd); close(child.error_fd) }

        var outputEOF = false, errorEOF = false
        var stopReason: CommandResult.Outcome?
        var stopStarted: TimeInterval?
        var killedAt: TimeInterval?
        var hasExited = false
        var failure: Int32?

        // Fair fixed read budgets stop a busy stdout from starving stderr,
        // timeout checks or cancellation. Retain only the configured prefix.
        func drain(_ fd: Int32, into data: inout Data, eof: inout Bool, truncated: inout Bool, isError: Bool) {
            guard !eof else { return }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            for _ in 0..<4 {
                let count = read(fd, &buffer, buffer.count)
                if count == 0 { eof = true; return }
                if count < 0 {
                    if errno == EINTR { continue }
                    if errno != EAGAIN && errno != EWOULDBLOCK { failure = errno; eof = true }
                    return
                }
                let retained = min(count, max(0, spec.outputLimit - data.count))
                data.append(contentsOf: buffer.prefix(retained))
                if retained > 0 { outputHandler?(Data(buffer.prefix(retained)), isError) }
                if retained < count { truncated = true }
            }
        }

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if stopReason == nil {
                if cancellation.isCancelled { stopReason = .cancelled }
                else if now - started >= spec.timeout { stopReason = .timedOut }
                else if failure != nil { stopReason = .supervisionFailed }
                if stopReason != nil {
                    stopStarted = now
                    _ = ssp_signal_group(child.pid, SIGTERM)
                }
            }
            drain(child.output_fd, into: &output, eof: &outputEOF, truncated: &outputTruncated, isError: false)
            drain(child.error_fd, into: &errors, eof: &errorEOF, truncated: &errorTruncated, isError: true)
            if !hasExited {
                let observation = ssp_has_exited(child.pid)
                hasExited = observation == 1
                if observation < 0 {
                    // Another process-wide reaper would invalidate PID ownership.
                    // Never signal a PID/group after losing our unreaped child.
                    if observation == -ECHILD { return result(.supervisionFailed, systemError: ECHILD) }
                    failure = -observation
                }
            }
            // The child remains unreaped while signaling its process group,
            // so a reused PID can never target an unrelated new process.
            if killedAt == nil, hasExited || stopStarted.map({ now - $0 >= 0.2 }) == true {
                _ = ssp_signal_group(child.pid, SIGKILL)
                killedAt = now
            }
            if hasExited && outputEOF && errorEOF { break }
            // A detached descendant can keep a pipe open; it cannot hold the
            // collector forever. Detached services are not owned by this runner.
            if let killedAt, hasExited, now - killedAt >= 0.3 {
                outputTruncated = outputTruncated || !outputEOF
                errorTruncated = errorTruncated || !errorEOF
                break
            }
            var polls = [pollfd(fd: outputEOF ? -1 : child.output_fd, events: Int16(POLLIN), revents: 0),
                         pollfd(fd: errorEOF ? -1 : child.error_fd, events: Int16(POLLIN), revents: 0)]
            _ = polls.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 10) }
        }
        var exitCode: Int32 = -1, signal: Int32 = 0
        let reapError = ssp_reap(child.pid, &exitCode, &signal)
        if reapError != 0 { failure = reapError }
        return result(stopReason ?? (failure == nil ? .exited : .supervisionFailed),
                      exit: exitCode >= 0 ? exitCode : nil,
                      signal: signal == 0 ? nil : signal, systemError: failure)
    }
}
