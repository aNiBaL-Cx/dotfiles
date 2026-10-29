#!/usr/bin/env bash
# SwiftBar plugin: my in-progress Linear tickets, their PRs, linked herdr agents
# and unread Linear/GitHub notifications. Refreshes every 2 minutes (filename).
# Linear token: ~/.linear_api_token (personal API key, chmod 600; shared with lineark).
# An agent is linked to a ticket when its workspace/tab label, cwd or title
# contains the ticket ID (e.g. SQ2-123).
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
# SwiftBar runs without LANG: cut -c would then split multibyte chars, and SwiftBar
# treats invalid UTF-8 output as empty and hides the plugin.
export LC_ALL=en_US.UTF-8
# Free text goes through clean: "|" separates SwiftBar params, and ":" becomes "∶"
# so ":word:" in a title never turns into an inline icon.
clean() { sed 's/|/¦/g; s/:/∶/g'; }
# Icons are SF Symbols (Apple's icon set, built into macOS). SwiftBar 2.1.1 draws
# sfimage as a template (always black/white), so colored icons are inline
# ":name:" symbols tinted by sfcolor (1st symbol), sfcolor1/sfcolor2 (2nd).
icon() { echo "sfimage=$1"; }

# herdr sessions to show, one per line; no file = "default" only.
# The "herdr sessions" submenu calls "$0 toggle <session>".
SESSIONS_FILE="$HOME/.config/swiftbar/linear-work-sessions"
if [ "$1" = toggle ] && [ -n "$2" ]; then
  mkdir -p "$(dirname "$SESSIONS_FILE")"
  [ -f "$SESSIONS_FILE" ] || echo default > "$SESSIONS_FILE"
  if grep -qxF "$2" "$SESSIONS_FILE"; then
    grep -vxF "$2" "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp"; mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
  else
    echo "$2" >> "$SESSIONS_FILE"
  fi
  exit 0
fi
selected_sessions=$(cat "$SESSIONS_FILE" 2>/dev/null || echo default)
running_sessions=$(herdr session list 2>/dev/null | awk 'NR > 1 && $2 == "running" { print $1 }')

TOKEN_FILE="$HOME/.linear_api_token"
if [ ! -s "$TOKEN_FILE" ]; then
  echo ":questionmark.circle:"
  echo "---"
  echo "No Linear token in ~/.linear_api_token | $(icon key)"
  echo "Create personal API key | href=https://linear.app/settings/account/security $(icon arrow.up.right.square)"
  exit 0
fi

query='{
  viewer {
    assignedIssues(first: 50, filter: { state: { type: { eq: "started" } } }) {
      nodes { identifier title url priority priorityLabel state { name }
              attachments { nodes { url } } }
    }
  }
  notifications(first: 50) {
    nodes { readAt snoozedUntilAt ... on IssueNotification { type issue { identifier title url } } }
  }
}'
linear=$(curl -s --max-time 15 https://api.linear.app/graphql \
  -H "Authorization: $(cat "$TOKEN_FILE")" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg q "$query" '{query: $q}')")
if [ -z "$linear" ] || ! jq -e '.data.viewer' >/dev/null <<<"$linear"; then
  echo ":exclamationmark.triangle:"; echo "---"; echo ":exclamationmark.triangle.fill: Linear API request failed | color=red sfcolor=red"
  jq -r '.errors[]?.message' <<<"$linear" 2>/dev/null | cut -c1-120 | clean
  [ -z "$linear" ] && echo "No response (network or timeout)"
  echo "Refresh | refresh=true $(icon arrow.clockwise)"; exit 0
fi

