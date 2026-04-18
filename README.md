# Claude Code Devcontainers

Baseline devcontainer configs for [Claude Code](https://claude.ai/code). Adds a secure, firewall-restricted dev environment to any repo in one command.

> **Requires [`jq`](https://jqlang.github.io/jq/)** — used by the installer and updater to manage extensions.

## Bootstrap a new repo

**Interactive** — prompts for template, target directory, and VS Code extensions:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh")
```

> `install.sh` downloads only the files it needs — no clone required.

**Non-interactive** — pass the template (and optionally a target directory) as arguments:

```bash
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript /path/to/project
```

Then open the folder in VS Code → **Reopen in Container**.

### Windows

The installer works in **Git Bash** (ships with [Git for Windows](https://gitforwindows.org/)). Use the non-interactive form (`curl | bash -s -- typescript`) — `bash <(...)` process substitution is not supported in Git Bash.

## Updating an existing install

Run `update.sh` from inside the container (or directly on the host):

```bash
.devcontainer/update.sh
```

The updater fetches the latest upstream version of itself first, then syncs all upstream-owned files while leaving your project-local customizations untouched. It prints a GitHub compare URL so you can review what changed.

## Templates

| Template     | Base image                                        | Extra tooling                                    |
| ------------ | ------------------------------------------------- | ------------------------------------------------ |
| `typescript` | `mcr.microsoft.com/devcontainers/base:debian`     | Node 24, git-delta, Claude Code                  |
| `php`        | `mcr.microsoft.com/devcontainers/base:debian`     | PHP 8.2 + extensions, Composer, WP-CLI, Node 24  |
| `research`   | `mcr.microsoft.com/devcontainers/base:debian`     | Pandoc, ripgrep, Markdown tools — firewall disabled (`UNRESTRICTED_NETWORK=true`) |

All templates include:

- Claude Code with `--dangerously-skip-permissions` aliased (safe inside the firewall-restricted container)
- `iptables` firewall: allowlists only necessary outbound domains, drops everything else
- Transparent HTTPS proxy (mitmproxy) with OAuth credential management
- Persistent shell history and Claude config across container rebuilds
- git-delta, fzf, zsh

## First use

After the container starts, authenticate Claude Code:

```bash
claude /login
```

Credentials are persisted in `.devcontainer/.data/proxy/credentials.json` and survive container rebuilds.

## What gets installed

```
.devcontainer/
├── proxy/
│   ├── Dockerfile                  # mitmproxy sidecar image
│   ├── addon.py                    # token swap + request inspection
│   └── start.sh                    # firewall setup + transparent proxy launch
├── claude-wt.zsh                   # git worktree helper for multi-branch Claude sessions
├── devcontainer.json
├── docker-compose.yml
├── docker-compose.override.yml     # project-local Docker Compose overrides (yours to edit)
├── extensions.json                 # upstream extension catalog
├── extensions.local.json           # your extension selections (generated on install)
├── postcreate.sh
├── postcreate.local.sh             # project-local post-create hook (yours to edit)
├── poststart.sh
├── poststart.local.sh              # project-local post-start hook (yours to edit)
├── shell-config.zsh
├── shell-config.local.zsh          # project-local shell config (yours to edit)
├── update.sh                       # upstream update script
└── .upstream-version               # version stamp, e.g. typescript@v1.2.0
```

Files marked "yours to edit" are installed once and never overwritten by `update.sh`.

## Customizing without forking

`update.sh` distinguishes between **upstream-owned** files (always synced) and **project-local** files (installed once, never touched again). Customize via the local files:

| What you want to customize | File to edit |
| -------------------------- | ------------ |
| Extra packages, repo setup | `postcreate.local.sh` |
| Per-session startup logic  | `poststart.local.sh` |
| Shell aliases, exports     | `shell-config.local.zsh` |
| Extra Docker services      | `docker-compose.override.yml` |
| VS Code extension selection | `extensions.local.json` |

## VS Code extensions

`extensions.json` is the upstream extension catalog. Extensions have two tiers:

- **base** — always installed (Claude Code, GitLens)
- **optional** — shown in the install prompt; your choices are saved to `extensions.local.json`

`update.sh` re-reads `extensions.local.json` on every upgrade so your selections survive.

## How the proxy works

The `claude-proxy` sidecar runs mitmproxy as a transparent HTTPS proxy alongside an `iptables`/`nftables` firewall. All outbound traffic from the dev container is redirected through it.

- **Domain allowlist**: only requests to whitelisted domains (GitHub, npm, Anthropic, VS Code, etc.) are forwarded; all others get a 403.
- **Credential management**: real OAuth tokens are captured from login responses, stored in `.devcontainer/.data/proxy/credentials.json`, and replaced with dummy tokens that are swapped back transparently on every outbound request. This prevents real tokens from appearing in Claude's context or logs.
- **CA certificate**: the proxy CA is automatically trusted in the system store and Python's `certifi` bundle on container start.

## Extending the firewall allowlist

Add extra domains via the `claude-proxy` service environment — no script fork needed:

```yaml
claude-proxy:
  environment:
    EXTRA_ALLOWED_DOMAINS: "registry.example.com cdn.example.com"
```

The proxy resolves and allowlists them at container start.

## Disabling the firewall

To allow all outbound traffic (e.g. for initial setup or debugging):

```yaml
claude-proxy:
  environment:
    UNRESTRICTED_NETWORK: "true"
```

## Forwarding host credentials

Host credentials are forwarded into the container before it starts via `initializeCommand` scripts. Each integration reads env vars from the host, writes them to `.devcontainer/.data/`, and the container loads them at startup.

### GitHub CLI (`gh`)

If `gh` is installed and authenticated on the host, the token is read automatically via `gh auth token` and forwarded into the container — no manual setup required.

### Atlassian CLI (`acli`)

Set the following env vars on the host before opening in container:

| Variable | Description |
| -------- | ----------- |
| `ATLASSIAN_API_TOKEN` | Atlassian API token |
| `ATLASSIAN_EMAIL` | Account email |
| `ATLASSIAN_SITE` | Site name (e.g. `myorg.atlassian.net`) |

`postcreate.sh` will authenticate `acli` for both Jira and Confluence automatically. If the vars are not set, the step is silently skipped.

## Git worktree helper

`claude-wt.zsh` provides a `claude-wt <branch>` function that creates a git worktree for `<branch>`, injects a one-shot VS Code task to launch Claude Code, and reopens VS Code into that worktree. Useful for running multiple Claude sessions on different branches simultaneously.

## Local usage (from a clone)

Interactive:

```bash
./install.sh
```

Non-interactive:

```bash
./install.sh [typescript|php|research] [target-directory]
```

`target-directory` defaults to the current directory.

## Repo layout

```
├── base/
│   ├── claude/
│   │   └── settings.json
│   ├── stubs/                      # init-only stub files installed into projects
│   ├── claude-wt.zsh
│   ├── extensions.json             # VS Code extension catalog
│   ├── postcreate.sh
│   ├── poststart.sh
│   ├── shell-config.zsh
│   └── update.sh                   # upstream update script
├── proxy/
│   ├── addon.py
│   ├── Dockerfile
│   └── start.sh
├── templates/
│   ├── php/
│   │   ├── devcontainer.json
│   │   ├── docker-compose.yml
│   │   ├── manifest.txt
│   │   ├── postcreate-php.sh
│   │   └── version.txt
│   ├── research/
│   │   ├── devcontainer.json
│   │   ├── docker-compose.yml
│   │   ├── manifest.txt
│   │   └── version.txt
│   └── typescript/
│       ├── devcontainer.json
│       ├── docker-compose.yml
│       ├── manifest.txt
│       └── version.txt
├── .devcontainer/                  # this repo's own devcontainer
│   └── devcontainer.json
├── .release-please-manifest.json
├── release-please-config.json
└── install.sh
```

## Adding a new template

1. Add `templates/<name>/devcontainer.json`, `docker-compose.yml`, `manifest.txt`, and `version.txt` (start at `0.0.0`)
2. Add `<name>` to the `TEMPLATES` and `DESCRIPTIONS` arrays in `install.sh`
3. Add a package entry to `release-please-config.json` and `.release-please-manifest.json`
4. Add a row to the Templates table above
