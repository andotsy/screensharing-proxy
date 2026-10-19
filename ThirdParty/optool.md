# optool dependency

`ThirdParty/optool` is a Git submodule of https://github.com/andotsy/optool,
pinned to `57440b7a0838923d344e9aca0c48ad1c114c4924`.
The fork is based on https://github.com/alexzielenski/optool at
`2898b51da0c0f2f5d7302af5ec82b858ebd4013c`.
License: BSD-2-Clause; see `optool/LICENSE`.

ArgumentParser: https://github.com/mysteriouspants/ArgumentParser
Revision: fdf684fa2d9e89f40067217e615f7e54a8267c28 (upstream submodule pin).
It remains a nested submodule of optool. Used under its BSD option; full terms
are in `optool/optool/FSArgumentParser/LICENSE.md`.

The fork's fixes: insertion checks every padding byte and uses zero-initialized
NSData growth rather than reading up to eight bytes from a four-byte variable.
These are the same source changes previously bundled with Rubyfier 1.1.1.
Only `install -c load` on a newly copied system executable is used.
No signature-unrestriction, ASLR-removal or system-app mutation is performed.

Initialize both pinned dependencies with `git submodule update --init --recursive`.
CI checks them out recursively. The build compiles optool and bundles its binary
and both licenses; using the released patcher does not require Git or a download
of either dependency.
