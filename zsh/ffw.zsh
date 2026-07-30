# ffw — pick a git worktree from any repo under a root and cd into it.
#
# Terminal-only counterpart to the tmux `prefix + w` popup
# (tmux/scripts/worktrees.sh): same inventory, no pane handling, so it works in
# editors and terminals that aren't tmux.
#
# Root of repos: $WORKTREE_ROOT if set, else $FF_ROOT.
#
# Any args become the initial filter, matched against the worktree PATH (repo
# name included, relative to the root) and its BRANCH. Multiple words are ANDed.
# One match cds straight in; several open the selector; none exits quietly.
#   ffw                     # selector over everything
#   ffw 1400                # matches path or branch
#   ffw 1397 marionette     # narrow by repo
#   ffw feat/SQ2            # matches the branch side
#
# Primary master/main checkouts are skipped — this is for jumping between
# feature worktrees.
ffw() {
  # NB: never name a variable `path` here — zsh ties it to $PATH.
  local base="${WORKTREE_ROOT:-$FF_ROOT}" repo wt br rel sel line
  local -a items          # "relpath<TAB>branch<TAB>abspath", one per worktree
  local -i w=0

  [[ -n "$base" ]] || { echo "ffw: set \$WORKTREE_ROOT or \$FF_ROOT"; return 1 }

  for repo in "$base"/*/; do
    [[ -d "$repo/.git" ]] || continue
    repo="${repo%/}"
    while IFS=$'\t' read -r wt br; do
      [[ -n "$wt" ]] || continue
      rel="${wt#$base/}"
      (( ${#rel} > w )) && w=${#rel}
      items+=("$rel	$br	$wt")
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
        /^worktree /  { p = substr($0, 10); b = "" }
        /^branch /    { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
        /^detached$/  { b = "(detached)" }
        /^$/          { emit() }
        END           { emit() }
        function emit() {
          if (p == "") return
          if (b == "master" || b == "main") { p = ""; b = ""; return }
          printf "%s\t%s\n", p, b
          p = ""; b = ""
        }')
  done

  (( ${#items} )) || { echo "no worktrees under $base"; return 1 }

  # fzf matches on what it DISPLAYS, so path and branch both go in the visible
  # column; the absolute path rides along hidden in field 2 for the cd.
  local -a rows
  for line in ${(o)items}; do
    rows+=("${(r:$w:)${line%%	*}}  ${${line#*	}%%	*}	${line##*	}")
  done

  sel=$(print -l $rows |
        fzf --delimiter=$'\t' --with-nth=1 --prompt='worktree > ' \
            --height=60% --reverse --query="$*" --select-1 --exit-0 |
        cut -f2)
  [[ -n "$sel" ]] || return 0

  cd "$sel"
}
