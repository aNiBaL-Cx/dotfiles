#!/usr/bin/env bash
# Records the agent's state for the tmux agent TUI + sidebar. This is the
# robust, version-independent signal: it comes from Claude's stable hook API,
# not from scraping the UI. Written per pane to /tmp/agent-state-<pane_id>.
# Wiring (settings.json): UserPromptSubmit -> working ; Stop/Notification -> idle.
# Usage: agent-state.sh <working|idle>
#
# Also records which Claude SESSION this pane runs, for claude-resurrect
# (~/.config/tmux/scripts/claude-resurrect). /tmp does not survive the reboot
# resurrect exists to handle, so that record lives under
# ~/.claude/pane-sessions/, keyed by coordinates resurrect restores faithfully
# (session:window.pane) plus the cwd — NOT by pane_id, which is reassigned on
# restore.

[ -z "$TMUX" ] && exit 0

IFS='|' read -r pane sess win pidx cwd <<< "$(tmux display-message -t "${TMUX_PANE:-}" \
  -p '#{pane_id}|#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}' 2>/dev/null)"
[ -z "$pane" ] && exit 0

printf '%s' "${1:-idle}" > "/tmp/agent-state-$pane"

# The hook payload (JSON on stdin) carries session_id. Skip when run by hand from
# a terminal, where cat would block on the tty.
[ -t 0 ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
session_id=$(cat | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && exit 0

dir="$HOME/.claude/pane-sessions"
mkdir -p "$dir" 2>/dev/null || exit 0
printf '%s' "$session_id" > "$dir/${sess}__${win}.${pidx}__$(printf '%s' "$cwd" | sed 's/[/.]/-/g')"

exit 0
