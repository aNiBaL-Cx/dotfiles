#!/usr/bin/env bash
# Usage: install.sh <name> <vault-path> [HH:MM]
# Links the gitleaks pre-commit hook into the vault and schedules vault-commit.sh daily (default 19:30).
set -euo pipefail
name=${1:?usage: install.sh <name> <vault-path> [HH:MM]}
vault=$(cd "${2:?usage: install.sh <name> <vault-path> [HH:MM]}" && pwd)
time=${3:-19:30}
dir=$(cd "$(dirname "$0")" && pwd)
git -C "$vault" rev-parse --git-dir >/dev/null
ln -sf "$dir/pre-commit" "$vault/.git/hooks/pre-commit"
plist="$HOME/Library/LaunchAgents/vault-commit.$name.plist"
sed -e "s#VAULT_NAME#$name#g" -e "s#SCRIPT_DIR#$dir#g" -e "s#VAULT_PATH#$vault#g" \
    -e "s#LOG_FILE#$HOME/Library/Logs/vault-commit-$name.log#g" \
    -e "s#HOUR#$((10#${time%%:*}))#" -e "s#MINUTE#$((10#${time##*:}))#" \
    "$dir/vault-commit.plist.template" >"$plist"
plutil -lint "$plist" >/dev/null
launchctl bootout "gui/$(id -u)/vault-commit.$name" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "installed vault-commit.$name: $vault daily at $time"
