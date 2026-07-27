#!/usr/bin/env bash
# Send a notification that an agent wants attention. Called by notify-ready.sh
# once it has decided you are NOT looking at the agent's window — that gate
# lives there, this script only delivers.
#
# Usage: notify-push.sh <title> <message> <dedupe-key>
#
# Delivery (all optional, all independent):
#   - local macOS banner  — on by default, zero config (osascript)
#   - ntfy                — set NTFY_TOPIC (and optionally NTFY_SERVER)
#   - Pushover            — set PUSHOVER_TOKEN + PUSHOVER_USER
#
# Config lives in ~/.claude/notify.conf (untracked, machine-local):
#   NTFY_TOPIC=my-agents
#   NOTIFY_LOCAL=0          # disable the macOS banner
#   NOTIFY_DEBOUNCE=60      # seconds; per dedupe-key
# With no config the local banner still fires and the remote senders no-op.
#
# Never blocks: every curl is bounded by --max-time, so a dead network cannot
# hang Claude's Stop hook.

title="${1:-agent}"
message="${2:-ready}"
key="${3:-default}"

CONF="${NOTIFY_CONF:-$HOME/.claude/notify.conf}"
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

: "${NOTIFY_LOCAL:=1}"
: "${NOTIFY_DEBOUNCE:=60}"
: "${NTFY_SERVER:=https://ntfy.sh}"
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

if [ "$NOTIFY_LOCAL" = 1 ] && command -v osascript >/dev/null 2>&1; then
  # Quote-escape for AppleScript string literals.
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  osascript -e "display notification \"$(esc "$message")\" with title \"$(esc "$title")\"" \
    >/dev/null 2>&1 || true
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
