# Versioning & Update Mechanism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add semver versioning, a safe upstream update mechanism, and a local override layer to claude-devcontainers so downstream projects can receive upstream improvements without losing customizations.

**Architecture:** Every install writes a `template@version` stamp; `sync` manifest files are always overwritten on update; user customizations live exclusively in `*.local.*` sibling files that upstream never touches. Extensions move from a hardcoded shell array to a `base/extensions.json` catalog; `jq` builds and injects the final extensions list into `devcontainer.json` at install/update time, eliminating the invalid-JSON `__VSCODE_EXTENSIONS__` substitution.

**Tech Stack:** Bash 3.2 (macOS-compatible), `jq` (new required dependency), `curl`, GitHub Releases API, semver git tags.

---

## File Map

| File | Status | Responsibility |
|------|--------|----------------|
| `base/extensions.json` | Create | Extension catalog — base/optional tiers, scopes, defaults |
| `base/update.sh` | Create | Self-updating upgrade script installed into each project |
| `base/stubs/docker-compose.override.yml` | Create | Stub with comments; installed as `init` |
| `base/stubs/postcreate.local.sh` | Create | Stub with comments; installed as `init` |
| `base/stubs/poststart.local.sh` | Create | Stub with comments; installed as `init` |
| `base/stubs/shell-config.local.zsh` | Create | Stub with comments; installed as `init` |
| `install.sh` | Modify | Add `jq` check, flag parsing, tag resolution, extensions via jq, auto-detect update, stamp write, `extensions.local.json` write |
| `base/postcreate.sh` | Modify | Source `postcreate.local.sh` at end if present |
| `base/poststart.sh` | Modify | Source `poststart.local.sh` at end if present |
| `base/shell-config.zsh` | Modify | Source `shell-config.local.zsh` at end if present |
| `templates/typescript/devcontainer.json` | Modify | `[__VSCODE_EXTENSIONS__]` → `[]` |
| `templates/php/devcontainer.json` | Modify | `[__VSCODE_EXTENSIONS__]` → `[]` |
| `templates/research/devcontainer.json` | Modify | `[__VSCODE_EXTENSIONS__]` → `[]` |
| `templates/typescript/manifest.txt` | Modify | Add `extensions.json`, `update.sh`, stubs as `:init` |
| `templates/php/manifest.txt` | Modify | Same |
| `templates/research/manifest.txt` | Modify | Same |

---

## Task 1: Create `base/extensions.json`

**Files:**
- Create: `base/extensions.json`

- [ ] **Step 1: Write the catalog file**

```json
[
  {"id": "Anthropic.claude-code",                   "label": "Claude Code",            "tier": "base",     "scopes": ["all"]},
  {"id": "eamodio.gitlens",                         "label": "GitLens",                "tier": "base",     "scopes": ["all"]},
  {"id": "CodeSmith.markdown-inline-editor-vscode", "label": "Markdown Inline Editor", "tier": "optional", "default": true, "scopes": ["all"]},
  {"id": "yzhang.markdown-all-in-one",              "label": "Markdown All-in-One",    "tier": "optional", "default": true, "scopes": ["all"]},
  {"id": "MermaidChart.vscode-mermaid-chart",       "label": "Mermaid Chart",          "tier": "optional", "default": true, "scopes": ["all"]},
  {"id": "jackiotyu.git-worktree-manager",          "label": "Git Worktree Manager",   "tier": "optional", "default": true, "scopes": ["all"]},
  {"id": "dbaeumer.vscode-eslint",                  "label": "ESLint",                 "tier": "optional", "default": true, "scopes": ["typescript"]},
  {"id": "esbenp.prettier-vscode",                  "label": "Prettier",               "tier": "optional", "default": true, "scopes": ["typescript", "php"]},
  {"id": "bmewburn.vscode-intelephense-client",     "label": "PHP Intelephense",       "tier": "optional", "default": true, "scopes": ["php"]},
  {"id": "xdebug.php-debug",                        "label": "PHP Debug",              "tier": "optional", "default": true, "scopes": ["php"]},
  {"id": "davidanson.vscode-markdownlint",          "label": "Markdownlint",           "tier": "optional", "default": true, "scopes": ["research"]}
]
```

- [ ] **Step 2: Verify valid JSON**

