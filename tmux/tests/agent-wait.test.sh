#!/usr/bin/env bash
# Headless tests for tmux-agent-wait: no tmux server needed. AGENT_STATE_DIR
# points the script at a temp dir, and with TMUX unset it assumes panes are
# live and reads only the state files. Covers argument handling and every
# exit code that does not depend on tmux.
#
# Run: tmux/tests/agent-wait.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
W="$here/../scripts/tmux-agent-wait"

D=$(mktemp -d)
export AGENT_STATE_DIR="$D"
unset TMUX

pass=0; fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s (exit %s)\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %s: expected %s got %s\n' "$1" "$2" "$3"; fi
}
run() { "$W" -q --interval 100 "$@"; echo $?; }

echo "-- usage errors"
check "no selector"      1 "$(run --for idle)"
check "bad --for"        1 "$(run --for banana %1)"
check "bad selector"     1 "$(run --for idle nonsense)"
check "unknown option"   1 "$(run --frobnicate %1)"
check "non-numeric"      1 "$(run --timeout abc %1)"

echo "-- never started (missing state file)"
check "grace exceeded"   4 "$(run --grace 1 --timeout 10 %1)"

echo "-- already idle"
printf 'idle' > "$D/agent-state-%1"
check "single idle"      0 "$(run --grace 1 --timeout 5 %1)"

echo "-- working then idle"
printf 'working' > "$D/agent-state-%2"
( sleep 1; printf 'idle' > "$D/agent-state-%2" ) &
check "transitions"      0 "$(run --timeout 10 %2)"
wait

echo "-- stays working -> timeout"
printf 'working' > "$D/agent-state-%3"
check "timeout"          2 "$(run --timeout 1 %3)"

echo "-- all vs any"
printf 'idle'    > "$D/agent-state-%4"
printf 'working' > "$D/agent-state-%5"
check "any matches"      0 "$(run --any --timeout 2 %4 %5)"
check "all times out"    2 "$(run --timeout 1 %4 %5)"
printf 'idle' > "$D/agent-state-%5"
check "all matches"      0 "$(run --timeout 5 %4 %5)"

echo "-- settle guard (idle must hold)"
printf 'idle' > "$D/agent-state-%6"
( sleep 0.15; printf 'working' > "$D/agent-state-%6" ) &
check "flap not idle"    2 "$(run --settle 5 --timeout 1 %6)"
wait

echo "-- --help"
"$W" --help >/dev/null 2>&1; check "help exits 0" 0 "$?"

rm -rf "$D"
printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
