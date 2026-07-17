# dotfiles

Personal tmux setup for an AI-agent-heavy workflow on macOS (Ghostty).

## What's in it

**Modal workflow, tmux-native.** Zellij-style sticky modes (pane / tab / resize /
session / scroll) entered with the prefix (`Ctrl+Space`), with a bottom hint bar
that shows the active mode's keys — no prefixless captures, so `Ctrl+t/p/n/s`
stay free for the shell and editors.

**Agent tooling** (popups + a docked sidebar):

- `prefix g` — agent TUI: every Claude/agent pane across all sessions with live
  state (idle / working / done-unseen); jump, multi-select, bulk-kill.
- `prefix b` — agent sidebar: 34-col live list as a real split; jump with enter.
- copy-mode `a` / `prefix a` — annotation buffer: collect quoted selections +
  notes per window in a small popup, bracket-paste into the window's agent pane
  (`:wq` send, `:cq` stash).
- `prefix w` — cross-repo worktree picker: groups worktrees by name across
  sibling repos (root inferred from the current repo, or `$WORKTREE_ROOT`).
- `prefix W` — worktree manager for the current repo: open/jump, new, delete,
  rename.

**Quality of life:** catppuccin (mocha) + TPM, resurrect/continuum session
persistence (Claude panes relaunch as `claude --continue`), extended keys
(CSI u) for Shift+Enter in TUIs, undercurl, copy-on-select to the macOS
clipboard, per-pane title borders.

**Claude Code integration (optional).** The status bar shows the active pane's
Claude statusline, and window tabs turn red when an agent finishes while you're
not looking. Both are fed by Claude Code hooks (statusLine command +
Stop/Notification hooks writing `/tmp/claude-statusline-<pane>` /
window-format overrides) that live outside this repo — without them the
segments simply stay empty.

## Install

```sh
git clone https://github.com/aNiBaL-Cx/dotfiles ~/projects/dotfiles
~/projects/dotfiles/install.sh
```

Symlinks `tmux/tmux.conf` → `~/.tmux.conf` and each script into
`~/.config/tmux/scripts/` (per-file, so local-only scripts can coexist), and
clones TPM if missing. Then inside tmux: `prefix + I` to install plugins.

Machine-local bindings go in `~/.tmux.conf.local` (sourced last, if present).

## Dependencies

- tmux ≥ 3.5, macOS (`pbcopy`/`pbpaste`)
- Homebrew bash ≥ 4 (the TUIs use `read -N`)
- `fzf`, `nvim` (annotation buffer / pickers)

## Credits

- Modal config originally based on
  [hamvocke's tmux guide](https://www.hamvocke.com/blog/a-guide-to-customizing-your-tmux-conf/).
- Agent TUI, sidebar, notify pattern, and annotation-buffer idea adapted from
  [leandronsp/dotfiles](https://github.com/leandronsp/dotfiles).
