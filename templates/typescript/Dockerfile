FROM mcr.microsoft.com/devcontainers/javascript-node:24

ARG TZ
ENV TZ="${TZ:-UTC}"
ENV DEVCONTAINER=true

USER root

# Install firewall tooling — everything else is provided by the MCR base image
RUN apt-get update && apt-get install -y --no-install-recommends \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  fzf \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Persist shell history across container restarts
RUN mkdir -p /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R node:node /commandhistory

# Ensure workspace and Claude config directories exist
RUN mkdir -p /workspace /home/node/.claude \
  && chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

# Install git-delta for richer diffs
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
  && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node

# Extend the MCR image's existing .zshrc with our customisations
RUN printf '\n# ── Claude Code devcontainer ──────────────────────────────────\n\
export HISTFILE=/commandhistory/.bash_history\n\
export SAVEHIST=10000\n\
setopt INC_APPEND_HISTORY\n\
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh\n\
[ -f /usr/share/doc/fzf/examples/completion.zsh ]    && source /usr/share/doc/fzf/examples/completion.zsh\n\
alias claude="claude --dangerously-skip-permissions"\n' \
  >> /home/node/.zshrc

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Firewall script — COPY path is relative to the Docker build context (repo root).
# When deployed via install.sh the script is copied next to this Dockerfile and
# the COPY line is patched to: COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY base/init-firewall.sh /usr/local/bin/init-firewall.sh
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh \
  && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
  && chmod 0440 /etc/sudoers.d/node-firewall
USER node
