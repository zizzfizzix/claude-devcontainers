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

PROJECT_NAME="${TARGET##*/}"
WORKSPACE_FOLDER="/${PROJECT_NAME}"

# Escape values for use as sed replacement strings (delimiter is |)
_sed_escape() { printf '%s\n' "$1" | sed 's/[\\&|]/\\&/g'; }
SAFE_PROJECT_NAME=$(_sed_escape "$PROJECT_NAME")
SAFE_WORKSPACE_FOLDER=$(_sed_escape "$WORKSPACE_FOLDER")

# Create the bind-mount data directories and keep them out of git.
mkdir -p "${DEST}/.data/history" "${DEST}/.data/proxy" "${DEST}/.data/certs"

# Fetch every file listed in the template's manifest.
# Format: src:dest[:init]
#   src   — path relative to repo root
#   dest  — path relative to DEST
#   init  — optional flag: skip if the destination file already exists
MANIFEST=$(curl -fsSL "${REPO}/templates/${TEMPLATE}/manifest.txt")
while IFS=: read -r src dest flag; do
  [[ -z "$src" || "$src" == \#* ]] && continue
  if [[ -z "$dest" ]]; then
    echo "ERROR: malformed manifest line (missing dest field): '$src'" >&2
    exit 1
  fi
  outfile="${DEST}/${dest}"
  [[ "$flag" == "init" && -f "$outfile" ]] && continue
  mkdir -p "$(dirname "$outfile")"
  curl -fsSL "${REPO}/${src}" \
    | sed "s|__PROJECT_NAME__|${SAFE_PROJECT_NAME}|g;s|__WORKSPACE_FOLDER__|${SAFE_WORKSPACE_FOLDER}|g" \
    > "$outfile"
done <<< "$MANIFEST"

GITIGNORE="${TARGET}/.gitignore"
if ! grep -qF '.devcontainer/.data/' "$GITIGNORE" 2>/dev/null; then
  printf '\n# Claude Code devcontainer — local state (credentials, history)\n.devcontainer/.data/\n' >> "$GITIGNORE"
  echo "  Added .devcontainer/.data/ to ${GITIGNORE}"
fi

echo ""
echo "Open ${TARGET} in VS Code → Reopen in Container."
echo "On first use, run: claude /login"
echo "Credentials are stored in .devcontainer/.data/ and persist across rebuilds."
