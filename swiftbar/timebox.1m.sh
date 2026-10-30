#!/usr/bin/env bash
# SwiftBar plugin: today's timebox plan. The timebox skill writes one note per day
# to Daily-Notes/Plans/<YYYY-MM-DD>.md (embedded in the daily note); this shows
# the current block in the menu bar and ticks a block when clicked.
# Block line format (the contract with the skill): "- [ ] HH:MM–HH:MM <text>".
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export LC_ALL=en_US.UTF-8
clean() { sed 's/|/¦/g; s/:/∶/g; s/\*\*//g'; }

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
PLAN="$HOME/notes/Daily-Notes/Plans/$(date +%F).md"

# "$0 tick <line>" flips the checkbox on that line of the plan.
if [ "$1" = tick ] && [ -n "$2" ]; then
  perl -i -pe "if (\$. == $2) { s/^- \[ \]/- [x]/ or s/^- \[[xX]\]/- [ ]/ }" "$PLAN"
  exit 0
fi

if [ ! -f "$PLAN" ]; then
  echo ":calendar.badge.exclamationmark: No plan"
  echo "---"
  echo "Run /timebox to plan today | refresh=true sfimage=info.circle"
  exit 0
fi

now=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
mins() { echo $(( 10#${1%%:*} * 60 + 10#${1#*:} )); }

# line \t done \t start \t end \t text
blocks=$(awk 'match($0, /^- \[[ xX]\] [0-9][0-9]:[0-9][0-9]–[0-9][0-9]:[0-9][0-9] /) {
  done = substr($0, 4, 1) != " "
  # byte offsets: macOS awk is not UTF-8 aware and "–" is 3 bytes
  print NR "\t" done "\t" substr($0, 7, 5) "\t" substr($0, 15, 5) "\t" substr($0, RLENGTH + 1)
}' "$PLAN")

title="" ; menu="" ; done_menu=""
while IFS=$'\t' read -r line done start end text; do
  [ -z "$line" ] && continue
  s=$(mins "$start"); e=$(mins "$end")
  # Short menu bar label: the part before " — " or ":" ("🎯 IMD Canvas", "📥 Batch").
  label=${text%% — *}; label=$(cut -c1-20 <<<"${label%%:*}" | clean); text=$(clean <<<"$text")
  if [ "$done" = 1 ]; then sym="checkmark.circle.fill"; col="#4CC9B0"
  elif [ "$now" -ge "$s" ] && [ "$now" -lt "$e" ]; then sym="arrow.right.circle.fill"; col="#F2C94C"
  elif [ "$now" -ge "$e" ]; then sym="exclamationmark.circle"; col="#EB5757"
  else sym="circle"; col=gray; fi
  if [ -z "$title" ] && [ "$done" = 0 ] && [ "$now" -lt "$e" ]; then
    if [ "$now" -ge "$s" ]; then title="$label · $((e - now))m"
    else title="$start $label"; fi
  fi
  item=":$sym: ${start}–${end}  $text | sfcolor=$col bash=$SELF param1=tick param2=$line terminal=false refresh=true"$'\n'
  if [ "$done" = 1 ]; then done_menu+="$item"; else menu+="$item"; fi
done <<<"$blocks"

echo ":timer: ${title:-Day done}"
echo "---"
printf '%s' "$menu"
[ -n "$done_menu" ] && printf -- '---\n%s' "$done_menu"
echo "---"
echo "Open plan in Obsidian | href=obsidian://open?vault=Notes&file=Daily-Notes%2FPlans%2F$(date +%F) sfimage=arrow.up.right.square"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
