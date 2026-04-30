#!/usr/bin/env bash
# Build an already-configured LLVM tree.
#
# Usage:
#   llvm-build [ninja targets...]
#
# Environment overrides:
#   LLVM_BUILD   Path to build directory (default: ./build)
#   NINJA_JOBS   -j value passed to ninja (default: ninja's auto)
set -euo pipefail

LLVM_BUILD="${LLVM_BUILD:-build}"

if [[ ! -f "${LLVM_BUILD}/build.ninja" ]]; then
    echo "error: ${LLVM_BUILD}/build.ninja not found; run 'llvm-configure' first." >&2
    exit 2
fi

jobs_args=()
if [[ -n "${NINJA_JOBS:-}" ]]; then
    jobs_args=(-j "${NINJA_JOBS}")
fi

echo "==> Building (${LLVM_BUILD})"
exec ninja -C "${LLVM_BUILD}" "${jobs_args[@]}" "$@"
