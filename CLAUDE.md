# Claude Code Devcontainers

Baseline devcontainer configs for Claude Code — installs a firewall-restricted dev environment into any repo via a single `install.sh` invocation.

## Stack & Layout

- Pure Bash — no build system, no package manager
- `install.sh` — bootstraps a template into a target repo (local or via `curl | bash`)
- `base/` — shared shell config, postcreate/poststart hooks, Claude settings
- `proxy/` — mitmproxy sidecar: iptables firewall + OAuth token swap
- `templates/typescript|php|research/` — per-template `devcontainer.json`, `docker-compose.yml`, `manifest.txt`
- Each `manifest.txt` lists `src:dest[:init]` lines that `install.sh` copies/fetches

## Key Commands

```bash
# Interactive installer (prompts for template + directory)
./install.sh

# Non-interactive: pass template (and optional target directory) directly
./install.sh typescript [target-directory]

# From a local checkout of this repo (interactive)
CLAUDE_DEVCONTAINERS_REPO=/path/to/this/repo ./install.sh

# Lint shell scripts (if shellcheck is available)
shellcheck install.sh base/*.sh proxy/start.sh
```

## Adding a Template

1. Create `templates/<name>/devcontainer.json`, `docker-compose.yml`, `manifest.txt`
2. Add `<name>` to the `TEMPLATES` and `DESCRIPTIONS` arrays in `install.sh`

Update this file when you discover project conventions, preferences, or patterns worth preserving for future Claude Code sessions — keep it under 300 lines.
