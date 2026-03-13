#!/usr/bin/env bash
# Bootstrap a Claude Code devcontainer into a target repository.
#
# One-liner (no clone needed):
#   curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript
#
# Local usage (from a clone):
#   ./install.sh [typescript|php|research] [target-directory]
#
# target-directory defaults to the current directory.
# Set CLAUDE_DEVCONTAINERS_REPO to override the raw-file base URL.

set -euo pipefail

TEMPLATE="${1:-typescript}"
TARGET="${2:-$(pwd)}"
REPO="${CLAUDE_DEVCONTAINERS_REPO:-https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main}"
DEST="${TARGET}/.devcontainer"

case "$TEMPLATE" in
  typescript|php|research) ;;
  *)
    echo "ERROR: unknown template '${TEMPLATE}'. Available: typescript, php, research" >&2
    exit 1
    ;;
esac

[[ -d "$TARGET" ]] || { echo "ERROR: '${TARGET}' is not a directory" >&2; exit 1; }

echo "Installing '${TEMPLATE}' devcontainer into ${DEST}..."
mkdir -p "$DEST"

WORKSPACE_FOLDER="/${TARGET##*/}"

# Create the bind-mount data directories and keep them out of git.
mkdir -p "${DEST}/.data/history" "${DEST}/.data/proxy"

# Fetch every file listed in the template's manifest.
# Format: src:dest[:init]
#   src   — path relative to repo root
#   dest  — path relative to DEST
#   init  — optional flag: skip if the destination file already exists
MANIFEST=$(curl -fsSL "${REPO}/templates/${TEMPLATE}/manifest.txt")
while IFS=: read -r src dest flag; do
  [[ -z "$src" || "$src" == \#* ]] && continue
  outfile="${DEST}/${dest}"
  [[ "$flag" == "init" && -f "$outfile" ]] && continue
  mkdir -p "$(dirname "$outfile")"
  curl -fsSL "${REPO}/${src}" \
    | sed "s|__WORKSPACE_FOLDER__|${WORKSPACE_FOLDER}|g" \
    > "$outfile"
done <<< "$MANIFEST"

GITIGNORE="${TARGET}/.gitignore"
if ! grep -qF '.devcontainer/.data/' "$GITIGNORE" 2>/dev/null; then
  printf '\n# Claude Code devcontainer — local state (credentials, history)\n.devcontainer/.data/\n' >> "$GITIGNORE"
  echo "  Added .devcontainer/.data/ to ${GITIGNORE}"
fi

echo ""

if ! command -v docker &>/dev/null; then
  echo "Docker not found — skipping proxy setup."
  echo "To complete setup later, run:"
  echo "  docker compose -f ${DEST}/docker-compose.yml up -d --wait claude-proxy"
  echo "  docker compose -f ${DEST}/docker-compose.yml exec claude-proxy node /app/login.js"
  echo "Then open ${TARGET} in VS Code → Reopen in Container."
  exit 0
fi

echo "Building credential proxy..."
docker compose -f "${DEST}/docker-compose.yml" build claude-proxy

echo "Starting credential proxy..."
docker compose -f "${DEST}/docker-compose.yml" up -d --wait claude-proxy

HEALTHZ=$(docker compose -f "${DEST}/docker-compose.yml" exec claude-proxy \
  wget -qO- http://localhost:3100/healthz 2>/dev/null || echo '{}')

if echo "$HEALTHZ" | grep -q '"credentialsLoaded":true'; then
  echo "Credentials already loaded — skipping login."
else
  echo ""
  docker compose -f "${DEST}/docker-compose.yml" run --rm -p 1455:1455 claude-proxy node /app/login.js
fi

echo ""
echo "Open ${TARGET} in VS Code → Reopen in Container."
echo "Credentials are stored in a Docker volume and will persist across rebuilds."
