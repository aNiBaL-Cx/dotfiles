#!/usr/bin/env bash
# Annotation buffer (small popup, top-right). A persistent per-window buffer
# collects copy-mode selections (quoted) and your notes; sending bracket-pastes
# it into the window's claude/agent pane.
#
# Entry points (tmux.conf):
#   copy-mode a : append the selection to the buffer, then edit it
#   prefix a    : open the buffer without adding a selection
#
# Editor exit semantics:
#   :wq  -> send the buffer to the agent pane, then clear it
#   :cq  -> stash — keep the buffer for the next round, send nothing
#   save emptied (whitespace-only) -> nothing sent, buffer cleared
#
# NOTE: no `set -e`. Errors are handled explicitly and shown (die) so the popup
# never just flashes closed without saying why.
set -uo pipefail

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >> "${TMPDIR:-/tmp}/tmux-annotate.log"; }

# Show a message and hold the popup open until a key is pressed, so failures are
# visible instead of a silent flash.
die() {
  printf '\n\033[31mannotate: %s\033[0m\n\npress any key…' "$*" >&2
  read -rsn1 _ </dev/tty 2>/dev/null || true
  exit 1
}

# display-popup does NOT format-expand its shell-command, so the source pane
# can't be passed as an argument. Inside a popup, $TMUX_PANE is empty but the
# current pane still resolves to the active (source) pane.
src_pane="$(tmux display-message -p '#{pane_id}')"
[ -n "$src_pane" ] || die "could not determine the source pane"
log "start src_pane=$src_pane PATH=$PATH"

# Resolve the editor up front so a missing editor is a clear error, not a
# silent exit misread as "user cancelled".
editor="${EDITOR:-nvim}"
editor_bin="${editor%% *}"
command -v "$editor_bin" >/dev/null 2>&1 \
  || die "editor '$editor_bin' not found in this popup's PATH.
PATH=$PATH
Fix: ensure the dir containing nvim is on PATH for the tmux server."
log "editor=$editor"

# Persistent per-window buffer, keyed by window_id (stable under
# renumber-windows, unlike the index).
win_id="$(tmux display-message -p -t "$src_pane" '#{window_id}')"
tmpfile="/tmp/tmux-annot-buf-${win_id#@}.md"

# Append the copy-mode selection handed over by the copy-mode-vi a binding.
# Absent file = opened via prefix a (review/extend without a new selection).
sel_file="/tmp/tmux-annot-sel"
if [ -s "$sel_file" ]; then
  sed 's/^/> /' "$sel_file" >> "$tmpfile"
  printf '\n' >> "$tmpfile"
fi
rm -f "$sel_file"
log "buffer $tmpfile ($(wc -l < "$tmpfile" 2>/dev/null || echo 0) lines)"

# Edit. :cq (non-zero exit) = stash, keep the buffer.
$editor "$tmpfile"
rc=$?
log "editor exit rc=$rc"
[ "$rc" -eq 0 ] || exit 0

# Nothing but whitespace left -> nothing to send; clear the buffer.
if ! grep -q '[^[:space:]]' "$tmpfile" 2>/dev/null; then
  : > "$tmpfile"
  exit 0
fi

# Target = a claude/agent pane in the SAME window as the source. Current
# Claude Code panes report their version as pane_current_command (e.g.
# 2.1.211), older ones "claude"; cursor-agent/agent kept for those TUIs.
win="$(tmux display-message -p -t "$src_pane" '#{window_id}')" || die "no window for $src_pane"
tab=$'\t'
target=""; count=0
while IFS= read -r pid; do target="$pid"; count=$((count + 1)); done < <(
  tmux list-panes -t "$win" -F "#{pane_id}${tab}#{pane_current_command}" \
    | awk -F"$tab" '$2 ~ /^[0-9]/ || $2 == "claude" || $2 == "agent" || $2 == "cursor-agent" {print $1}'
)
log "candidates=$count"

if [ "$count" -ne 1 ]; then
  command -v fzf >/dev/null 2>&1 || die "fzf not found (needed to pick a target pane)"
  target="$(
    tmux list-panes -t "$win" \
      -F "#{pane_id}${tab}#{pane_index}: #{pane_current_command}  #{pane_title}" \
      | fzf --delimiter="$tab" --with-nth=2.. \
            --prompt='send annotations to > ' --height=40% --reverse \
      | cut -f1
  )"
fi

[ -n "$target" ] || exit 0

# Bracket-paste into the target's input; no Enter — you review and submit.
tmux load-buffer -b tmux-annot "$tmpfile" || die "load-buffer failed"
tmux paste-buffer -p -b tmux-annot -t "$target" || die "paste-buffer failed"
tmux delete-buffer -b tmux-annot 2>/dev/null || true
: > "$tmpfile"
log "pasted to $target"
