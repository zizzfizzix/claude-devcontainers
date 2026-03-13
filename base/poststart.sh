#!/usr/bin/env bash
set -euo pipefail

# Firewall rules (only present in templates that include init-firewall.sh)
if [ -f /usr/local/bin/init-firewall.sh ]; then
  sudo /usr/local/bin/init-firewall.sh
fi

# Spoof Anthropic hostnames to the mitmproxy container
PROXY_IP=$(getent hosts claude-proxy | awk '{print $1}')
printf "%s\tapi.anthropic.com\n%s\tplatform.claude.com\n" "$PROXY_IP" "$PROXY_IP" \
  | sudo tee -a /etc/hosts

# Trust the mitmproxy CA cert (system store + certifi bundle)
sudo cp /proxy-certs/mitmca.pem /usr/local/share/ca-certificates/claude-proxy-ca.crt
sudo update-ca-certificates

CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null || true)
if [[ -n "$CERTIFI_PATH" ]]; then
  cat /proxy-certs/mitmca.pem | sudo tee -a "$CERTIFI_PATH" > /dev/null
fi
