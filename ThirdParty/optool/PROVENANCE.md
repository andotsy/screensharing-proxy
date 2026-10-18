# Bundled optool

Upstream: https://github.com/alexzielenski/optool
Revision: 2898b51da0c0f2f5d7302af5ec82b858ebd4013c
License: BSD-2-Clause; see LICENSE.

ArgumentParser: https://github.com/mysteriouspants/ArgumentParser
Revision: fdf684fa2d9e89f40067217e615f7e54a8267c28 (upstream submodule pin).
Used under its BSD option; full terms in optool/FSArgumentParser/LICENSE.md.

Local changes: insertion checks every padding byte and uses zero-initialized
NSData growth rather than reading up to eight bytes from a four-byte variable.
Only `install -c load` on a hash-checked, newly copied system executable is used.
No signature-unrestriction, ASLR-removal or system-app mutation is performed.
