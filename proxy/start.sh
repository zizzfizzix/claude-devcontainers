#!/bin/sh
# Redirect incoming port 443 to mitmproxy's unprivileged listener so we don't
# need CAP_NET_BIND_SERVICE.  Requires CAP_NET_ADMIN (set in docker-compose).
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j REDIRECT --to-port 8443

LISTEN_IP=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.connect(('8.8.8.8', 80))
print(s.getsockname()[0])
")
exec mitmdump \
  --mode transparent \
  --listen-host "$LISTEN_IP" \
  --listen-port 8443 \
  --set confdir=/data/mitmproxy \
  --set block_global=false \
  -s /app/addon.py