```bash
jq . base/extensions.json
```

Expected: pretty-printed JSON with no errors.

- [ ] **Step 3: Verify jq queries work correctly**

```bash
# Base extensions for typescript
jq -r '[.[] | select(.tier == "base" and (.scopes | (contains(["all"]) or contains(["typescript"])))) | .id]' base/extensions.json
# Expected: ["Anthropic.claude-code","eamodio.gitlens"]

# Optional extensions for php
jq -c '[.[] | select(.tier == "optional" and (.scopes | (contains(["all"]) or contains(["php"]))))]' base/extensions.json
# Expected: all-scoped optionals + php-scoped optionals
```

- [ ] **Step 4: Commit**

```bash
git add base/extensions.json
git commit -m "feat: add extensions catalog (base/extensions.json)"
```

---

## Task 2: Remove `__VSCODE_EXTENSIONS__` from devcontainer.json templates

**Files:**
- Modify: `templates/typescript/devcontainer.json`
- Modify: `templates/php/devcontainer.json`
- Modify: `templates/research/devcontainer.json`

- [ ] **Step 1: Update typescript template**

In `templates/typescript/devcontainer.json`, replace:
```json
      "extensions": [__VSCODE_EXTENSIONS__],
```
with:
```json
      "extensions": [],
```

- [ ] **Step 2: Update php template**

In `templates/php/devcontainer.json`, replace:
```json
      "extensions": [__VSCODE_EXTENSIONS__],
```
with:
```json
      "extensions": [],
```

- [ ] **Step 3: Update research template**

In `templates/research/devcontainer.json`, replace:
```json
      "extensions": [__VSCODE_EXTENSIONS__],
```
with:
```json
      "extensions": [],
```

- [ ] **Step 4: Verify all three are valid JSON**

```bash
jq . templates/typescript/devcontainer.json
jq . templates/php/devcontainer.json
jq . templates/research/devcontainer.json
```

Expected: no errors from any.

- [ ] **Step 5: Commit**

```bash
git add templates/typescript/devcontainer.json templates/php/devcontainer.json templates/research/devcontainer.json
git commit -m "fix: replace __VSCODE_EXTENSIONS__ substitution with empty array placeholder"
```

---

## Task 3: Source local override hooks in base scripts

**Files:**
- Modify: `base/postcreate.sh`
- Modify: `base/poststart.sh`
- Modify: `base/shell-config.zsh`

- [ ] **Step 1: Update `base/postcreate.sh`**

Append at the end of the file:

```bash

# Project-local postcreate hook — create .devcontainer/postcreate.local.sh to add project-specific setup.
if [[ -f "${DEVCONTAINER_DIR}/postcreate.local.sh" ]]; then
  bash "${DEVCONTAINER_DIR}/postcreate.local.sh"
fi
```

- [ ] **Step 2: Update `base/poststart.sh`**

Append at the end of the file (note `poststart.sh` does not define `DEVCONTAINER_DIR`; add the definition first, then the hook):

```bash

DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Project-local poststart hook — create .devcontainer/poststart.local.sh to add project-specific startup steps.
if [[ -f "${DEVCONTAINER_DIR}/poststart.local.sh" ]]; then
  bash "${DEVCONTAINER_DIR}/poststart.local.sh"
fi
```

- [ ] **Step 3: Update `base/shell-config.zsh`**

Append at the end of the file:

```zsh

# Project-local shell config — create .devcontainer/shell-config.local.zsh to add aliases, env vars, etc.
[[ -f /workspaces/*/.devcontainer/shell-config.local.zsh ]] && source /workspaces/*/.devcontainer/shell-config.local.zsh
```

Note: `shell-config.zsh` is installed system-wide into `/etc/zsh/zshrc.d/` by `postcreate.sh`, so it cannot use a relative path. The glob `/workspaces/*/.devcontainer/` matches the single project workspace directory.

- [ ] **Step 4: Verify syntax**

```bash
bash -n base/postcreate.sh
bash -n base/poststart.sh
zsh -n base/shell-config.zsh
```

Expected: no output (no syntax errors).

- [ ] **Step 5: Commit**

```bash
git add base/postcreate.sh base/poststart.sh base/shell-config.zsh
git commit -m "feat: source local override hooks at end of base scripts"
```

