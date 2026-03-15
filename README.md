# Claude Code Devcontainers

Baseline devcontainer configs for [Claude Code](https://claude.ai/code). Adds a secure, firewall-restricted dev environment to any repo in one command.

## Bootstrap a new repo

```bash
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript
```

Replace `typescript` with `php` as needed. Then open the folder in VS Code → **Reopen in Container**.

> `install.sh` downloads only the three files it needs — no clone required.

## Templates

| Template     | Base image                                           | Extra tooling                                   |
| ------------ | ---------------------------------------------------- | ----------------------------------------------- |
| `typescript` | `mcr.microsoft.com/devcontainers/javascript-node:24` | Node 24, git-delta, Claude Code                 |
| `php`        | `mcr.microsoft.com/devcontainers/php:8.2`            | PHP 8.2 + extensions, Composer, WP-CLI, Node 24 |

All templates include:

- Claude Code with `--dangerously-skip-permissions` aliased (safe inside the firewall-restricted container)
- `iptables` firewall: allowlists only necessary outbound domains, drops everything else
- Persistent shell history and Claude config across container rebuilds
   - git-delta, fzf, zsh

 

## What gets installed

```
.devcontainer/
├── proxy/
│   ├── Dockerfile        # mitmproxy sidecar image
│   ├── addon.py          # token swap + request inspection
│   └── start.sh          # firewall setup + transparent proxy launch
├── claude-wt.zsh
├── devcontainer.json
├── docker-compose.yml
├── postcreate.sh
├── poststart.sh
└── shell-config.zsh
```

## Extending the firewall allowlist

Add extra domains via the `claude-proxy` service environment — no script fork needed:

```yaml
claude-proxy:
  environment:
    EXTRA_ALLOWED_DOMAINS: "registry.example.com cdn.example.com"
```

The proxy resolves and allowlists them at container start.

## Local usage (from a clone)

```bash
./install.sh [typescript|php] [target-directory]
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
2. Add `<name>` to the `case` statement in `install.sh`
3. Add a row to the table above
