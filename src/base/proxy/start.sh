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

# ---------------------------------------------------------------------------
# iptables filter rules (egress firewall)
#
# We use iptables (nft backend) for the filter table. The default iptables on
# this image uses the nftables backend — do NOT switch to iptables-legacy, as
# Docker also uses nftables and mixing backends causes rules to silently fail.
# ---------------------------------------------------------------------------
iptables -F
iptables -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# Allow established connections BEFORE setting DROP policy — eliminates the gap
# where in-flight return packets would be dropped.
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost — both by interface (-o lo) and by destination (-d 127.0.0.0/8).
# The destination match is needed because nat REDIRECT changes the destination to
# 127.0.0.1, but the filter OUTPUT chain runs BEFORE re-routing, so the output
# interface is still eth0, not lo.
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT

if [ "${UNRESTRICTED_NETWORK:-false}" = "true" ]; then
    # ---------------------------------------------------------------------------
    # Unrestricted mode — no domain filtering, all outbound traffic allowed.
    # Still allow host gateway explicitly and lock down INPUT/FORWARD.
    # ---------------------------------------------------------------------------
    echo "UNRESTRICTED_NETWORK=true: skipping domain filtering — all outbound traffic allowed"

    for tool in iptables nft; do
        command -v "$tool" >/dev/null || { echo "ERROR: required tool '$tool' not found"; exit 1; }
    done

    HOST_IP=$(ip route show default | awk 'NR==1 {print $3}')
    if [ -n "$HOST_IP" ] && _valid_ip "$HOST_IP"; then
        echo "Host gateway detected as: $HOST_IP"
        iptables -A INPUT -s "$HOST_IP" -j ACCEPT
        iptables -A OUTPUT -d "$HOST_IP" -j ACCEPT
    fi

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    # OUTPUT remains ACCEPT — no domain restrictions

    echo "Firewall configuration complete (unrestricted)"
else
    # ---------------------------------------------------------------------------
    # Restricted mode — domain allowlist enforced via ipset + mitmproxy.
    # ---------------------------------------------------------------------------

    # Verify required tools are available
    for tool in aggregate dig jq curl ipset iptables nft; do
        command -v "$tool" >/dev/null || { echo "ERROR: required tool '$tool' not found"; exit 1; }
    done

    # -------------------------------------------------------------------------
    # Build the allowed-domains ipset (IP allowlist for direct egress)
    # -------------------------------------------------------------------------
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
    if ! gh_raw=$(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]'); then
        echo "ERROR: Failed to extract GitHub IP ranges (jq failed)"
        exit 1
    fi
    gh_ips=$(echo "$gh_raw" | aggregate -q 2>/dev/null || true)
    if [ -z "$gh_ips" ]; then
        echo "ERROR: Failed to aggregate GitHub IP ranges (aggregate produced empty output)"
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

    # -------------------------------------------------------------------------
    # Resolve allowed domains in parallel
    # -------------------------------------------------------------------------
    # NOTE: IPs are resolved once at container start and cached in ipset. If a
    # domain's IPs rotate (e.g. CDN), the allowlist becomes stale and connections
    # will be blocked until the container is restarted.

    domains=(
        "github.com"
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
        "githubusercontent.com"
        "objects.githubusercontent.com"
        "release-assets.githubusercontent.com"
        "raw.githubusercontent.com"
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

    # -------------------------------------------------------------------------
    # Remaining filter rules (depend on ipset and host network detection)
    # -------------------------------------------------------------------------
    # Take only the first default route to avoid multi-line HOST_IP from multiple NICs.
    HOST_IP=$(ip route show default | awk 'NR==1 {print $3}')
    if [ -z "$HOST_IP" ] || ! _valid_ip "$HOST_IP"; then
        echo "ERROR: Failed to detect a valid host IP (got: ${HOST_IP:-empty})"
        exit 1
    fi

    echo "Host gateway detected as: $HOST_IP"

    iptables -A INPUT -s "$HOST_IP" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_IP" -j ACCEPT

    # Allow only specific outbound traffic to allowed domains
    iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

    # Explicitly REJECT all other outbound traffic for immediate feedback
    iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

    # Set default policies to DROP — all ACCEPT rules are now in place, so there
    # is no gap where legitimate traffic would be blocked.
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

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

    # Pass the allowed domains to the addon for clear 403 errors
    export ALLOWED_DOMAINS="${domains[*]}"
fi

# ---------------------------------------------------------------------------
# Transparent proxy via nftables nat REDIRECT
#
# Three things conspire to make this tricky in Docker:
#
# 1. Docker uses nftables (iptables-nft) for its internal DNS NAT. It creates
#    an "ip nat" table with an OUTPUT chain at priority dstnat (-100). If we
#    add REDIRECT rules via iptables (even iptables-nft), they land in this
#    same chain but AFTER Docker's rules. A separate nft table at a different
#    priority doesn't work either — once conntrack sees the first nat chain's
#    "policy accept", it records a no-NAT decision and skips later chains.
#    Fix: nft insert into Docker's own chain so our rules run first.
#
# 2. The devcontainer shares our network namespace (network_mode: service:)
#    but has a separate user namespace. nftables "meta skuid" returns NFT_BREAK
#    (no match at all) when it can't map the socket owner's UID across the
#    namespace boundary. So "meta skuid != 0 redirect" silently skips packets
#    from the devcontainer instead of redirecting them.
#    Fix: use two rules — "meta skuid 0 accept" (matches proxy, whose UID IS
#    resolvable in our own namespace) then unconditional "redirect" for the rest.
#
# 3. The "meta skuid 0 accept" rule must be scoped to tcp dport 443. Otherwise
#    it also matches mitmproxy's DNS lookups to 127.0.0.11:53, preventing
#    Docker's DNS DNAT rule (later in the chain) from translating port 53 to
#    Docker's internal DNS port — breaking name resolution for mitmproxy.
# ---------------------------------------------------------------------------
MITMPROXY_UID=$(id -u)

# Remove any redirect/skip rules we inserted on a previous run so that a
# container restart doesn't accumulate duplicate entries in Docker's nat chain.
for handle in $(nft -a list chain ip nat OUTPUT 2>/dev/null \
    | awk '/redirect to :8443|meta skuid [0-9]+ accept/ {
        for (i=1; i<=NF; i++) if ($i == "handle") { print $(i+1); break }
    }'); do
    nft delete rule ip nat OUTPUT handle "$handle" 2>/dev/null || true
done

nft insert rule ip nat OUTPUT tcp dport { 80, 443 } redirect to :8443
nft insert rule ip nat OUTPUT tcp dport { 80, 443 } meta skuid "$MITMPROXY_UID" accept

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
