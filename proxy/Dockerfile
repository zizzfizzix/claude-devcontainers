FROM ghcr.io/mitmproxy/mitmproxy:latest

COPY addon.py /app/

RUN mkdir -p /data /certs

EXPOSE 443 3100

HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=5s \
  CMD wget -qO- http://localhost:3100/healthz || exit 1

CMD ["mitmdump", "--mode", "transparent", "--listen-host", "::", \
     "--listen-port", "443", "--set", "confdir=/data/mitmproxy", \
     "--set", "block_global=false", "-s", "/app/addon.py"]