---

## Task 4: Create stub override files

**Files:**
- Create: `base/stubs/docker-compose.override.yml`
- Create: `base/stubs/postcreate.local.sh`
- Create: `base/stubs/poststart.local.sh`
- Create: `base/stubs/shell-config.local.zsh`

- [ ] **Step 1: Create `base/stubs/docker-compose.override.yml`**

```yaml
# docker-compose.override.yml — project-local Docker Compose overrides.
#
# Docker Compose automatically merges this file with docker-compose.yml.
# Use it to add extra services (databases, caches, etc.) or override
# service settings without editing the upstream docker-compose.yml.
#
# This file is never overwritten by upstream updates.
#
# Example — add a Postgres service:
#
# services:
#   postgres:
#     image: postgres:16
#     environment:
#       POSTGRES_PASSWORD: secret
#     volumes:
#       - postgres-data:/var/lib/postgresql/data
#
# volumes:
#   postgres-data:
```

- [ ] **Step 2: Create `base/stubs/postcreate.local.sh`**

```bash
#!/usr/bin/env bash
# postcreate.local.sh — project-local post-create setup.
#
# This script is sourced at the end of postcreate.sh after the container is
# first created. Use it for project-specific one-time setup steps.
#
# This file is never overwritten by upstream updates.
#
# Examples:
#   npm install
#   composer install
#   cp .env.example .env
```

- [ ] **Step 3: Create `base/stubs/poststart.local.sh`**

```bash
#!/usr/bin/env bash
# poststart.local.sh — project-local post-start setup.
#
# This script is sourced at the end of poststart.sh every time the container
# starts. Use it for project-specific startup steps.
#
# This file is never overwritten by upstream updates.
#
# Examples:
#   export DATABASE_URL=postgres://localhost/myapp
#   ./scripts/start-services.sh
```

- [ ] **Step 4: Create `base/stubs/shell-config.local.zsh`**

```zsh
# shell-config.local.zsh — project-local shell configuration.
#
# Sourced at the end of shell-config.zsh for every interactive zsh session.
# Use it for project-specific aliases, environment variables, and shell setup.
#
# This file is never overwritten by upstream updates.
#
# Examples:
#   alias dc='docker compose'
#   export NODE_ENV=development
```

- [ ] **Step 5: Commit**

```bash
git add base/stubs/
git commit -m "feat: add stub override files for project-local customization"
```

---

## Task 5: Create `base/update.sh`

**Files:**
- Create: `base/update.sh`

- [ ] **Step 1: Write the update script**

```bash
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
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n base/update.sh
shellcheck base/update.sh || true
```

Expected: no syntax errors. `shellcheck` may warn about the glob expand; those are acceptable.

- [ ] **Step 3: Commit**

```bash
git add base/update.sh
git commit -m "feat: add self-updating update.sh upgrade script"
```

---

## Task 6: Update all manifest files

**Files:**
- Modify: `templates/typescript/manifest.txt`
- Modify: `templates/php/manifest.txt`
- Modify: `templates/research/manifest.txt`

- [ ] **Step 1: Replace `templates/typescript/manifest.txt`**

```
base/claude/.claude.json:.data/claude/.claude.json:init
base/claude/settings.json:.data/claude/settings.json:init
base/claude-wt.zsh:claude-wt.zsh
base/postcreate.sh:postcreate.sh
base/poststart.sh:poststart.sh
base/shell-config.zsh:shell-config.zsh
proxy/addon.py:proxy/addon.py
proxy/Dockerfile:proxy/Dockerfile
proxy/start.sh:proxy/start.sh
templates/typescript/devcontainer.json:devcontainer.json
templates/typescript/docker-compose.yml:docker-compose.yml
base/features/acli/devcontainer-feature.json:features/acli/devcontainer-feature.json
base/features/acli/install.sh:features/acli/install.sh
base/extensions.json:extensions.json
base/update.sh:update.sh
base/stubs/docker-compose.override.yml:docker-compose.override.yml:init
base/stubs/postcreate.local.sh:postcreate.local.sh:init
base/stubs/poststart.local.sh:poststart.local.sh:init
base/stubs/shell-config.local.zsh:shell-config.local.zsh:init
```

- [ ] **Step 2: Replace `templates/php/manifest.txt`**

