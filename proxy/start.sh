#!/bin/sh
# Traffic arrives here because the devcontainer's /etc/hosts points Anthropic
# hostnames at this container's IP — no DNAT or iptables needed.
# NET_BIND_SERVICE capability (set in docker-compose) allows binding port 443.
exec mitmdump \
  --mode transparent \
  --listen-host 0.0.0.0 \
  --listen-port 443 \
  --set confdir=/data/mitmproxy \
  --set block_global=false \
  -s /app/addon.py
