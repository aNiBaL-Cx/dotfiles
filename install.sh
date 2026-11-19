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

# Single-file link: the rest of ~/.config/herdr is runtime state (sockets, logs,
# session.json). Herdr writes config.toml itself (settings screen, onboarding);
# if a save ever replaces the link with a plain file, copy it back here.
mkdir -p "$HOME/.config/herdr"
ln -sfn "$repo/herdr/config.toml" "$HOME/.config/herdr/config.toml"
echo "linked ~/.config/herdr/config.toml"

# herdr-plus worktree auto-layouts. Linked per file: the plugin's config dir also
# holds files it seeds itself (quick-actions/).
hp="$HOME/.config/herdr/plugins/config/cloudmanic.herdr-plus/worktrees"
mkdir -p "$hp"
for f in "$repo"/herdr/herdr-plus/worktrees/*.toml; do
  ln -sfn "$f" "$hp/$(basename "$f")"
  echo "linked $hp/$(basename "$f")"
done

# Starts the tmux server at login with no GUI, so @continuum-restore brings the
# last session back after a reboot (replaces @continuum-boot — see tmux.conf).
#
# The plist sets EnvironmentVariables/PATH on purpose: launchd's default PATH is
# /usr/bin:/bin:/usr/sbin:/sbin, and the server passes its own PATH to every
# run-shell job, so a server started by this agent leaves tpm, catppuccin,
# continuum and resurrect unable to find the `tmux` they shell out to. It fails
# silently — default green status bar, no theme, no restore, empty boot log.
mkdir -p "$HOME/Library/LaunchAgents"
ln -sfn "$repo/tmux/com.anibal.tmux.plist" "$HOME/Library/LaunchAgents/com.anibal.tmux.plist"
echo "linked ~/Library/LaunchAgents/com.anibal.tmux.plist"

# Re-bootstrap so an edited plist takes effect now instead of at next login.
# bootout fails when it isn't loaded yet, bootstrap fails when it already is —
# hence the guards, with launchctl print as the actual check.
launchctl bootout "gui/$(id -u)/com.anibal.tmux" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.anibal.tmux.plist" 2>/dev/null || true
if launchctl print "gui/$(id -u)/com.anibal.tmux" >/dev/null 2>&1; then
  echo "loaded com.anibal.tmux"
else
  echo "WARNING: com.anibal.tmux not loaded — launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.anibal.tmux.plist"
fi

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
# Global agent instructions: agents/AGENTS.md is the one copy. Claude Code's
# CLAUDE.md imports it from ~/.agents/AGENTS.md; each ~/.codex* home reads its
# own AGENTS.md. An existing real file is skipped, not overwritten.
mkdir -p "$HOME/.agents"
for dir in "$HOME/.agents" "$HOME"/.codex*/; do
  [ -d "$dir" ] || continue  # no ~/.codex* home: the glob stays literal
  target="${dir%/}/AGENTS.md"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skipped $target (existing file — merge it into agents/AGENTS.md first)"
  else
    ln -sfn "$repo/agents/AGENTS.md" "$target"
    echo "linked $target"
  fi
done

