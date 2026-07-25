#!/usr/bin/env bash
# tmux-dependent tests for tmux-agent-wait: selector resolution and the pane
# liveness states (exited / gone), which need a real server.
#
# Runs on an isolated socket (-L waittest) so your real sessions are never
# touched. Note -L only changes the SOCKET, not the config file: ~/.tmux.conf
# still loads, so base-index applies — read window indexes, don't assume :0.
#
# The fake agent has to be a real binary named `claude`, because macOS reports
# pane_current_command from the kernel process name: a shell script shows up as
# sh/bash and a symlink to /bin/sleep shows up as sleep. Needs cc (Xcode CLT).
#
# Run: tmux/tests/agent-wait.tmux.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
W="$here/../scripts/tmux-agent-wait"
S=waittest

command -v cc >/dev/null || { echo "skipped: cc not available (needs Xcode CLT)"; exit 0; }
command -v tmux >/dev/null || { echo "skipped: tmux not installed"; exit 0; }

T=$(mktemp -d)
export AGENT_STATE_DIR="$T/state"; mkdir -p "$AGENT_STATE_DIR" "$T/bin"

printf '#include <unistd.h>\nint main(void){for(;;)pause();return 0;}\n' > "$T/c.c"
cc -o "$T/bin/claude" "$T/c.c" || { echo "cannot build stub agent"; exit 1; }

mkdir -p "$T/repo"; cd "$T/repo" || exit 1
git init -q . && git commit -q --allow-empty -m init
git worktree add -q -b feat/wt "$T/repo/.worktrees/wt" >/dev/null 2>&1
WT="$T/repo/.worktrees/wt"

tmux -L $S kill-server 2>/dev/null
tmux -L $S new-session -d -s s1 -c "$WT" "$T/bin/claude"
sleep 1.2
PANE=$(tmux -L $S list-panes -a -F '#{pane_id}|#{pane_current_command}' | awk -F'|' '$2=="claude"{print $1;exit}')
SOCK=$(tmux -L $S display-message -p '#{socket_path}')
LOC=$(tmux -L $S list-panes -a -F '#{pane_id}|#{session_name}:#{window_index}' | awk -F'|' -v p="$PANE" '$1==p{print $2;exit}')

cleanup() { tmux -L $S kill-server 2>/dev/null; cd /tmp || return; rm -rf "$T"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s (exit %s)\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %s: expected %s got %s\n' "$1" "$2" "$3"; fi; }
inwait() { TMUX="$SOCK,0,0" "$W" -q --interval 200 "$@"; echo $?; }

echo "-- setup"
[ -n "$PANE" ] && printf '  ok   fake agent pane %s at %s\n' "$PANE" "$LOC" || { echo "  FAIL no agent pane"; exit 1; }

echo "-- selector resolution (state says idle)"
printf 'idle' > "$AGENT_STATE_DIR/agent-state-$PANE"
# $WT is an unresolved /var/... path while tmux reports /private/var/... — this
# is the regression guard for abspath() in the script.
check "path: resolves"      0 "$(inwait --grace 2 --timeout 5 "path:$WT")"
check "branch: resolves"    0 "$(cd "$T/repo" && inwait --grace 2 --timeout 5 branch:feat/wt)"
check "sess:win resolves"   0 "$(inwait --grace 2 --timeout 5 "$LOC")"
check "raw pane id"         0 "$(inwait --grace 2 --timeout 5 "$PANE")"
check "bad path errors"     1 "$(inwait --timeout 3 path:/nope/nope)"
check "bad branch errors"   1 "$(cd "$T/repo" && inwait --timeout 3 branch:no-such)"

echo "-- state file drives the result, not the selector"
printf 'working' > "$AGENT_STATE_DIR/agent-state-$PANE"
check "working times out"   2 "$(inwait --timeout 1 "path:$WT")"

echo "-- --for exit"
check "exit not yet"        2 "$(inwait --for exit --timeout 1 "$PANE")"
# Replace the agent with a plain shell: the pane lives, the command reverts.
( sleep 0.6; tmux -L $S respawn-pane -k -t "$PANE" "$SHELL" 2>/dev/null ) &
check "exit on revert"      0 "$(inwait --for exit --timeout 8 "$PANE")"
wait

echo "-- --for idle on a dead agent"
printf 'working' > "$AGENT_STATE_DIR/agent-state-$PANE"
check "exited while waiting" 3 "$(inwait --for idle --timeout 5 "$PANE")"

echo "-- pane gone entirely"
# Not by restarting the server: a fresh server hands out %0 again, so the old
# id would resolve to a live pane. Use an id that cannot exist.
check "gone counts as exit" 0 "$(inwait --for exit --timeout 4 %999)"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
