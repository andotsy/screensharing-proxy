#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
printf 'Loopback TCP/UDP experiment — full High Performance operation is unproven.\n'
printf 'Run on the controlling Mac. Disconnect its existing Screen Sharing session.\n'
read -r -p 'Screen-sharing host IPv4 address: ' remote_address
report="$PWD/loopback-$(date -u +%Y%m%dT%H%M%SZ).json"
printf 'After Relay ready, connect Screen Sharing to 127.0.0.1, Port 15900, High Performance.\n'
printf 'This attempt ends after 10 minutes or TCP close. Ctrl-C stops early and saves a report.\n'
exec ./screensharing-proxy-experiment loopback --remote "$remote_address" --output "$report"
