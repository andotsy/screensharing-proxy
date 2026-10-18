import Foundation
import ProxyCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private struct ExperimentReport: Encodable {
    let schemaVersion = 5
    let experiment: String
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let requestedDurationSeconds: Int
    var elapsedSeconds = 0.0
    var termination = "starting"
    var relayReady = false
    var relayStopAcknowledged = false
    var receivedBytes: UInt64?
    var submittedBytes: UInt64?
    var receivedDatagrams: UInt64?
    var submittedDatagrams: UInt64?
    var forwardedToNativeBytes: UInt64?
    var forwardedToRemoteBytes: UInt64?
    var forwardedToNativeDatagrams: UInt64?
    var forwardedToRemoteDatagrams: UInt64?
    var droppedDatagrams: UInt64 = 0
    var failure: BackendFailureCode?
    var failureOperation: BackendOperation?
    var failureSystemError: BackendSystemError?
    var nativeTCPAccepted: Bool?
    var remoteTCPConnected: Bool?
    var nativeTCPReadClosed: Bool?
    var remoteTCPReadClosed: Bool?
    var nativeTCPConnectionCount: UInt64?
    var remoteTCPConnectionCount: UInt64?
    var completedTCPConnectionCount: UInt64?
    var lastTCPClosure: TCPClosureReason?
    var discardedTCPBytes: UInt64 = 0
    let highPerformanceSession = "unverified"
    let counterScope: String

    init(duration: Int, mode: RubyRelayConfiguration.Mode) {
        requestedDurationSeconds = duration
        if mode == .loopback {
            experiment = "loopback-ruby-tcp-udp"
            forwardedToNativeBytes = 0; forwardedToRemoteBytes = 0
            forwardedToNativeDatagrams = 0; forwardedToRemoteDatagrams = 0
            nativeTCPAccepted = false; remoteTCPConnected = false
            nativeTCPReadClosed = false; remoteTCPReadClosed = false
            nativeTCPConnectionCount = 0; remoteTCPConnectionCount = 0; completedTCPConnectionCount = 0
            counterScope = "Successful TCP/UDP socket submissions in each direction; datagram counts exclude TCP. Native authentication, decoding and input remain unverified."
        } else {
            experiment = "incoming-ruby-udp"
            receivedBytes = 0; submittedBytes = 0; receivedDatagrams = 0; submittedDatagrams = 0
            counterScope = "Received by Ruby; submitted to the local UDP stack. Submission does not prove Apple received, authenticated or decoded media. Outbound native feedback is not counted."
        }
    }
}

/// Synchronous callbacks arrive from the supervisor's worker. The lock protects
/// the finite aggregate and the first stop reason; no event history is retained.
private final class Observation: @unchecked Sendable {
    private let lock = NSLock()
    private var report: ExperimentReport
    private var stopReason: String?
    private let mode: RubyRelayConfiguration.Mode
    private let listenerPort: UInt16

    init(options: IncomingExperimentOptions) {
        mode = options.mode; listenerPort = options.listenerPort
        report = .init(duration: options.duration, mode: options.mode)
    }

