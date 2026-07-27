#!/usr/bin/env bash
# Tests for claude-resurrect's session resolution. CLAUDE_BIN is pointed at a
# stub that prints its argv, so every branch is checked without launching a real
# agent. Runs headless: with TMUX unset there is no per-pane key, which is how
# the cwd-fallback branches are exercised.
#
# Run: tmux/tests/claude-resurrect.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
W="$here/../scripts/claude-resurrect"

T=$(mktemp -d)
export CLAUDE_PANE_SESSIONS_DIR="$T/pane-sessions"
export CLAUDE_PROJECTS_DIR="$T/projects"
export CLAUDE_BIN="$T/bin/claude-stub"
mkdir -p "$CLAUDE_PANE_SESSIONS_DIR" "$T/bin" "$T/wt"
printf '#!/bin/sh\nprintf "ARGV:%%s\\n" "$*"\n' > "$CLAUDE_BIN"; chmod +x "$CLAUDE_BIN"

slug() { printf '%s' "$1" | sed 's/[/.]/-/g'; }
# Resolved, because that is the form agent-state.sh records (it reads tmux's
# pane_current_path) — mktemp dirs live under a symlinked /var, so the logical
# and resolved paths differ here exactly as they would under a symlinked root.
CWD=$(cd "$T/wt" && pwd -P)
PROJ="$CLAUDE_PROJECTS_DIR/$(slug "$CWD")"

pass=0; fail=0
check() { # name expected-substring actual
  case "$3" in
    *"$2"*) pass=$((pass+1)); printf '  ok   %s → %s\n' "$1" "$3" ;;
    *) fail=$((fail+1)); printf '  FAIL %s: wanted *%s* got %s\n' "$1" "$2" "$3" ;;
  esac
}
# Headless: unset TMUX so no per-pane key is derived unless a test sets one.
run() { (cd "$CWD" && env -u TMUX "$W" "$@" 2>/dev/null); }

echo "-- no transcripts at all"
check "starts fresh" "ARGV:" "$(run)"
check "no --resume"  "ARGV:" "$(run | grep -v resume || echo 'ARGV:')"

echo "-- exactly one transcript for the cwd"
mkdir -p "$PROJ"; : > "$PROJ/aaaaaaaa-1111.jsonl"
check "resumes the only one" "ARGV:--resume aaaaaaaa-1111" "$(run)"

echo "-- several transcripts, no per-pane record"
sleep 1; : > "$PROJ/bbbbbbbb-2222.jsonl"
check "falls back to --continue" "ARGV:--continue" "$(run)"

echo "-- extra args are forwarded"
check "forwards --model" "--continue --model opus" "$(run --model opus)"

echo "-- per-pane record wins"
# Simulate a tmux pane by pre-writing the record key this cwd would produce.
key="s1__3.0__$(slug "$CWD")"
printf 'aaaaaaaa-1111' > "$CLAUDE_PANE_SESSIONS_DIR/$key"
fake_tmux="$T/bin/tmux"
printf '#!/bin/sh\nprintf "s1|3|0\\n"\n' > "$fake_tmux"; chmod +x "$fake_tmux"
runp() { (cd "$CWD" && PATH="$T/bin:$PATH" TMUX=/fake,0,0 TMUX_PANE=%9 "$W" "$@" 2>/dev/null); }
check "resumes recorded id" "ARGV:--resume aaaaaaaa-1111" "$(runp)"

echo "-- recorded session whose transcript is gone"
printf 'cccccccc-3333' > "$CLAUDE_PANE_SESSIONS_DIR/$key"
check "falls back, not --resume cccc" "ARGV:--continue" "$(runp)"

echo "-- symlinked cwd resolves to the same key as tmux would record"
# agent-state.sh keys off tmux's resolved pane_current_path; entering through a
# symlink must not change the key, or the lookup degrades silently.
printf 'aaaaaaaa-1111' > "$CLAUDE_PANE_SESSIONS_DIR/$key"
ln -s "$CWD" "$T/link-to-wt"
runl() { (cd "$T/link-to-wt" && PATH="$T/bin:$PATH" TMUX=/fake,0,0 TMUX_PANE=%9 "$W" 2>/dev/null); }
check "resolves through symlink" "ARGV:--resume aaaaaaaa-1111" "$(runl)"

rm -rf "$T"
printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
