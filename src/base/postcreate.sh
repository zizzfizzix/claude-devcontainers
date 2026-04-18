#!/usr/bin/env bash
set -euo pipefail

DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure history directory is writable by this user
sudo mkdir -p /commandhistory
sudo chown "$(id -u):$(id -g)" /commandhistory
touch /commandhistory/.bash_history

# Trust the mitmproxy CA cert so HTTPS requests in this script work.
# Retry since the proxy container may not have written the cert yet even after
# the health check passes (the cert is written in the addon's running() hook).
sudo mkdir -p /usr/local/share/ca-certificates
for i in $(seq 1 10); do
    if [ -f /proxy-certs/mitmca.pem ]; then
        break
    fi
    echo "Waiting for proxy CA cert (attempt $i/10)..."
    sleep 2
done
if [ ! -f /proxy-certs/mitmca.pem ]; then
    echo "ERROR: Proxy CA cert not found at /proxy-certs/mitmca.pem after waiting"
    exit 1
fi
sudo cp /proxy-certs/mitmca.pem /usr/local/share/ca-certificates/claude-proxy-ca.crt
sudo update-ca-certificates 2>&1 | tail -5

# git-delta (no feature available)
ARCH=$(dpkg --print-architecture)
GIT_DELTA_VERSION="${GIT_DELTA_VERSION:-0.18.2}"
TMP=$(mktemp --suffix=.deb)
echo "Downloading git-delta ${GIT_DELTA_VERSION} (${ARCH})..."
curl -fsSL -o "$TMP" "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"
sudo dpkg -i "$TMP"
rm "$TMP"

# Install shell config and claude tools into zsh's drop-in directory
sudo mkdir -p /etc/zsh/zshrc.d
sudo install -m 644 "$DEVCONTAINER_DIR/shell-config.zsh" /etc/zsh/zshrc.d/shell-config.zsh
sudo install -m 644 "$DEVCONTAINER_DIR/claude-wt.zsh"    /etc/zsh/zshrc.d/claude-wt.zsh

# Install zsh-ai-plugin (@ natural-language-to-command)
# https://github.com/zizzfizzix/zsh-ai-plugin
git clone --depth=1 https://github.com/zizzfizzix/zsh-ai-plugin /tmp/zsh-ai-plugin
sudo install -m 644 /tmp/zsh-ai-plugin/at-command.plugin.zsh /etc/zsh/zshrc.d/at-command.zsh
rm -rf /tmp/zsh-ai-plugin

# Wire up the drop-in directory in /etc/zsh/zshrc if not already done
grep -qF 'zshrc.d' /etc/zsh/zshrc 2>/dev/null || \
  echo 'for f in /etc/zsh/zshrc.d/*.zsh; do source "$f"; done' | sudo tee -a /etc/zsh/zshrc > /dev/null

# Authenticate acli with an API token if credentials were provided via initializeCommand.
if [[ -n "${ATLASSIAN_API_TOKEN:-}" && -n "${ATLASSIAN_EMAIL:-}" && -n "${ATLASSIAN_SITE:-}" ]]; then
  echo "Authenticating acli (jira + confluence)..."
  echo "$ATLASSIAN_API_TOKEN" | acli jira auth login --site "$ATLASSIAN_SITE" --email "$ATLASSIAN_EMAIL" --token
  echo "$ATLASSIAN_API_TOKEN" | acli confluence auth login --site "$ATLASSIAN_SITE" --email "$ATLASSIAN_EMAIL" --token
fi

# Project-local postcreate hook — create .devcontainer/postcreate.local.sh to add project-specific setup.
if [[ -f "${DEVCONTAINER_DIR}/postcreate.local.sh" ]]; then
  . "${DEVCONTAINER_DIR}/postcreate.local.sh"
fi
