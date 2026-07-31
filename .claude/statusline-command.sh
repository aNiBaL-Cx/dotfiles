#!/usr/bin/env bash
# Claude Code statusLine hook (settings.json -> statusLine.command).
# Writes a compact status string to a per-pane temp file that the tmux
# status bar displays for the active pane (see status-right in ~/.tmux.conf).
# Prints to stdout only when not running under tmux, so Claude Code renders
# it natively there without duplicating the tmux status bar.
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // ""')
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | floor')
usage_5h=$(echo "$input" | jq -r 'if .rate_limits.five_hour.used_percentage then (.rate_limits.five_hour.used_percentage | floor | tostring) else empty end')
usage_7d=$(echo "$input" | jq -r 'if .rate_limits.seven_day.used_percentage then (.rate_limits.seven_day.used_percentage | floor | tostring) else empty end')

# "Opus 4.6 (1M context)" -> "Opus 4.6"
short_model="${model%% (*}"

bar_len=10
filled=$(( ctx * bar_len / 100 ))
[ "$filled" -gt "$bar_len" ] && filled=$bar_len
empty=$(( bar_len - filled ))
bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"

output="$short_model [$bar] ${ctx}%"
[ -n "$usage_5h" ] && output="$output · 5h:${usage_5h}%"
[ -n "$usage_7d" ] && output="$output · 7d:${usage_7d}%"

if [ -n "$TMUX_PANE" ]; then
  printf '%s\n' "$output" > "/tmp/claude-statusline-${TMUX_PANE}"
else
  printf '%s\n' "$output"
fi
