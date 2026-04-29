#!/usr/bin/env bash
# Wrapper that invokes the GitHub Copilot CLI using a credential supplied
# via the Docker secret bind mount or an environment variable.
#
# Lookup order:
#   1. /run/secrets/copilot_token   (preferred; bind-mounted by the host)
#   2. $COPILOT_TOKEN               (passed via `docker run -e ...`)
#
# The token is exposed to `copilot` as $GH_TOKEN (and $GITHUB_TOKEN) for the
# duration of that single invocation only. It is never echoed and is not
# exported into the parent shell.
#
# Usage:
#   copilot-run [args passed straight through to `copilot`]
#
# Examples:
#   copilot-run --prompt "Summarize the most recent commit"
#   copilot-run /help
set -euo pipefail

SECRET_FILE="${COPILOT_TOKEN_FILE:-/run/secrets/copilot_token}"

if [[ -r "${SECRET_FILE}" ]]; then
    token="$(< "${SECRET_FILE}")"
elif [[ -n "${COPILOT_TOKEN:-}" ]]; then
    token="${COPILOT_TOKEN}"
else
    echo "copilot-run: no credential found." >&2
    echo "             expected ${SECRET_FILE} or \$COPILOT_TOKEN to be set." >&2
    exit 2
fi

# Strip any stray trailing whitespace/newlines without disturbing the value.
token="${token%$'\n'}"
token="${token%$'\r'}"

if [[ -z "${token}" ]]; then
    echo "copilot-run: credential is empty." >&2
    exit 2
fi

# Pass the token to copilot via env vars scoped to this single command.
# `env -u` clears any inherited values first so we don't accidentally
# fall back to a stale token from the parent environment.
exec env -u COPILOT_TOKEN \
    GH_TOKEN="${token}" \
    GITHUB_TOKEN="${token}" \
    copilot "$@"
