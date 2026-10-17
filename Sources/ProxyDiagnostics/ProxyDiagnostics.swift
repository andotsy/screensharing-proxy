import Foundation
import ProxyCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct ProxyDiagnostics {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.isEmpty || args == ["--help"] { print(usage); return }
            if args == ["--version"] { print("screensharing-proxy-diagnose \(ProxyBuild.version)"); return }
            guard args.first == "collect" || args.first == "discover" else { throw CLIError("Expected 'collect' or 'discover'.") }
            let discoveryOnly = args.first == "discover"
            var remote: IPAddress?, samples = discoveryOnly ? 1 : 3, interval = 1.0, includePrivate = false
            var output: String?
            var phase = "snapshot"
            var index = 1
            var seen: Set<String> = []
            while index < args.count {
                let flag = args[index]
                guard seen.insert(flag).inserted else { throw CLIError("Duplicate option: \(flag)") }
                if flag == "--include-private" { includePrivate = true; index += 1; continue }
                guard index + 1 < args.count else { throw CLIError("Missing value for \(flag).") }
                let value = args[index + 1]
                switch flag {
                case "--remote":
                    guard let parsed = IPAddress(value) else { throw CLIError("--remote requires a numeric IPv4 or IPv6 address.") }
                    remote = parsed
                case "--samples":
                    guard let parsed = Int(value) else { throw CLIError("--samples requires an integer.") }
                    samples = parsed
                case "--interval":
                    guard let parsed = Double(value) else { throw CLIError("--interval requires seconds.") }
                    interval = parsed
                case "--output": output = value
                case "--phase": phase = value
                default: throw CLIError("Unknown option: \(flag)")
                }
                index += 2
            }
            let options = try DiagnosticOptions(remote: remote, samples: samples, interval: interval, includePrivate: includePrivate, capturePhase: phase)
            // Ignore only in the CLI and handle via a Dispatch source. The runner
            // restores normal signal disposition for every child it creates.
            signal(SIGINT, SIG_IGN)
            let collection = Task { await DiagnosticsCollector().inspect(options) }
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            interrupt.setEventHandler { collection.cancel() }
            interrupt.resume()
            let collected = await collection.value
            let report = collected.report
            interrupt.cancel()
            var data = try report.json()
            data.append(10)
            if let output {
                // Exclusive creation avoids overwriting existing reports, and
                // owner-only permissions protect an opt-in private report.
                let fd = open(output, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
                guard fd >= 0 else { throw CLIError("Could not create report (errno \(errno)); choose a new output path.") }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                do { try handle.write(contentsOf: data); try handle.close() }
                catch { try? handle.close(); throw error }
            } else { try FileHandle.standardOutput.write(contentsOf: data) }
            if collection.isCancelled { exit(130) }
            if report.platform != "macOS" { exit(2) }
            if discoveryOnly && collected.discovery.status != .selected { exit(3) }
        } catch {
            let text = "\(error)\nUse --help for usage.\n"
            try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
            exit(64)
        }
    }

    struct CLIError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static let usage = """
    screensharing-proxy-diagnose collect [options]
    screensharing-proxy-diagnose discover [options]
    screensharing-proxy-diagnose --version

    Read-only macOS evidence collection; does not start a proxy or change the firewall.
    discover automatically locates/selects an explicitly allowed proxyd (one snapshot).
      --remote IP          Match sockets for this numeric remote IP, including unknown process names.
      --samples N          Socket snapshots, 1...10 (default 3).
      --interval SECONDS   Pause between snapshots, 0.2...5 (default 1).
      --phase NAME         Label as snapshot (default), baseline, or duringSession.
      --output PATH        Create a new owner-only JSON report; otherwise write to stdout.
      --include-private    Include private addresses and full executable paths.

    Reports redact private addresses/paths by default. No packet payloads, process
    arguments or environment variables are collected. Ctrl-C writes a partial report.
    A report is diagnostic evidence, not proof of High Performance relay readiness.
    Use the app for paired captures with comparable redacted address/path tokens.
    Exit codes: 0 collected/selected, 2 unsupported platform, 3 discovery unresolved,
    64 invalid invocation/output error, 130 interrupted (partial report).
    """
}
