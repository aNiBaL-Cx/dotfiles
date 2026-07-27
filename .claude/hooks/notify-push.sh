#!/usr/bin/env bash
# Send a notification that an agent wants attention. Called by notify-ready.sh
# once it has decided you are NOT looking at the agent's window — that gate
# lives there, this script only delivers.
#
# Usage: notify-push.sh <title> <message> <dedupe-key> [tmux-target]
#
# With a tmux target (session:window), CLICKING the banner jumps to that agent's
# window and foregrounds the terminal, via tmux-agent-jump.
#
# Delivery (all optional, all independent):
#   - local macOS banner  — on by default, zero config
#   - ntfy                — set NTFY_TOPIC (and optionally NTFY_SERVER)
#   - Pushover            — set PUSHOVER_TOKEN + PUSHOVER_USER
#
# The banner prefers terminal-notifier: it can set the click action (-execute)
# and supersede its own previous banner for the same pane (-group). osascript is
# the fallback and can do neither — macOS attributes its notifications to Script
# Editor, so clicking one opens Script Editor / a Finder window. That is why
# terminal-notifier is preferred, not a nicety.
#
# Deliberately NOT using -sender (which would show the terminal's icon): that
# code path never returns, leaving a resident process and a stalled hook.
#
# Config lives in ~/.claude/notify.conf (untracked, machine-local):
#   NTFY_TOPIC=my-agents
#   NOTIFY_LOCAL=0          # disable the macOS banner
#   NOTIFY_DEBOUNCE=60      # seconds; per dedupe-key
#   NOTIFY_TERMINAL_APP=com.mitchellh.ghostty
# With no config the local banner still fires and the remote senders no-op.
#
# Never blocks: every curl is bounded by --max-time, so a dead network cannot
# hang Claude's Stop hook.

title="${1:-agent}"
message="${2:-ready}"
key="${3:-default}"
tmux_target="${4:-}"

CONF="${NOTIFY_CONF:-$HOME/.claude/notify.conf}"
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

: "${NOTIFY_LOCAL:=1}"
: "${NOTIFY_DEBOUNCE:=60}"
: "${NTFY_SERVER:=https://ntfy.sh}"
# Which terminal the banner impersonates and foregrounds on click. Bundle id (has
# a dot) or app name. TERM_PROGRAM is just "tmux" inside a session, so this can't
# be auto-detected.
: "${NOTIFY_TERMINAL_APP:=com.mitchellh.ghostty}"
STATE_DIR="${NOTIFY_STATE_DIR:-${TMPDIR:-/tmp}}"

# Debounce per key: an agent that stops three times for permission while you are
# away should not send three notifications.
stamp="$STATE_DIR/agent-notified-$(printf '%s' "$key" | tr -c 'A-Za-z0-9_.-' '_')"
now=$(date +%s)
if [ -f "$stamp" ]; then
  last=$(cat "$stamp" 2>/dev/null)
  case "$last" in
    ''|*[!0-9]*) last=0 ;;
  esac
  [ $((now - last)) -lt "$NOTIFY_DEBOUNCE" ] && exit 0
fi
printf '%s' "$now" > "$stamp"

if [ "$NOTIFY_LOCAL" = 1 ]; then
  notifier="${NOTIFY_NOTIFIER:-$(command -v terminal-notifier 2>/dev/null)}"
  jumper="${NOTIFY_JUMPER:-$HOME/.config/tmux/scripts/tmux-agent-jump}"

  if [ -n "$notifier" ] && [ -x "$notifier" ]; then
    # NO -sender. It makes terminal-notifier impersonate another app's bundle id,
    # and that path never returns — the process stays resident, which would hang
    # this Stop hook. -execute and -activate both return promptly on their own.
    # Cost of dropping it is cosmetic: the banner shows terminal-notifier's icon
    # instead of the terminal's.
    set -- -title "$title" -message "$message" -group "$key"
    # Click -> jump to the agent's window. Without a target (or without the
    # jumper installed) just foreground the terminal. Either way an explicit
    # click action is what stops macOS from opening Script Editor / a Finder
    # window, which is what a plain notification does.
    if [ -n "$tmux_target" ] && [ -x "$jumper" ]; then
      set -- "$@" -execute "$jumper $tmux_target $NOTIFY_TERMINAL_APP"
    else
      set -- "$@" -activate "$NOTIFY_TERMINAL_APP"
    fi
    # Backgrounded anyway: a notifier that blocks must never be able to stall the
    # hook. Nothing here depends on its exit status.
    "$notifier" "$@" >/dev/null 2>&1 &
  elif command -v osascript >/dev/null 2>&1; then
    # Fallback: no click action possible, and clicking opens Script Editor.
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    osascript -e "display notification \"$(esc "$message")\" with title \"$(esc "$title")\"" \
      >/dev/null 2>&1 || true
  fi
fi

if [ -n "${NTFY_TOPIC:-}" ]; then
  curl -fsS --max-time 3 \
    -H "Title: $title" \
    -H "Tags: robot" \
    -d "$message" \
    "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1 || true
fi

if [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ]; then
  curl -fsS --max-time 3 \
    --form-string "token=$PUSHOVER_TOKEN" \
    --form-string "user=$PUSHOVER_USER" \
    --form-string "title=$title" \
    --form-string "message=$message" \
    https://api.pushover.net/1/messages.json >/dev/null 2>&1 || true
fi

exit 0
