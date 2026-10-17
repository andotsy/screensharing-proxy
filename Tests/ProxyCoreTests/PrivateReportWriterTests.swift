import Foundation
import Testing
@testable import ProxyCore

@Suite("Private report export")
struct PrivateReportWriterTests {
    @Test func refusesOverwriteAndReplacesOnlyWhenRequested() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("report.json")
        try PrivateReportWriter.write(Data("first".utf8), to: target)
        #expect(throws: (any Error).self) { try PrivateReportWriter.write(Data("second".utf8), to: target) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "first")
        try PrivateReportWriter.write(Data("replacement".utf8), to: target, replaceExisting: true)
        #expect(try String(contentsOf: target, encoding: .utf8) == "replacement")
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["report.json"])
    }

    @Test func neverFollowsAnOutputSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original")
        let alias = root.appendingPathComponent("alias")
        try Data("untouched".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        #expect(throws: (any Error).self) { try PrivateReportWriter.write(Data("new".utf8), to: alias) }
        try PrivateReportWriter.write(Data("new".utf8), to: alias, replaceExisting: true)
        #expect(try String(contentsOf: original, encoding: .utf8) == "untouched")
        #expect(try String(contentsOf: alias, encoding: .utf8) == "new")
    }
}
