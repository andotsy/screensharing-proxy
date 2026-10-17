import Testing
@testable import ProxyCore

@Suite("Automatic allowed-proxyd selection")
struct ProxydDiscoveryTests {
    func candidate(_ path: String = "/usr/libexec/proxyd", rule: FirewallRule = .allow,
                   running: Bool = false, accessible: Bool = true, resolved: String? = nil) -> ProxyCandidate {
        .init(executable: path, resolvedExecutable: resolved ?? path, sources: ["firewallList"], incomingRule: rule,
              ruleSource: "firewallList", runningObserved: running, executableAccessible: accessible)
    }
    func evaluate(_ candidates: [ProxyCandidate], state: String = "enabled", blockAll: String = "disabled") -> ProxydDiscoveryResult {
        .evaluate(candidates: candidates, firewallState: state, blockAll: blockAll)
    }

    @Test func uniqueAllowedCandidateIsSelected() {
        let result = evaluate([candidate(), candidate("/usr/local/libexec/proxyd", rule: .block)])
        #expect(result.status == .selected)
        #expect(result.selected?.executable == "/usr/libexec/proxyd")
    }

    @Test func prefersOnlyRunningAllowedExecutable() {
        let result = evaluate([candidate(), candidate("/opt/tools/proxyd", running: true)])
        #expect(result.status == .selected)
        #expect(result.selected?.executable == "/opt/tools/proxyd")
    }

    @Test func multipleAllowedExecutablesRemainAmbiguous() {
        #expect(evaluate([candidate(), candidate("/opt/tools/proxyd")]).status == .ambiguous)
        #expect(evaluate([candidate(running: true), candidate("/opt/tools/proxyd", running: true)]).status == .ambiguous)
    }

    @Test func blocksUnknownPermissionsAndGlobalOverrides() {
        #expect(evaluate([candidate()], blockAll: "enabled").status == .blocked)
        #expect(evaluate([candidate()], blockAll: "unknown").selected == nil)
        #expect(evaluate([candidate()], state: "unknown").status == .permissionUnknown)
        #expect(evaluate([candidate()], state: "disabled").status == .firewallDisabled)
        #expect(evaluate([candidate(rule: .unknown)]).status == .permissionUnknown)
        #expect(evaluate([candidate(rule: .block)]).status == .blocked)
    }

    @Test func staleAllowEntryDoesNotSelectMissingExecutable() {
        #expect(evaluate([candidate(accessible: false)]).status == .unavailable)
        #expect(evaluate([]).status == .notFound)
    }

    @Test func deduplicatesAliasesButRejectsConflictingRules() {
        let alias = "/opt/proxy/proxyd"
        #expect(evaluate([candidate(), candidate(alias, resolved: "/usr/libexec/proxyd")]).status == .selected)
        #expect(evaluate([candidate(), candidate(alias, rule: .block, resolved: "/usr/libexec/proxyd")]).status == .permissionUnknown)
    }

    @Test func ruleQueriesRejectContradictoryOrUnrecognizedText() {
        #expect(FirewallParser.queriedRule("The application is not blocked.") == .allow)
        #expect(FirewallParser.queriedRule("The application is blocked") == .block)
        #expect(FirewallParser.queriedRule("The application is blocked\nThe application is not blocked") == .unknown)
        #expect(FirewallParser.queriedRule("The application is not registered") == .unknown)
        #expect(FirewallParser.blockAll("Block all DISABLED!") == "disabled")
        #expect(FirewallParser.blockAll("Block all ENABLED!\nBlock all DISABLED!") == "unknown")
    }
}
