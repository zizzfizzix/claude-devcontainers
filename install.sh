#!/usr/bin/env bash
# Bootstrap a Claude Code devcontainer into a target repository.
#
# Interactive (prompts for template, directory, and extensions):
#   ./install.sh
#   bash <(curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh")
#
# Non-interactive:
#   ./install.sh [typescript|php|research] [target-directory]
#   curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript
#
# Local mode (copy from a local checkout instead of fetching from GitHub):
#   CLAUDE_DEVCONTAINERS_REPO=/path/to/local/checkout ./install.sh [typescript|php|research] [target-directory]
#
# target-directory defaults to the current directory.
# Set CLAUDE_DEVCONTAINERS_REPO to override the raw-file base URL or point to a local directory.
#
# Works on Linux, macOS, WSL, and Git Bash (Windows).

set -euo pipefail

# ANSI colors — empty strings when stdout is not a TTY
if [[ -t 1 ]]; then
  _BOLD='\033[1m'; _DIM='\033[2m'; _GREEN='\033[1;32m'; _BLUE='\033[1;34m'; _RESET='\033[0m'
else
  _BOLD=''; _DIM=''; _GREEN=''; _BLUE=''; _RESET=''
fi

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required. Install with: brew install jq  (macOS) or  apt install jq  (Linux)" >&2
  exit 1
}

REPO="${CLAUDE_DEVCONTAINERS_REPO:-https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main}"

