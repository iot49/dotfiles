#!/bin/bash
# Claude Code status line: model, context used, hostname, git branch, directory.
# Reads the JSON payload Claude Code pipes on stdin.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown model"' 2>/dev/null)
[ -z "$model" ] || [ "$model" = "null" ] && model="unknown model"

dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] || [ "$dir" = "null" ] && dir="$PWD"

branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

host=$(hostname -s)

display_dir="${dir/#$HOME/~}"

# Context: tokens used of the window, and the percentage Claude Code computes.
used=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)
max=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)

# 213647 -> 214k, 1000000 -> 1.0M
human() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n / 1000000
    else if (n >= 1000) printf "%dk", (n + 500) / 1000
    else printf "%d", n
  }'
}

ctx=""
if [ -n "$used" ] && [ -n "$max" ]; then
  ctx="$(human "$used")/$(human "$max")"
  [ -n "$pct" ] && ctx="$ctx ${pct}%"
fi

parts=("$model")
[ -n "$ctx" ] && parts+=("$ctx")
parts+=("$host")
[ -n "$branch" ] && parts+=("$branch")
parts+=("$display_dir")

printf '%s' "${parts[0]}"
for p in "${parts[@]:1}"; do printf ' | %s' "$p"; done
printf '\n'
