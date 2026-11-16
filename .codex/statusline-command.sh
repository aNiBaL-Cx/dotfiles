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
  | def limit($minutes): [$limits[] | select(.window_minutes == $minutes)] | first
      | {used_percentage: .used_percent?, resets_at: .resets_at?};
  {
    model: {display_name: ($turn.payload.model // "codex")},
    context_window: (if $info then {
      used_percentage: ($info.last_token_usage.total_tokens * 100 / $info.model_context_window),
      context_window_size: $info.model_context_window,
      current_usage: {input_tokens: $info.last_token_usage.total_tokens, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
    } else {used_percentage: 0} end),
    rate_limits: {five_hour: limit(300), seven_day: limit(10080)}
  }' | "$HOME/.claude/statusline-command.sh" >/dev/null
