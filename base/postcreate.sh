#!/usr/bin/env bash
set -euo pipefail

# Ensure history directory is writable by this user
sudo mkdir -p /commandhistory
sudo chown "$(id -u):$(id -g)" /commandhistory
touch /commandhistory/.bash_history

# git-delta (no feature available)
ARCH=$(dpkg --print-architecture)
GIT_DELTA_VERSION="${GIT_DELTA_VERSION:-0.18.2}"
TMP=$(mktemp --suffix=.deb)
wget -qO "$TMP" "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"
sudo dpkg -i "$TMP"
rm "$TMP"

# Shell customisations (idempotent — fzf feature may or may not wire these up)
ZSHRC="${HOME}/.zshrc"
grep -qF 'HISTFILE='        "$ZSHRC" 2>/dev/null || printf '\nexport HISTFILE=/commandhistory/.bash_history\nexport SAVEHIST=10000\nsetopt INC_APPEND_HISTORY\n' >> "$ZSHRC"
grep -qF 'key-bindings.zsh' "$ZSHRC" 2>/dev/null || echo '[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh' >> "$ZSHRC"
grep -qF 'completion.zsh'   "$ZSHRC" 2>/dev/null || echo '[ -f /usr/share/doc/fzf/examples/completion.zsh ]    && source /usr/share/doc/fzf/examples/completion.zsh'    >> "$ZSHRC"
grep -qF 'alias claude='    "$ZSHRC" 2>/dev/null || echo 'alias claude="claude --dangerously-skip-permissions"' >> "$ZSHRC"

# Set up init-firewall.sh if this template includes it
DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$DEVCONTAINER_DIR/init-firewall.sh" ]]; then
  sudo install -m 755 "$DEVCONTAINER_DIR/init-firewall.sh" /usr/local/bin/init-firewall.sh
  ME="$(whoami)"
  printf '%s ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh\n' "$ME" \
    | sudo tee "/etc/sudoers.d/$ME-firewall" > /dev/null
  sudo chmod 440 "/etc/sudoers.d/$ME-firewall"
fi
