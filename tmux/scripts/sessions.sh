#!/usr/bin/env bash
# Session switcher: fzf list of sessions, most recently active first.
#
#   enter   switch to the session
#   ctrl-x  kill it — the list reopens, so several stale ones can go in one pass
#
# Sessions are the per-task unit (prefix w creates one session per worktree
# name, one window per repo); this is the counterpart for hopping between them.
# choose-tree (session mode `w`) stays for the full tree; this is the flat,
# type-to-filter list.
#
# The current session is marked and refuses to be killed — the popup runs
# inside it, so killing it would take the popup with it.
# Called from tmux: display-popup -E "sessions.sh"
set -uo pipefail

die() {
  printf '\n\033[31msessions: %s\033[0m\n\npress any key…' "$*" >&2
  read -rsn1 _ </dev/tty 2>/dev/null || true
  exit 1
}

command -v fzf >/dev/null 2>&1 || die "fzf not found in this popup's PATH.
PATH=$PATH"

tab=$'\t'
cur="$(tmux display-message -p '#{session_name}')"

while :; do
  # activity first for the sort, then dropped; marker column shows current/attached.
  list="$(
    tmux list-sessions -F "#{session_activity}${tab}#{session_name}${tab}#{session_windows}w${tab}#{?session_attached,attached,}${tab}#{session_path}" 2>/dev/null \
      | sort -rn \
      | cut -f2-
  )"
  [ -n "$list" ] || die "no sessions"

  out="$(
    printf '%s\n' "$list" \
      | awk -F"$tab" -v t="$tab" -v cur="$cur" \
            '{ mark = ($1 == cur ? "*" : " "); print mark $1 t $2 t $3 t $4 }' \
      | fzf --delimiter="$tab" --with-nth=1,2,3,4 \
            --prompt='session > ' --height=100% --reverse --no-sort \
            --expect=ctrl-x \
            --header='enter switch · ctrl-x kill'
  )"

  key="$(printf '%s\n' "$out" | sed -n 1p)"
  sel="$(printf '%s\n' "$out" | sed -n 2p | cut -f1)"
  [ -n "$sel" ] || exit 0
  name="${sel# }"; name="${name#\*}"

  if [ "$key" = "ctrl-x" ]; then
    if [ "$name" = "$cur" ]; then
      printf '\n\033[33mwon'"'"'t kill "%s" — this popup is running in it\033[0m\n' "$name" >&2
      sleep 1
      continue
    fi
    tmux kill-session -t "=$name" 2>/dev/null
    continue
  fi

  tmux switch-client -t "=$name"
  exit 0
done
