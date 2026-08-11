# wt / wtedit — jump into, or open in an editor, git worktrees from any repo
# under a root.
#
# Terminal-only counterpart to the tmux `prefix + w` popup
# (tmux/scripts/worktrees.sh): same inventory, no pane handling, so it works in
# editors and terminals that aren't tmux.
#
# Root of repos, in order: the parent of the current repo's primary checkout (so
# sibling repos are in scope from inside a worktree), else the current
# directory. $WORKTREE_ROOT is a last resort, used only when that guess holds no
# repos — running from $HOME, say.
#
# Primary master/main checkouts are skipped throughout: this is for moving
# between feature worktrees.

# Resolve the root, or fail with a message naming the caller ($1).
_wt_root() {
  local me="${1:-wt}" common base

  # --git-common-dir is the PRIMARY checkout's .git even from inside a linked
  # worktree, so two :h's land on the folder that holds the repos.
  common=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ -n "$common" ]]; then
    [[ "$common" == /* ]] || common="$PWD/$common"
    base="${common:A:h:h}"
  else
    base="$PWD"
  fi

  # Direct children with a .git DIRECTORY are primary checkouts; a linked
  # worktree has a .git file, and its worktrees belong to its own repo's list.
  local -a repos=("$base"/*/.git(N/:h))
  if (( ! ${#repos} )) && [[ -n "$WORKTREE_ROOT" && "$WORKTREE_ROOT" != "$base" ]]; then
    base="$WORKTREE_ROOT"
    repos=("$base"/*/.git(N/:h))
  fi
  if (( ! ${#repos} )); then
    print -u2 "$me: no git repos in $base"
    [[ -n "$WORKTREE_ROOT" ]] || print -u2 "$me: set \$WORKTREE_ROOT to a folder of repos to search from anywhere"
    return 1
  fi

  print -r -- "$base"
}

# Every worktree under $1, one "relpath<TAB>branch<TAB>abspath" line each.
_wt_inventory() {
  local base="$1" repo tree br
  for repo in "$base"/*/.git(N/:h); do
    while IFS=$'\t' read -r tree br; do
      [[ -n "$tree" ]] || continue
      print -r -- "${tree#$base/}	$br	$tree"
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
}

# Inventory lines (as args) -> fzf rows. fzf matches on what it DISPLAYS, so
# path and branch both go in the visible column, padded into two; the absolute
# path rides along hidden in field 2.
_wt_rows() {
  local line
  local -i w=0
  for line in "$@"; do
    (( ${#${line%%	*}} > w )) && w=${#${line%%	*}}
  done
  for line in ${(o)@}; do
    print -r -- "${(r:$w:)${line%%	*}}  ${${line#*	}%%	*}	${line##*	}"
  done
}

# wt — pick a worktree and cd into it.
#
# Any args become the initial filter, matched against the worktree PATH (repo
# name included, relative to the root) and its BRANCH. Multiple words are ANDed.
# One match cds straight in; several open the selector; none exits quietly.
#   wt                     # selector over everything
#   wt 1400                # matches path or branch
#   wt 1397 marionette     # narrow by repo
#   wt feat/SQ2            # matches the branch side
wt() {
  # NB: never name a variable `path` here — zsh ties it to $PATH.
  local base sel
  base=$(_wt_root "$0") || return 1

  local -a items=(${(f)"$(_wt_inventory "$base")"})
  (( ${#items} )) || { print -u2 "wt: no worktrees under $base"; return 1 }

  sel=$(_wt_rows "${items[@]}" |
        fzf -i --delimiter=$'\t' --with-nth=1 --prompt='worktree > ' \
            --height=60% --reverse --query="$*" --select-1 --exit-0 |
        cut -f2)
  [[ -n "$sel" ]] || return 0

  cd "$sel"
}

# wtedit — open worktrees in ONE editor window.
#
# Same matching as `wt` (path + branch, words ANDed, case-insensitive), but
# every match opens instead of one being picked: a ticket that spans backend and
# two frontends lands in a single multi-root window.
#   wtedit SQ2-1095        # every repo's SQ2-1095 worktree
#   wtedit 1397 react      # narrow by repo
#   wtedit                 # selector, TAB to multi-select
#
# Editor: $WT_EDITOR, else $VISUAL, else $EDITOR. Flags are allowed
# (WT_EDITOR="cursor --profile work").
wtedit() {
  local ed="${WT_EDITOR:-${VISUAL:-$EDITOR}}" base line key
  [[ -n "$ed" ]] || { print -u2 "wtedit: set \$WT_EDITOR (or \$VISUAL/\$EDITOR)"; return 1 }

  base=$(_wt_root "$0") || return 1

  local -a items=(${(f)"$(_wt_inventory "$base")"})
  (( ${#items} )) || { print -u2 "wtedit: no worktrees under $base"; return 1 }

  local -a hits keep
  if (( $# )); then
    # Filter on path + branch only — the hidden abspath field shares the root
    # with every other line, so matching it would match everything.
    hits=("${items[@]}")
    local word
    for word in "$@"; do
      keep=()
      for line in "${hits[@]}"; do
        key="${line%	*}"
        [[ "${(L)key}" == *"${(L)word}"* ]] && keep+=("$line")
      done
      hits=("${keep[@]}")
    done
    (( ${#hits} )) || { print -u2 "wtedit: no worktrees matching '$*' under $base"; return 1 }
  else
    hits=(${(f)"$(_wt_rows "${items[@]}" |
          fzf -i --delimiter=$'\t' --with-nth=1 --multi \
              --prompt='edit worktrees > ' --height=60% --reverse)"})
    (( ${#hits} )) || return 0
  fi

  # Both branches carry the absolute path in the last tab-separated field.
  local -a folders
  for line in "${hits[@]}"; do folders+=("${line##*	}"); done

  print -r -- "wtedit: opening ${#folders} worktree(s):"
  for line in "${folders[@]}"; do print -r -- "  ${line#$base/}"; done

  # Each editor takes multiple folders differently.
  local -a cmd=(${=ed})
  case "${cmd[1]:t}" in
    code|cursor|vscode|windsurf)
      # VS Code family: open the first, --add the rest into the same window.
      if (( ${#folders} > 1 )); then
        "${cmd[@]}" "${folders[1]}" --add "${folders[@]:1}"
      else
        "${cmd[@]}" "${folders[1]}"
      fi
      ;;
    vim|nvim|vi)
      # No multi-root project in a terminal editor: one tab per folder.
      "${cmd[@]}" -p "${folders[@]}"
      ;;
    *)
      # Zed and anything else that takes space-separated paths in one window.
      "${cmd[@]}" "${folders[@]}"
      ;;
  esac
}
