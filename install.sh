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

# Templates that include a docker-compose.yml also ship a credential-proxy sidecar.
# Detect this by trying to fetch the file (exit code 0 = exists).
HAS_PROXY=false
COMPOSE_URL="${REPO}/templates/${TEMPLATE}/docker-compose.yml"
if curl -fsSL --output /dev/null --silent --fail "$COMPOSE_URL"; then
  HAS_PROXY=true
  fetch "templates/${TEMPLATE}/docker-compose.yml" "${DEST}/docker-compose.yml"

  mkdir -p "${DEST}/proxy"
  fetch "proxy/Dockerfile" "${DEST}/proxy/Dockerfile"
  fetch "proxy/server.js"  "${DEST}/proxy/server.js"
  fetch "proxy/login.js"   "${DEST}/proxy/login.js"

  # Create the bind-mount data directories and keep them out of git.
  mkdir -p "${DEST}/.data/history" "${DEST}/.data/claude" "${DEST}/.data/proxy"

  # Pre-populate Claude config so the first-run wizard and IDE-integration
  # prompts are skipped on container start.
  # Claude stores onboarding state in .claude.json (internal) and user
  # preferences in settings.json (exposed settings).
  CLAUDE_JSON="${DEST}/.data/claude/.claude.json"
  if [[ ! -f "$CLAUDE_JSON" ]]; then
    fetch "base/claude/.claude.json" "$CLAUDE_JSON"
    echo "  Wrote default Claude state to ${CLAUDE_JSON}"
  fi

  CLAUDE_SETTINGS="${DEST}/.data/claude/settings.json"
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    fetch "base/claude/settings.json" "$CLAUDE_SETTINGS"
    echo "  Wrote default Claude settings to ${CLAUDE_SETTINGS}"
  fi
  GITIGNORE="${TARGET}/.gitignore"
  if ! grep -qF '.devcontainer/.data/' "$GITIGNORE" 2>/dev/null; then
    printf '\n# Claude Code devcontainer — local state (credentials, history)\n.devcontainer/.data/\n' >> "$GITIGNORE"
    echo "  Added .devcontainer/.data/ to ${GITIGNORE}"
  fi
fi

echo ""

if [[ "$HAS_PROXY" == "true" ]]; then
  # Start the proxy sidecar and run OAuth login before the user opens VS Code.
  # login.js only needs a browser callback (no stdin), so this works when piped from curl.
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

  # Check if credentials are already present (e.g. re-running install on an existing setup).
  HEALTHZ=$(docker compose -f "${DEST}/docker-compose.yml" exec claude-proxy \
    wget -qO- http://localhost:3100/healthz 2>/dev/null || echo '{}')

  if echo "$HEALTHZ" | grep -q '"credentialsLoaded":true'; then
    echo "Credentials already loaded — skipping login."
  else
    echo ""
    # Run login in a temporary container with port 1455 published only for the
    # duration of the OAuth flow. The container shares the .data/proxy volume
    # so credentials land where the main proxy service reads them.
    docker compose -f "${DEST}/docker-compose.yml" run --rm -p 1455:1455 claude-proxy node /app/login.js
  fi

  echo ""
  echo "Open ${TARGET} in VS Code → Reopen in Container."
  echo "Credentials are stored in a Docker volume and will persist across rebuilds."
else
  echo "Open ${TARGET} in VS Code → Reopen in Container."
fi
