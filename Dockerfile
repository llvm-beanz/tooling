# LLVM build/test environment.
#
# This image provisions a build/test toolchain, bakes in the CMake
# initial-cache file (Config.cmake), and clones llvm-project from
# https://github.com/llvm/llvm-project.git at image-build time. The clone
# lives at /home/dev/dev/llvm-project. Configure/build/test still happen
# inside a running container via the helper scripts.
#
# Typical usage (from the host):
#   docker build -t llvm-dev .
#   docker run --rm -it llvm-dev
#   # then inside the container:
#   llvm-configure                   # uses /opt/llvm-tooling/Config.cmake
#   llvm-build                       # ninja -C build
#   llvm-test                        # ninja -C build check-all

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

# Core toolchain + LLVM build/test prerequisites.
# Kept intentionally broad so a wide range of CMake cache files
# (clang, clang-tools-extra, mlir, lld, lldb, libcxx, compiler-rt, ...)
# can configure successfully without rebuilding the image.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        gnupg \
        sudo \
        locales \
        tzdata \
        pkg-config \
        build-essential \
        cmake \
        ninja-build \
        ccache \
        sccache \
        clang \
        clang-tidy \
        clang-format \
        lld \
        lldb \
        llvm-dev \
        libclang-dev \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-psutil \
        zlib1g-dev \
        libzstd-dev \
        libxml2-dev \
        libedit-dev \
        libncurses-dev \
        libffi-dev \
        libtinfo-dev \
        swig \
        binutils-dev \
        file \
        unzip \
        xz-utils \
        gdb \
        less \
        nano \
        vim \
        libvulkan-dev \
        vulkan-tools \
        vulkan-validationlayers \
        mesa-vulkan-drivers \
        spirv-tools; \
    rm -rf /var/lib/apt/lists/*; \
    locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    CC=clang \
    CXX=clang++ \
    CMAKE_GENERATOR=Ninja \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json

# Install Node.js 22 (required by GitHub Copilot CLI) from NodeSource and
# then install the Copilot CLI globally. After install, `copilot` is on PATH.
# The user still needs to authenticate (`copilot` will prompt) on first run.
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*; \
    npm install -g @github/copilot

# Bake the CMake initial-cache file into the image. `llvm-configure` will use
# this by default, so callers don't need to pass a path.
COPY Config.cmake /opt/llvm-tooling/Config.cmake
ENV LLVM_CACHE_FILE=/opt/llvm-tooling/Config.cmake

# Install helper scripts and put them on PATH as `llvm-configure`,
# `llvm-build`, `llvm-test`, `copilot-run`.
COPY scripts/ /opt/llvm-tooling/scripts/
RUN set -eux; \
    chmod +x /opt/llvm-tooling/scripts/*.sh; \
    ln -s /opt/llvm-tooling/scripts/configure.sh  /usr/local/bin/llvm-configure; \
    ln -s /opt/llvm-tooling/scripts/build.sh      /usr/local/bin/llvm-build; \
    ln -s /opt/llvm-tooling/scripts/test.sh       /usr/local/bin/llvm-test; \
    ln -s /opt/llvm-tooling/scripts/copilot-run.sh /usr/local/bin/copilot-run; \
    ln -s /opt/llvm-tooling/scripts/agent-setup.sh /usr/local/bin/agent-setup

# A non-root user keeps file ownership on bind-mounted workspaces sane.
# UID/GID can be overridden at build time to match the host user.
ARG USER_NAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    if getent group "${USER_GID}" >/dev/null; then \
        groupmod -n "${USER_NAME}" "$(getent group ${USER_GID} | cut -d: -f1)"; \
    else \
        groupadd --gid "${USER_GID}" "${USER_NAME}"; \
    fi; \
    if id -u "${USER_UID}" >/dev/null 2>&1; then \
        existing="$(getent passwd ${USER_UID} | cut -d: -f1)"; \
        usermod -l "${USER_NAME}" -d /home/${USER_NAME} -m -g "${USER_GID}" "${existing}" || true; \
    else \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USER_NAME}"; \
    fi; \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME}; \
    chmod 0440 /etc/sudoers.d/${USER_NAME}

USER ${USER_NAME}

# Clone llvm-project at image-build time. Always pulls from the upstream
# repository so the resulting image is reproducible from this Dockerfile alone.
# `receive.denyCurrentBranch=updateInstead` lets you push to the checked-out
# branch from a host-side `git push` and have the working tree update.
# Clone the auxiliary repos referenced by Config.cmake. Config.cmake looks
# for these under $HOME/dev/, so place them there. Each is opt-in inside
# Config.cmake (guarded by `if (EXISTS ...)`).
#
#   llvm/offload-test-suite        -> LLVM_EXTERNAL_OFFLOADTEST_SOURCE_DIR
#   llvm/offload-golden-images     -> GOLDENIMAGE_DIR
#   microsoft/DirectXShaderCompiler -> DXC_DIR. Config.cmake expects a
#       *built* DXC at build-rel/bin/, so we build it below.
RUN set -eux; \
    mkdir -p /home/${USER_NAME}/dev; \
    git clone --branch main \
        https://github.com/llvm/llvm-project.git \
        /home/${USER_NAME}/dev/llvm-project; \
    git -C /home/${USER_NAME}/dev/llvm-project config receive.denyCurrentBranch updateInstead; \
    git clone --branch main --depth 1 \
        https://github.com/llvm/offload-test-suite.git \
        /home/${USER_NAME}/dev/offload-test-suite; \
    git clone --branch main --depth 1 \
        https://github.com/llvm/offload-golden-images.git \
        /home/${USER_NAME}/dev/offload-golden-images; \
    git clone --recurse-submodules --branch main --depth 1 \
        https://github.com/microsoft/DirectXShaderCompiler.git \
        /home/${USER_NAME}/dev/DirectXShaderCompiler

# Build DXC into ~/dev/DirectXShaderCompiler/build-rel so Config.cmake's
# DXC_DIR path picks it up (~/dev/DirectXShaderCompiler/build-rel/bin/).
# Also install DXC's `llvm-dis` as `dxil-dis` in /usr/local/bin (the path
# Config.cmake's DXIL_DIS variable points at). The dev user runs as a
# non-root user; use sudo (granted earlier) for the system install.
RUN set -eux; \
    cmake \
        -S /home/${USER_NAME}/dev/DirectXShaderCompiler \
        -B /home/${USER_NAME}/dev/DirectXShaderCompiler/build-rel \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -C /home/${USER_NAME}/dev/DirectXShaderCompiler/cmake/caches/PredefinedParams.cmake; \
    cmake --build /home/${USER_NAME}/dev/DirectXShaderCompiler/build-rel \
        --target all llvm-dis; \
    sudo install -m 0755 \
        /home/${USER_NAME}/dev/DirectXShaderCompiler/build-rel/bin/llvm-dis \
        /usr/local/bin/dxil-dis

# Install the post-receive hook into the llvm-project clone. The hook
# checks out each pushed branch and, if `agent_prompt.md` exists at the
# repo root on that ref, runs `copilot-run --allow-all` with the file's
# contents as the prompt.
COPY --chown=${USER_UID}:${USER_GID} hooks/post-receive \
    /home/${USER_NAME}/dev/llvm-project/.git/hooks/post-receive
RUN chmod +x /home/${USER_NAME}/dev/llvm-project/.git/hooks/post-receive

CMD ["bash"]
