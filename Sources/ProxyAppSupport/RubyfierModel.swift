import Foundation
import ProxyCore
#if os(macOS)
import Observation

@MainActor @Observable
public final class RubyfierModel {
    public private(set) var isBusy = false
    public private(set) var consoleData = Data()
    public private(set) var message = "Ready to create your app."
    public private(set) var createdApp: URL?
    @ObservationIgnored private var operation: Task<Void, Never>?
    private let script: URL?
    public var consoleText: String { String(decoding: consoleData, as: UTF8.self) }
    public var payloadAvailable: Bool { script.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    public init(resources: URL? = Bundle.main.resourceURL) {
        script = resources?.appendingPathComponent("Rubyfier/patch.rb")
    }

    public func create(in directory: URL) {
        guard operation == nil else { return }
        guard let script, payloadAvailable else {
            message = "This build is missing its bundled patcher."
            return
        }
        isBusy = true
        createdApp = nil
        consoleData = Data()
        message = "Creating Screen Sharing Rubyfied…"
        operation = Task {
            let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(256))
            let runner = BoundedCommandRunner { data, _ in continuation.yield(data) }
            let command = Task {
                let result = await runner.run(CommandSpec("/usr/bin/ruby", ["--disable-gems", script.path, directory.path],
                                                          timeout: 90, outputLimit: 131_072))
                continuation.finish()
                return result
            }
            await withTaskCancellationHandler {
                for await data in stream {
                    consoleData.append(data)
                    if consoleData.count > 262_144 { consoleData.removeFirst(consoleData.count - 262_144) }
                }
            } onCancel: { command.cancel() }
            let result = await command.value
            if result.complete {
                createdApp = directory.appendingPathComponent("Screen Sharing Rubyfied.app")
                message = "Screen Sharing Rubyfied is ready to open."
            } else if result.outcome == .cancelled {
                message = "Creation cancelled."
            } else {
                message = "Couldn’t create the app. The console has the details."
            }
            isBusy = false
            operation = nil
        }
    }

    public func cancel() { operation?.cancel() }
    public func waitForCompletion() async { await operation?.value }
}
#endif
