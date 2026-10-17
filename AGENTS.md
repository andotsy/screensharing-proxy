# Screen Sharing Proxy

This is the working repository. Other workspace checkouts are read-only;
never edit, build, run, or commit in them for this project. Use the existing
isolated checkout, not an additional Git worktree. Do not publish names, links,
commit identifiers or documentation copied from private reference projects.

Read `docs/IMPLEMENTATION_PLAN.md` and `docs/TRANSPORT_FINDINGS.md`. The viewer's
allowed executable is recalled as `proxyd`; its identity and forwarding API are
unverified on the restricted Mac. Prefer installation on the controlling Mac
alone, but the user explicitly permits a companion on the remote Mac if needed.
The goal includes full keyboard/mouse control, not read-only viewing.
Do not implement a guessed service
interface, change firewall rules, or describe TCP forwarding as a High Performance
Screen Sharing solution. Keep unknown evidence distinct from a passing check.

The first implementation provides diagnostic and process-control infrastructure.
Use Swift 6.2+; run `swift test -Xswiftc -warnings-as-errors` and
`swift build -c release -Xswiftc -warnings-as-errors`. Portable tests run on Linux;
actual macOS probes and Screen Sharing require explicit testing on a Mac.

Bound subprocess deadlines, output, cleanup and cancellation. Never launch a
shell with user input. Do not log process environments, command arguments from
other applications, protocol payloads or credentials. Shared reports redact
private endpoint/path details by default. Do not kill system services or modify
global network state. No commit, push, tag or release is implied by local work.
