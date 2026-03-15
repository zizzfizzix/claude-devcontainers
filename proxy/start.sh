#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

_valid_cidr() {
    local cidr="$1" ip prefix
    IFS=/ read -r ip prefix <<< "$cidr"
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix >= 1 && prefix <= 32 )) || return 1
    local -a octets
    IFS=. read -ra octets <<< "$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    local octet
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] && (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

_valid_ip() {
    local ip="$1"
    local -a octets
    IFS=. read -ra octets <<< "$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    local octet
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] && (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# Disable IPv6 to prevent egress bypass
# ---------------------------------------------------------------------------
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    echo "IPv6 firewall set to DROP"
else
    echo "WARNING: ip6tables not found — IPv6 blocked via sysctl only"
fi

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Verify required tools are available
for tool in aggregate dig jq curl ipset iptables; do
    command -v "$tool" >/dev/null || { echo "ERROR: required tool '$tool' not found"; exit 1; }
done

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
gh_ips=$(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q 2>/dev/null || true)
if [ -z "$gh_ips" ]; then
    echo "ERROR: Failed to aggregate GitHub IP ranges"
    exit 1
fi
while read -r cidr; do
    if ! _valid_cidr "$cidr"; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add --exist allowed-domains "$cidr"
done <<< "$gh_ips"

# ---------------------------------------------------------------------------
# Resolve allowed domains in parallel
# ---------------------------------------------------------------------------
# NOTE: IPs are resolved once at container start and cached in ipset. If a
# domain's IPs rotate (e.g. CDN), the allowlist becomes stale and connections
# will be blocked until the container is restarted.

domains=(
    "json.schemastore.org"
    "claude.com"
    "platform.claude.com"
    "storage.googleapis.com"
    "claude.ai"
    "registry.npmjs.org"
    "api.anthropic.com"
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
)

# Append extra domains from environment variable (space-separated)
if [ -n "${EXTRA_ALLOWED_DOMAINS:-}" ]; then
    IFS=' ' read -ra extra_domains <<< "$EXTRA_ALLOWED_DOMAINS"
    domains+=("${extra_domains[@]}")
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Resolving ${#domains[@]} domains in parallel..."
for i in "${!domains[@]}"; do
    domain="${domains[$i]}"
    (
        dig +time=5 +tries=2 +noall +answer A "$domain" \
            | awk '$4 == "A" {print $5}' \
            > "${tmpdir}/${i}"
    ) &
done
wait  # wait for all background DNS lookups

for i in "${!domains[@]}"; do
    domain="${domains[$i]}"
    ips=$(cat "${tmpdir}/${i}")
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain — skipping (domain will not be allowed)"
        continue
    fi
    while read -r ip; do
        if ! _valid_ip "$ip"; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add --exist allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# ---------------------------------------------------------------------------
# Set up transparent proxy via OUTPUT chain (shared network namespace)
# ---------------------------------------------------------------------------
# Loop prevention: skip REDIRECT for mitmproxy's own outbound connections
iptables -t nat -A OUTPUT -m owner --uid-owner "$(id -u)" -j RETURN
# Redirect all other outbound HTTPS to transparent proxy port
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8443

export PYTHONUNBUFFERED=1

MITM_ARGS=(
  --mode transparent
  --listen-host 0.0.0.0
  --listen-port 8443
  --web-host 0.0.0.0
  --web-port 8081
  --set confdir=/data/mitmproxy
  --set block_global=false
  --set connection_strategy=lazy
  # See: https://github.com/mitmproxy/mitmproxy/issues/7551#issuecomment-2781367454
  --set web_password='$argon2i$v=19$m=8,t=1,p=1$YWFhYWFhYWE$nXD9kg'
  -s /app/addon.py
)

exec mitmweb "${MITM_ARGS[@]}"
