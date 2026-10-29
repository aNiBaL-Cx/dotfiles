#!/usr/bin/env bash
# Codex hook (Stop + PostToolUse in ~/.codex/hooks.json). Codex has no
# statusLine hook, so this reads the session rollout named by the hook's
# transcript_path, reshapes its latest turn_context/token_count events into the
# JSON Claude Code sends, and pipes it through ~/.claude/statusline-command.sh —
# one formatter, one /tmp/agent-statusline-<pane> file for tmux.
input=$(cat)
[ -n "$TMUX_PANE" ] || exit 0  # Codex draws its own footer outside tmux
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[ -f "$transcript" ] || exit 0

turn=$(grep '"type":"turn_context"' "$transcript" | tail -1)
tokens=$(grep '"type":"token_count"' "$transcript" | tail -1)
[ -n "$tokens" ] || exit 0

# Rate limits: primary/secondary are null on some plans; match by window size.
jq -n --argjson turn "${turn:-null}" --argjson tokens "$tokens" '
  $tokens.payload.info as $info
  | [$tokens.payload.rate_limits.primary, $tokens.payload.rate_limits.secondary | select(. != null)] as $limits
  | def used($minutes): [$limits[] | select(.window_minutes == $minutes) | .used_percent] | first;
  {
    model: {display_name: ($turn.payload.model // "codex")},
    context_window: {used_percentage: (if $info then $info.last_token_usage.total_tokens * 100 / $info.model_context_window else 0 end)},
    rate_limits: {five_hour: {used_percentage: used(300)}, seven_day: {used_percentage: used(10080)}}
  }' | "$HOME/.claude/statusline-command.sh" >/dev/null