# "Ready/Waiting for Deploy" are started-type states but the work is done: hide them.
linear=$(jq '.data.viewer.assignedIssues.nodes |= map(select(.state.name | test("deploy"; "i") | not))' <<<"$linear")
# Keep only unread, non-snoozed issue notifications (what the Linear Inbox shows).
# snoozedUntilAt has milliseconds; strip them so it compares with `now | todate`.
linear=$(jq '.data.notifications.nodes |= map(select(.readAt == null and .issue
  and ((.snoozedUntilAt // "" | sub("\\.[0-9]+"; "")) < (now | todate))))' <<<"$linear")

# One line per agent across the selected running herdr sessions:
# session/pane_id \t status \t "searchable text" (session, labels, cwd, title).
agent_rows=$(for s in $(grep -xF -f <(echo "$selected_sessions") <<<"$running_sessions"); do
  agents=$(herdr --session "$s" agent list 2>/dev/null)
  workspaces=$(herdr --session "$s" workspace list 2>/dev/null)
  tabs=$(herdr --session "$s" tab list 2>/dev/null)
  jq -r --arg s "$s" --argjson ws "${workspaces:-null}" --argjson tb "${tabs:-null}" '
    ([$ws.result.workspaces[]? | {(.workspace_id): .label}] | add // {}) as $wl
    | ([$tb.result.tabs[]? | {(.tab_id): .label}] | add // {}) as $tl
    | .result.agents[]?
    | ["\($s)/\(.pane_id)", .agent_status,
       ([$s, $wl[.workspace_id], $tl[.tab_id], .cwd, .terminal_title_stripped, .name] | map(. // "") | join(" "))]
    | @tsv' <<<"${agents:-null}" 2>/dev/null
done)
# herdr session badge: inline cpu symbol (no robot in SF Symbols) tinted with a distinct color. The color
# follows the session's position in the full session list (stopped ones included),
# so it only shifts when sessions are created or deleted; a name hash collided too
# often. The line needs symbolize on (the default) and the color as sfcolor.
SESSION_COLORS=("#5E9EF2" "#F2994A" "#BB87FC" "#4CC9B0" "#EB5757" "#F2C94C" "#F06EAA" "#8BC34A" "#56CCF2" "#A1887F")
all_sessions=$(herdr session list 2>/dev/null | awk 'NR > 1 { print $1 }')
session_badge() { echo ":cpu: $1"; }
session_color() {
  local i; i=$(awk -v s="$1" '$0 == s { print NR - 1; exit }' <<<"$all_sessions")
  echo "${SESSION_COLORS[${i:-0} % ${#SESSION_COLORS[@]}]}"
}
# SwiftBar action that focuses an agent row's pane in its session.
focus_action() { echo "bash=$HOME/.local/bin/herdr param1=--session param2=${1%%/*} param3=agent param4=focus param5=${1#*/} terminal=false"; }

# Unread GitHub notifications, as PR html URLs, only for PRs linked to my tickets
# (the full inbox is mostly old subscribed noise).
pr_urls=$(jq -r '.data.viewer.assignedIssues.nodes[].attachments.nodes[].url
  | select(test("github.com/.+/pull/[0-9]+"))' <<<"$linear")
gh_unread=$(gh api notifications --jq '.[] | select(.subject.type == "PullRequest") | .subject.url
  | sub("api.github.com/repos"; "github.com") | sub("/pulls/"; "/pull/")' 2>/dev/null \
  | grep -xF -f <(echo "$pr_urls"))

unread_linear=$(jq '.data.notifications.nodes | length' <<<"$linear")
issues=$(jq -c '.data.viewer.assignedIssues.nodes | sort_by(if .priority == 0 then 5 else .priority end)[]' <<<"$linear")
n_issues=$(grep -c . <<<"$issues")
n_working=$(awk -F'\t' '$2 == "working"' <<<"$agent_rows" | grep -c .)
n_gh=$(grep -c . <<<"$gh_unread")

# Menu bar title: inline ":symbol:" syntax (no user text here, so symbolize is safe).
title=":square.stack.3d.up: $n_issues"
[ $((unread_linear + n_gh)) -gt 0 ] && title="$title  :bubble.left: $((unread_linear + n_gh))"
[ "$n_working" -gt 0 ] && title="$title  :cpu: $n_working"
echo "$title"
echo "---"

# "<symbol> <color>" pairs for inline icons.
prio_icon() {
  case "$1" in
    1) echo "exclamationmark.square.fill #EB5757" ;; 2) echo "arrow.up.circle.fill #F2994A" ;;
    3) echo "equal.circle.fill #F2C94C" ;;           4) echo "arrow.down.circle.fill #5E9EF2" ;;
    *) echo "minus.circle gray" ;;
  esac
}
agent_icon() {
  case "$1" in
    working) echo "bolt.circle.fill #F2C94C" ;; done) echo "checkmark.circle.fill #4CC9B0" ;;
    blocked) echo "exclamationmark.octagon.fill #EB5757" ;; *) echo "moon.zzz gray" ;;
  esac
}
# Agent line: status icon, then the session badge.
agent_line() {  # $1 session/pane  $2 status  $3 extra text
  local sym col scol; read -r sym col <<<"$(agent_icon "$2")"; scol=$(session_color "${1%%/*}")
  echo "--:$sym: $(session_badge "${1%%/*}")  $(clean <<<"${1#*/}") · $2$3 | sfcolor=$col sfcolor1=$scol sfcolor2=$scol $(focus_action "$1")"
}

# CI rollup: failing (any failure), running (any pending), passing (all passed), "" no checks.
ci_state() {
  jq -r '[.statusCheckRollup[]? | (.conclusion // .state // "") | ascii_upcase] as $c
    | if ($c | length) == 0 then ""
      elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT" or . == "ACTION_REQUIRED") then "failing"
      elif any($c[]; . == "" or . == "PENDING" or . == "EXPECTED") then "running"
      else "passing" end'
}

matched_panes=""
while IFS= read -r issue; do
  [ -z "$issue" ] && continue
  id=$(jq -r .identifier <<<"$issue")
  read -r psym pcol <<<"$(prio_icon "$(jq -r .priority <<<"$issue")")"
  echo ":$psym: $id · $(jq -r .state.name <<<"$issue" | clean) — $(jq -r .title <<<"$issue" | clean) | href=$(jq -r .url <<<"$issue") sfcolor=$pcol"
  echo "--$(jq -r '.priorityLabel' <<<"$issue") · open in Linear | href=$(jq -r .url <<<"$issue") $(icon arrow.up.right.square)"

  for pr_url in $(jq -r '.attachments.nodes[].url | select(test("github.com/.+/pull/[0-9]+"))' <<<"$issue"); do
    pr=$(gh pr view "$pr_url" --json number,state,isDraft,reviewDecision,statusCheckRollup 2>/dev/null) || continue
    review=$(jq -r 'if .state == "MERGED" then "merged" elif .state == "CLOSED" then "closed"
      elif .isDraft then "draft" else ({APPROVED: "approved", CHANGES_REQUESTED: "changes requested",
      REVIEW_REQUIRED: "review pending"}[.reviewDecision // ""] // "no review") end' <<<"$pr")
    repo=$(sed -E 's#https://github.com/[^/]+/([^/]+)/pull/.*#\1#' <<<"$pr_url")
    ci=$(ci_state <<<"$pr"); new=""
    grep -qxF "$pr_url" <<<"$gh_unread" && new=" · new activity"
    # Icon color = the state that needs you most (order matters; see PR_LEGEND).
    case "$review/$ci" in
      merged/*) color="#A371F7" ;; closed/*|draft/*) color=gray ;;
      */failing) color="#EB5757" ;; "changes requested"/*) color="#F2994A" ;;
      approved/passing|approved/) color="#4CC9B0" ;; *) color="#F2C94C" ;;
    esac
    echo "--:arrow.triangle.pull: $repo#$(jq -r .number <<<"$pr") · $review${ci:+ · CI $ci}$new | href=$pr_url sfcolor=$color"
  done

  while IFS=$'\t' read -r pane status _; do
    [ -z "$pane" ] && continue
    matched_panes="$matched_panes $pane "
    agent_line "$pane" "$status"
  # Full ID (SQ2-2267) anywhere, or the bare number as its own word: tabs-sync
  # names tabs "🚀 2267 Title". "Almeida-2267" does not count.
  done < <(awk -F'\t' -v id="$id" -v num="${id##*-}" \
    'toupper($3) ~ (id "([^0-9]|$)") || $3 ~ ("(^|[ /])" num "([^0-9]|$)")' <<<"$agent_rows")
done <<<"$issues"

other_agents=$(awk -F'\t' -v m="$matched_panes" 'NF && !index(m, " " $1 " ")' <<<"$agent_rows")
if [ -n "$other_agents" ]; then
  echo "---"
  echo "Other agents ($(grep -c . <<<"$other_agents")) | refresh=true $(icon cpu)"  # actionless headers render greyed out
  while IFS=$'\t' read -r pane status text; do
    agent_line "$pane" "$status" " — $(cut -c1-50 <<<"${text#"${pane%%/*} "}" | clean)"
  done <<<"$other_agents"
fi

if [ $((unread_linear + n_gh)) -gt 0 ]; then
  echo "---"
  echo "Unread | refresh=true $(icon tray.fill)"
  jq -r '.data.notifications.nodes[]
    | ":bubble.left.fill: \(.issue.identifier) · \(.type) — \(.issue.title | gsub("\\|"; "¦") | gsub(":"; "∶")) | href=\(.issue.url) sfcolor=#5E6AD2"' <<<"$linear"
  while IFS= read -r url; do
    [ -n "$url" ] && echo "$(sed -E 's#https://github.com/[^/]+/##; s#/pull/#\##' <<<"$url") | href=$url $(icon arrow.triangle.pull)"
  done <<<"$gh_unread"
fi

echo "---"
if [ -n "$running_sessions" ]; then
  echo "herdr sessions | refresh=true $(icon rectangle.stack)"
  for s in $running_sessions; do
    checked=false; grep -qxF "$s" <<<"$selected_sessions" && checked=true
    echo "--$(session_badge "$s") | sfcolor=$(session_color "$s") checked=$checked bash=$(cd "$(dirname "$0")" && pwd)/$(basename "$0") param1=toggle param2=$s terminal=false refresh=true"
  done
fi
# Legend: built from the same helpers as the menu, so it cannot drift.
# Items get refresh=true because actionless items render greyed out.
PR_LEGEND=("#EB5757 CI failing" "#F2994A changes requested" "#F2C94C review pending / CI running"
  "#4CC9B0 approved, CI passing" "#A371F7 merged" "gray draft / closed")
echo "Legend | refresh=true $(icon info.circle)"
echo "--Priority"
PRIO_LABELS=("No priority" Urgent High Medium Low)  # index = Linear priority
for p in 1 2 3 4 0; do
  read -r sym col <<<"$(prio_icon "$p")"
  echo "--:$sym: ${PRIO_LABELS[$p]} | sfcolor=$col refresh=true"
done
echo "-----"
echo "--Pull request (worst state wins)"
for entry in "${PR_LEGEND[@]}"; do
  echo "--:arrow.triangle.pull: ${entry#* } | sfcolor=${entry%% *} refresh=true"
done
echo "-----"
echo "--Agent"
for st in working done blocked idle; do
  read -r sym col <<<"$(agent_icon "$st")"
  echo "--:$sym: $st | sfcolor=$col refresh=true"
done
echo "-----"
echo "--herdr session"
for s in $all_sessions; do echo "--$(session_badge "$s") | sfcolor=$(session_color "$s") refresh=true"; done
echo "-----"
echo "--Menu bar"
echo "--:square.stack.3d.up: tickets in progress | refresh=true"
echo "--:bubble.left: unread Linear + GitHub on my PRs | refresh=true"
echo "--:cpu: agents working | refresh=true"
echo "Refresh | refresh=true $(icon arrow.clockwise)"
