# Claude Code Devcontainers

Baseline devcontainer configs for [Claude Code](https://claude.ai/code). Adds a secure, firewall-restricted dev environment to any repo in one command.

## Bootstrap a new repo

Run the installer and follow the prompts:

```bash
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash
```

It will ask you to pick a template and confirm the target directory. Then open the folder in VS Code → **Reopen in Container**.

> `install.sh` downloads only the files it needs — no clone required.

To skip the prompts, pass the template (and optionally a target directory) as arguments:

```bash
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript /path/to/project
```

### Windows

The installer works in **Git Bash** (ships with [Git for Windows](https://gitforwindows.org/)) without any changes. Run the same `curl | bash` command above from a Git Bash terminal.

## Templates

| Template     | Base image                                        | Extra tooling                                    |
| ------------ | ------------------------------------------------- | ------------------------------------------------ |
| `typescript` | `mcr.microsoft.com/devcontainers/base:debian`     | Node 24, git-delta, Claude Code                  |
| `php`        | `mcr.microsoft.com/devcontainers/base:debian`     | PHP 8.2 + extensions, Composer, WP-CLI, Node 24  |
| `research`   | `mcr.microsoft.com/devcontainers/base:debian`     | Pandoc, ripgrep, Dendron, Markdown tools — firewall disabled (`UNRESTRICTED_NETWORK=true`) |

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
│   ├── Dockerfile        # mitmproxy sidecar image
│   ├── addon.py          # token swap + request inspection
│   └── start.sh          # firewall setup + transparent proxy launch
├── claude-wt.zsh         # git worktree helper for multi-branch Claude sessions
├── devcontainer.json
├── docker-compose.yml
├── postcreate.sh
├── poststart.sh
└── shell-config.zsh
```

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
│   ├── claude-wt.zsh
│   ├── postcreate.sh     # shared post-create hook; installs shell config
│   ├── poststart.sh      # shared post-start hook; trusts proxy CA cert
│   └── shell-config.zsh
├── proxy/
│   ├── addon.py          # mitmproxy addon: token swap + request inspection
│   ├── Dockerfile        # mitmproxy sidecar image + firewall tools
│   └── start.sh          # firewall setup + transparent proxy launch
├── templates/
│   ├── php/
│   │   ├── devcontainer.json
│   │   ├── docker-compose.yml
│   │   ├── manifest.txt        # files install.sh copies into a target repo
│   │   └── postcreate-php.sh
│   ├── research/
│   │   ├── devcontainer.json
│   │   ├── docker-compose.yml
│   │   └── manifest.txt
│   └── typescript/
│       ├── devcontainer.json
│       ├── docker-compose.yml
│       └── manifest.txt
├── .devcontainer/        # this repo's own devcontainer
│   └── devcontainer.json
└── install.sh
```

## Adding a new template

1. Add `templates/<name>/devcontainer.json`, `docker-compose.yml`, and `manifest.txt`
2. Add `<name>` to the `TEMPLATES` and `DESCRIPTIONS` arrays in `install.sh`
3. Add a row to the table above
