import Foundation

/// A small interoperable ZIP using stored entries. Fixed names, bounded sizes,
/// CRC32 and a central directory keep export independent of a shell or runtime.
public enum DiagnosticArchive {
    public static func make(report: DiagnosticReport) throws -> Data {
        let readme = """
        Screen Sharing Proxy diagnostics — \(ProxyBuild.version)
        Collected: \(report.collectedAt)

        Send this ZIP to the person investigating your Screen Sharing connection.
        diagnostics.json contains OS, firewall, service, executable and TCP/UDP
        socket evidence from \(report.samples.count) snapshots. Probe outcomes and
        limitations indicate incomplete or unavailable observations.

        Private addresses and paths are redacted by default. This archive contains
        no packet contents, credentials or process environments. It is diagnostic
        evidence; it does not prove a firewall drop or a working traffic relay.
        """
        return try zip([("diagnostics.json", report.json()), ("README.txt", Data(readme.utf8))])
    }

    private static func zip(_ entries: [(String, Data)]) throws -> Data {
        var archive = Data(), directory = Data()
        for (name, contents) in entries {
            guard contents.count <= 32 * 1_024 * 1_024 else { throw CocoaError(.fileWriteOutOfSpace) }
            let filename = Data(name.utf8), size = UInt32(contents.count)
            let offset = UInt32(archive.count), checksum = crc32(contents)
            archive.u32(0x04034b50); archive.u16(20); archive.u16(0x0800)
            archive.u16(0); archive.u16(0); archive.u16(0x0021) // stored; 1980-01-01
            archive.u32(checksum); archive.u32(size); archive.u32(size)
            archive.u16(UInt16(filename.count)); archive.u16(0)
            archive.append(filename); archive.append(contents)

            directory.u32(0x02014b50); directory.u16(0x0314); directory.u16(20)
            directory.u16(0x0800); directory.u16(0); directory.u16(0); directory.u16(0x0021)
            directory.u32(checksum); directory.u32(size); directory.u32(size)
            directory.u16(UInt16(filename.count)); directory.u16(0); directory.u16(0)
            directory.u16(0); directory.u16(0); directory.u32(0o100600 << 16)
            directory.u32(offset); directory.append(filename)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.u32(0x06054b50); archive.u16(0); archive.u16(0)
        archive.u16(UInt16(entries.count)); archive.u16(UInt16(entries.count))
        archive.u32(UInt32(directory.count)); archive.u32(directoryOffset); archive.u16(0)
        return archive
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var value = UInt32(value)
        for _ in 0..<8 { value = value & 1 == 0 ? value >> 1 : (value >> 1) ^ 0xedb88320 }
        return value
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func u16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func u32(_ value: UInt32) {
        u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(truncatingIfNeeded: value >> 16))
    }
}
