import Foundation
#if os(macOS)
import Observation
#endif
import ProxyCore

@MainActor
#if os(macOS)
@Observable
#endif
public final class RelayModel {
    public enum Activity: Equatable { case idle, starting, listening, forwarding, stopping }
    public var remoteAddress = ""
    public var remotePort = 5900
    public var listenerPort = 15900
    public var mediaBase = 5900
    public private(set) var activity = Activity.idle
    public private(set) var message = "Enter the address of the Mac you want to control."
    public private(set) var report: RelaySessionReport?
    public private(set) var saving = false
    public private(set) var megabitsPerSecond = 0.0
    private let runner: any RelayRunning
    private let launcher: any ViewerLaunching
    private let saver: any DiagnosticArchiveSaving
    private var runnerTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var started = ProcessInfo.processInfo.systemUptime
    private var lastUpdate = ProcessInfo.processInfo.systemUptime
    private var lastBytes: UInt64 = 0
    private enum Update: Sendable { case event(BackendEnvelope), finished(RubyRelayRunResult) }

    public init(saver: any DiagnosticArchiveSaving, runner: any RelayRunning = RubyRelayRunner(),
                launcher: any ViewerLaunching = ScreenSharingLauncher()) {
        self.saver = saver; self.runner = runner; self.launcher = launcher
    }
    public var isRunning: Bool { activity != .idle }
    public var canConnect: Bool {
        !isRunning && !saving && RubyRelayConfiguration.validRemoteAddress(remoteAddress.trimmingCharacters(in: .whitespaces)) &&
        (1024...65535).contains(remotePort) && (1024...65535).contains(listenerPort) && (1024...65533).contains(mediaBase)
    }
    public func connect() {
        guard canConnect else { return }
        let id = UUID(); sessionID = id
        var configuration = RubyRelayConfiguration(sessionID: id, remoteAddress: remoteAddress.trimmingCharacters(in: .whitespaces))
        configuration.mode = .loopback
        configuration.remoteControlPort = UInt16(remotePort); configuration.listenerPort = UInt16(listenerPort)
        configuration.mediaBase = UInt16(mediaBase); configuration.maximumDurationSeconds = 0
        started = ProcessInfo.processInfo.systemUptime; lastUpdate = started; lastBytes = 0; megabitsPerSecond = 0
        report = RelaySessionReport(); activity = .starting; message = "Starting relay…"
        let (events, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(64))
        runnerTask = Task { [runner, configuration] in
            let result = await runner.run(configuration: configuration) { continuation.yield(.event($0)) }
            continuation.yield(.finished(result)); continuation.finish()
        }
        // Keep this consumer alive during stop so final counters and the stop
        // acknowledgement arrive before the process slot is released.
        eventsTask = Task { [weak self] in
            for await update in events {
                guard let self, self.sessionID == id else { continue }
                switch update {
                case let .event(envelope):
                    guard envelope.sessionID == id else { continue }
                    receive(envelope.event)
                case let .finished(result): finish(result)
                }
            }
            guard let self, self.sessionID == id else { return }
            self.launchTask?.cancel(); await self.launchTask?.value
            self.launchTask = nil; self.runnerTask = nil; self.eventsTask = nil; self.sessionID = nil
            self.activity = .idle; self.megabitsPerSecond = 0
        }
    }
    public func disconnect() {
        guard isRunning, activity != .stopping else { return }
        activity = .stopping; message = "Stopping relay…"
        launchTask?.cancel(); runnerTask?.cancel()
    }
    public func stop() async {
        disconnect(); saveTask?.cancel(); saver.cancel()
        await eventsTask?.value; await saveTask?.value
    }
    public func saveReport() {
        guard !saving, let report, let data = try? report.json() else { return }
        saving = true
        saveTask = Task { [weak self, saver] in
            let result = await saver.save(data)
            guard let self else { return }
            if case .failed = result { message = "Couldn’t save the session report. Try another location." }
            saving = false; saveTask = nil
        }
    }
    private func receive(_ event: BackendEvent) {
        report?.elapsedSeconds = ProcessInfo.processInfo.systemUptime - started
        switch event {
        case .ready:
            guard activity != .stopping else { return }
            activity = .listening; message = "Sign in in Screen Sharing. Choose High Performance when offered."
            let id = sessionID, port = UInt16(listenerPort)
            launchTask = Task { [weak self, launcher] in
                let opened = await launcher.open(port: port)
                guard let self, self.sessionID == id, !Task.isCancelled, self.isRunning else { return }
                if !opened { self.message = "Open Screen Sharing and connect to 127.0.0.1:\(port)." }
            }
        case let .traffic(received, sent):
            report?.forwardedToNativeBytes = received; report?.forwardedToRemoteBytes = sent
            let now = ProcessInfo.processInfo.systemUptime
            if now > lastUpdate, received >= lastBytes { megabitsPerSecond = Double(received - lastBytes) * 8 / (now - lastUpdate) / 1_000_000 }
            lastUpdate = now; lastBytes = received
        case let .media(received, sent, dropped):
            report?.forwardedToNativeDatagrams = received; report?.forwardedToRemoteDatagrams = sent; report?.droppedDatagrams = dropped
        case let .controlConnections(accepted, connected, completed):
            report?.nativeTCPConnectionCount = accepted; report?.remoteTCPConnectionCount = connected
            report?.completedTCPConnectionCount = completed
            guard activity != .stopping else { return }
            if connected > completed { activity = .forwarding; message = "Relay running. Keep this app open while sharing." }
            else if completed > 0 { activity = .listening; message = "Ready for Screen Sharing to reconnect." }
        case .control: break
        case let .connectionClosed(reason, discarded):
            report?.lastTCPClosure = reason; report?.discardedTCPBytes += discarded
        case let .failureContext(operation, error, port):
            report?.failureOperation = operation; report?.failureSystemError = error; report?.failurePort = port
        case let .failed(code): report?.failure = code
        case .stopped: report?.relayStopAcknowledged = true
        }
    }
    private func finish(_ result: RubyRelayRunResult) {
        report?.elapsedSeconds = ProcessInfo.processInfo.systemUptime - started
        switch result {
        case .cancelled: report?.termination = "stopped"; message = "Relay stopped."
        case .exited(0): report?.termination = "ended"; message = "Connection ended. Connect to start again."
        case .exited: report?.termination = "failed"; message = "The relay stopped unexpectedly. Save the session report for details."
        case let .failed(code):
            report?.termination = "failed"; report?.failure = code
            switch code {
            case .addressInUse:
                if let port = report?.failurePort {
                    let isTCP = report?.failureOperation == .tcpListenerBind || report?.failureOperation == .tcpListen
                    let transport = isTCP ? "TCP" : "UDP"
                    message = "\(transport) port \(port) is already in use. The relay left its existing owner running."
                } else { message = "A required port is already in use. Save the session report for details." }
            case .connectionTimedOut: message = "The connection timed out. Check the host address and try again."
            case .localAddressUnavailable, .routeChanged: message = "The network address is no longer available. Connect again after the network recovers."
            case .unavailable: message = "The system Ruby relay could not start on this Mac."
            default: message = "Couldn’t continue the connection. Check the host and save the session report for details."
            }
        }
    }
}
