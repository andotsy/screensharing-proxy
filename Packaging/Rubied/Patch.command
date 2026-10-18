#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
/usr/bin/ruby --disable-gems ./patch.rb "$@"
