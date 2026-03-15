# Skip the permissions prompt: the devcontainer firewall and credential proxy
# already provide the safety boundaries, so the interactive approval layer
# adds friction without meaningful protection inside this environment.
alias claude="command claude --dangerously-skip-permissions"

# claude-wt [name]
# Creates a git worktree, injects a one-shot VS Code task that launches claude,
# then reloads VS Code into the worktree.
claude-wt() {
  local NAME="${1:-wt-$(date +%s)}"
  local GIT_ROOT
  GIT_ROOT=$(git rev-parse --show-toplevel) || return 1
  local WT="$GIT_ROOT/.claude/worktrees/$NAME"

  git worktree add "$WT" || return 1
  mkdir -p "$WT/.vscode"

  local TASKS_FILE="$WT/.vscode/tasks.json"
  local EXISTED=false
  [ -f "$TASKS_FILE" ] && EXISTED=true

  # Build a self-destruct cleanup command the task will run before launching claude.
  # This removes the auto-run task so it doesn't fire again on subsequent folder opens.
  # - If tasks.json was created by us: delete the whole file.
  # - If tasks.json already existed: surgically remove only our "Launch Claude" entry
  #   from the tasks array, leaving everything else intact.
  local CLEANUP
  if $EXISTED; then
    CLEANUP='tmp=$(mktemp) && jq "del(.tasks[] | select(.label == \"Launch Claude\"))" .vscode/tasks.json > "$tmp" && mv "$tmp" .vscode/tasks.json'
  else
    CLEANUP='rm .vscode/tasks.json'
  fi

  # Build the task object using jq.
  # --arg passes the command string as a JSON-safe $cmd variable so that
  # special characters in CLEANUP don't break the JSON structure.
  # runOn: folderOpen makes VS Code trigger this automatically when the worktree opens.
  local NEW_TASK
  NEW_TASK=$(jq -n --arg cmd "$CLEANUP && claude --dangerously-skip-permissions" '{
    label: "Launch Claude",
    type: "shell",
    command: $cmd,
    presentation: { reveal: "always", panel: "new" },
    runOptions: { runOn: "folderOpen" }
  }')

  if $EXISTED; then
    # Append our task to the existing tasks array, preserving all other tasks.
    local TMP_TASKS
    TMP_TASKS=$(mktemp)
    jq --argjson task "$NEW_TASK" '.tasks += [$task]' "$TASKS_FILE" \
      > "$TMP_TASKS" && mv "$TMP_TASKS" "$TASKS_FILE"
  else
    # Create a minimal tasks.json containing only our launch task.
    jq -n --argjson task "$NEW_TASK" '{ "version": "2.0.0", tasks: [$task] }' \
      > "$TASKS_FILE"
  fi

  code -r "$WT"
}
