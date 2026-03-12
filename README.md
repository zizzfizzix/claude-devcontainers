# Claude Code Devcontainers

Baseline devcontainer configs for [Claude Code](https://claude.ai/code). Adds a secure, firewall-restricted dev environment to any repo in one command.

## Bootstrap a new repo

```bash
curl -fsSL "https://raw.githubusercontent.com/zizzfizzix/claude-devcontainers/main/install.sh" | bash -s -- typescript
```

Replace `typescript` with `php` as needed. Then open the folder in VS Code → **Reopen in Container**.

> `install.sh` downloads only the three files it needs — no clone required.

---

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

---

## What gets installed

```
.devcontainer/
  Dockerfile          ← from templates/<name>/Dockerfile
  devcontainer.json   ← context: ".." (project root)
  init-firewall.sh    ← always from base/init-firewall.sh
```

---

## Extending the firewall allowlist

Add extra domains via `containerEnv` — no script fork needed:

```json
"containerEnv": {
  "EXTRA_ALLOWED_DOMAINS": "registry.example.com cdn.example.com"
}
```

`init-firewall.sh` resolves and allows them at container start.

---

## Local usage (from a clone)

```bash
./install.sh [typescript|php] [target-directory]
```

`target-directory` defaults to the current directory.

---

## Repo layout

```
base/
  init-firewall.sh    ← the only truly shared file; all templates use this

templates/
  typescript/
    Dockerfile        ← mcr javascript-node:24 + firewall tools + Claude Code
    devcontainer.json
  php/
    Dockerfile        ← mcr php:8.2 + Node.js + WP-CLI
    devcontainer.json

.devcontainer/        ← this repo's own devcontainer
  devcontainer.json   ← references ../templates/typescript/Dockerfile; no duplication

install.sh
```

---

## Adding a new template

1. Add `templates/<name>/Dockerfile` and `templates/<name>/devcontainer.json`
2. Add `<name>` to the `case` statement in `install.sh`
3. Add a row to the table above
