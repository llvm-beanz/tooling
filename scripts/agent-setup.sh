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

# Rebuild DXC. If the build tree hasn't been configured yet (e.g. the very
# first run, during image build), configure it first using DXC's predefined
# initial cache. Subsequent runs just do an incremental ninja against the
# refreshed source tree.
DXC_SRC="${DEV_ROOT}/DirectXShaderCompiler"
DXC_BUILD="${DXC_SRC}/build-rel"
if [[ ! -f "${DXC_BUILD}/build.ninja" ]]; then
    echo "agent-setup: configuring DXC build (${DXC_BUILD})"
    cmake \
        -S "${DXC_SRC}" \
        -B "${DXC_BUILD}" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -C "${DXC_SRC}/cmake/caches/PredefinedParams.cmake"
fi

echo "agent-setup: building DXC (${DXC_BUILD})"
cmake --build "${DXC_BUILD}" --target all llvm-dis

# Install the freshly built DXC artifacts into /usr/local so that
# Config.cmake (and anything else on PATH) picks them up.
echo "agent-setup: installing DXC artifacts to /usr/local"
sudo install -m 0755 "${DXC_BUILD}/bin/dxc" /usr/local/bin/dxc
sudo install -m 0755 "${DXC_BUILD}/bin/llvm-dis" /usr/local/bin/dxil-dis
sudo install -d /usr/local/lib
for f in "${DXC_BUILD}"/lib/libdxcompiler.so*; do
    [[ -e "$f" ]] || continue
    sudo install -m 0755 "$f" /usr/local/lib/
done
sudo ldconfig

echo "agent-setup: done"
