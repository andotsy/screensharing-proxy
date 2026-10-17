#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
printf 'Incoming UDP experiment — full High Performance operation is unproven.\n'
printf 'Disconnect the existing Screen Sharing session before running this test.\n'
printf 'Leave network settings unchanged. Wait for Relay ready before reconnecting.\n'
read -r -p 'Remote Mac IPv4 address: ' remote_address
report="$PWD/incoming-$(date -u +%Y%m%dT%H%M%SZ).json"
printf 'The 10-minute test saves counters beside this command. Ctrl-C stops early.\n'
exec ./screensharing-proxy-experiment incoming --remote "$remote_address" --output "$report"
