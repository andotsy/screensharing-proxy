import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum PrivateReportWriter {
    /// Use replaceExisting only after the user has confirmed replacement, for
    /// example through NSSavePanel. A symlink is replaced rather than followed.
    public static func write(_ data: Data, to destination: URL, replaceExisting: Bool = false) throws {
        guard destination.isFileURL else { throw POSIXError(.EINVAL) }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".ssp-report-\(UUID().uuidString)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); _ = unlink(temporary.path) }
        guard fchmod(fd, mode_t(0o600)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try handle.write(contentsOf: data)
        try handle.close()
        let outcome = replaceExisting ? rename(temporary.path, destination.path) : link(temporary.path, destination.path)
        guard outcome == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
