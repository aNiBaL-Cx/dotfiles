#!/usr/bin/env bash
# Claude Code statusLine hook (settings.json -> statusLine.command).
# Writes a compact status string to a per-pane temp file that the tmux
# status bar displays for the active pane (see status-right in ~/.tmux.conf).
# Prints nothing back to Claude Code so the info appears only once, in tmux.
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // ""')
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | floor')
usage_5h=$(echo "$input" | jq -r 'if .rate_limits.five_hour.used_percentage then (.rate_limits.five_hour.used_percentage | floor | tostring) else empty end')
usage_7d=$(echo "$input" | jq -r 'if .rate_limits.seven_day.used_percentage then (.rate_limits.seven_day.used_percentage | floor | tostring) else empty end')

# "Opus 4.6 (1M context)" -> "Opus 4.6"
short_model="${model%% (*}"

output="$short_model · ctx:${ctx}%"
[ -n "$usage_5h" ] && output="$output · 5h:${usage_5h}%"
[ -n "$usage_7d" ] && output="$output · 7d:${usage_7d}%"

if [ -n "$TMUX_PANE" ]; then
  printf '%s\n' "$output" > "/tmp/claude-statusline-${TMUX_PANE}"
fi
