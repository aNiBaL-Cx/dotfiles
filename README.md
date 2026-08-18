# dotfiles

Personal tmux + zsh + nvim setup for an AI-agent-heavy workflow on macOS
(Ghostty).

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
- `claude-resurrect` — no keybinding; how resurrect brings claude panes back.
  Resumes the session recorded **for that pane** instead of `claude --continue`,
  which resumed the newest session for the *directory* — a coin flip with two
  claudes in one worktree. Prints which branch it took.
- `tmux-agent-wait` — no keybinding; the scriptable counterpart to the agent
  TUI. Blocks until agent panes go idle (or exit) so fan-out scripts can launch
  N agents, wait, then collect. Selectors: `%5`, `active`, `path:<dir>`,
  `branch:<ref>`, `<session>:<window>`. Distinct exit codes for timeout, early
  exit, and never-started; `--help` for the rest.

**Quality of life:** catppuccin (mocha) + TPM, resurrect/continuum session
persistence (Claude panes come back via `claude-resurrect`), extended keys
(CSI u) for Shift+Enter in TUIs, undercurl, copy-on-select to the macOS
clipboard, per-pane title borders.

**zsh.** Oh My Zsh (robbyrussell), rbenv/nvm/pnpm/bun wiring guarded so absent
tools are skipped, man pages in nvim (`MANPAGER`), a `yolo` Claude helper, and
generic git/tmux/claude aliases. Work-specific env, functions, and aliases stay
in an untracked `~/.zshrc.local`, sourced last.

**nvim.** Stock [LazyVim](https://www.lazyvim.org/) plus a thin layer: PT-keyboard
remaps (`ç`/`Ç` → `]`/`[`, `<leader>\` split), indent folding, zellij-aware
`Ctrl+hjkl` navigation, and `Space a` on a visual selection — sends it to the
tmux annotation buffer with a `file:line` header (the nvim entry point to the
copy-mode `a` flow above).

**Chrome.** `chrome-tab-groups` — bulk-delete saved tab groups (the chips on the
bookmarks bar), which Chrome itself only lets you remove one at a time. Filter
by title, substring or `--regex`; listing is the default and `--delete` commits.
Listing works with Chrome open (it reads a throwaway copy, since Chrome locks
the store); deleting needs Chrome quit, or `--restart` to have it quit and
relaunched for you — with a confirmation first, because tabs only reopen if the
profile is set to "Continue where you left off". The groups live in the
profile's sync LevelDB alongside preferences, sessions and passkeys, so every
delete backs the store up first and only ever touches `saved_tab_group` keys.
Groups re-sync unless tab group sync is off. `--help` for the rest.

**Claude Code integration (optional).** The status bar shows the active pane's
Claude statusline — model, a 10-slot context bar, and rate-limit usage when the
API reports it (`Opus 5 [██████░░░░] 62% · 5h:19% · 7d:65%`); window tabs turn
red when an agent finishes while you're not looking; and a notification (macOS
banner, plus ntfy/Pushover when configured) reaches you outside tmux. Fed by
Claude Code hooks (statusLine command + Stop/Notification hooks writing
`/tmp/claude-statusline-<pane>`, `/tmp/agent-state-<pane>`,
`~/.claude/pane-sessions/`, and window-format overrides) — without them the
segments simply stay empty and `claude-resurrect` falls back to `--continue`.

`statusline-command.sh` picks its output channel from `$TMUX_PANE`: under tmux
it writes the pane file only, so the string isn't shown twice; anywhere else
(Orca's PTYs, a plain terminal) it prints to stdout and Claude Code renders the
status line itself.

## Install

```sh
git clone https://github.com/aNiBaL-Cx/dotfiles ~/projects/dotfiles
~/projects/dotfiles/install.sh
```

Symlinks `tmux/tmux.conf` → `~/.tmux.conf`, each script into
`~/.config/tmux/scripts/` (per-file, so local-only scripts can coexist),
`.claude/hooks/*` + `.claude/statusline-command.sh` + `.claude/CLAUDE.md` into
`~/.claude/`,
`nvim/` → `~/.config/nvim` (whole dir; an existing real directory is skipped —
move it aside first), `zsh/*` → `~/.zshrc`, `~/.zprofile`, `~/.zshenv`,
`~/.aliases`, `chrome/chrome-tab-groups` → `~/.local/bin/`,
`tmux/com.anibal.tmux.plist` → `~/Library/LaunchAgents/` (then re-bootstraps it
through `launchctl`), and clones TPM if missing. Then inside tmux: `prefix + I`
to install plugins.

The LaunchAgent starts the tmux server at login with no GUI, so
`@continuum-restore` brings the last session back after a reboot. It sets `PATH`
explicitly because launchd's default omits `/opt/homebrew/bin` and the server
hands its `PATH` to every `run-shell` job — without it, tpm, catppuccin,
continuum and resurrect all fail silently on the `tmux` they shell out to, and
you get a default green status bar with no theme and no session restore.

`chrome-tab-groups` needs one npm package; `install.sh` fetches it into
`chrome/node_modules/` (untracked) when npm is available.

Machine-local config goes in `~/.tmux.conf.local` and `~/.zshrc.local`
(both sourced last, if present).

`~/.claude/settings.json` is **not** linked and must be wired by hand: the tracked
copy is portable (`$HOME` paths) while a live one picks up absolute paths and any
agent-hook entries other tools manage — linking would strip those and they would
be reinstalled, so the two would fight. `settings.local.json` (per-machine
permission grants) is gitignored, and `.claude/skills/` is left alone because
those are symlinked in from elsewhere.

## Tests

Scripts under `tmux/scripts/` are testable headless via env-var overrides
(`AGENT_STATE_DIR`, `AGENT_PANES_FILE`, `WT_CWD`). Suites live in `tmux/tests/`
— deliberately not in `tmux/scripts/`, which `install.sh` symlinks wholesale.

```bash
tmux/tests/agent-wait.test.sh         # headless, no tmux server
tmux/tests/agent-wait.tmux.test.sh    # live tmux on an isolated -L socket
tmux/tests/claude-resurrect.test.sh   # session resolution, stubbed CLAUDE_BIN
tmux/tests/agent-jump.test.sh          # notification click action, stubbed tmux/open
chrome/tests/chrome-tab-groups.test.sh # fixture LevelDB, stubbed pgrep
```

The chrome suite builds a throwaway LevelDB shaped like Chrome's sync store and
stubs `pgrep`, so it never reads a real profile and passes with Chrome open. It
asserts that a delete leaves every non-`saved_tab_group` key intact.

The tmux suite needs `cc` (it compiles a stub binary named `claude`, since
macOS reports `pane_current_command` from the kernel process name) and skips
itself when unavailable. It never touches your real tmux server.

## Dependencies

- tmux ≥ 3.5, macOS (`pbcopy`/`pbpaste`)
- Homebrew bash ≥ 4 (the TUIs use `read -N`)
- `fzf`, `nvim` (annotation buffer / pickers)
- node (any recent version) for `chrome-tab-groups` only — resolved via
  `$CHROME_TAB_GROUPS_NODE`, `PATH`, then the newest nvm install

## Credits

- Modal config originally based on
  [hamvocke's tmux guide](https://www.hamvocke.com/blog/a-guide-to-customizing-your-tmux-conf/).
- Agent TUI, sidebar, notify pattern, and annotation-buffer idea adapted from
  [leandronsp/dotfiles](https://github.com/leandronsp/dotfiles).
