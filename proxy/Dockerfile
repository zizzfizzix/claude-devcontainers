FROM ghcr.io/mitmproxy/mitmproxy:latest

RUN apt-get update && apt-get install -y --no-install-recommends iptables && rm -rf /var/lib/apt/lists/*

COPY addon.py start.sh /app/

RUN mkdir -p /data /certs && chmod +x /app/start.sh

EXPOSE 443 3100

HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=5s \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:3100/healthz')" || exit 1

CMD ["/app/start.sh"]
