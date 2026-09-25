#!/usr/bin/env bash
# List every pane running an agent (claude / agent / cursor-agent) across all
# sessions and windows; jump focus to the selected one.
#
# Called from tmux: display-popup -E "agents.sh"
set -uo pipefail

die() {
  printf '\n\033[31magents: %s\033[0m\n\npress any key…' "$*" >&2
  read -rsn1 _ </dev/tty 2>/dev/null || true
  exit 1
}

command -v fzf >/dev/null 2>&1 || die "fzf not found in this popup's PATH.
PATH=$PATH"

tab=$'\t'
fmt="#{pane_id}${tab}#{session_name}:#{window_index} #{window_name}${tab}#{pane_current_command}${tab}#{pane_current_path}"

list="$(tmux list-panes -a -F "$fmt" \
  | awk -F"$tab" '$3 == "claude" || $3 == "agent" || $3 == "cursor-agent"')"

[ -n "$list" ] || die "no agent panes found (claude / agent / cursor-agent)"

sel_pane="$(
  printf '%s\n' "$list" \
    | fzf --delimiter="$tab" --with-nth=2.. \
          --prompt='agent > ' --height=100% --reverse \
          --preview 'tmux capture-pane -p -t {1} | tail -40' \
    | cut -f1
)"

[ -n "$sel_pane" ] || exit 0

sess="$(tmux display-message -p -t "$sel_pane" '#{session_name}')"
tmux switch-client -t "$sess" 2>/dev/null || true
tmux select-window -t "$sel_pane"
tmux select-pane -t "$sel_pane"
