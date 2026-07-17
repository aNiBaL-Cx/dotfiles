# nvim → annotate bridge

Send a visual selection from nvim into the existing tmux annotate pipeline
(`tmux/scripts/annotate.sh`) with one keymap, instead of re-finding the text
in tmux copy-mode.

## Behavior

- Visual-mode keymap `<leader>a` ("Send to agent") in nvim.
- Writes the selection to `/tmp/tmux-annot-sel` — the same handoff file the
  copy-mode `a` binding uses — prefixed with a location header
  (`relative/path.lua:6-12`, cwd-relative; single-line selections collapse to
  `:6`; unnamed buffers get no header).
- Opens the annotate popup with the same `tmux display-popup` invocation as
  the `prefix a` binding. From there `annotate.sh` is unchanged: selection
  arrives `> `-quoted in the per-window buffer, `:wq` sends to the window's
  claude pane, `:cq` stashes.

## Technical details

- Code: ~25 lines appended to `~/.config/nvim/lua/config/keymaps.lua`.
  No plugin, no tmux changes.
- Selection read via `vim.fn.getregion()` (nvim 0.10+), so charwise,
  linewise, and blockwise all work without touching registers.
- Popup launched with `vim.system()` (async, non-blocking).
- Not inside tmux (`$TMUX` unset) → `vim.notify` warning, nothing written.
- Pane targeting, multi-candidate fzf pick, and error display stay in
  `annotate.sh`.

## Rejected alternatives

- Direct paste into the claude pane (skips the collect/stash buffer).
- file:line reference only (loses the quoted snippet).
- leandronsp-style watched file (requires an agent-side watcher; Claude Code
  has none).

## Done when

In a tmux window with a claude pane: select lines in nvim → `<leader>a` →
popup shows the quoted selection with the file:line header → `:wq` lands the
text unsubmitted in claude's input. `:cq` stashes. Charwise `v` selection
captures only the selected text.
