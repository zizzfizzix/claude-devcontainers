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

fetch() { curl -fsSL "${REPO}/$1" -o "$2"; }

# Patch: in-repo Dockerfiles use "COPY base/init-firewall.sh ..." (repo-root context).
# Deployed containers have init-firewall.sh adjacent to the Dockerfile, so fix the path.
fetch_dockerfile() {
  curl -fsSL "${REPO}/$1" \
    | sed 's|COPY base/init-firewall\.sh|COPY init-firewall.sh|g' \
    > "${DEST}/Dockerfile"
}

# init-firewall.sh is the only file that lives in base/ — shared by all templates
fetch "base/init-firewall.sh" "${DEST}/init-firewall.sh"
chmod +x "${DEST}/init-firewall.sh"

fetch_dockerfile "templates/${TEMPLATE}/Dockerfile"
fetch "templates/${TEMPLATE}/devcontainer.json" "${DEST}/devcontainer.json"

echo "Done. ${DEST}:"
ls -1 "$DEST"
echo ""
echo "Open ${TARGET} in VS Code → Reopen in Container."
