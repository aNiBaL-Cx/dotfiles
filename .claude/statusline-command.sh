#!/usr/bin/env bash
# Claude Code statusLine hook (settings.json -> statusLine.command).
# Prints a compact status string for Claude Code's footer, and under tmux also
# writes it to a per-pane temp file for the tmux status bar, sidebar and agent
# TUI. Always printed, so an unfocused Claude pane still shows its own line.
# The footer gets the bar colored by context use; the tmux file stays plain.
input=$(cat)

# One jq call. Fields are joined with the unit separator (\x1f): a tab would
# collapse empty fields under `read`.
IFS=$'\x1f' read -r model ctx tokens usage_5h usage_7d agent < <(echo "$input" | jq -r '
  def short: if . >= 1000000 then ((. / 100000 | round) / 10 | tostring | sub("\\.0$"; "")) + "M"
             elif . >= 1000 then (. / 1000 | round | tostring) + "k"
             else (round | tostring) end;
  # epoch -> " ~Xh" under a day (rounded up), " ~Xd" from a day
  def eta: if . == null then "" else (. - now) as $s
           | if $s <= 0 then " ~0h" elif $s >= 86400 then " ~\($s / 86400 | floor)d"
             else " ~\(($s + 3599) / 3600 | floor)h" end end;
  def limit($label): if .used_percentage then "\($label):\(.used_percentage | floor)%\(.resets_at | eta)" else "" end;
  .context_window as $c
  | ($c.used_percentage // 0 | floor) as $pct
  | ($c.context_window_size // 0) as $size
  # current_usage is null before the first call and right after /compact
  | ($c.current_usage | if . then .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens else null end
     // ($pct * $size / 100)) as $used
  | [ (.model.display_name // "" | sub(" \\(.*"; "")),
      ($pct | tostring),
      (if $size > 0 then "\($used | short)/\($size | short) \($pct)%" else "\($pct)%" end),
      (.rate_limits.five_hour // {} | limit("5h")),
      (.rate_limits.seven_day // {} | limit("7d")),
      (.agent.name // "") ]
  | join("\u001f")')

bar_len=10
filled=$(( ctx * bar_len / 100 ))
[ "$filled" -gt "$bar_len" ] && filled=$bar_len
empty=$(( bar_len - filled ))
bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"

# green < 50%, yellow < 80%, red from 80%: time to /compact
if [ "$ctx" -ge 80 ]; then color='\033[31m'
elif [ "$ctx" -ge 50 ]; then color='\033[33m'
else color='\033[32m'; fi
reset='\033[0m'

rest=""
[ -n "$usage_5h" ] && rest="$rest · $usage_5h"
[ -n "$usage_7d" ] && rest="$rest · $usage_7d"
[ -n "$agent" ] && rest="$rest · $agent"

[ -n "$TMUX_PANE" ] && printf '%s [%s] %s%s\n' "$model" "$bar" "$tokens" "$rest" > "/tmp/agent-statusline-${TMUX_PANE}"
printf "%s ${color}[%s]${reset} %s%s\n" "$model" "$bar" "$tokens" "$rest"
