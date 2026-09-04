#!/bin/bash
# Claude Code status line: model, context used, rate limits, hostname, git branch.
# Reads the JSON payload Claude Code pipes on stdin.

input=$(cat)

ask() { echo "$input" | jq -r "$1 // empty" 2>/dev/null; }

model=$(ask '.model.display_name // .model.id')
[ -z "$model" ] && model="unknown model"

# The directory is not shown; it locates the repository the branch comes from.
dir=$(ask '.workspace.current_dir // .cwd')
[ -z "$dir" ] && dir="$PWD"

branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

host=$(hostname -s)

# Context: tokens used of the window, and the percentage Claude Code computes.
used=$(ask '.context_window.total_input_tokens')
max=$(ask '.context_window.context_window_size')
pct=$(ask '.context_window.used_percentage')

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
  [ -n "$pct" ] && ctx="$ctx $(printf '%.0f' "$pct")%"
fi

# Rate limits: the windows this account reports, absent on API-key accounts.
limits=""
for window in five_hour:5h seven_day:7d spend_limit:spend; do
  field=${window%%:*}
  label=${window##*:}
  value=$(ask ".rate_limits.${field}.used_percentage")
  [ -z "$value" ] && continue
  limits="${limits}${limits:+ }${label} $(printf '%.0f' "$value")%"
done

parts=("$model")
[ -n "$ctx" ] && parts+=("$ctx")
[ -n "$limits" ] && parts+=("$limits")
parts+=("$host")
[ -n "$branch" ] && parts+=("$branch")

printf '%s' "${parts[0]}"
for p in "${parts[@]:1}"; do printf ' | %s' "$p"; done
printf '\n'
