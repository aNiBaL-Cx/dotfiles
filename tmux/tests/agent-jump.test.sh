#!/usr/bin/env bash
# Tests for tmux-agent-jump, the notification click action.
#
# Exercises the REAL invocation path: terminal-notifier spawns the jumper with no
# TMUX in the environment, so `tmux` resolves to the default socket. The tests
# therefore run with TMUX unset and put a forwarding `tmux` stub on PATH that
# redirects to an isolated -L socket, plus an `open` stub that records instead of
# foregrounding an app.
#
# Run: tmux/tests/agent-jump.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
W="$here/../scripts/tmux-agent-jump"
S=jumptest

command -v tmux >/dev/null || { echo "skipped: tmux not installed"; exit 0; }

T=$(mktemp -d); mkdir -p "$T/bin"
REAL_TMUX=$(command -v tmux)
printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$REAL_TMUX" "$S" > "$T/bin/tmux"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %s/open.log\n' "$T" > "$T/bin/open"
chmod +x "$T/bin/tmux" "$T/bin/open"

cleanup() { "$REAL_TMUX" -L $S kill-server 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT INT TERM

"$REAL_TMUX" -L $S kill-server 2>/dev/null
"$REAL_TMUX" -L $S new-session -d -s js 'sleep 60'
"$REAL_TMUX" -L $S new-window -t js 'sleep 60'
W1=$("$REAL_TMUX" -L $S list-windows -t js -F '#{window_index}' | head -1)
W2=$("$REAL_TMUX" -L $S list-windows -t js -F '#{window_index}' | tail -1)

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s (%s)\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %s: expected %s got %s\n' "$1" "$2" "$3"; fi; }
jump() { (PATH="$T/bin:$PATH" env -u TMUX "$W" "$@"); echo $?; }
active() { "$REAL_TMUX" -L $S display-message -t js -p '#{window_index}'; }

echo "-- no-ops exit 0"
check "no target"           0 "$(jump)"
check "unknown session"     0 "$(jump nosuch:1)"

echo "-- moves the active window (the actual job)"
"$REAL_TMUX" -L $S select-window -t "js:$W2"
check "starts on W2" "$W2" "$(active)"
check "jump exits 0"        0 "$(jump "js:$W1" '')"
check "now on W1"    "$W1" "$(active)"
check "jump back exits 0"   0 "$(jump "js:$W2" '')"
check "now on W2"    "$W2" "$(active)"

echo "-- terminal foregrounding"
: > "$T/open.log"
jump "js:$W1" '' >/dev/null
check "empty app: open not called" "0" "$(wc -l < "$T/open.log" | tr -d ' ')"
: > "$T/open.log"
jump "js:$W2" com.mitchellh.ghostty >/dev/null
check "bundle id uses -b" "-b com.mitchellh.ghostty" "$(cat "$T/open.log")"
: > "$T/open.log"
jump "js:$W1" Ghostty >/dev/null
check "app name uses -a" "-a Ghostty" "$(cat "$T/open.log")"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
