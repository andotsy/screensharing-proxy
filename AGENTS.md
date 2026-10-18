# Screen Sharing Proxy

This is the working repository. Other workspace checkouts are read-only;
never edit, build, run, or commit in them for this project. Use the existing
isolated checkout, not an additional Git worktree. Do not publish names, links,
commit identifiers or documentation copied from private reference projects.

Read `docs/IMPLEMENTATION_PLAN.md` and `docs/TRANSPORT_FINDINGS.md`. The viewer's
allowed executable was recalled as `proxyd`, but neither Mac's capture found it.
The restricted Mac lists Ruby and a Python launcher shim as allowed, while a
Python.app runtime is blocked; actual receiving permission is still untested.
Prefer installation on the controlling Mac
alone, but the user explicitly permits a companion on the remote Mac if needed.
The user selected system Ruby for the next experiment and explicitly declined
interface configuration changes, including adding/removing loopback aliases.
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

All commits must use `andotsy <143706459+andotsy@users.noreply.github.com>`
for both author and committer. Publish through the authorized GitHub access on
`debian@debian-vm.local`. Check identities before pushing; never use a personal
or workplace email address for this repository.
