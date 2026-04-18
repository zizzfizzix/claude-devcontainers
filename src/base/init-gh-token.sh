#!/usr/bin/env bash
set -euo pipefail

DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$DEVCONTAINER_DIR/.data/.env.gh"
mkdir -p "$DEVCONTAINER_DIR/.data"

if command -v gh >/dev/null 2>&1 && token=$(gh auth token 2>/dev/null) && [ -n "$token" ]; then
    printf 'GH_TOKEN=%s\n' "$token" > "$env_file"
    echo "gh: token written to .data/.env.gh"
else
    printf '' > "$env_file"
    echo "gh: not found or not authenticated — GH_TOKEN not set"
fi
