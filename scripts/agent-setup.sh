#!/usr/bin/env bash
# Reset and refresh the auxiliary repos used by Config.cmake, then rebuild
# DXC. Intended to be invoked from the post-receive hook before running
# Copilot, so the agent always sees a clean, up-to-date environment.
#
# Repos:
#   ~/dev/DirectXShaderCompiler   -> rebuilt into build-rel (target: all)
#   ~/dev/offload-test-suite      -> reset + pull
#   ~/dev/offload-golden-images   -> reset + pull
#
# Output is verbose; redirect at the call site if you want it captured.
set -euo pipefail

DEV_ROOT="${DEV_ROOT:-${HOME}/dev}"

refresh_repo() {
    local repo="$1"
    if [[ ! -d "${repo}/.git" ]]; then
        echo "agent-setup: skip ${repo} (not a git repo)"
        return 0
    fi
    echo "agent-setup: refreshing ${repo}"
    git -C "${repo}" fetch --tags origin
    git -C "${repo}" reset --hard origin/main
    git -C "${repo}" pull --ff-only origin main
}

refresh_repo "${DEV_ROOT}/DirectXShaderCompiler"
refresh_repo "${DEV_ROOT}/offload-test-suite"
refresh_repo "${DEV_ROOT}/offload-golden-images"

# Rebuild DXC. The build tree was already configured at image-build time,
# so this is just an incremental ninja invocation against the refreshed
# source tree.
DXC_BUILD="${DEV_ROOT}/DirectXShaderCompiler/build-rel"
if [[ -f "${DXC_BUILD}/build.ninja" ]]; then
    echo "agent-setup: rebuilding DXC (${DXC_BUILD})"
    cmake --build "${DXC_BUILD}" --target all
else
    echo "agent-setup: ${DXC_BUILD}/build.ninja missing; skipping DXC rebuild" >&2
fi

echo "agent-setup: done"
