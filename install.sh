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

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  echo "installed TPM"
fi

echo
echo "done — inside tmux: prefix + I to install plugins, prefix + r to reload"
