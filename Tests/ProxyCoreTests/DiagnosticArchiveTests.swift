import Foundation
import Testing
@testable import ProxyCore

@Suite("Diagnostic ZIP compatibility")
struct DiagnosticArchiveTests {
    @Test func standardUnzipReadsEveryEntryAndVerifiesChecksums() async throws {
        let report = DiagnosticReport(schemaVersion: 2, collectedAt: "fixture", platform: "macOS",
            privateDetailsIncluded: false, remoteFilter: nil)
        let data = try DiagnosticArchive.make(report: report)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("diagnostics.zip")
        try PrivateReportWriter.write(data, to: zip)
        let runner = BoundedCommandRunner()
        #expect(await runner.run(CommandSpec("/usr/bin/unzip", ["-t", zip.path])).succeeded)
        let listing = await runner.run(CommandSpec("/usr/bin/unzip", ["-Z", "-1", zip.path]))
        #expect(listing.text.split(separator: "\n") == ["diagnostics.json", "README.txt"])
        let json = await runner.run(CommandSpec("/usr/bin/unzip", ["-p", zip.path, "diagnostics.json"]))
        #expect(json.output == (try report.json()))
        let readme = await runner.run(CommandSpec("/usr/bin/unzip", ["-p", zip.path, "README.txt"]))
        #expect(readme.text.contains("Send this ZIP"))
        var broken = data
        let location = try #require(broken.range(of: Data("fixture".utf8))).lowerBound
        broken[location] ^= 1
        try PrivateReportWriter.write(broken, to: zip, replaceExisting: true)
        #expect(!(await runner.run(CommandSpec("/usr/bin/unzip", ["-t", zip.path])).succeeded))
    }
}
