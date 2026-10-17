import CProcessSupport
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct RubyRelayConfiguration: Encodable, Sendable {
    public enum Mode: String, Encodable, Sendable { case addressSeparated, incoming, loopback }
    public let version = 1
    public var mode = Mode.addressSeparated
    public let sessionID: UUID
    public let remoteAddress: String
    public var remoteControlPort: UInt16 = 5900
    public var mediaBase: UInt16 = 5900
    public var listenerAddress = "127.0.0.2"
    public var nativeAddress = "127.0.0.1"
    public var listenerPort: UInt16 = 15900
    public var externalAddress: String?

    public init(sessionID: UUID, remoteAddress: String) {
        self.sessionID = sessionID; self.remoteAddress = remoteAddress
    }

    public static func validRemoteAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts.allSatisfy({ part in UInt8(part).map { String($0) == String(part) } == true }),
              let first = UInt8(parts[0]), (1...223).contains(first), first != 127,
              let last = UInt8(parts[3]), last != 255 else { return false }
        return true
    }
}

public enum RubyRelayResources {
    public static var script: URL { Bundle.module.url(forResource: "relay", withExtension: "rb")! }
    public static var incomingScript: URL { Bundle.module.url(forResource: "incoming-relay", withExtension: "rb")! }
    public static var loopbackScript: URL { Bundle.module.url(forResource: "loopback-relay", withExtension: "rb")! }
}

public enum RubyRelayRunResult: Sendable, Equatable {
    case exited(Int32), cancelled, failed(BackendFailureCode)
}

private final class RelayCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    func cancel() { lock.withLock { requested = true } }
    var isCancelled: Bool { lock.withLock { requested } }
}

/// Long-lived adapter supervision, separate from bounded diagnostic commands.
/// Owns the child's stdin, stdout, process group, exit observation and reaping.
public struct RubyRelayRunner: Sendable {
    public let executable: String
    public let script: String?
    public init(executable: String = "/usr/bin/ruby", script: String? = nil) {
        self.executable = executable; self.script = script
    }

