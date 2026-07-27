#!/usr/bin/env bash
# Claude Code Stop/Notification hook: when Claude is waiting for input and
# you're not looking at its window, highlight that window's tab in red
# (catppuccin red on base). If the agent lives in a different session than
# the one you're viewing, also turn the viewed session's status-left red.
#
# Resets live in ~/.tmux.conf: the pane-focus-in / client-focus-in /
# client-session-changed hooks unset the window-level window-status-format
# (falling back to catppuccin's global format) and the session-level
# status-left.

[ -z "$TMUX" ] && exit 0
[ -z "$TMUX_PANE" ] && exit 0

claude_session=$(tmux display-message -t "$TMUX_PANE" -p '#S') || exit 0
claude_window=$(tmux display-message -t "$TMUX_PANE" -p '#I')
window_target="${claude_session}:${claude_window}"

# Skip when you're actually looking: some focused client is displaying this
# session AND window. (Multiple clients possible: Ghostty + Cursor panel.)
while IFS='|' read -r c_session c_window c_flags; do
  if [ "$c_session" = "$claude_session" ] && [ "$c_window" = "$claude_window" ] \
     && [[ "$c_flags" == *focused* ]]; then
    exit 0
  fi
done < <(tmux list-clients -F '#{session_name}|#{window_index}|#{client_flags}')

# Red tab on the agent's window. Window-level override — catppuccin's global
# window-status-format returns when the tmux reset hooks unset it.
tmux set-window-option -t "$window_target" window-status-format "#[fg=#1e1e2e,bg=#f38ba8,bold] #I #W "

# Notification (macOS banner always; ntfy/Pushover when configured). The red tab
# only exists inside tmux — this is the signal that reaches you when Ghostty is
# in the background or you are away from the machine. Debounced per pane.
claude_window_name=$(tmux display-message -t "$TMUX_PANE" -p '#W')
meta=$(awk -F' · ' 'NR==1{print $1 (NF>1?" · "$2:"")}' \
  "/tmp/claude-statusline-${TMUX_PANE}" 2>/dev/null)
"$(dirname "$0")/notify-push.sh" \
  "agent ready · ${claude_window_name}" \
  "${claude_session}:${claude_window}${meta:+ · $meta}" \
  "$TMUX_PANE"

# Cross-session: mark status-left red in every session currently being viewed
# that is not the agent's own.
while IFS= read -r viewed_session; do
  [ "$viewed_session" = "$claude_session" ] && continue
  tmux set-option -t "$viewed_session" status-left "#[fg=#1e1e2e,bg=#f38ba8,bold] #S ⏳ #[default] "
done < <(tmux list-clients -F '#{session_name}' | sort -u)

exit 0
