#!/usr/bin/env bash
# Worktree picker across sibling repos, grouped by worktree name (e.g. a
# ticket slug reused across several repos).
#
# Two ways to open the pick:
#
#   enter   SESSION mode (default) — one session named after the worktree, one
#           window per repo in the group. Switches to it; an existing session
#           with that name is reused, never rebuilt.
#   ctrl-p  PANE mode (the original) — its worktree in the CURRENT repo is
#           opened (or the first, if the current repo isn't in the group). An
#           idle shell pane is reused (cd in place); a busy one (claude session,
#           dev server, ...) gets a new pane instead, since a cd would just type
#           into that program. If the name also exists in OTHER repos, you're
#           asked whether to open those in new panes too.
#
# Root of repos: $WORKTREE_ROOT if set, else inferred as the parent directory
# of the current repo's primary checkout (a "folder of repos" layout).
# Called from tmux: display-popup -E "worktrees.sh"
set -uo pipefail

die() {
  printf '\n\033[31mworktrees: %s\033[0m\n\npress any key…' "$*" >&2
  read -rsn1 _ </dev/tty 2>/dev/null || true
  exit 1
}

command -v fzf >/dev/null 2>&1 || die "fzf not found in this popup's PATH.
PATH=$PATH"

tab=$'\t'

src_pane="$(tmux display-message -p '#{pane_id}')"
[ -n "$src_pane" ] || die "could not determine the source pane"
src_path="$(tmux display-message -p -t "$src_pane" '#{pane_current_path}')"

# Primary repo dir of the current pane (parent of the common .git), so we can
# prefer that repo's worktree as the current-pane target.
cur_repo=""
gitdir="$(git -C "$src_path" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$gitdir" ]; then
  case "$gitdir" in /*) : ;; *) gitdir="$src_path/$gitdir" ;; esac
  cur_repo="$(cd "$gitdir/.." 2>/dev/null && pwd || true)"
fi

# Root of repos: explicit env wins; else infer from the current repo.
if [ -n "${WORKTREE_ROOT:-}" ]; then
  root="$WORKTREE_ROOT"
elif [ -n "$cur_repo" ]; then
  root="$(dirname "$cur_repo")"
else
  die "not inside a git repo and WORKTREE_ROOT is unset"
fi

# Collect every worktree across all primary repos under $root.
# Emit: name<TAB>repo<TAB>path   (skip primary master/main checkouts).
inventory="$(
  for d in "$root"/*/; do
    [ -d "$d/.git" ] || continue          # primary checkouts only
    repo="$(basename "$d")"
    git -C "$d" worktree list --porcelain 2>/dev/null | awk -v repo="$repo" -v t="$tab" '
      /^worktree /{ path = substr($0, 10) }
      /^branch /  { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
      /^detached/ { br = "(detached)" }
      /^$/        { emit() }
      END         { emit() }
      function emit(   n, a, base) {
        if (path == "") return
        if (br == "master" || br == "main") { path=""; br=""; return }
        n = split(path, a, "/"); base = a[n]
        print base t repo t path
        path=""; br=""
      }'
  done
)"

[ -n "$inventory" ] || die "no worktrees found under $root"

# Grouped picker: one row per worktree name + the repos it spans.
out="$(
  printf '%s\n' "$inventory" \
    | awk -F"$tab" '{ if (!($1 in seen)) order[++n]=$1; seen[$1]; repos[$1]=repos[$1] (repos[$1]?", ":"") $2 }
                    END { for (i=1;i<=n;i++) printf "%s\t%s\n", order[i], repos[order[i]] }' \
    | sort \
    | fzf --delimiter="$tab" --with-nth=1,2 \
          --prompt='worktree > ' --height=60% --reverse \
          --expect=ctrl-p \
          --header='enter session · ctrl-p panes'
)"
# With --expect, fzf prints the pressed key (empty line for a plain enter) first.
key="$(printf '%s\n' "$out" | sed -n 1p)"
sel="$(printf '%s\n' "$out" | sed -n 2p | cut -f1)"
[ -n "$sel" ] || exit 0

# All worktree paths for the selected name, with the repo each one belongs to
# (the repo names the window in session mode).
paths=(); wt_repos=()
while IFS="$tab" read -r r p; do
  [ -n "$p" ] || continue
  wt_repos+=("$r"); paths+=("$p")
done < <(
  printf '%s\n' "$inventory" | awk -F"$tab" -v s="$sel" '$1==s{print $2 FS $3}'
)
[ "${#paths[@]}" -gt 0 ] || die "no paths for '$sel'"

# Primary = the group member under the current repo, else the first.
primary_i=-1
if [ -n "$cur_repo" ]; then
  for i in "${!paths[@]}"; do
    case "${paths[$i]}" in "$cur_repo"/*|"$cur_repo") primary_i=$i; break ;; esac
  done
fi
[ "$primary_i" -ge 0 ] || primary_i=0
primary="${paths[$primary_i]}"

# SESSION MODE (default): the worktree name is the session, each repo a window.
# Session names can't hold "." or ":" (tmux parses them as target separators).
if [ "$key" != "ctrl-p" ]; then
  name="$(printf '%s' "$sel" | tr ':.' '--')"
  if ! tmux has-session -t "=$name" 2>/dev/null; then
    first_win="$(tmux new-session -d -s "$name" -c "$primary" -n "${wt_repos[$primary_i]}" \
                   -P -F '#{window_id}')" || die "could not create session '$name'"
    for i in "${!paths[@]}"; do
      [ "$i" -eq "$primary_i" ] && continue
      tmux new-window -t "=$name" -c "${paths[$i]}" -n "${wt_repos[$i]}"
    done
    tmux select-window -t "$first_win"
  fi
  tmux switch-client -t "=$name"
  exit 0
fi

# If the current pane is an idle shell, reuse it (cd in place). If it is busy
# (a claude session, dev server, etc.) a cd would just type into that program,
# so open the primary in a NEW pane instead.
win="$(tmux display-message -p -t "$src_pane" '#{window_id}')"
src_cmd="$(tmux display-message -p -t "$src_pane" '#{pane_current_command}')"
case "$src_cmd" in
  *sh)
    tmux send-keys -t "$src_pane" -l "cd $(printf '%q' "$primary")"
    tmux send-keys -t "$src_pane" Enter
    primary_pane="$src_pane"
    ;;
  *)
    primary_pane="$(tmux split-window -t "$src_pane" -c "$primary" -P -F '#{pane_id}')"
    ;;
esac

# The rest (other repos) -> optional new panes.
rest=()
for p in "${paths[@]}"; do [ "$p" != "$primary" ] && rest+=("$p"); done

if [ "${#rest[@]}" -gt 0 ]; then
  printf '\n"%s" also has worktrees in %d other repo(s):\n' "$sel" "${#rest[@]}"
  for p in "${rest[@]}"; do printf '  %s\n' "$p"; done
  printf '\nOpen them in new panes too? [y/N] '
  read -rsn1 ans </dev/tty 2>/dev/null || ans=""
  echo
  case "$ans" in
    y|Y)
      for p in "${rest[@]}"; do
        tmux split-window -t "$primary_pane" -c "$p"
      done
      tmux select-layout -t "$win" tiled
      ;;
  esac
fi

tmux select-pane -t "$primary_pane"
