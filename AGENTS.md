# Screen Sharing Rubyfier

This is the working repository. Other workspace checkouts are read-only;
never edit, build, run, or commit in them for this project. Use the existing
isolated checkout, not an additional Git worktree. Do not publish names, links,
commit identifiers or documentation copied from private reference projects.

The repository contains only the Rubyfier patcher: the native app
(`Sources/ScreenSharingRubyfier`, `ProxyAppSupport`, `ProxyCore`), the transport
library and launcher (`Sources/Rubied`), the Ruby relay (`Sources/Rubied/Relay`)
and the runtime patcher (`Packaging/Rubied`). Read `README.md` and
`docs/RUBIED_PATCHER.md` first.

The patcher exists for Macs whose firewall blocks incoming connections for
Screen Sharing; system Ruby owns the external TCP/UDP sockets. Do not change
firewall rules, network interfaces or loopback aliases. Keep unverified behavior
(other macOS builds, a firewall that actually blocks Screen Sharing) described as
unverified.

Use Swift 6.2+; run `swift test -Xswiftc -warnings-as-errors`,
`bash Packaging/build-app.sh`, and the `Scripts/test-*.py` checks CI runs.
Screen Sharing behavior requires explicit testing on a Mac.

Bound subprocess deadlines, output, cleanup and cancellation. Never launch a
shell with user input. Do not log process environments, command arguments from
other applications, protocol payloads or credentials. Do not kill system services
or modify global network state. No commit, push, tag or release is implied by
local work. Existing tags and published release assets must never be replaced.

All commits must use `andotsy <143706459+andotsy@users.noreply.github.com>`
for both author and committer. Publish through the authorized GitHub access on
`debian@debian-vm.local`. Check identities before pushing; never use a personal
or workplace email address for this repository.
