#!/usr/bin/env bash
set -euo pipefail

# Ensure history directory is writable by this user
sudo mkdir -p /commandhistory
sudo chown "$(id -u):$(id -g)" /commandhistory
touch /commandhistory/.bash_history

# Trust the mitmproxy CA cert so HTTPS requests in this script work
sudo mkdir -p /usr/local/share/ca-certificates
sudo cp /proxy-certs/mitmca.pem /usr/local/share/ca-certificates/claude-proxy-ca.crt
sudo update-ca-certificates 2>&1 | tail -5

# git-delta (no feature available)
ARCH=$(dpkg --print-architecture)
GIT_DELTA_VERSION="${GIT_DELTA_VERSION:-0.18.2}"
TMP=$(mktemp --suffix=.deb)
echo "Downloading git-delta ${GIT_DELTA_VERSION} (${ARCH})..."
wget -O "$TMP" "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"
[[ -s "$TMP" ]] || { echo "ERROR: Failed to download git-delta"; rm -f "$TMP"; exit 1; }
sudo dpkg -i "$TMP"
rm "$TMP"

DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install shell config and claude tools into zsh's drop-in directory
sudo mkdir -p /etc/zsh/zshrc.d
sudo install -m 644 "$DEVCONTAINER_DIR/shell-config.zsh" /etc/zsh/zshrc.d/shell-config.zsh
sudo install -m 644 "$DEVCONTAINER_DIR/claude-wt.zsh"    /etc/zsh/zshrc.d/claude-wt.zsh

# Wire up the drop-in directory in /etc/zsh/zshrc if not already done
grep -qF 'zshrc.d' /etc/zsh/zshrc 2>/dev/null || \
  echo 'for f in /etc/zsh/zshrc.d/*.zsh; do source "$f"; done' | sudo tee -a /etc/zsh/zshrc > /dev/null
