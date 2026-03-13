FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG TZ
ENV TZ="${TZ:-UTC}"
ENV DEVCONTAINER=true

USER root

# Install productivity tools for research and writing workflows
RUN apt-get update && apt-get install -y --no-install-recommends \
  fzf \
  pandoc \
  ripgrep \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

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
