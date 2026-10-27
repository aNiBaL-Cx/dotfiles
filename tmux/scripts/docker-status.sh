#!/usr/bin/env bash
# Docker/Colima container indicator for the tmux status bar.
#
# Prints "<icon> running/total", coloured by the worst state found:
#   green  every container up, none reporting unhealthy
#   peach  something still starting, or a container exists but is not running
#   red    a container reports (unhealthy)
#   grey   daemon unreachable (colima stopped) -> "off"
#
# One `docker ps -a` call, ~80ms. Deliberately does NOT call `colima status`
# (~540ms every refresh): a failed docker call already means the VM is down.
# Counts every container on the machine, not just one project's.

set -u

ICON=''   # nf-dev-docker (JetBrains Mono Nerd Font); swap for 🐳 if you prefer

GREEN='#a6e3a1'
PEACH='#fab387'
RED='#f38ba8'
GREY='#6c7086'

out=$(docker ps -a --format '{{.State}}|{{.Status}}' 2>/dev/null) || {
  printf '#[fg=%s]%s off#[default] ' "$GREY" "$ICON"
  exit 0
}

if [ -z "$out" ]; then
  printf '#[fg=%s]%s 0#[default] ' "$GREY" "$ICON"
  exit 0
fi

total=0
running=0
unhealthy=0
starting=0

while IFS='|' read -r state status; do
  total=$((total + 1))
  [ "$state" = running ] && running=$((running + 1))
  case $status in
    *'(unhealthy)'*) unhealthy=$((unhealthy + 1)) ;;
    *'(health: starting)'*) starting=$((starting + 1)) ;;
  esac
done <<< "$out"

if [ "$unhealthy" -gt 0 ]; then
  colour=$RED
elif [ "$starting" -gt 0 ] || [ "$running" -ne "$total" ]; then
  colour=$PEACH
else
  colour=$GREEN
fi

printf '#[fg=%s]%s %d/%d#[default] ' "$colour" "$ICON" "$running" "$total"
