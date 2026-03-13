#!/bin/sh
# Resolve the container's own IPv4 address at runtime so mitmproxy only binds
# to the interface the devcontainer actually connects to.
LISTEN_IP=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.connect(('8.8.8.8', 80))
print(s.getsockname()[0])
")
exec mitmdump \
  --mode transparent \
  --listen-host "$LISTEN_IP" \
  --listen-port 443 \
  --set confdir=/data/mitmproxy \
  --set block_global=false \
  -s /app/addon.py