```
base/claude/.claude.json:.data/claude/.claude.json:init
base/claude/settings.json:.data/claude/settings.json:init
base/claude-wt.zsh:claude-wt.zsh
base/postcreate.sh:postcreate.sh
base/poststart.sh:poststart.sh
base/shell-config.zsh:shell-config.zsh
proxy/addon.py:proxy/addon.py
proxy/Dockerfile:proxy/Dockerfile
proxy/start.sh:proxy/start.sh
templates/php/devcontainer.json:devcontainer.json
templates/php/docker-compose.yml:docker-compose.yml
templates/php/postcreate-php.sh:postcreate-php.sh
base/features/acli/devcontainer-feature.json:features/acli/devcontainer-feature.json
base/features/acli/install.sh:features/acli/install.sh
base/extensions.json:extensions.json
base/update.sh:update.sh
base/stubs/docker-compose.override.yml:docker-compose.override.yml:init
base/stubs/postcreate.local.sh:postcreate.local.sh:init
base/stubs/poststart.local.sh:poststart.local.sh:init
base/stubs/shell-config.local.zsh:shell-config.local.zsh:init
```

- [ ] **Step 3: Replace `templates/research/manifest.txt`**

```
base/claude/.claude.json:.data/claude/.claude.json:init
base/claude/settings.json:.data/claude/settings.json:init
base/claude-wt.zsh:claude-wt.zsh
base/postcreate.sh:postcreate.sh
base/poststart.sh:poststart.sh
base/shell-config.zsh:shell-config.zsh
proxy/addon.py:proxy/addon.py
proxy/Dockerfile:proxy/Dockerfile
proxy/start.sh:proxy/start.sh
templates/research/devcontainer.json:devcontainer.json
templates/research/docker-compose.yml:docker-compose.yml
base/features/acli/devcontainer-feature.json:features/acli/devcontainer-feature.json
base/features/acli/install.sh:features/acli/install.sh
base/extensions.json:extensions.json
base/update.sh:update.sh
base/stubs/docker-compose.override.yml:docker-compose.override.yml:init
base/stubs/postcreate.local.sh:postcreate.local.sh:init
base/stubs/poststart.local.sh:poststart.local.sh:init
base/stubs/shell-config.local.zsh:shell-config.local.zsh:init
```

- [ ] **Step 4: Commit**

```bash
git add templates/typescript/manifest.txt templates/php/manifest.txt templates/research/manifest.txt
git commit -m "feat: update manifests — add extensions.json, update.sh, and local override stubs"
```

---

## Task 7: Refactor `install.sh` — extensions selection via jq

**Files:**
- Modify: `install.sh`

This task replaces the hardcoded `_EXT_REGISTRY` array with jq-based reading from `base/extensions.json`. The overall structure of `install.sh` is preserved; only the extension-related sections change.

- [ ] **Step 1: Add `jq` check after the color block (line ~27)**

After the colors block and before `REPO=...`, insert:

```bash
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required. Install with: brew install jq  (macOS) or  apt install jq  (Linux)" >&2
  exit 1
}
```

- [ ] **Step 2: Add `_resolve_latest_tag` function**

After the `LOCAL_MODE` detection block (after line ~38), insert:

```bash
_resolve_latest_tag() {
  if [[ "$LOCAL_MODE" == true ]]; then
    git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0-local"
  else
    curl -fsSL "https://api.github.com/repos/zizzfizzix/claude-devcontainers/releases/latest" \
      | jq -r '.tag_name'
  fi
}
```

- [ ] **Step 3: Replace the `_EXT_REGISTRY` block and extension selection UI**

Remove everything from `# --- VS Code extension selection ---` through `SAFE_VSCODE_EXTENSIONS=...` (lines 112–164) and replace with:

