import Foundation
import ProxyCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private struct ExperimentReport: Encodable {
    let schemaVersion = 1
    let experiment = "incoming-ruby-udp"
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let requestedDurationSeconds: Int
    var elapsedSeconds = 0.0
    var termination = "starting"
    var relayReady = false
    var relayStopAcknowledged = false
    var receivedBytes: UInt64 = 0
    var submittedBytes: UInt64 = 0
    var receivedDatagrams: UInt64 = 0
    var submittedDatagrams: UInt64 = 0
    var droppedDatagrams: UInt64 = 0
    var failure: BackendFailureCode?
    let highPerformanceSession = "unverified"
    let counterScope = "Received by Ruby; submitted to the local UDP stack. Submission does not prove Apple received, authenticated or decoded media. Outbound native feedback is not counted."
}

/// Synchronous callbacks arrive from the supervisor's worker. The lock protects
/// the finite aggregate and the first stop reason; no event history is retained.
private final class Observation: @unchecked Sendable {
    private let lock = NSLock()
    private var report: ExperimentReport
    private var stopReason: String?

    init(duration: Int) { report = .init(requestedDurationSeconds: duration) }

    func record(_ envelope: BackendEnvelope) {
        lock.withLock {
            switch envelope.event {
            case .ready:
                report.relayReady = true
                status("Relay ready. Connect Apple's Screen Sharing directly to the remote Mac in High Performance mode.\n")
            case let .traffic(received, sent):
                report.receivedBytes = received
                report.submittedBytes = sent
            case let .media(received, sent, dropped):
                report.receivedDatagrams = received
                report.submittedDatagrams = sent
                report.droppedDatagrams = dropped
            case .stopped: report.relayStopAcknowledged = true
            case let .failed(code): report.failure = code
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
        try output.write(contentsOf: encoder.encode(ExperimentReport(requestedDurationSeconds: options.duration)))

        status("Experimental incoming UDP relay. Disconnect any existing session before starting.\n")
        status("No working High Performance result is implied. Ctrl-C stops the relay and saves counters.\n")
        let observation = Observation(duration: options.duration)
        let started = ProcessInfo.processInfo.systemUptime
        // These dispositions affect this dedicated command only. Children get
        // normal signal handling from the shared process-spawn implementation.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let relay = Task {
            await RubyRelayRunner().run(configuration: options.configuration(), onEvent: { observation.record($0) })
        }
        let signals = [SIGINT, SIGTERM, SIGHUP].map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                observation.stop("interrupted")
                relay.cancel()
            }
            source.resume()
            return source
        }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(options.duration)) }
            catch { return }
            observation.stop("durationReached")
            relay.cancel()
        }
        let result = await relay.value
        deadline.cancel()
        for source in signals { source.cancel() }
        let report = observation.finish(result, elapsed: ProcessInfo.processInfo.systemUptime - started)
        var data = try encoder.encode(report)
        data.append(10)
        try output.seek(toOffset: 0)
        try output.write(contentsOf: data)
        try output.truncate(atOffset: UInt64(data.count))
        try output.synchronize()
        status("Report saved. Received \(report.receivedDatagrams), locally submitted \(report.submittedDatagrams), dropped \(report.droppedDatagrams) datagrams.\n")
        if let failure = report.failure { status("Relay failure: \(failure.rawValue).\n"); return 1 }
        if case .exited(let code) = result, code != 0 { return 1 }
        if report.termination == "interrupted" { return 130 }
        return 0
    }
    #endif

    private static let usage = """
    screensharing-proxy-experiment incoming --remote IPv4 --output NEW.json [options]

    Separate, unproven incoming-UDP experiment using /usr/bin/ruby.
    Disconnect any existing Screen Sharing session first. Wait for 'Relay ready',
    then connect Apple's client directly to the remote Mac in High Performance mode.
    TCP and native outbound feedback remain direct. No interface, route, firewall
    or service configuration is changed. Existing UDP owners cause startup failure.

      --remote IPv4       Numeric IPv4 address of the remote Mac (required).
      --output PATH       New owner-only JSON report (required; never overwritten).
      --media-base PORT   Existing UDP base on the Macs, 1024...65533 (default 5900).
      --duration SECONDS  Stop after 10...1200 seconds (default 600).

    Ctrl-C, termination or the duration limit stops and reaps the owned Ruby child.
    Reports contain aggregate counters and OS version, without endpoints, payloads
    or credentials. Local submission does not prove delivery, decoding or feedback.
    Record video, audio, keyboard/mouse control and reconnect results separately.
    This command is not a working-proxy release and does not enable the app's tabs.

    Exit codes: 0 timed experiment/relay ended, 1 relay failure, 2 non-macOS,
    64 invalid invocation/report error, 130 interrupted with saved report.
    """
}
