#!/usr/bin/env bash
# Usage: vault-commit.sh <vault-path> [log-file]
# Commits and pushes everything changed in the vault, unless gitleaks finds a secret.
set -euo pipefail
vault=${1:?usage: vault-commit.sh <vault-path> [log-file]}
exec >>"${2:-$HOME/Library/Logs/vault-commit-$(basename "$vault").log}" 2>&1
echo "=== $(date '+%F %T')"
cd "$vault"
unset GITHUB_TOKEN # a stale token in the launchd env breaks an https push
git add -A
git diff --cached --quiet && exit 0
gitleaks git --staged --redact --no-banner || { echo "gitleaks hit: commit aborted"; git reset -q; exit 1; }
git commit -m "notes: $(date +%F)"
git push origin HEAD
