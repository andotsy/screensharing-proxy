#!/bin/bash
set -euo pipefail

# Keeps Swift/Clang caches in writable storage without replacing HOME.
if [[ $# -eq 0 ]]; then
    printf 'Usage: bash Scripts/swift-cloud.sh <build|test|run> [arguments...]\n' >&2
    exit 64
fi
action=$1
shift
case "$action" in build|test|run) ;; *) printf 'Expected build, test or run.\n' >&2; exit 64 ;; esac
toolchain=/workspace/.toolchains/swift-6.2-RELEASE-ubuntu24.04/usr/bin/swift
if [[ ! -x "$toolchain" ]]; then
    printf 'The cloud Swift toolchain is missing; run the saved environment install script.\n' >&2
    exit 1
fi
export XDG_CACHE_HOME=/workspace/.cache
export CLANG_MODULE_CACHE_PATH=/workspace/.cache/clang
export SWIFTPM_MODULECACHE_OVERRIDE=/workspace/.cache/clang
exec "$toolchain" "$action" \
    --cache-path /workspace/.cache/swiftpm \
    --config-path /workspace/.cache/swiftpm-config \
    --security-path /workspace/.cache/swiftpm-security "$@"
