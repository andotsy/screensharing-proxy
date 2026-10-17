import Foundation
import Testing
@testable import ProxyCore

@Suite("Evidence parsing")
struct EvidenceParserTests {
    @Test func parsesNulDelimitedIPv4IPv6AndUnconnectedUDP() {
        let data = Data(("p42\0cScreen Sharing\0\nf9\0tIPv4\0PTCP\0n192.0.2.4:51000->192.0.2.5:5900\0TST=ESTABLISHED\0\n"
            + "f10\0tIPv6\0PUDP\0n[fe80::1%en0]:5901->[fe80::2%en0]:5902\0\n"
            + "p80\0cproxyd\0\nf3\0tIPv4\0PUDP\0n*:15901\0\n").utf8)
        let parsed = LsofParser.parse(data)
        #expect(parsed.unparsedRecords == 0)
        #expect(parsed.sockets.count == 3)
        #expect(parsed.sockets[0].remote?.port == 5900)
        #expect(parsed.sockets[0].state == "ESTABLISHED")
        #expect(parsed.sockets[1].local.address == "fe80::1%en0")
        #expect(parsed.sockets[1].remote?.address == "fe80::2%en0")
        #expect(parsed.sockets[2].pid == 80)
        #expect(parsed.sockets[2].remote == nil)
    }

    @Test func malformedOrPartialSocketsAreNotValidEvidence() {
        let parsed = LsofParser.parse(Data("p42\0cproxyd\0\nf3\0PTCP\0n127.0.0.1:99999\0f4\0PUDP\0n[badIPv6]:123\0f5\0".utf8))
        #expect(parsed.sockets.isEmpty)
        #expect(parsed.unparsedRecords == 3)
    }

    @Test func processPathsKeepSpacesButDoNotReadArguments() {
        let parsed = ProcessParser.parse(" 42 Sat Oct 17 10:00:00 2026 /System/Library/CoreServices/Screen Sharing.app/Contents/MacOS/Screen Sharing\n")
        #expect(parsed[42]?.executable == "/System/Library/CoreServices/Screen Sharing.app/Contents/MacOS/Screen Sharing")
        #expect(parsed[42]?.started == "Sat Oct 17 10:00:00 2026")
    }

    @Test func firewallRulesRequireExactRecognizedStatus() {
        let text = """
        ALF: total number of apps = 3
        1 : /usr/libexec/proxyd
              (Allow incoming connections)
        2 : /System/Library/screensharingd
              (Block incoming connections)
        3 : /Applications/Allow incoming connections.app
              (A future status format)
        """
        let entries = FirewallParser.parse(text)
        #expect(entries.map(\.rule) == [.allow, .block, .unknown])
        #expect(FirewallParser.globalState("Firewall is enabled. (State = 1)") == "enabled")
        #expect(FirewallParser.globalState("Permission denied") == "unknown")
    }

    @Test func manifestsRetainInterfaceNamesWithoutArgumentsOrEnvironment() throws {
        let plist: [String: Any] = ["Label": "com.apple.proxyd", "ProgramArguments": ["/usr/libexec/proxyd", "secret-argument"],
            "EnvironmentVariables": ["TOKEN": "private"], "MachServices": ["com.apple.proxyd": true],
            "Sockets": ["Listener": ["SockServiceName": "12345"]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let parsed = try #require(ServiceManifestParser.parse(data, path: "/System/Library/LaunchDaemons/proxyd.plist", candidatePaths: []))
        #expect(parsed.program == "/usr/libexec/proxyd")
        #expect(parsed.machServices == ["com.apple.proxyd"])
        #expect(parsed.socketNames == ["Listener"])
    }

    @Test func canonicalizesAndValidatesAddresses() {
        #expect(IPAddress("2001:0db8:0:0::1")?.value == "2001:db8::1")
        #expect(IPAddress("fe80::1%en0")?.value == "fe80::1%en0")
        #expect(IPAddress("192.0.2.1")?.value == "192.0.2.1")
        for bad in ["example.com", "127.0.0.1:5900", "127.0.0.1\0bad", "fe80::1%", "fe80::1%en0%extra", "127.0.0.1%en0"] {
            #expect(IPAddress(bad) == nil)
        }
    }

    @Test func redactionIsConsistentWithoutDisclosingMapping() {
        var redactor = ReportRedactor(includePrivate: false)
        #expect(redactor.address("192.0.2.4") == "address-1")
        #expect(redactor.address("192.0.2.4") == "address-1")
        #expect(redactor.address("2001:db8::1") == "address-2")
        #expect(redactor.address("127.0.0.1") == "127.0.0.1")
        #expect(redactor.path("/Users/alice/private/proxyd") == "private-path-1")
        #expect(redactor.path("/usr/libexec/proxyd") == "/usr/libexec/proxyd")
        #expect(redactor.path("/usr/local/alice/proxyd") == "private-path-2")
        #expect(redactor.path("/usr/bin/../../Users/alice/secret") == "private-path-3")
    }
}
