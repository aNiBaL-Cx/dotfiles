#!/usr/bin/env bash
# Symlink this repo's tmux config into place. Idempotent — safe to re-run.
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"

ln -sfn "$repo/tmux/tmux.conf" "$HOME/.tmux.conf"
echo "linked ~/.tmux.conf"

# Per-file links so machine-local scripts can coexist in the same directory.
mkdir -p "$HOME/.config/tmux/scripts"
for f in "$repo"/tmux/scripts/*; do
  chmod +x "$f"
  ln -sfn "$f" "$HOME/.config/tmux/scripts/$(basename "$f")"
  echo "linked ~/.config/tmux/scripts/$(basename "$f")"
done

# Claude Code: the hooks + statusline that feed the tmux status bar, agent TUI,
# notifications and claude-resurrect, plus the global writing guidelines. Per-file
# again, so machine-local hooks can sit alongside these.
#
# Deliberately NOT linked:
#   settings.json       — the tracked copy is portable ($HOME paths, no
#                         Orca-managed entries); the live one has absolute paths
#                         and Orca's 10 hook entries, which the app rewrites.
#                         Linking would strip them, Orca would put them back, and
#                         the two would fight forever. Wire it by hand.
#   settings.local.json — per-machine permission grants (gitignored).
#   skills/             — symlinked in from the notes vault, and ln -sfn into an
#                         existing real directory nests the link inside it.
mkdir -p "$HOME/.claude/hooks"
for f in "$repo"/.claude/hooks/*; do
  [ -e "$f" ] || continue
  chmod +x "$f"
  ln -sfn "$f" "$HOME/.claude/hooks/$(basename "$f")"
  echo "linked ~/.claude/hooks/$(basename "$f")"
done
chmod +x "$repo/.claude/statusline-command.sh"
ln -sfn "$repo/.claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
ln -sfn "$repo/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
echo "linked ~/.claude/statusline-command.sh ~/.claude/CLAUDE.md"

# Whole-dir link; ln -sfn into an existing real directory would nest the link
# inside it, so require it to be moved aside first.
if [ -d "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  echo "skipped ~/.config/nvim (existing directory — move it aside first)"
else
  ln -sfn "$repo/nvim" "$HOME/.config/nvim"
  echo "linked ~/.config/nvim"
fi

ln -sfn "$repo/zsh/zshrc"    "$HOME/.zshrc"
ln -sfn "$repo/zsh/zprofile" "$HOME/.zprofile"
ln -sfn "$repo/zsh/zshenv"   "$HOME/.zshenv"
ln -sfn "$repo/zsh/aliases"  "$HOME/.aliases"
echo "linked ~/.zshrc ~/.zprofile ~/.zshenv ~/.aliases"

# Not under tmux/scripts: the loop above chmods and links everything in that
# directory, which would drag node_modules along with it.
mkdir -p "$HOME/.local/bin"
chmod +x "$repo/chrome/chrome-tab-groups"
ln -sfn "$repo/chrome/chrome-tab-groups" "$HOME/.local/bin/chrome-tab-groups"
echo "linked ~/.local/bin/chrome-tab-groups"

if [ ! -d "$repo/chrome/node_modules" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm install --prefix "$repo/chrome" --silent --no-audit --no-fund
    echo "installed chrome-tab-groups dependencies"
  else
    echo "skipped chrome-tab-groups dependencies (no npm — run: npm install --prefix $repo/chrome)"
  fi
fi

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  echo "installed TPM"
fi

echo
echo "done — inside tmux: prefix + I to install plugins, prefix + r to reload"
