FROM mcr.microsoft.com/devcontainers/php:8.2

ARG TZ
ENV TZ="${TZ:-UTC}"
ENV DEVCONTAINER=true

USER root

# Install firewall tooling + additional PHP extensions for WordPress development.
# Composer is pre-installed by the MCR PHP image; PHP 8.2 CLI is the base image.
RUN apt-get update && apt-get install -y --no-install-recommends \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  fzf \
  php8.2-mysql \
  php8.2-gd \
  php8.2-intl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Node.js for Claude Code and WordPress asset tooling (Gutenberg, etc.).
# System-wide install so it is available at build time and for all users.
ARG NODE_VERSION=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
  && apt-get install -y nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Give the vscode user a writable global npm prefix (mirrors the node-image setup)
RUN mkdir -p /usr/local/share/npm-global \
  && chown vscode:vscode /usr/local/share/npm-global
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Install WP-CLI
ARG WP_CLI_VERSION=2.10.0
RUN curl -sL "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
  -o /usr/local/bin/wp \
  && chmod +x /usr/local/bin/wp

# Persist shell history across container restarts
RUN mkdir -p /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R vscode:vscode /commandhistory

# Ensure workspace and Claude config directories exist
RUN mkdir -p /workspace /home/vscode/.claude \
  && chown -R vscode:vscode /workspace /home/vscode/.claude

WORKDIR /workspace

# Install git-delta for richer diffs
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
  && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER vscode

# Extend the MCR image's existing .zshrc with our customisations
RUN printf '\n# ── Claude Code devcontainer ──────────────────────────────────\n\
export HISTFILE=/commandhistory/.bash_history\n\
export SAVEHIST=10000\n\
setopt INC_APPEND_HISTORY\n\
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh\n\
[ -f /usr/share/doc/fzf/examples/completion.zsh ]    && source /usr/share/doc/fzf/examples/completion.zsh\n\
alias claude="claude --dangerously-skip-permissions"\n' \
  >> /home/vscode/.zshrc

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh \
  && echo "vscode ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/vscode-firewall \
  && chmod 0440 /etc/sudoers.d/vscode-firewall
USER vscode
