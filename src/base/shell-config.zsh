# History
export HISTFILE=/commandhistory/.zsh_history
export SAVEHIST=10000
setopt INC_APPEND_HISTORY

# fzf
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ]   && source /usr/share/doc/fzf/examples/completion.zsh

# Project-local shell config — create .devcontainer/shell-config.local.zsh to add aliases, env vars, etc.
[[ -f /workspaces/*/.devcontainer/shell-config.local.zsh ]] && source /workspaces/*/.devcontainer/shell-config.local.zsh
