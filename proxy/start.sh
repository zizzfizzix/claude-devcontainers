#!/bin/sh
# Redirect incoming port 443 → 8443 so mitmproxy binds an unprivileged port.
# The failed TCP attempt to proxy:443 (nothing listening there) keeps the server
# connection in a non-open state, which lets tls_clienthello override the address.
# Requires NET_ADMIN (set in docker-compose).
/usr/sbin/iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j REDIRECT --to-port 8443

export PYTHONUNBUFFERED=1
exec mitmweb \
  --mode transparent \
  --listen-host 0.0.0.0 \
  --listen-port 8443 \
  --web-host 0.0.0.0 \
  --web-port 8081 \
  --set confdir=/data/mitmproxy \
  --set block_global=false \
  --set connection_strategy=lazy \
  --set web_password='$argon2i$v=19$m=8,t=1,p=1$YWFhYWFhYWE$nXD9kg' \
  -s /app/addon.py
