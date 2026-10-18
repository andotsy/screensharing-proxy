#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
printf 'Loopback TCP/UDP experiment — full High Performance operation is unproven.\n'
printf 'Run on the controlling Mac. Disconnect its existing Screen Sharing session.\n'
read -r -p 'Screen-sharing host IPv4 address: ' remote_address
report="$PWD/loopback-$(date -u +%Y%m%dT%H%M%SZ).json"
printf 'After Relay ready, Screen Sharing opens automatically. Choose High Performance when offered.\n'
printf 'Login reconnections stay in this attempt. Ctrl-C saves the report; limits are 10 minutes total or 2 minutes waiting for TCP.\n'
exec ./screensharing-proxy-experiment loopback --remote "$remote_address" --output "$report" --open-viewer
