FROM node:22-alpine

WORKDIR /app

# No package.json needed — zero npm dependencies.
COPY server.js login.js ./

# Credentials volume mount point
RUN mkdir -p /data

EXPOSE 3100

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -qO- http://localhost:3100/healthz 2>/dev/null || exit 1

CMD ["node", "/app/server.js"]
