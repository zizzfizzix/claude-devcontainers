FROM ghcr.io/mitmproxy/mitmproxy:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables nftables curl jq ipset dnsutils iproute2 aggregate \
    && rm -rf /var/lib/apt/lists/*

COPY addon.py start.sh /app/

RUN mkdir -p /data /certs && chmod +x /app/start.sh

EXPOSE 443 3100 8081

HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=5s \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:3100/healthz')" && \
      python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1',8443)); s.close()" || exit 1

CMD ["/app/start.sh"]
