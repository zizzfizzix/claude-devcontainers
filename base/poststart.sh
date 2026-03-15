#!/usr/bin/env bash
set -euo pipefail

# Firewall rules (only present in templates that include init-firewall.sh)
if [ -f /usr/local/bin/init-firewall.sh ]; then
  sudo /usr/local/bin/init-firewall.sh
fi

# Resolve proxy IP before touching /etc/hosts so partial writes don't occur on failure
PROXY_IP=$(getent hosts claude-proxy | awk '{print $1}')

# Remove IPv6 localhost so oauth callback servers bind to 127.0.0.1 (VS Code port forwarding connects via IPv4)
HOSTS_TMP=$(mktemp)
grep -v '^::1[[:space:]]' /etc/hosts > "$HOSTS_TMP"
sudo cp "$HOSTS_TMP" /etc/hosts
rm -f "$HOSTS_TMP"

# Point Anthropic hostnames at the proxy container
printf "%s\tapi.anthropic.com\n%s\tplatform.claude.com\n" "$PROXY_IP" "$PROXY_IP" | sudo tee -a /etc/hosts

# Trust the mitmproxy CA cert (system store + certifi bundle)
sudo mkdir -p /usr/local/share/ca-certificates
sudo cp /proxy-certs/mitmca.pem /usr/local/share/ca-certificates/claude-proxy-ca.crt
sudo update-ca-certificates 2>&1 | tail -5

CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null || true)
if [[ -n "$CERTIFI_PATH" ]]; then
  # Only append if the cert isn't already present (guard against repeated poststart runs)
  # Use a unique portion of the cert body (base64-encoded DER data) rather than the
  # generic "-----BEGIN CERTIFICATE-----" header that every cert shares.
  CERT_UNIQUE=$(grep -v -- "-----" /proxy-certs/mitmca.pem | head -3 | tr -d '\n')
  if ! grep -qF "$CERT_UNIQUE" "$CERTIFI_PATH" 2>/dev/null; then
    cat /proxy-certs/mitmca.pem | sudo tee -a "$CERTIFI_PATH" > /dev/null
  fi
fi
