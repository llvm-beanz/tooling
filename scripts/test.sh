#!/usr/bin/env bash
# Run LLVM tests against an already-built tree.
#
# Usage:
#   llvm-test [check targets...]   # default: check-all
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

if [[ $# -eq 0 ]]; then
    set -- check-all
fi

echo "==> Testing (${LLVM_BUILD}): $*"
exec ninja -C "${LLVM_BUILD}" "${jobs_args[@]}" "$@"
