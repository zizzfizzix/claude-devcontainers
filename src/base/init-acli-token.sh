#!/usr/bin/env bash
set -euo pipefail

DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$DEVCONTAINER_DIR/.data/.env.acli"
mkdir -p "$DEVCONTAINER_DIR/.data"

if [ -n "${ATLASSIAN_API_TOKEN:-}" ] && [ -n "${ATLASSIAN_EMAIL:-}" ] && [ -n "${ATLASSIAN_SITE:-}" ]; then
    printf 'ATLASSIAN_API_TOKEN=%s\nATLASSIAN_EMAIL=%s\nATLASSIAN_SITE=%s\n' \
        "$ATLASSIAN_API_TOKEN" "$ATLASSIAN_EMAIL" "$ATLASSIAN_SITE" > "$env_file"
    echo "acli: credentials written to .data/.env.acli"
else
    printf '' > "$env_file"
    echo "acli: ATLASSIAN_API_TOKEN/EMAIL/SITE not set — skipping"
fi
