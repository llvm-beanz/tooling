# LLVM build & test container

A self-contained Ubuntu 24.04 image that provisions everything needed to
configure, build, and test LLVM. The image bakes in the CMake initial-cache
file (`Config.cmake`), the helper scripts, **and a clone of
[llvm/llvm-project](https://github.com/llvm/llvm-project) at
`/home/dev/llvm/llvm-project`**. Configure/build/test run inside a container.
The container does not require, and does not see, any of your host filesystem.

## Files

| Path | Purpose |
| --- | --- |
| [Dockerfile](Dockerfile) | Build/test toolchain image (ubuntu:24.04). Clones llvm-project at build time. |
| [Config.cmake](Config.cmake) | Initial CMake cache, baked into the image at `/opt/llvm-tooling/Config.cmake`. |
| [scripts/configure.sh](scripts/configure.sh) | `cmake -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -C <cache>`. |
| [scripts/build.sh](scripts/build.sh) | `ninja -C build`. |
| [scripts/test.sh](scripts/test.sh) | `ninja -C build check-all` (or chosen targets). |

The scripts are linked inside the image as `llvm-configure`, `llvm-build`,
and `llvm-test`. The default working directory is `/home/dev/llvm`, and the
LLVM source tree lives at `/home/dev/llvm/llvm-project`.

## Build the image

From this directory:

```powershell
docker build -t llvm-dev .
```

`Config.cmake` is copied into the image during the build, so any edit to it
on the host requires rebuilding the image.

## Run a container

No bind mounts are needed. The container uses its own filesystem only.

```powershell
docker run --rm -it llvm-dev
```

## Workflow inside the container

```bash
# Default working directory is /home/dev/llvm.
# llvm-project is already cloned at /home/dev/llvm/llvm-project.

# 1. Configure (uses the Config.cmake baked into the image by default).
llvm-configure

# 2. Build.
llvm-build                  # everything wired into the default target
llvm-build clang            # or specific targets

# 3. Test.
llvm-test                   # check-all
llvm-test check-llvm check-clang
```

Each step can also be invoked one-shot from the host:

```powershell
docker run --rm llvm-dev bash -lc "llvm-configure && llvm-build clang"
```

Note that `--rm` discards the container (and its build tree) when it exits.
For an iterative workflow, use a long-lived container:

```powershell
docker run -dit --name llvm-dev-shell llvm-dev
docker exec -it llvm-dev-shell bash
# ...work...
docker stop llvm-dev-shell      # state preserved
docker start -ai llvm-dev-shell # resume
```

## Persisting build state across containers

If you want clones, build trees, or compiler caches to survive `docker rm`,
use **named Docker volumes** (managed by Docker, not bound to host paths):

```powershell
docker volume create llvm-src
docker volume create llvm-sccache

docker run --rm -it `
    -v llvm-src:/home/dev/llvm `
    -v llvm-sccache:/home/dev/.cache/sccache `
    -e SCCACHE_DIR=/home/dev/.cache/sccache `
    llvm-dev
```

`Config.cmake` automatically wires `sccache` in as the compiler launcher when
it's on `PATH` (it is, in this image).

## Pushing branches from your host clone to the container

The container's clone of llvm-project lives at
`/home/dev/llvm/llvm-project` inside the container. It isn't reachable as a
normal `git://`/`ssh://` URL, but git's `ext::` transport can tunnel
`git-receive-pack` (and `git-upload-pack`) through `docker exec`, so a running
container becomes a git remote.

The image configures the in-container clone with
`receive.denyCurrentBranch=updateInstead`, so pushes to the currently
checked-out branch update the working tree instead of being rejected.

### One-time setup

Start a long-lived container and add it as a remote on your host clone:

```powershell
# Start (or reuse) a container.
docker run -dit --name llvm-dev-shell llvm-dev

# From your local llvm-project checkout on the host:
cd path\to\your\llvm-project
git remote add container `
    "ext::docker exec -i llvm-dev-shell git-%S '/home/dev/llvm/llvm-project'"
```

`%S` expands to `upload-pack` or `receive-pack` depending on whether git is
fetching or pushing. The single quotes around the path are required by the
`ext::` transport.

### Use it

```powershell
git push container my-branch
git fetch container
git push container HEAD:some-other-branch
```

The container must be running (`docker start llvm-dev-shell` if it's stopped).
If you `docker rm` the container, recreate it the same way; the remote URL on
the host doesn't need to change as long as the container name stays the same.

### Alternative: bind a *separate* git directory

If you'd rather not keep a container running, you can bind a Docker-managed
volume that holds *only* the llvm-project clone (no host-filesystem exposure)
and reuse it:

```powershell
docker volume create llvm-src
docker run --rm -v llvm-src:/home/dev/llvm/llvm-project ^
    llvm-dev git -C /home/dev/llvm/llvm-project config receive.denyCurrentBranch updateInstead
```

Then point `ext::` at a transient container that mounts the same volume:

```powershell
git remote add container `
    "ext::docker run --rm -i -v llvm-src:/home/dev/llvm/llvm-project llvm-dev git-%S '/home/dev/llvm/llvm-project'"
```

A new container is spun up per git operation, so you don't need a long-lived
shell — at the cost of some startup overhead per push/fetch.

## Notes on `Config.cmake`

`Config.cmake` is copied into the image during `docker build`, so changes to
it on the host require rebuilding (`docker build -t llvm-dev .`).

The provided cache enables `clang`, `clang-tools-extra`, and `mlir` plus the
`libcxx` and `compiler-rt` runtimes, and conditionally pulls in extras
(`offload-test-suite`, `lwvm`, `DirectXShaderCompiler`, `dxil-dis`) when those
paths exist. None of those are installed in the image; edit `Config.cmake` to
drop the optional bits or add the corresponding install steps to the
Dockerfile if you need them.
