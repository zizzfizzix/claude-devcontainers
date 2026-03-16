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
# Bootstrap a template into the current directory
./install.sh typescript [target-directory]

# Or from a local checkout of this repo
CLAUDE_DEVCONTAINERS_REPO=/path/to/this/repo ./install.sh typescript /path/to/target

# Lint shell scripts (if shellcheck is available)
shellcheck install.sh base/*.sh proxy/start.sh
```

## Adding a Template

1. Create `templates/<name>/devcontainer.json`, `docker-compose.yml`, `manifest.txt`
2. Add `<name>` to the `case` statement in `install.sh`

Update this file when you discover project conventions, preferences, or patterns worth preserving for future Claude Code sessions — keep it under 300 lines.
