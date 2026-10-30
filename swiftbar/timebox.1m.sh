#!/usr/bin/env bash
# SwiftBar plugin: today's time blocks. Reads <TIMEBOX_PLAN_DIR>/<YYYY-MM-DD>.md, one
# block per line, "- [ ] HH:MM–HH:MM <text>" (en dash). Shows the current block in
# the menu bar, notifies when it changes, and ticks a block when clicked.
#
# Config, outside this repo: ~/.config/swiftbar/timebox.env
#   TIMEBOX_PLAN_DIR=/path/to/plans            directory holding the daily plan files
#   TIMEBOX_PLAN_URL='obsidian://...<date>...'  optional; opens today's plan, <date> = YYYY-MM-DD
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export LC_ALL=en_US.UTF-8
clean() { sed 's/|/¦/g; s/:/∶/g'; }

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
CONFIG="$HOME/.config/swiftbar/timebox.env"
STATE=/tmp/timebox.cur
[ -f "$CONFIG" ] && . "$CONFIG"
if [ -z "$TIMEBOX_PLAN_DIR" ]; then
  echo ":calendar.badge.exclamationmark: Timebox"
  echo "---"
  echo "Set TIMEBOX_PLAN_DIR in $CONFIG | sfimage=gear"
  exit 0
fi
today=$(date +%F)
PLAN="$TIMEBOX_PLAN_DIR/$today.md"
URL=${TIMEBOX_PLAN_URL//<date>/$today}
if [ -n "$URL" ]; then open_plan="href=$URL"; else open_plan="bash=/usr/bin/open param1=$PLAN terminal=false"; fi

# "$0 tick <HH:MM>" flips the checkbox of the block starting at that time.
if [ "$1" = tick ] && [ -n "$2" ]; then
  perl -i -pe "if (/^- \[[ xX]\] \Q$2\E–/) { s/^- \[ \]/- [x]/ or s/^- \[[xX]\]/- [ ]/ }" "$PLAN"
  exit 0
fi

if [ ! -f "$PLAN" ]; then
  echo ":calendar.badge.exclamationmark: No plan"
  echo "---"
  echo "No plan for $today | sfimage=info.circle"
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
unparsed=$(( $(grep -c '^- \[' "$PLAN") - $(grep -c . <<<"$blocks") ))

title="" ; cur="" ; menu="" ; done_menu="" ; icon=timer ; early=0
while IFS=$'\t' read -r line done start end text; do
  [ -z "$line" ] && continue
  s=$(mins "$start"); e=$(mins "$end")
  text=${text//\*\*/}; text=${text//\`/}
  # Menu bar label: focus blocks show the outcome ("🎯 QA on staging five"),
  # the rest the part before " — " or ": " ("🏠 Bike", "📥 Batch").
  label=${text%% — *}; label=${label%%: *}
  [[ $text == 🎯*" — "* ]] && label="🎯 ${text#* — }"
  label=$(cut -c1-24 <<<"$label" | clean); text=$(clean <<<"$text")
  if [ "$done" = 1 ]; then sym="checkmark.circle.fill"; col="#4CC9B0"
    [ "$now" -ge "$s" ] && [ "$now" -lt "$e" ] && early=1
  elif [ "$now" -ge "$s" ] && [ "$now" -lt "$e" ]; then sym="arrow.right.circle.fill"; col="#F2C94C"
  elif [ "$now" -ge "$e" ] && [[ $text == 🎯* ]]; then sym="exclamationmark.circle"; col="#EB5757"; icon=exclamationmark.circle
  else sym="circle"; col=gray; fi
  if [ -z "$title" ] && [ "$done" = 0 ] && [ "$now" -lt "$e" ]; then
    if [ "$now" -ge "$s" ]; then title="$label · $((e - now))m"; cur="$today $start"
    elif [ "$early" = 1 ]; then title="▸ $label · start now"
    else title="$start $label"; fi
  fi
  item=":$sym: ${start}–${end}  $text | sfcolor=$col bash=$SELF param1=tick param2=$start terminal=false refresh=true"$'\n'
  if [ "$done" = 1 ]; then done_menu+="$item"; else menu+="$item"; fi
done <<<"$blocks"

# One notification when the current block changes.
if [ -n "$cur" ] && [ "$cur" != "$(cat "$STATE" 2>/dev/null)" ]; then
  enc() { jq -rn --arg s "$1" '$s|@uri'; }
  open "swiftbar://notify?plugin=$(basename "$SELF")&title=Timebox&body=$(enc "$title")${URL:+&href=$(enc "$URL")}"
  echo "$cur" >"$STATE"
fi

echo ":$icon: ${title:-Day done}"
echo "---"
printf '%s' "$menu"
[ -n "$menu" ] && [ -n "$done_menu" ] && echo "---"
printf '%s' "$done_menu"
[ "$unparsed" -gt 0 ] && echo ":exclamationmark.triangle: $unparsed block lines not parsed (need \"- [ ] HH:MM–HH:MM\", en dash) | sfcolor=#EB5757"
echo "---"
echo "Open plan | $open_plan sfimage=arrow.up.right.square"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