    func record(_ envelope: BackendEnvelope) {
        lock.withLock {
            switch envelope.event {
            case .ready:
                report.relayReady = true
                if mode == .loopback {
                    status("Relay ready. Screen Sharing target: 127.0.0.1:\(listenerPort). Select High Performance when offered.\n")
                } else {
                    status("Relay ready. Connect Apple's Screen Sharing directly to the remote Mac in High Performance mode.\n")
                }
            case let .traffic(received, sent):
                if mode == .loopback {
                    report.forwardedToNativeBytes = received; report.forwardedToRemoteBytes = sent
                } else {
                    report.receivedBytes = received; report.submittedBytes = sent
                }
            case let .media(received, sent, dropped):
                if mode == .loopback {
                    report.forwardedToNativeDatagrams = received; report.forwardedToRemoteDatagrams = sent
                } else {
                    report.receivedDatagrams = received; report.submittedDatagrams = sent
                }
                report.droppedDatagrams = dropped
            case .stopped: report.relayStopAcknowledged = true
            case let .failed(code): report.failure = code
            case let .control(accepted, connected, nativeClosed, remoteClosed):
                report.nativeTCPAccepted = accepted; report.remoteTCPConnected = connected
                report.nativeTCPReadClosed = nativeClosed; report.remoteTCPReadClosed = remoteClosed
            case let .controlConnections(accepted, connected, completed):
                report.nativeTCPConnectionCount = accepted; report.remoteTCPConnectionCount = connected
                report.completedTCPConnectionCount = completed
            case let .connectionClosed(reason, discarded):
                report.lastTCPClosure = reason; report.discardedTCPBytes += discarded
            case let .failureContext(operation, systemError):
                report.failureOperation = operation; report.failureSystemError = systemError
            }
        }
    }

    func stop(_ reason: String) {
        lock.withLock { if stopReason == nil { stopReason = reason } }
    }

    func finish(_ result: RubyRelayRunResult, elapsed: Double) -> ExperimentReport {
        lock.withLock {
            report.elapsedSeconds = elapsed
            switch result {
            case .cancelled: report.termination = stopReason ?? "cancelled"
            case .failed(let failure):
                report.termination = "relayFailed"
                report.failure = failure
            case .exited(let code): report.termination = code == 0 ? "relayExited" : "relayFailed"
            }
            return report
        }
    }
}

private func status(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
}

