#!/usr/bin/env bash
# update.sh — upgrade the devcontainer to the latest upstream release.
#
# Run from inside the container or on the host:
#   bash .devcontainer/update.sh
#
# This script always self-updates first (fetches the latest version of itself
# from upstream, then exec's it) so the updater logic is never stale.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP_FILE="${SCRIPT_DIR}/.upstream-version"
REPO_OWNER="zizzfizzix"
REPO_NAME="claude-devcontainers"
GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}"

if [[ -t 1 ]]; then
  _BOLD='\033[1m'; _GREEN='\033[1;32m'; _BLUE='\033[1;34m'; _DIM='\033[2m'; _RESET='\033[0m'
else
  _BOLD=''; _GREEN=''; _BLUE=''; _DIM=''; _RESET=''
fi

command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq is required. Install with: apt install jq" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; exit 1; }

_resolve_latest_tag() {
  curl -fsSL "${GITHUB_API}/releases/latest" | jq -r '.tag_name'
}

# ── Phase 1: self-update ───────────────────────────────────────────────────────
# Fetch the latest update.sh and exec it so we always run the newest updater.
# _DC_UPDATING=1 prevents the exec'd copy from looping back into this block.
if [[ "${_DC_UPDATING:-}" != "1" ]]; then
  LATEST_TAG=$(_resolve_latest_tag)
  TMP_SELF=$(mktemp)
  curl -fsSL "${RAW_BASE}/${LATEST_TAG}/base/update.sh" > "$TMP_SELF"
  chmod +x "$TMP_SELF"
  _DC_UPDATING=1 _DC_LATEST_TAG="$LATEST_TAG" exec bash "$TMP_SELF"
fi

# ── Phase 2: read stamp ────────────────────────────────────────────────────────
if [[ ! -f "$STAMP_FILE" ]]; then
  echo "ERROR: ${STAMP_FILE} not found. Run install.sh to initialise." >&2
  exit 1
fi

STAMP=$(cat "$STAMP_FILE")
TEMPLATE="${STAMP%@*}"
CURRENT_VERSION="${STAMP#*@}"

# Re-use the tag resolved in Phase 1 to avoid a second API call.
LATEST_TAG="${_DC_LATEST_TAG:-$(_resolve_latest_tag)}"

if [[ "$CURRENT_VERSION" == "$LATEST_TAG" ]]; then
  printf "${_GREEN}Already up to date${_RESET} (%s@%s)\n" "$TEMPLATE" "$LATEST_TAG"
  exit 0
fi

printf "${_BOLD}Updating${_RESET} %s: %s → %s\n\n" "$TEMPLATE" "$CURRENT_VERSION" "$LATEST_TAG"

# ── Phase 3: read project identity from current devcontainer.json ──────────────
PROJECT_NAME=$(jq -r '.name' "${SCRIPT_DIR}/devcontainer.json")
WORKSPACE_FOLDER=$(jq -r '.workspaceFolder' "${SCRIPT_DIR}/devcontainer.json")

_sed_escape() { printf '%s\n' "$1" | sed 's/[\\&|]/\\&/g'; }
SAFE_PROJECT_NAME=$(_sed_escape "$PROJECT_NAME")
SAFE_WORKSPACE_FOLDER=$(_sed_escape "$WORKSPACE_FOLDER")

# ── Phase 4: sync upstream files ───────────────────────────────────────────────
MANIFEST=$(curl -fsSL "${RAW_BASE}/${LATEST_TAG}/templates/${TEMPLATE}/manifest.txt")

while IFS=: read -r src dest flag; do
  [[ -z "$src" || "$src" == \#* ]] && continue
  [[ -z "$dest" ]] && { echo "ERROR: malformed manifest line: '$src'" >&2; exit 1; }
  [[ "$flag" == "init" ]] && continue  # never overwrite init files
  outfile="${SCRIPT_DIR}/${dest}"
  mkdir -p "$(dirname "$outfile")"
  TMP=$(mktemp)
  if ! curl -fsSL "${RAW_BASE}/${LATEST_TAG}/${src}" \
    | sed "s|__PROJECT_NAME__|${SAFE_PROJECT_NAME}|g;s|__WORKSPACE_FOLDER__|${SAFE_WORKSPACE_FOLDER}|g" \
    > "$TMP"; then
    rm -f "$TMP"
    echo "ERROR: failed to fetch '${src}'" >&2
    exit 1
  fi
  mv "$TMP" "$outfile"
  printf "  ${_DIM}synced${_RESET}  %s\n" "$dest"
done <<< "$MANIFEST"

# ── Phase 5: re-inject extensions into devcontainer.json ──────────────────────
EXT_CATALOG="${SCRIPT_DIR}/extensions.json"
EXT_LOCAL="${SCRIPT_DIR}/extensions.local.json"

BASE_EXTS=$(jq --arg t "$TEMPLATE" \
  '[.[] | select(.tier == "base" and (.scopes | (contains(["all"]) or contains([$t])))) | .id]' \
  "$EXT_CATALOG")

if [[ -f "$EXT_LOCAL" ]]; then
  ALL_EXTS=$(jq -n --argjson base "$BASE_EXTS" --argjson local "$(cat "$EXT_LOCAL")" \
    '$base + $local | unique')
else
  ALL_EXTS="$BASE_EXTS"
fi

TMP=$(mktemp)
jq --argjson exts "$ALL_EXTS" '.customizations.vscode.extensions = $exts' \
  "${SCRIPT_DIR}/devcontainer.json" > "$TMP"
mv "$TMP" "${SCRIPT_DIR}/devcontainer.json"

# ── Phase 6: write stamp ───────────────────────────────────────────────────────
echo "${TEMPLATE}@${LATEST_TAG}" > "$STAMP_FILE"

printf "\n${_GREEN}Updated${_RESET} to %s@%s\n" "$TEMPLATE" "$LATEST_TAG"
printf "Changes: ${_BLUE}https://github.com/%s/%s/compare/%s...%s${_RESET}\n" \
  "$REPO_OWNER" "$REPO_NAME" "$CURRENT_VERSION" "$LATEST_TAG"
