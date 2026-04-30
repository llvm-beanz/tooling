#!/usr/bin/env bash
# start-llvm-dev.sh
#
# macOS/Linux equivalent of Start-LlvmDev.ps1.
#
# Provisions a Copilot credential file on the host and starts the llvm-dev
# container with that file bind-mounted as a Docker secret.
#
# The token is stored at $TOKEN_PATH (default: ~/.secrets/copilot-token)
# with mode 0600 and ownership of the current user. It's then bind-mounted
# into the container at /run/secrets/copilot_token (read-only). The token
# never ends up in the image, in `docker inspect` output, or in a Docker
# volume.
#
# Re-running this script with a new token rotates the credential. The
# container's `copilot-run` wrapper re-reads the file on every invocation,
# so no restart is needed unless you change --token-path.
#
# Usage:
#   ./start-llvm-dev.sh                            # prompt for token
#   ./start-llvm-dev.sh --token "$(cat tok.txt)"   # non-interactive
#   ./start-llvm-dev.sh --recreate                 # recreate container
#
# Options:
#   --token-path PATH      Where to store the token (default: ~/.secrets/copilot-token)
#   --token VALUE          Token value (omit to prompt; input is hidden)
#   --image NAME           Image name (default: llvm-dev)
#   --container NAME       Container name (default: llvm-dev-shell)
#   --recreate             Remove existing container before starting
#   -h, --help             Show this help
set -euo pipefail

TOKEN_PATH="${HOME}/.secrets/copilot-token"
TOKEN=""
IMAGE_NAME="llvm-dev"
CONTAINER_NAME="llvm-dev-shell"
RECREATE=0

usage() {
    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token-path) TOKEN_PATH="$2"; shift 2 ;;
        --token)      TOKEN="$2";      shift 2 ;;
        --image)      IMAGE_NAME="$2"; shift 2 ;;
        --container)  CONTAINER_NAME="$2"; shift 2 ;;
        --recreate)   RECREATE=1;      shift ;;
        -h|--help)    usage ;;
        *) echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ---------- 1. Acquire the token ----------
if [[ -z "${TOKEN}" ]]; then
    # -s suppresses echo. -r preserves backslashes. -p prints prompt to stderr-ish.
    printf 'GitHub token for Copilot (input hidden): ' >&2
    IFS= read -rs TOKEN
    printf '\n' >&2
fi

# Trim any trailing CR/LF.
TOKEN="${TOKEN%$'\r'}"
TOKEN="${TOKEN%$'\n'}"

if [[ -z "${TOKEN}" ]]; then
    echo "error: empty token; refusing to write." >&2
    exit 1
fi

# ---------- 2. Write the token file ----------
TOKEN_DIR="$(dirname "${TOKEN_PATH}")"
mkdir -p "${TOKEN_DIR}"
chmod 700 "${TOKEN_DIR}" 2>/dev/null || true

# Write atomically: temp file in the same directory, then rename. Mode 600
# is set on the temp file *before* the token bytes are written so there's
# no window where the token is readable by other users.
umask 077
TMP="$(mktemp "${TOKEN_DIR}/.copilot-token.XXXXXX")"
trap 'rm -f "${TMP}"' EXIT
printf '%s' "${TOKEN}" > "${TMP}"
chmod 600 "${TMP}"
mv "${TMP}" "${TOKEN_PATH}"
trap - EXIT

echo "==> Wrote token to ${TOKEN_PATH}"
unset TOKEN

# ---------- 3. Sanity-check the image ----------
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "error: docker image '${IMAGE_NAME}' not found." >&2
    echo "       Build it first: docker build -t ${IMAGE_NAME} ." >&2
    exit 1
fi

# ---------- 4. Start (or restart) the container ----------
container_state() {
    docker ps -a \
        --filter "name=^${CONTAINER_NAME}$" \
        --format '{{.State}}' 2>/dev/null
}

state="$(container_state)"

if [[ -n "${state}" && "${RECREATE}" -eq 1 ]]; then
    echo "==> Removing existing container '${CONTAINER_NAME}'"
    docker rm -f "${CONTAINER_NAME}" >/dev/null
    state=""
fi

if [[ -n "${state}" ]]; then
    if [[ "${state}" != "running" ]]; then
        echo "==> Starting existing container '${CONTAINER_NAME}' (was: ${state})"
        docker start "${CONTAINER_NAME}" >/dev/null
    else
        echo "==> Container '${CONTAINER_NAME}' already running; reusing."
        echo "    NOTE: bind mounts are fixed at create time. To pick up a"
        echo "          changed --token-path, re-run with --recreate."
    fi
else
    echo "==> Creating and starting container '${CONTAINER_NAME}'"
    docker run -dit \
        --name "${CONTAINER_NAME}" \
        --mount "type=bind,src=${TOKEN_PATH},dst=/run/secrets/copilot_token,readonly" \
        "${IMAGE_NAME}" >/dev/null
fi

cat <<EOF

Container ready.
  Open a shell:  docker exec -it ${CONTAINER_NAME} bash
  Run Copilot:   docker exec -it ${CONTAINER_NAME} copilot-run -p '...'
  Stop:          docker stop ${CONTAINER_NAME}
  Rotate token:  re-run this script (use --recreate to also rebind the mount)
EOF
