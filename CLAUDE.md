# Claude Code Devcontainers

Baseline devcontainer configs for Claude Code — installs a firewall-restricted dev environment into any repo via a single `install.sh` invocation.

## Stack & Layout

- Pure Bash — no build system, no package manager
- `install.sh` — bootstraps a template into a target repo (local or via `curl | bash`); requires `jq`
- `src/base/` — shared shell config, postcreate/poststart hooks, Claude settings, extension catalog, update script, proxy sidecar
- `src/base/proxy/` — mitmproxy sidecar: iptables firewall + OAuth token swap
- `src/templates/typescript|php|research/` — per-template `devcontainer.json`, `docker-compose.yml`, `manifest.txt`, `version.txt`
- Each `manifest.txt` lists `src:dest` (sync) or `src:dest:init` (init-once) lines that `install.sh` copies/fetches

## Key Commands

```bash
# Interactive installer (prompts for template + directory)
./install.sh

# Non-interactive: pass template (and optional target directory) directly
./install.sh typescript [target-directory]

# From a local checkout of this repo (interactive)
CLAUDE_DEVCONTAINERS_REPO=/path/to/this/repo ./install.sh

# Update an existing install to the latest upstream version
.devcontainer/update.sh

# Lint shell scripts (if shellcheck is available)
shellcheck install.sh src/base/*.sh src/base/proxy/start.sh
```

## Manifest File Tiers

Each line in `manifest.txt` is `src:dest` or `src:dest:init`:

- **sync** (`src:dest`) — overwritten on every `update.sh` run; upstream owns these files
- **init** (`src:dest:init`) — installed once and never touched again; the project owns these

Init files are stubs for local customization: `postcreate.local.sh`, `poststart.local.sh`, `shell-config.local.zsh`, `docker-compose.override.yml`.

## Local Override Layer

Upstream scripts source local overrides at the end of their execution:

- `postcreate.sh` → sources `postcreate.local.sh` if present
- `poststart.sh` → sources `poststart.local.sh` if present
- `shell-config.zsh` → sources `shell-config.local.zsh` if present
- `docker-compose.override.yml` — auto-merged by Dev Containers (array in `dockerComposeFile`)

Never add `*.local.*` files to `manifest.txt` — they are project-owned and safe from upstream overwrites.

## Extensions

`src/base/extensions.json` is the extension catalog. Each entry has:

- `id` — VS Code extension ID
- `label` — display name shown in the install prompt
- `tier` — `"base"` (always installed) or `"optional"` (user-selectable)
- `default` — whether optional extensions are pre-checked
- `scopes` — `["all"]` or a list of template names where the extension is relevant

During install, `jq` injects selected extensions into `devcontainer.json`. User selections are persisted to `extensions.local.json` (an init file), which `update.sh` re-reads on every upgrade so the selection survives.

## Update Mechanism

`update.sh` (a sync file, always upgraded by `update.sh` itself):

1. Fetches the latest `update.sh` from upstream and re-execs itself with `_DC_UPDATING=1` to ensure the updater is always current
2. Reads `.devcontainer/.upstream-version` (format: `typescript@v1.2.0`) for the template name and current version
3. Resolves the latest GitHub release tag for that template
4. Syncs all `sync` manifest files; skips `init` files
5. Re-injects extensions (base catalog + `extensions.local.json`)
6. Writes the new version stamp and prints a GitHub compare URL

## Versioning

Each template is versioned independently via Release Please (manifest mode):

- `src/templates/<name>/version.txt` — current version for that template
- `.release-please-manifest.json` — Release Please state
- `release-please-config.json` — package definitions; `src/base/` changes bump all templates
- GitHub releases tagged as `typescript-v1.0.0`, `php-v1.0.0`, `research-v1.0.0`

## Shell Compatibility

`install.sh` and `update.sh` must be compatible with **bash 3.2** (macOS default). Avoid bash 4+ features:

- Use `case "$var" in n|N|no|No|NO)` instead of `${var,,}` (lowercase expansion)
- Use indexed arrays only — no associative arrays (`declare -A`)
- Test with `bash --version` if unsure; macOS ships 3.2 due to GPLv3 licensing

## Adding a Template

1. Create `src/templates/<name>/devcontainer.json`, `docker-compose.yml`, `manifest.txt`, `version.txt` (start at `0.0.0`)
2. Add `<name>` to the `TEMPLATES` and `DESCRIPTIONS` arrays in `install.sh`
3. Add a package entry to `release-please-config.json` and `.release-please-manifest.json`
4. Add relevant scopes to entries in `src/base/extensions.json` if needed

Update this file when you discover project conventions, preferences, or patterns worth preserving for future Claude Code sessions — keep it under 300 lines.