# Codex: no statusLine hook, so Stop/PostToolUse hooks rebuild the same line from
# the session rollout. hooks.json is shared with herdr and caveman, so merge the
# entry in (idempotent) rather than linking the file. Every ~/.codex* home (one
# per account, via CODEX_HOME) gets the hook and the hooks feature flag. Codex keeps
# a trusted hash per hook in config.toml; a new or changed entry may need approving
# in /hooks before it runs.
chmod +x "$repo/.codex/statusline-command.sh"
ln -sfn "$repo/.codex/statusline-command.sh" "$HOME/.codex/statusline-command.sh"
cmd="$HOME/.codex/statusline-command.sh"
pane_name="$HOME/.claude/hooks/herdr-pane-name.sh"
for home in "$HOME"/.codex*/; do
  home=${home%/}
  [ -f "$home/config.toml" ] || continue
  hooks="$home/hooks.json"
  [ -f "$hooks" ] || echo '{"hooks":{}}' > "$hooks"
  jq --arg cmd "$cmd" '
    reduce ("Stop", "PostToolUse") as $event (.;
      if any(.hooks[$event][]?.hooks[]?; .command == $cmd) then .
      else .hooks[$event] += [{hooks: [{type: "command", command: $cmd, timeout: 5}]}] end)
  ' "$hooks" > "$hooks.tmp" && mv "$hooks.tmp" "$hooks"
  jq --arg cmd "$pane_name codex" '
    if any(.hooks.SessionStart[]?.hooks[]?; .command == $cmd) then .
    else .hooks.SessionStart += [{matcher: "startup|resume|clear|compact", hooks: [{type: "command", command: $cmd, timeout: 10}]}] end
  ' "$hooks" > "$hooks.tmp" && mv "$hooks.tmp" "$hooks"
  # Work + personal Codex: one account lives in ~/.codex, the other in e.g.
  # ~/.codex-personal (launched with CODEX_HOME). `herdr integration install codex`
  # only wires ~/.codex, so a second home gets a copy of its state hook here;
  # without it Herdr still sees the agent but never gets its session id.
  # Re-run install after `herdr integration install codex` to refresh the copy.
  herdr_state="$HOME/.codex/herdr-agent-state.sh"
  if [ "$home" != "$HOME/.codex" ] && [ -f "$herdr_state" ]; then
    cp "$herdr_state" "$home/herdr-agent-state.sh"
    jq --arg cmd "bash '$home/herdr-agent-state.sh' session" '
      if any(.hooks.SessionStart[]?.hooks[]?; .command == $cmd) then .
      else .hooks.SessionStart = [{hooks: [{type: "command", command: $cmd, timeout: 10}]}] + (.hooks.SessionStart // []) end
    ' "$hooks" > "$hooks.tmp" && mv "$hooks.tmp" "$hooks"
    echo "copied herdr-agent-state.sh into $home (SessionStart)"
  fi
  if ! grep -q '^\[features\]' "$home/config.toml"; then
    printf '\n[features]\nhooks = true\n' >> "$home/config.toml"
  elif ! grep -q '^hooks = true' "$home/config.toml"; then
    echo "warning: add 'hooks = true' under [features] in $home/config.toml"
  fi
  # Codex's own footer: the hook above only feeds tmux, so outside tmux (Herdr)
  # this is the line you see. An existing status_line is left as it is.
  status_line='status_line = ["model-with-reasoning", "used-tokens", "context-window-size", "five-hour-limit", "weekly-limit"]'
  if ! grep -q '^status_line' "$home/config.toml"; then
    if grep -q '^\[tui\]' "$home/config.toml"; then
      awk -v line="$status_line" '{ print } /^\[tui\]$/ { print line }' "$home/config.toml" > "$home/config.toml.tmp" \
        && mv "$home/config.toml.tmp" "$home/config.toml"
    else
      printf '\n[tui]\n%s\n' "$status_line" >> "$home/config.toml"
    fi
    echo "added the Codex status_line to $home/config.toml"
  fi
  echo "hooked $cmd (Stop + PostToolUse) and herdr-pane-name.sh (SessionStart) in $hooks"
done

# Grok loads every file in ~/.grok/hooks/, and herdr owns herdr.json there, so the
# Herdr pane/agent naming hook gets a file of its own.
if [ -d "$HOME/.grok" ]; then
  mkdir -p "$HOME/.grok/hooks"
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s grok","timeout":10}]}]}}\n' "$pane_name" > "$HOME/.grok/hooks/pane-name.json"
  echo "wrote ~/.grok/hooks/pane-name.json"
  # Grok's status line takes a command (off by default). An existing
  # [ui.status_line] is left as it is.
  chmod +x "$repo/.grok/statusline-command.sh"
  ln -sfn "$repo/.grok/statusline-command.sh" "$HOME/.grok/statusline-command.sh"
  if ! grep -q '^\[ui\.status_line\]' "$HOME/.grok/config.toml" 2>/dev/null; then
    printf '\n[ui.status_line]\ntype = "command"\ncommand = "~/.grok/statusline-command.sh"\n' >> "$HOME/.grok/config.toml"
    echo "added the Grok status_line to ~/.grok/config.toml"
  fi
fi

# Agent skills shared by Claude Code (~/.claude/skills) and Codex/Copilot/Gemini
# (~/.agents/skills). Per-skill dir links, so vault-linked skills coexist. An
# existing real directory is skipped — ln -sfn would nest the link inside it.
for d in "$repo"/agents/skills/*/; do
  name="$(basename "$d")"
  for target in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    mkdir -p "$target"
    if [ -d "$target/$name" ] && [ ! -L "$target/$name" ]; then
      echo "skipped $target/$name (existing directory — move it aside first)"
    else
      ln -sfn "${d%/}" "$target/$name"
      echo "linked $target/$name"
    fi
  done
done

# Per-project skills (sandboxed agents, repos that commit their skills).
# agents/skills-copy.local is gitignored: one target dir per line, ~ allowed,
# # comments. A plain line means copies: a symlinked skill there is replaced by
# a real copy. A line starting with "link " means symlinks: a copied skill there
# is replaced by a symlink, unless it holds files the repo skill lacks (then it
# is skipped and reported). Only skills the target already has are touched;
# SKILLS_COPY_ADD=1 also adds the repo skills it lacks. No skill is ever removed.
copy_list="$repo/agents/skills-copy.local"
resolve() { (cd "$1" 2>/dev/null && pwd -P); }
protected=" $(resolve "$HOME/.claude/skills") $(resolve "$HOME/.agents/skills") $(resolve "$repo/agents/skills") "
if [ -f "$copy_list" ]; then
  while IFS= read -r target || [ -n "$target" ]; do
    target="${target%%#*}"; target="${target%"${target##*[![:space:]]}"}"
    target="${target#"${target%%[![:space:]]*}"}"
    [ -n "$target" ] || continue
    mode=copy
    case "$target" in
      link[[:space:]]*) mode=link; target="${target#link}"; target="${target#"${target%%[![:space:]]*}"}" ;;
    esac
    target="${target/#\~/$HOME}"
    case "$target" in /*) ;; *) echo "skipped $target (relative path)"; continue ;; esac
    [ -d "$target" ] || { echo "skipped $target (no such directory)"; continue; }
    # Resolved, so a project dir that is itself a symlink to one of these is caught:
    # writing there would replace the global links or the repo's own skills.
    case "$protected" in
      *" $(resolve "$target") "*) echo "skipped $target (resolves to a global skills dir or the repo)"; continue ;;
    esac
    updated=0; added=0; kept=""
    for d in "$repo"/agents/skills/*/; do
      name="$(basename "$d")"; src="${d%/}"; dst="$target/$name"
      if [ -d "$dst" ]; then
        updated=$((updated + 1))
      elif [ "${SKILLS_COPY_ADD:-0}" = 1 ]; then
        added=$((added + 1))
      else
        continue
      fi
      if [ "$mode" = copy ]; then
        [ -L "$dst" ] && rm "$dst"
        rsync -a "$d" "$dst/"
      # diff exits 1 on any difference; under pipefail that would hide grep's match.
      elif [ -d "$dst" ] && [ ! -L "$dst" ] && { diff -rq "$src" "$dst" || true; } | grep -qF "Only in $dst"; then
        kept="$kept $name"; updated=$((updated - 1))
      else
        { [ -d "$dst" ] && [ ! -L "$dst" ] && rm -rf "$dst"; } || true
        ln -sfn "$src" "$dst"
      fi
    done
    echo "$mode: updated $updated, added $added skills in $target"
    [ -z "$kept" ] || echo "  kept as copies (they hold files the repo lacks):$kept"
  done < "$copy_list"
fi

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

# Obsidian keeps hotkeys per vault, in <vault>/.obsidian/hotkeys.json. Merged, not
# linked: a symlink target outside the vault breaks on other machines and under
# MEGA sync. The repo's commands win; commands bound only in the vault are kept.
# Vaults come from Obsidian's own registry, so re-run after adding one.
obsidian_registry="$HOME/Library/Application Support/obsidian/obsidian.json"
if [ -f "$obsidian_registry" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; [print(v["path"]) for v in json.load(open(sys.argv[1]))["vaults"].values()]' "$obsidian_registry" |
  while IFS= read -r vault; do
    [ -d "$vault/.obsidian" ] || continue
    python3 -c '
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
merged = json.load(open(dst)) if os.path.exists(dst) else {}
merged.update(json.load(open(src)))
with open(dst, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
' "$repo/obsidian/hotkeys.json" "$vault/.obsidian/hotkeys.json"
    echo "merged hotkeys.json into $vault"
  done
else
  echo "skipped Obsidian hotkeys (no vault registry or python3)"
fi

# Copied, not linked: colima rewrites its config on `colima start --<flag>`,
# which would replace a symlink. An existing config is never overwritten.
colima_conf="$HOME/.colima/default/colima.yaml"
if [ -e "$colima_conf" ]; then
  echo "skipped $colima_conf (exists)"
else
  mkdir -p "$(dirname "$colima_conf")"
  cp "$repo/colima/colima.yaml" "$colima_conf"
  echo "copied $colima_conf"
fi

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  echo "installed TPM"
fi

echo
echo "done — inside tmux: prefix + I to install plugins, prefix + r to reload"
