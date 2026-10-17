# Transport findings

Status on 2026-10-17: **backend undecided; live experiment pending**.

The user recalls that `proxyd`, not `/usr/bin/python3`, is permitted to receive
incoming connections on the viewer. The user prefers a viewer-only installation.
Neither the executable's exact identity nor a supported forwarding API has been
observed on a Mac in this session.

The working transport hypothesis includes an RFB control path, UDP media and
feedback. A TCP 5900 relay alone is insufficient evidence of a complete High
Performance session. The actual flow and current failure's cause still need
to be established on the viewer and remote Macs.

The current machine is Debian Linux x86_64. The new Swift diagnostic collector
has been built here, with macOS-shaped **synthetic fixtures** used to test its
parsing, redaction and partial-evidence behavior. Its macOS commands have not
been run on the actual viewer. A denied read of the GitHub API added no evidence
about Apple's `proxyd`; no inference is made from that network restriction.

| Question | Current answer |
| --- | --- |
| Exact viewer/remote macOS builds | Not collected |
| Allowed executable path / signing identity | Not collected |
| Actual filter and effective rule | User-reported restriction; not reproduced |
| Documented `proxyd` interface | Unknown |
| Receiving socket owner(s) | Not collected |
| Media/feedback endpoint negotiation | Unknown |
| Loopback delivery and source-tuple compatibility | Not tested |
| Complete High Performance session via relay | Not tested |

Next action: run the collector described in `DIAGNOSTICS.md` on the viewer with
the failing session active. It records evidence without changing the network.
Then investigate the exact service and run the plan's controlled experiment.
Create `docs/adr/0001-transport.md` only when evidence supports a real choice.

The portable protocol/lifecycle code controls a future **app-owned adapter**.
It is not a protocol for Apple's daemon and does not grant permission to stop,
reconfigure or replace that service.
