#!/bin/bash
# Claude Code status line: model name, hostname, git branch, working directory.
# Reads the JSON payload Claude Code pipes on stdin.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown model"' 2>/dev/null)
[ -z "$model" ] || [ "$model" = "null" ] && model="unknown model"

dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] || [ "$dir" = "null" ] && dir="$PWD"

branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

host=$(hostname -s)

display_dir="${dir/#$HOME/~}"

if [ -n "$branch" ]; then
  printf '%s | %s | %s | %s\n' "$model" "$host" "$branch" "$display_dir"
else
  printf '%s | %s | %s\n' "$model" "$host" "$display_dir"
fi
