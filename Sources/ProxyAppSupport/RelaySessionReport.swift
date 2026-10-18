import Foundation
import ProxyCore

public struct RelaySessionReport: Encodable, Sendable {
    public let schemaVersion = 2
    public let toolVersion = ProxyBuild.version
    public let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    public var termination = "starting"
    public var elapsedSeconds = 0.0
    public var forwardedToNativeBytes: UInt64 = 0
    public var forwardedToRemoteBytes: UInt64 = 0
    public var forwardedToNativeDatagrams: UInt64 = 0
    public var forwardedToRemoteDatagrams: UInt64 = 0
    public var droppedDatagrams: UInt64 = 0
    public var nativeTCPConnectionCount: UInt64 = 0
    public var remoteTCPConnectionCount: UInt64 = 0
    public var completedTCPConnectionCount: UInt64 = 0
    public var relayStopAcknowledged = false
    public var failure: BackendFailureCode?
    public var failureOperation: BackendOperation?
    public var failureSystemError: BackendSystemError?
    public var failurePort: UInt16?
    public var lastTCPClosure: TCPClosureReason?
    public var discardedTCPBytes: UInt64 = 0
    public let highPerformanceSession = "unverified"
    public let counterScope = "Successful socket submissions, not native decoding or input verification. No addresses, payloads or credentials are recorded."
    public init() {}
    public var transport: String {
        if forwardedToNativeDatagrams > 0 || forwardedToRemoteDatagrams > 0 { return "TCP + UDP" }
        return forwardedToNativeBytes > 0 || forwardedToRemoteBytes > 0 ? "TCP only" : "Waiting for traffic"
    }
    public func json() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

