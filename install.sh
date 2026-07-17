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

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  echo "installed TPM"
fi

echo
echo "done — inside tmux: prefix + I to install plugins, prefix + r to reload"
