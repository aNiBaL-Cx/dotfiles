#!/usr/bin/env bash
# Grok status line ([ui.status_line] command in ~/.grok/config.toml). Grok sends
# Claude-shaped JSON, but its live window is context_window.context_tokens, not
# current_usage; map it and reuse the Claude formatter, which also writes the
# /tmp/agent-statusline-<pane> file for tmux. Grok sends no rate limits.
jq -c '.context_window.current_usage = (.context_window.context_tokens // null
  | if . then {input_tokens: ., cache_creation_input_tokens: 0, cache_read_input_tokens: 0} else null end)' \
  | "$HOME/.claude/statusline-command.sh"
