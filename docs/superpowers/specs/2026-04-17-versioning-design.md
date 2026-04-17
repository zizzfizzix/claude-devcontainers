# Versioning & Update Mechanism Design

**Date:** 2026-04-17  
**Status:** Approved

## Problem

Downstream projects that use claude-devcontainers have no way to receive upstream improvements. Every file is copied at install time with no record of what version was installed, and no mechanism to update without overwriting local customizations.

## Goals

1. Downstream projects can update to the latest upstream changes safely
2. Local customizations survive updates
3. `devcontainer.json` JSON validation errors are eliminated
4. Update flow is simple enough to run from inside the container

## Non-Goals

- Version pinning (versions are for delta awareness only, updates always go to latest)
- Per-file conflict resolution
- Supporting `main`/branch tracking (released tags only)

---

## Design

### 1. Versioning

The repo uses semver git tags (`v1.0.0`, `v1.1.0`, …). Every install writes a stamp file:

```
.devcontainer/.upstream-version
```

Contents: `typescript@v1.2.0` (template name + installed version). The stamp is always present after install — there is no `main` or unversioned state going forward. At install time, `install.sh` resolves the latest tag via the GitHub API unless `--version v1.x.x` is passed explicitly.

The stamp is purely informational: it tells `update.sh` what version was previously installed so it can surface a meaningful delta (changelog link or tag comparison URL). It does not pin the project to that version.

### 2. File Ownership

The manifest gains a third tier alongside the existing `init` flag:

| Tier | Manifest flag | Files | On update |
|------|--------------|-------|-----------|
| `sync` | (default, no flag) | `postcreate.sh`, `poststart.sh`, `shell-config.zsh`, `proxy/*`, `features/*`, `update.sh`, `devcontainer.json`, `docker-compose.yml` | Always overwritten |
| `init` | `:init` | `.data/claude/.claude.json`, `.data/claude/settings.json` | Installed once, never touched again |
| User-owned | not in manifest | `*.local.*` files, `docker-compose.override.yml` | Never touched by any upstream tooling |

`devcontainer.json` and `docker-compose.yml` move from implicitly user-owned to `sync`. Upstream always wins on these files. Users extend them via the override layer below.

### 3. Override Layer

Users never edit `sync` files directly. Instead, additive override files are sourced/merged at runtime:

| Override file | Mechanism |
|--------------|-----------|
| `docker-compose.override.yml` | Docker Compose merges this natively with `docker-compose.yml` |
| `postcreate.local.sh` | Sourced at the end of `postcreate.sh` if the file exists |
| `poststart.local.sh` | Sourced at the end of `poststart.sh` if the file exists |
| `shell-config.local.zsh` | Sourced at the end of `shell-config.zsh` if the file exists |
| `selected-extensions.local.json` | Merged with `selected-extensions.json` by the vscode-extensions feature |

On first install, stub versions of each override file are created with explanatory comments. These stubs are `init`-flagged so they are never overwritten.

### 4. Extensions

#### Registry — `base/extensions.json` (sync)

The extension registry moves out of `install.sh` into a standalone `base/extensions.json` data file:

```json
[
  {"id": "Anthropic.claude-code",              "label": "Claude Code",           "tier": "base",     "scopes": ["all"]},
  {"id": "eamodio.gitlens",                    "label": "GitLens",               "tier": "base",     "scopes": ["all"]},
  {"id": "dbaeumer.vscode-eslint",             "label": "ESLint",                "tier": "optional", "default": true,  "scopes": ["typescript"]},
  {"id": "esbenp.prettier-vscode",             "label": "Prettier",              "tier": "optional", "default": true,  "scopes": ["typescript", "php"]},
  ...
]
```

Two tiers:
- **`base`** — always installed; never shown in the interactive selection UI; written into `selected-extensions.json` on install/update
- **`optional`** — presented in the toggle UI at install time; user's choices written to `selected-extensions.local.json`

`install.sh` requires `jq` to read this file. It checks for `jq` at startup and exits with a clear install instruction if missing.

#### Runtime — `./features/vscode-extensions` (new devcontainer feature)

Replaces the `__VSCODE_EXTENSIONS__` sed substitution. Reads at container build time:

- `selected-extensions.json` — base extensions written by `install.sh`/`update.sh`; `sync` tier
- `selected-extensions.local.json` — optional selections from interactive install; `init` tier; user edits freely

Merges both lists (deduplicating) and installs them as VS Code extensions.

This eliminates the only substitution in `devcontainer.json` that produced invalid JSON. The remaining substitutions (`__PROJECT_NAME__`, `__WORKSPACE_FOLDER__`) are valid JSON strings and cause no validation errors. No templating language is needed.

### 5. Update Mechanism

#### `update.sh` (sync file, lives in `.devcontainer/`)

Modelled after oh-my-zsh's upgrade script:

1. **Self-update first:** fetches the latest `update.sh` from upstream, writes it over itself, then `exec`s the new version. This ensures the updater logic is never stale.
2. **Resolve latest tag** via GitHub API.
3. **Overwrite all `sync` files** from the latest tag.
4. **Write new stamp** to `.upstream-version`.
5. **Print delta summary:** previous version → new version, with a GitHub comparison URL (`/compare/v1.0.0...v1.2.0`).

Works identically from the host or from inside the container.

#### `install.sh` auto-detect

When `install.sh` runs against a target directory that already contains `.devcontainer/.upstream-version`, it detects this and offers an update flow instead of a fresh install:

```
Devcontainer typescript@v1.0.0 found. Update to v1.2.0? [Y/n]:
```

Accepting runs the same logic as `update.sh`. Non-interactive: `install.sh --update` (template read from stamp) or `install.sh typescript --update`.

---

## Migration from Unversioned Installs

Projects installed before versioning was introduced have no `.upstream-version` stamp. When `install.sh` detects a `.devcontainer/` directory without a stamp, it offers:

```
Existing devcontainer found (unversioned). Update to v1.2.0? [Y/n]:
```

Accepting runs the full update flow and writes the stamp for the first time. The user is warned to review their `docker-compose.yml` and `devcontainer.json` after the update since those files were previously user-owned and will now be overwritten.

---

## File Changes Summary

| File | Change |
|------|--------|
| `install.sh` | Add `jq` check, `--version` flag, latest-tag resolution, auto-detect update flow, write stamp, create override stubs; read extension registry from `base/extensions.json` |
| `base/extensions.json` | New: extension registry with `base`/`optional` tiers and per-template scopes |
| `templates/*/manifest.txt` | All files become `sync` except `.data/claude/*` which stay `init`; add `selected-extensions.json`; add stub override files as `init` |
| `templates/*/devcontainer.json` | Remove `__VSCODE_EXTENSIONS__`; reference new `./features/vscode-extensions` feature |
| `base/postcreate.sh` | Source `postcreate.local.sh` at end if present |
| `base/poststart.sh` | Source `poststart.local.sh` at end if present |
| `base/shell-config.zsh` | Source `shell-config.local.zsh` at end if present |
| `base/features/vscode-extensions/` | New feature: reads + merges `selected-extensions.json` and `selected-extensions.local.json` |
| `base/update.sh` | New sync file: self-updating upgrade script (fetched into `.devcontainer/update.sh`) |
| Stub override files | `docker-compose.override.yml`, `postcreate.local.sh`, `poststart.local.sh`, `shell-config.local.zsh` — created as `init` on first install |