@main
struct ProxyRelayExperiment {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["--help"] { print(usage); return }
        if arguments == ["--version"] {
            print("screensharing-proxy-experiment \(ProxyBuild.version)")
            return
        }
        do {
            let options = try IncomingExperimentOptions(arguments: arguments)
            #if os(macOS)
            exit(try await run(options))
            #else
            _ = options
            status("This experiment requires macOS and its system Ruby.\n")
            exit(2)
            #endif
        } catch {
            // Do not serialize filesystem errors, private paths or endpoints.
            if let invocation = error as? IncomingExperimentOptions.InvalidInvocation {
                status(invocation.description + "\n")
            } else {
                status("Could not create or save the report. Choose a new writable output path.\n")
            }
            exit(64)
        }
    }

    #if os(macOS)
    private static func run(_ options: IncomingExperimentOptions) async throws -> Int32 {
        // Reserve the report before opening any relay sockets. No replacement,
        // symlink traversal or private endpoint data in the resulting file.
        let fd = open(options.output, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try output.write(contentsOf: encoder.encode(ExperimentReport(duration: options.duration, mode: options.mode)))

        status("Experimental \(options.mode.rawValue) relay. Disconnect any existing session before starting.\n")
        if options.mode == .incoming {
            status("This incoming-only candidate failed a previously working live setup; retained for research.\n")
        }
        status("No working High Performance result is implied. Ctrl-C stops the relay and saves counters.\n")
        let observation = Observation(options: options)
        let started = ProcessInfo.processInfo.systemUptime
        // These dispositions affect this dedicated command only. Children get
        // normal signal handling from the shared process-spawn implementation.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let ready = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let viewer: Task<Void, Never>? = options.openViewer ? Task {
            for await _ in ready.stream {
                guard !Task.isCancelled else { return }
                // Launch Apple's public URL handler only after all sockets are
                // reserved. No saved connection, authentication or mode edits.
                let result = await BoundedCommandRunner().run(CommandSpec(
                    "/usr/bin/open", ["-b", "com.apple.ScreenSharing", "vnc://127.0.0.1:\(options.listenerPort)"],
                    timeout: 5, outputLimit: 4096
                ))
                guard !Task.isCancelled else { return }
                if result.succeeded {
                    status("Screen Sharing launch requested. Authenticate normally and choose High Performance when offered.\n")
                } else {
                    status("Could not open Screen Sharing. Use New Connection (Command-N), enter 127.0.0.1:\(options.listenerPort), then Connect.\n")
                }
                return
            }
        } : nil
        let relay = Task {
            await RubyRelayRunner().run(configuration: options.configuration(), onEvent: {
                observation.record($0)
                if options.openViewer, $0.event == .ready { ready.continuation.yield(()) }
            })
        }
        let signals = [SIGINT, SIGTERM, SIGHUP].map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                observation.stop("interrupted")
                viewer?.cancel()
                relay.cancel()
            }
            source.resume()
            return source
        }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(options.duration)) }
            catch { return }
            observation.stop("durationReached")
            viewer?.cancel()
            relay.cancel()
        }
        let result = await relay.value
        ready.continuation.finish()
        viewer?.cancel()
        await viewer?.value
        deadline.cancel()
        for source in signals { source.cancel() }
        let report = observation.finish(result, elapsed: ProcessInfo.processInfo.systemUptime - started)
        var data = try encoder.encode(report)
        data.append(10)
        try output.seek(toOffset: 0)
        try output.write(contentsOf: data)
        try output.truncate(atOffset: UInt64(data.count))
        try output.synchronize()
        if options.mode == .loopback {
            status("Report saved. Forwarded \(report.forwardedToNativeDatagrams ?? 0) datagrams to native, \(report.forwardedToRemoteDatagrams ?? 0) to remote; dropped \(report.droppedDatagrams).\n")
        } else {
            status("Report saved. Received \(report.receivedDatagrams ?? 0), locally submitted \(report.submittedDatagrams ?? 0), dropped \(report.droppedDatagrams) datagrams.\n")
        }
        if let failure = report.failure {
            status("Relay failure: \(failure.rawValue).\n")
            if let operation = report.failureOperation { status("Failure stage: \(operation.rawValue).\n") }
            if let systemError = report.failureSystemError { status("Socket error: \(systemError.rawValue).\n") }
            return 1
        }
        if case .exited(let code) = result, code != 0 { return 1 }
        if report.termination == "interrupted" { return 130 }
        return 0
    }
    #endif

    private static let usage = """
    screensharing-proxy-experiment loopback --remote IPv4 --output NEW.json [options]
    screensharing-proxy-experiment incoming --remote IPv4 --output NEW.json [options]

    Separate, unproven experiments using /usr/bin/ruby. Disconnect existing
    Screen Sharing sessions first and wait for 'Relay ready'. In loopback mode,
    connect Apple's client to 127.0.0.1 with TCP Port 15900 (or --listen-port),
    and select High Performance. TCP and both UDP directions go through Ruby.
    Incoming mode keeps TCP and outbound feedback direct; that candidate failed
    a working live setup and is retained for research. No interface, route,
    firewall or service configuration is changed. Existing owners cause failure.

      --remote IPv4       Numeric IPv4 address of the remote Mac (required).
      --output PATH       New owner-only JSON report (required; never overwritten).
      --media-base PORT   Existing UDP base on the Macs, 1024...65533 (default 5900).
      --duration SECONDS  Stop after 10...1200 seconds (default 600).
      --listen-port PORT  Loopback mode's local TCP port (default 15900).
      --remote-control-port PORT  Loopback mode's remote TCP port (default 5900).
      --open-viewer       Open Apple's Screen Sharing after loopback Relay ready.

    Ctrl-C, termination or the duration limit stops and reaps the owned Ruby child.
    Reports contain aggregate counters and OS version, without endpoints, payloads
    or credentials. Local submission does not prove delivery, decoding or feedback.
    Loopback mode permits login reconnections; idle TCP gaps time out after two minutes.
    Record video, audio, keyboard/mouse control and reconnect results separately.
    This command is not a working-proxy release and does not enable the app's tabs.

    Exit codes: 0 timed experiment/relay ended, 1 relay failure, 2 non-macOS,
    64 invalid invocation/report error, 130 interrupted with saved report.
    """
}
