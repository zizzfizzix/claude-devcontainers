alias claude="command claude --dangerously-skip-permissions"

# claude-wt [name]
# Creates a git worktree, injects a one-shot VS Code task that launches claude,
# then reloads VS Code into the worktree.
claude-wt() {
  local NAME="${1:-wt-$(date +%s)}"
  local WT=".claude/worktrees/$NAME"

  git worktree add "$WT" || return 1
  mkdir -p "$WT/.vscode"

  local TASKS_FILE="$WT/.vscode/tasks.json"
  local EXISTED=false
  [ -f "$TASKS_FILE" ] && EXISTED=true

  # The task deletes itself then runs claude.
  # If we created tasks.json from scratch, delete the whole file.
  # If it already existed, only remove our task entry.
  local CLEANUP
  if $EXISTED; then
    CLEANUP='jq "del(.tasks[] | select(.label == \"Launch Claude\"))" .vscode/tasks.json > /tmp/tasks.json && mv /tmp/tasks.json .vscode/tasks.json'
  else
    CLEANUP='rm .vscode/tasks.json'
  fi

  local NEW_TASK
  NEW_TASK=$(jq -n --arg cmd "$CLEANUP && claude --dangerously-skip-permissions" '{
    label: "Launch Claude",
    type: "shell",
    command: $cmd,
    presentation: { reveal: "always", panel: "new" },
    runOptions: { runOn: "folderOpen" }
  }')

  if $EXISTED; then
    jq --argjson task "$NEW_TASK" '.tasks += [$task]' "$TASKS_FILE" \
      > /tmp/tasks.json && mv /tmp/tasks.json "$TASKS_FILE"
  else
    jq -n --argjson task "$NEW_TASK" '{ "version": "2.0.0", tasks: [$task] }' \
      > "$TASKS_FILE"
  fi

  code -r "$WT"
}