    public func run(configuration: RubyRelayConfiguration,
                    onEvent: @escaping @Sendable (BackendEnvelope) -> Void) async -> RubyRelayRunResult {
        let cancellation = RelayCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: execute(configuration, cancellation: cancellation, onEvent: onEvent))
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    private func execute(_ configuration: RubyRelayConfiguration, cancellation: RelayCancellation,
                         onEvent: @escaping @Sendable (BackendEnvelope) -> Void) -> RubyRelayRunResult {
        let resource: URL
        switch configuration.mode {
        case .addressSeparated: resource = RubyRelayResources.script
        case .incoming: resource = RubyRelayResources.incomingScript
        case .loopback: resource = RubyRelayResources.loopbackScript
        }
        let script = script ?? resource.path
        guard executable.hasPrefix("/"), script.hasPrefix("/"),
              !executable.utf8.contains(0), !script.utf8.contains(0),
              var input = try? JSONEncoder().encode(configuration), input.count < 4096 else {
            return .failed(.invalidConfiguration)
        }
        if cancellation.isCancelled { return .cancelled }
        input.append(10)
        let arguments: [String] = [executable, "--disable-gems", script]
        let argv = arguments.map { strdup($0) } + [nil]
        // Do not inherit RUBYOPT, RUBYLIB, GEM_* or arbitrary user startup hooks.
        let environment: [String] = ["PATH=/usr/bin:/bin", "LC_ALL=C"]
        let envp = environment.map { strdup($0) } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else {
            return .failed(.internalFailure)
        }
        var child = ssp_child()
        let spawnError = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                ssp_spawn_interactive(executable, args.baseAddress, env.baseAddress, &child)
            }
        }
        guard spawnError == 0 else { return .failed(.unavailable) }
        var inputFD = child.input_fd
        defer {
            if inputFD >= 0 { close(inputFD) }
            close(child.output_fd); close(child.error_fd)
        }
        // Suppress SIGPIPE only on this worker while writing the private pipe.
        // Do not alter the app's process-wide signal policy.
        var pipeSignal = sigset_t(), previousMask = sigset_t()
        sigemptyset(&pipeSignal); sigaddset(&pipeSignal, SIGPIPE)
        pthread_sigmask(SIG_BLOCK, &pipeSignal, &previousMask)
        defer {
            if sigismember(&previousMask, SIGPIPE) == 0 {
                var pending = sigset_t(); sigpending(&pending)
                if sigismember(&pending, SIGPIPE) != 0 { var signal: Int32 = 0; sigwait(&pipeSignal, &signal) }
            }
            pthread_sigmask(SIG_SETMASK, &previousMask, nil)
        }
        var decoder = BackendLineDecoder(), inputOffset = 0
        var failure: BackendFailureCode?
        var ready = false, outputEOF = false
        var frameWindow = ProcessInfo.processInfo.systemUptime, framesInWindow = 0
        let started = ProcessInfo.processInfo.systemUptime
        var stopAt: TimeInterval?, sentTERM = false, sentKILL = false
        var errorBytes = 0
        var buffer = [UInt8](repeating: 0, count: 8192)
        func receive(_ bytes: Data) throws {
            let now = ProcessInfo.processInfo.systemUptime
            if now - frameWindow >= 1 { frameWindow = now; framesInWindow = 0 }
            for event in try decoder.feed(bytes) {
                framesInWindow += 1
                guard framesInWindow <= 32, event.sessionID == configuration.sessionID else {
                    throw BackendProtocolError.invalidMessage
                }
                switch event.event {
                case .ready:
                    guard !ready else { throw BackendProtocolError.invalidMessage }
                    ready = true
                case .traffic, .media:
                    guard ready else { throw BackendProtocolError.invalidMessage }
                case let .failed(code): failure = code
                case .stopped: break
                }
                onEvent(event)
            }
        }
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            // Check ownership before any cancellation signal. ECHILD means a
            // foreign reaper invalidated our guarantee against PID reuse.
            let observation = ssp_has_exited(child.pid)
            if observation == -ECHILD { return .failed(.internalFailure) }
            if observation < 0 { failure = .internalFailure }
            if !ready && now - started > 8 && stopAt == nil { failure = .connectionTimedOut }
            if cancellation.isCancelled || failure != nil {
                if stopAt == nil {
                    stopAt = now
                    if inputFD >= 0 { close(inputFD); inputFD = -1 }
                }
            }
            if let stopAt {
                if now - stopAt >= 1 && !sentTERM { _ = ssp_signal_group(child.pid, SIGTERM); sentTERM = true }
                if now - stopAt >= 2 && !sentKILL { _ = ssp_signal_group(child.pid, SIGKILL); sentKILL = true }
            }
            if inputFD >= 0 && inputOffset < input.count {
                let count = input.withUnsafeBytes { bytes in
                    write(inputFD, bytes.baseAddress!.advanced(by: inputOffset), input.count - inputOffset)
                }
                if count > 0 { inputOffset += count }
                else if count < 0 && errno != EAGAIN && errno != EINTR { failure = .incompatibleProtocol }
            }
            // Limit work per iteration so a flooding child cannot starve stop/exit.
            for _ in 0..<8 where !outputEOF {
                let count = read(child.output_fd, &buffer, buffer.count)
                if count == 0 { outputEOF = true; break }
                if count < 0 {
                    if errno != EAGAIN && errno != EINTR { failure = .incompatibleProtocol }
                    break
                }
                do {
                    try receive(Data(buffer.prefix(count)))
                } catch { failure = .incompatibleProtocol }
            }
            for _ in 0..<8 {
                let count = read(child.error_fd, &buffer, buffer.count)
                if count <= 0 { break }
                errorBytes += count // Never retain or publish Ruby stderr/private paths.
                if errorBytes > 65_536 { failure = .incompatibleProtocol; break }
            }
            let exited = ssp_has_exited(child.pid)
            if exited == -ECHILD { return .failed(.internalFailure) }
            if exited == 1 {
                // PID is still reserved by the unreaped child. Clean descendants first.
                _ = ssp_signal_group(child.pid, SIGKILL)
                // Drain final complete frames from the now-dead child.
                for _ in 0..<16 where !outputEOF {
                    let count = read(child.output_fd, &buffer, buffer.count)
                    if count <= 0 { outputEOF = true; break }
                    do {
                        try receive(Data(buffer.prefix(count)))
                    } catch { failure = .incompatibleProtocol }
                }
                do { try decoder.finish() } catch { failure = .incompatibleProtocol }
                var exitCode: Int32 = -1, signal: Int32 = 0
                let reapError = ssp_reap(child.pid, &exitCode, &signal)
                if cancellation.isCancelled { return .cancelled }
                if let failure { return .failed(failure) }
                if reapError != 0 || signal != 0 { return .failed(.internalFailure) }
                return .exited(exitCode)
            }
            if outputEOF && stopAt == nil { failure = .incompatibleProtocol }
            var descriptor = pollfd(fd: outputEOF ? -1 : child.output_fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 40)
        }
    }
}