```bash
# --- Fetch extension catalog ---
if [[ "$LOCAL_MODE" == true ]]; then
  EXT_CATALOG_JSON=$(cat "${REPO}/base/extensions.json")
else
  EXT_CATALOG_JSON=$(curl -fsSL "${REPO}/base/extensions.json")
fi

# Build arrays of optional extensions scoped to this template
_EXT_IDS=(); _EXT_LABELS=(); _EXT_STATES=()
while IFS= read -r _entry; do
  _eid=$(printf '%s' "$_entry"   | jq -r '.id')
  _elabel=$(printf '%s' "$_entry" | jq -r '.label')
  _edefault=$(printf '%s' "$_entry" | jq -r '.default // true')
  _EXT_IDS+=("$_eid")
  _EXT_LABELS+=("$_elabel")
  [[ "$_edefault" == "true" ]] && _EXT_STATES+=(1) || _EXT_STATES+=(0)
done < <(printf '%s' "$EXT_CATALOG_JSON" | jq -c --arg t "$TEMPLATE" \
  '.[] | select(.tier == "optional" and (.scopes | (contains(["all"]) or contains([$t]))))')

# Interactive extension toggle UI (same UX as before, now driven by catalog)
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
```

- [ ] **Step 4: Add `_inject_extensions` function after `_fetch_file`**

After the `_fetch_file()` function definition (around line 178), add:

```bash
# Build and inject the final extensions list into a devcontainer.json file.
# Reads base extensions from the catalog and merges with extensions.local.json.
_inject_extensions() {
  local devcontainer_file="$1"
  local catalog_file="$2"   # .devcontainer/extensions.json
  local local_file="$3"     # .devcontainer/extensions.local.json (may not exist)
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
```

- [ ] **Step 5: Replace `SAFE_VSCODE_EXTENSIONS` usage in the manifest loop**

The manifest loop currently pipes through sed including `s|__VSCODE_EXTENSIONS__|...|g`. Remove `SAFE_VSCODE_EXTENSIONS` from the sed command — the line becomes:

```bash
  if ! _fetch_file "$src" \
    | sed "s|__PROJECT_NAME__|${SAFE_PROJECT_NAME}|g;s|__WORKSPACE_FOLDER__|${SAFE_WORKSPACE_FOLDER}|g" \
    > "$TMP"; then
```

- [ ] **Step 6: Write `extensions.local.json` and inject extensions after the manifest loop**

After the manifest loop's closing `done <<< "$MANIFEST"` line, add:

```bash
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
```

- [ ] **Step 7: Verify syntax**

```bash
bash -n install.sh
shellcheck install.sh || true
```

Expected: no syntax errors.

- [ ] **Step 8: Test fresh install (local mode)**

```bash
TEST_DIR=$(mktemp -d)
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh typescript "$TEST_DIR"
```

Expected:
- `.devcontainer/devcontainer.json` exists and contains `"Anthropic.claude-code"` in the extensions array
- `.devcontainer/extensions.json` exists (the catalog)
- `.devcontainer/extensions.local.json` exists with user's optional selections
- No `__VSCODE_EXTENSIONS__` anywhere in `.devcontainer/devcontainer.json`

```bash
jq '.customizations.vscode.extensions' "$TEST_DIR/.devcontainer/devcontainer.json"
grep -r '__VSCODE_EXTENSIONS__' "$TEST_DIR/.devcontainer/" && echo "FAIL" || echo "PASS"
```

- [ ] **Step 9: Commit**

```bash
git add install.sh
git commit -m "feat: replace hardcoded extension registry with jq-based extensions.json catalog"
```

---

## Task 8: Add versioning, stamp writing, and auto-detect to `install.sh`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add flag parsing before the interactive/non-interactive mode check**

After the `TEMPLATES`/`DESCRIPTIONS` arrays (around line 45), add:

```bash
# Parse named flags before positional args
VERSION_TAG=""
UPDATE_MODE=false
_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION_TAG="$2"; shift 2 ;;
    --update)  UPDATE_MODE=true; shift ;;
    *)         _ARGS+=("$1"); shift ;;
  esac
done
set -- "${_ARGS[@]+"${_ARGS[@]}"}"
```

- [ ] **Step 2: Add auto-detect update logic at the start of the interactive/non-interactive block**

The current check is `if [[ $# -eq 0 && ! ( -t 0 && -t 1 ) ]]; then`. Before that check, insert:

```bash
# Auto-detect: if --update was passed, read template from the stamp in the target dir.
if [[ "$UPDATE_MODE" == true && $# -eq 0 ]]; then
  _target_stamp="${2:-.}/.devcontainer/.upstream-version"
  [[ ! -f "$_target_stamp" ]] && { echo "ERROR: no .upstream-version found in target. Run install.sh without --update for a fresh install." >&2; exit 1; }
  _stamp_content=$(cat "$_target_stamp")
  set -- "${_stamp_content%@*}"  # inject template as positional arg
fi
```