# Detect local mode: REPO is a local path if it starts with /, ./, or ../
if [[ "$REPO" == /* || "$REPO" == ./* || "$REPO" == ../* ]]; then
  REPO="$(cd "$REPO" && pwd)"  # resolve to absolute path
  LOCAL_MODE=true
  [[ -d "$REPO" ]] || { echo "ERROR: local repo path '${REPO}' is not a directory" >&2; exit 1; }
else
  LOCAL_MODE=false
fi

_resolve_latest_tag() {
  if [[ "$LOCAL_MODE" == true ]]; then
    git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0-local"
  else
    curl -fsSL "https://api.github.com/repos/zizzfizzix/claude-devcontainers/releases/latest" \
      | jq -r '.tag_name'
  fi
}

TEMPLATES=(typescript php research)
DESCRIPTIONS=(
  "typescript  – Node.js / TypeScript (npm registry access)"
  "php         – PHP 8.2 + Composer (packagist / WordPress domains)"
  "research    – Markdown / notes (unrestricted network)"
)

if [[ $# -eq 0 && ! ( -t 0 && -t 1 ) ]]; then
  printf "ERROR: no template specified. When piping, pass the template explicitly:\n" >&2
  printf "  curl -fsSL '%s/install.sh' | bash -s -- typescript\n" \
    "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main" >&2
  exit 1
elif [[ $# -eq 0 ]]; then
  # ── Interactive mode ────────────────────────────────────────────────────────
  printf "\n${_BOLD}Claude Code Devcontainer Installer${_RESET}\n"
  printf "${_DIM}===================================${_RESET}\n\n"
  printf "${_BLUE}Select a template:${_RESET}\n\n"

  PS3=$'\nTemplate: '
  select desc in "${DESCRIPTIONS[@]}"; do
    idx=$(( REPLY - 1 ))
    if [[ $idx -ge 0 && $idx -lt ${#TEMPLATES[@]} ]]; then
      TEMPLATE="${TEMPLATES[$idx]}"
      break
    fi
    echo "Please enter a number between 1 and ${#TEMPLATES[@]}."
  done

  echo ""
  read -rp "Target directory [.]: " raw_target
  raw_target="${raw_target:-.}"
  TARGET="$(cd "$raw_target" && pwd)"

  echo ""
  echo "  Template : $TEMPLATE"
  echo "  Target   : $TARGET"
  echo ""
  read -rp "Proceed? [Y/n]: " confirm
  case "$confirm" in
    n|N|no|No|NO) echo "Aborted."; exit 0 ;;
  esac
else
  # ── Non-interactive mode (original behaviour) ───────────────────────────────
  TEMPLATE="${1:-typescript}"
  TARGET="$(cd "${2:-.}" && pwd)"
fi

# Validate template
valid=false
for t in "${TEMPLATES[@]}"; do [[ "$t" == "$TEMPLATE" ]] && valid=true && break; done
if [[ "$valid" == false ]]; then
  echo "ERROR: unknown template '${TEMPLATE}'. Available: ${TEMPLATES[*]}" >&2
  exit 1
fi

[[ -d "$TARGET" ]] || { echo "ERROR: '${TARGET}' is not a directory" >&2; exit 1; }

DEST="${TARGET}/.devcontainer"
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

# --- Fetch extension catalog ---
if [[ "$LOCAL_MODE" == true ]]; then
  EXT_CATALOG_JSON=$(cat "${REPO}/base/extensions.json")
else
  EXT_CATALOG_JSON=$(curl -fsSL "${REPO}/base/extensions.json")
fi

# Build arrays of optional extensions scoped to this template
_EXT_IDS=(); _EXT_LABELS=(); _EXT_STATES=()
while IFS= read -r _entry; do
  _eid=$(printf '%s' "$_entry"    | jq -r '.id')
  _elabel=$(printf '%s' "$_entry" | jq -r '.label')
  _edefault=$(printf '%s' "$_entry" | jq -r '.default // true')
  _EXT_IDS+=("$_eid")
  _EXT_LABELS+=("$_elabel")
  [[ "$_edefault" == "true" ]] && _EXT_STATES+=(1) || _EXT_STATES+=(0)
done < <(printf '%s' "$EXT_CATALOG_JSON" | jq -c --arg t "$TEMPLATE" \
  '.[] | select(.tier == "optional" and (.scopes | (contains(["all"]) or contains([$t]))))')

# Interactive extension toggle UI
if [[ -t 0 && -t 1 ]]; then
  while true; do
    printf "\n${_BLUE}VS Code extensions${_RESET} — toggle by number, Enter to accept:\n\n"
    for _i in "${!_EXT_IDS[@]}"; do
      if [[ "${_EXT_STATES[$_i]}" == "1" ]]; then
        printf "  ${_GREEN}[x]${_RESET} %2d. %-40s ${_DIM}%s${_RESET}\n" "$((_i+1))" "${_EXT_LABELS[$_i]}" "${_EXT_IDS[$_i]}"
      else
        printf "  ${_DIM}[ ] %2d. %-40s %s${_RESET}\n" "$((_i+1))" "${_EXT_LABELS[$_i]}" "${_EXT_IDS[$_i]}"
      fi
    done
    echo ""
    read -r -p "  Toggle (space-separated numbers) or Enter to accept: " _input || break
    [[ -z "$_input" ]] && break
    for _num in $_input; do
      if [[ "$_num" =~ ^[0-9]+$ ]] && (( _num >= 1 && _num <= ${#_EXT_IDS[@]} )); then
        _idx=$((_num - 1))
        [[ "${_EXT_STATES[$_idx]}" == "1" ]] && _EXT_STATES[$_idx]=0 || _EXT_STATES[$_idx]=1
      fi
    done
  done
fi

# Fetch every file listed in the template's manifest.
# Format: src:dest[:init]
#   src   — path relative to repo root
#   dest  — path relative to DEST
#   init  — optional flag: skip if the destination file already exists
_fetch_file() {
  local src="$1"
  if [[ "$LOCAL_MODE" == true ]]; then
    cat "${REPO}/${src}"
  else
    curl -fsSL "${REPO}/${src}"
  fi
}

_inject_extensions() {
  local devcontainer_file="$1"
  local catalog_file="$2"
  local local_file="$3"
  local template="$4"

  local base_exts
  base_exts=$(jq --arg t "$template" \
    '[.[] | select(.tier == "base" and (.scopes | (contains(["all"]) or contains([$t])))) | .id]' \
    "$catalog_file")

  local all_exts
  if [[ -f "$local_file" ]]; then
    all_exts=$(jq -n --argjson base "$base_exts" --argjson local "$(cat "$local_file")" \
      '$base + $local | unique')
  else
    all_exts="$base_exts"
  fi

  local tmp
  tmp=$(mktemp)
  jq --argjson exts "$all_exts" '.customizations.vscode.extensions = $exts' \
    "$devcontainer_file" > "$tmp"
  mv "$tmp" "$devcontainer_file"
}

if [[ "$LOCAL_MODE" == true ]]; then
  MANIFEST=$(cat "${REPO}/templates/${TEMPLATE}/manifest.txt")
else
  MANIFEST=$(curl -fsSL "${REPO}/templates/${TEMPLATE}/manifest.txt")
fi

while IFS=: read -r src dest flag; do
  [[ -z "$src" || "$src" == \#* ]] && continue
  if [[ -z "$dest" ]]; then
    echo "ERROR: malformed manifest line (missing dest field): '$src'" >&2
    exit 1
  fi
  outfile="${DEST}/${dest}"
  [[ "$flag" == "init" && -f "$outfile" ]] && continue
  mkdir -p "$(dirname "$outfile")"
  TMP=$(mktemp)
  if ! _fetch_file "$src" \
    | sed "s|__PROJECT_NAME__|${SAFE_PROJECT_NAME}|g;s|__WORKSPACE_FOLDER__|${SAFE_WORKSPACE_FOLDER}|g" \
    > "$TMP"; then
    rm -f "$TMP"
    echo "ERROR: failed to fetch '$src'" >&2
    exit 1
  fi
  mv "$TMP" "$outfile"
done <<< "$MANIFEST"

# Write extensions.local.json from the user's optional selections (init — created once).
EXT_LOCAL="${DEST}/extensions.local.json"
if [[ ! -f "$EXT_LOCAL" ]]; then
  _SELECTED_EXTS=""
  for _i in "${!_EXT_IDS[@]}"; do
    [[ "${_EXT_STATES[$_i]}" == "1" ]] || continue
    [[ -n "$_SELECTED_EXTS" ]] && _SELECTED_EXTS+=","
    _SELECTED_EXTS+="\"${_EXT_IDS[$_i]}\""
  done
  printf '[%s]\n' "$_SELECTED_EXTS" > "$EXT_LOCAL"
fi

# Inject the merged extensions list into devcontainer.json.
_inject_extensions "${DEST}/devcontainer.json" "${DEST}/extensions.json" "$EXT_LOCAL" "$TEMPLATE"

GITIGNORE="${TARGET}/.gitignore"
if ! grep -qF '.devcontainer/.data/' "$GITIGNORE" 2>/dev/null; then
  printf '\n# Claude Code devcontainer — local state (credentials, history)\n.devcontainer/.data/\n' >> "$GITIGNORE"
  echo "  Added .devcontainer/.data/ to ${GITIGNORE}"
fi

echo ""
echo "Open ${TARGET} in VS Code → Reopen in Container."
echo "On first use, run: claude /login"
echo "Credentials are stored in .devcontainer/.data/ and persist across rebuilds."
