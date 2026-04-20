#!/usr/bin/env bash
set -euo pipefail

DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$DEVCONTAINER_DIR/.data/.env.glab"
mkdir -p "$DEVCONTAINER_DIR/.data"

if [ -n "${GITLAB_TOKEN:-}" ]; then
    {
        printf 'GITLAB_TOKEN=%s\n' "$GITLAB_TOKEN"
        [ -n "${GITLAB_HOST:-}" ] && printf 'GITLAB_HOST=%s\n' "$GITLAB_HOST"
        [ -n "${GL_HOST:-}" ] && printf 'GL_HOST=%s\n' "$GL_HOST"
    } > "$env_file"
    echo "glab: token written to .data/.env.glab"
else
    printf '' > "$env_file"
    echo "glab: GITLAB_TOKEN not set — skipping"
fi
