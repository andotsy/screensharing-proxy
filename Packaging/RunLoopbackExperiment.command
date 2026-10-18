#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
printf 'Loopback TCP/UDP experiment — port diagnostics v6, local TCP port 5900.\n'
printf 'Run on the controlling Mac. Disconnect its existing Screen Sharing session.\n'
printf 'Apple disables High Performance for the previous localhost port 15900. This attempt tests port 5900.\n'
printf 'If port 5900 is occupied or Screen Sharing refuses a connection to this Mac, stop and keep the report.\n'
printf 'This build reports the exact failed socket operation and affected port.\n'
read -r -p 'Screen-sharing host IPv4 address: ' remote_address
report="$PWD/loopback-port-diagnostics-v6-$(date -u +%Y%m%dT%H%M%SZ).json"
printf 'After Relay ready, Screen Sharing opens automatically. Choose High Performance when offered.\n'
printf 'Login reconnections stay in this attempt. Ctrl-C saves the report; limits are 10 minutes total or 2 minutes waiting for TCP.\n'
exec ./screensharing-proxy-experiment loopback --remote "$remote_address" --listen-port 5900 --output "$report" --open-viewer