- [ ] **Step 3: Add auto-detect prompt in interactive mode**

Inside the `elif [[ $# -eq 0 ]]; then` interactive block, after TARGET is set and before the `Proceed?` confirmation, insert:

```bash
  VERSION_STAMP="${TARGET}/.devcontainer/.upstream-version"
  if [[ -f "$VERSION_STAMP" ]]; then
    _existing=$(cat "$VERSION_STAMP")
    _latest=$(_resolve_latest_tag)
    printf "\n${_BOLD}Existing devcontainer found:${_RESET} %s\n" "$_existing"
    printf "Update to %s? [Y/n]: " "$_latest"
    read -r _upd_confirm
    case "$_upd_confirm" in
      n|N|no|No|NO) echo "Aborted."; exit 0 ;;
    esac
    UPDATE_MODE=true
    TEMPLATE="${_existing%@*}"
    VERSION_TAG="$_latest"
  elif [[ -d "${TARGET}/.devcontainer" ]]; then
    printf "\n${_BOLD}WARNING:${_RESET} Existing (unversioned) devcontainer found.\n"
    printf "Updating will overwrite devcontainer.json and docker-compose.yml.\n"
    printf "Review these files after update. Continue? [Y/n]: "
    read -r _upd_confirm
    case "$_upd_confirm" in
      n|N|no|No|NO) echo "Aborted."; exit 0 ;;
    esac
  fi
```

- [ ] **Step 4: Resolve and use the version tag**

After the template validation block (after the `if [[ "$valid" == false ]]` check), add:

```bash
# Resolve the version tag to use for fetching files.
if [[ -z "$VERSION_TAG" ]]; then
  VERSION_TAG=$(_resolve_latest_tag)
fi

# In remote mode, switch REPO base URL to the resolved tag.
if [[ "$LOCAL_MODE" == false ]]; then
  REPO="https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/${VERSION_TAG}"
fi
```

- [ ] **Step 5: Write the stamp file after `.gitignore` update**

At the very end of `install.sh`, before the final `echo` instructions, add:

```bash
# Write version stamp
echo "${TEMPLATE}@${VERSION_TAG}" > "${DEST}/.upstream-version"
```

- [ ] **Step 6: Verify syntax**

```bash
bash -n install.sh
shellcheck install.sh || true
```

- [ ] **Step 7: Test fresh install writes stamp**

```bash
TEST_DIR=$(mktemp -d)
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh typescript "$TEST_DIR"
cat "$TEST_DIR/.devcontainer/.upstream-version"
```

Expected output: something like `typescript@v0.0.0-local` (local mode returns the latest local tag or fallback).

- [ ] **Step 8: Test auto-detect re-run**

```bash
# Run again on same directory — should offer update prompt
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh typescript "$TEST_DIR"
```

Expected: detects existing stamp, shows `Existing devcontainer found: typescript@...`, prompts for update.

- [ ] **Step 9: Verify override stubs are created as init (not overwritten on re-run)**

```bash
echo "# my custom override" > "$TEST_DIR/.devcontainer/postcreate.local.sh"
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh typescript "$TEST_DIR"
# Accept the update prompt
cat "$TEST_DIR/.devcontainer/postcreate.local.sh"
```

Expected: still contains `# my custom override` (`:init` flag respected).

- [ ] **Step 10: Commit**

```bash
git add install.sh
git commit -m "feat: add versioning, stamp writing, and auto-detect update flow to install.sh"
```

---

## Task 9: Integration test — full local install and update simulation

**Files:** None (testing only)

- [ ] **Step 1: Fresh install — typescript**

```bash
TEST_DIR=$(mktemp -d)
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh typescript "$TEST_DIR"
```

