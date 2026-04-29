#!/usr/bin/env bash
# Configure an LLVM build tree using a CMake initial-cache file.
#
# Usage:
#   llvm-configure [path/to/Config.cmake] [extra cmake args...]
#
# With no cache-file argument, the Config.cmake baked into the image at
# /opt/llvm-tooling/Config.cmake is used. ${LLVM_CACHE_FILE} (if set)
# overrides that default.
#
# Environment overrides:
#   LLVM_SRC         Path to llvm-project source tree (default: ./llvm-project)
#   LLVM_BUILD       Path to build directory          (default: ./build)
#   LLVM_CACHE_FILE  Default cache file when no positional arg is given
#                    (default: /opt/llvm-tooling/Config.cmake)
#
# The configuration always uses:
#     -G Ninja
#     -DCMAKE_BUILD_TYPE=RelWithDebInfo
# Anything else (enabled projects/runtimes, targets, distribution components,
# sanitizers, sccache wiring, etc.) must come from the cache file.
set -euo pipefail

DEFAULT_CACHE_FILE="${LLVM_CACHE_FILE:-/opt/llvm-tooling/Config.cmake}"

if [[ $# -gt 0 && "${1:-}" != -* ]]; then
    cache_file="$1"; shift
else
    cache_file="${DEFAULT_CACHE_FILE}"
fi

if [[ ! -f "${cache_file}" ]]; then
    echo "error: cache file not found: ${cache_file}" >&2
    echo "usage: llvm-configure [path/to/Config.cmake] [extra cmake args...]" >&2
    exit 2
fi
cache_file="$(readlink -f "${cache_file}")"

LLVM_SRC="${LLVM_SRC:-llvm-project}"
LLVM_BUILD="${LLVM_BUILD:-build}"

if [[ ! -f "${LLVM_SRC}/llvm/CMakeLists.txt" ]]; then
    echo "error: ${LLVM_SRC}/llvm/CMakeLists.txt not found." >&2
    echo "       Run 'llvm-clone' first or set LLVM_SRC to your llvm-project checkout." >&2
    exit 2
fi

echo "==> Configuring"
echo "    source: ${LLVM_SRC}"
echo "    build:  ${LLVM_BUILD}"
echo "    cache:  ${cache_file}"

cmake \
    -S "${LLVM_SRC}/llvm" \
    -B "${LLVM_BUILD}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -C "${cache_file}" \
    "$@"