Verify:
```bash
# Stamp exists
cat "$TEST_DIR/.devcontainer/.upstream-version"

# devcontainer.json is valid JSON with extensions populated
jq '.customizations.vscode.extensions | length > 0' "$TEST_DIR/.devcontainer/devcontainer.json"

# Catalog exists
jq '. | length > 0' "$TEST_DIR/.devcontainer/extensions.json"

# Local selections written
jq '. | type == "array"' "$TEST_DIR/.devcontainer/extensions.local.json"

# Stubs created
ls "$TEST_DIR/.devcontainer/postcreate.local.sh"
ls "$TEST_DIR/.devcontainer/docker-compose.override.yml"

# update.sh exists and has correct syntax
bash -n "$TEST_DIR/.devcontainer/update.sh"
```

Expected: all checks pass, no errors.

- [ ] **Step 2: Verify no `__VSCODE_EXTENSIONS__` remains anywhere**

```bash
grep -r '__VSCODE_EXTENSIONS__' "$TEST_DIR/.devcontainer/" && echo "FAIL" || echo "PASS"
```

Expected: `PASS`

- [ ] **Step 3: Verify override stubs survive re-install**

```bash
echo "# sentinel" >> "$TEST_DIR/.devcontainer/postcreate.local.sh"
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh typescript "$TEST_DIR"
grep -q "sentinel" "$TEST_DIR/.devcontainer/postcreate.local.sh" && echo "PASS" || echo "FAIL"
```

Expected: `PASS`

- [ ] **Step 4: Fresh install — php**

```bash
TEST_PHP=$(mktemp -d)
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh php "$TEST_PHP"
jq '.customizations.vscode.extensions' "$TEST_PHP/.devcontainer/devcontainer.json"
```

Expected: extensions array includes `esbenp.prettier-vscode` and `bmewburn.vscode-intelephense-client`.

- [ ] **Step 5: Fresh install — research**

```bash
TEST_RES=$(mktemp -d)
CLAUDE_DEVCONTAINERS_REPO="$(pwd)" ./install.sh research "$TEST_RES"
jq '.customizations.vscode.extensions' "$TEST_RES/.devcontainer/devcontainer.json"
```

Expected: extensions array includes `davidanson.vscode-markdownlint`.

- [ ] **Step 6: Run shellcheck on all modified scripts**

```bash
shellcheck install.sh base/postcreate.sh base/poststart.sh base/update.sh base/stubs/postcreate.local.sh base/stubs/poststart.local.sh
```

Expected: no errors (warnings about dynamic paths are acceptable).

---

## Task 10: Tag v1.0.0

**Files:** None (git operations only)

- [ ] **Step 1: Verify clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`

- [ ] **Step 2: Create and push the tag**

```bash
git tag -a v1.0.0 -m "feat: versioning, update mechanism, extension catalog, local override layer"
```

- [ ] **Step 3: Confirm the releases API will resolve correctly (dry run)**

```bash
# Simulate what _resolve_latest_tag would return after push
git describe --tags --abbrev=0
```

Expected: `v1.0.0`

- [ ] **Step 4: Push tag** (confirm with user before running)

```bash
git push origin v1.0.0
```

---

## Self-Review

**Spec coverage check:**

| Spec section | Covered by |
|---|---|
| Semver git tags | Task 10 |
| `.upstream-version` stamp (template@version) | Task 8 step 5 |
| Latest tag resolution via GitHub API | Task 7 step 2 + Task 8 step 4 |
| Sync / init manifest tiers | Task 6 |
| `devcontainer.json` + `docker-compose.yml` as sync | Task 6 (no `:init` flag) |
| Override layer — shell scripts | Task 3 |
| Override layer — docker-compose.override.yml | Task 4 + Task 6 |
| Override layer — extensions.local.json | Task 7 steps 6 |
| Stub files created on first install | Task 4 + Task 6 |
| Extensions catalog `base/extensions.json` | Task 1 |
| Base / optional tier split | Task 1 |
| `jq` required, checked at startup | Task 7 step 1 |
| `__VSCODE_EXTENSIONS__` eliminated | Task 2 + Task 7 step 5 |
| `update.sh` self-updates before running | Task 5 |
| `update.sh` syncs sync files, skips init | Task 5 |
| `update.sh` re-injects extensions | Task 5 |
| `install.sh` auto-detects existing devcontainer | Task 8 step 3 |
| Unversioned migration warning | Task 8 step 3 |
| `--update` flag + `--version` flag | Task 8 steps 1-2 |
| Delta summary with GitHub compare URL | Task 5 |
