#!/usr/bin/env bash
# Tests for chrome-tab-groups. Every case runs against a fixture LevelDB built
# by fixture.mjs — never a real Chrome profile. pgrep is stubbed on PATH so the
# "is Chrome running" gate is controlled rather than depending on whether the
# machine happens to have Chrome open.
#
# Run: chrome/tests/chrome-tab-groups.test.sh

here="$(cd "$(dirname "$0")" && pwd)"
CLI="$here/../chrome-tab-groups"
NODE="${CHROME_TAB_GROUPS_NODE:-$(command -v node)}"

[ -n "$NODE" ] || { echo "no node found"; exit 1; }
[ -d "$here/../node_modules/classic-level" ] || {
  echo "dependencies missing — run: npm install --prefix $here/.."; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Stub pgrep as "nothing matched", i.e. Chrome is not running. The chrome-up
# test swaps in the opposite stub.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/pgrep"
chmod +x "$TMP/bin/pgrep"
export PATH="$TMP/bin:$PATH"

pass=0; fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s (%s)\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %s: expected %s got %s\n' "$1" "$2" "$3"; fi
}

fresh() { # -> path to a brand new fixture db
  local db="$TMP/db-$RANDOM$RANDOM"
  "$NODE" "$here/fixture.mjs" "$db" || { echo "fixture failed"; exit 1; }
  printf '%s\n' "$db"
}

keys() { # db [prefix] -> matching key count
  # Absolute require path: node -e resolves modules against the cwd, which is
  # wherever the test was launched from, not the chrome/ directory.
  "$NODE" -e '
    const { ClassicLevel } = require(process.argv[3])
    const db = new ClassicLevel(process.argv[1], { createIfMissing: false })
    db.open().then(async () => {
      let n = 0
      for await (const k of db.keys()) if (k.startsWith(process.argv[2] || "")) n++
      process.stdout.write(String(n))
      await db.close()
    })
  ' "$1" "${2:-}" "$here/../node_modules/classic-level"
}

# Strip the ANSI attributes, then everything up to the "N tabs  " column, which
# leaves just the title.
titles() { # db -> sorted group titles, comma separated
  "$CLI" --db "$1" -q 2>/dev/null |
    sed -e 's/'$'\033''\[[0-9;]*m//g' -e 's/^.*tabs\{0,1\}  //' |
    LC_ALL=C sort | paste -sd, -
}

run() { "$CLI" --db "$@" >/dev/null 2>&1; echo $?; }

echo "-- usage errors"
DB=$(fresh)
check "unknown option"        1 "$(run "$DB" --frobnicate)"
check "delete without filter" 1 "$(run "$DB" --delete)"
check "two filters"           1 "$(run "$DB" SQ2 NEXT)"
check "--all with filter"     1 "$(run "$DB" --all SQ2 --delete)"
check "--profile empty"       1 "$("$CLI" --profile >/dev/null 2>&1; echo $?)"
check "missing db"            1 "$(run "$TMP/nonexistent-db")"

echo "-- chrome running gate"
chrome_up()   { printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/pgrep"; }
chrome_down() { printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/pgrep"; }

chrome_up
check "listing still works"   0 "$(run "$DB")"
check "delete blocked"        2 "$(run "$DB" SQ2 --delete)"
check "restart needs delete"  1 "$(run "$DB" SQ2 --restart)"
check "no tty, no --yes"      1 "$(run "$DB" SQ2 --delete --restart </dev/null)"
chrome_down

echo "-- --restart quits, deletes, relaunches"
DB=$(fresh)
# pgrep reports Chrome up until osascript "quits" it; open records the relaunch.
cat > "$TMP/bin/pgrep" <<EOF
#!/bin/sh
[ -f "$TMP/quit" ] && exit 1
exit 0
EOF
printf '#!/bin/sh\ntouch %s/quit\necho "$@" >> %s/osascript.log\n' "$TMP" "$TMP" > "$TMP/bin/osascript"
printf '#!/bin/sh\necho "$@" >> %s/open.log\n' "$TMP" > "$TMP/bin/open"
chmod +x "$TMP/bin/pgrep" "$TMP/bin/osascript" "$TMP/bin/open"

check "restart deletes"       0 "$(run "$DB" SQ2-13 --delete --restart --yes)"
check "asked chrome to quit"  0 "$(grep -q 'quit app' "$TMP/osascript.log"; echo $?)"
check "relaunched chrome"     0 "$(grep -q 'Google Chrome' "$TMP/open.log"; echo $?)"
check "group is gone"         "NEXT,Reviews,SQ2-1095" "$(titles "$DB")"

rm -f "$TMP/quit" "$TMP/bin/osascript" "$TMP/bin/open"
chrome_down

echo "-- listing"
DB=$(fresh)
check "lists all"             0 "$(run "$DB")"
check "no match exits 3"      3 "$(run "$DB" zzzznope)"
check "all four groups"       "NEXT,Reviews,SQ2-1095,rake SQ2-1365" "$(titles "$DB")"

echo "-- dry run changes nothing"
before=$(keys "$DB")
run "$DB" SQ2 >/dev/null
check "key count unchanged"   "$before" "$(keys "$DB")"

echo "-- substring vs regex"
DB=$(fresh)
check "substring SQ2"         2 "$("$CLI" --db "$DB" SQ2 -q 2>/dev/null | wc -l | tr -d ' ')"
check "substring case-insens" 2 "$("$CLI" --db "$DB" sq2 -q 2>/dev/null | wc -l | tr -d ' ')"
check "regex anchored"        1 "$("$CLI" --db "$DB" --regex '^SQ2' -q 2>/dev/null | wc -l | tr -d ' ')"
check "regex alternation"     2 "$("$CLI" --db "$DB" --regex 'NEXT|Reviews' -q 2>/dev/null | wc -l | tr -d ' ')"
check "bad regex errors"      1 "$(run "$DB" --regex '[')"

echo "-- delete removes the group and its tabs"
DB=$(fresh)
check "delete succeeds"       0 "$(run "$DB" SQ2-13 --delete)"
check "3 groups left"         "NEXT,Reviews,SQ2-1095" "$(titles "$DB")"
# Fixture holds 16 saved_tab_group keys: 4 group dt + 3 group md (NEXT has
# none) + 4 tab dt + 4 tab md + GlobalMetadata. Deleting rake SQ2-1365 takes
# its own pair plus a pair for each of its 2 tabs = 6.
check "tab records gone"      10 "$(keys "$DB" saved_tab_group-)"

echo "-- delete leaves other sync types alone"
for prefix in preferences- search_engines- sessions- webauthn_credential- saved_tab_group-GlobalMetadata; do
  case "$prefix" in
    preferences-) want=2 ;;
    *) want=1 ;;
  esac
  check "kept $prefix"        "$want" "$(keys "$DB" "$prefix")"
done

echo "-- backup is written and restores"
DB=$(fresh)
"$CLI" --db "$DB" --all --delete >/dev/null 2>&1
check "everything deleted"    3 "$(run "$DB")"
backup=$(ls -d "$DB".backup-* 2>/dev/null | head -1)
check "backup exists"         0 "$([ -d "$backup" ]; echo $?)"
rm -rf "$DB" && mv "$backup" "$DB"
check "restored"              "NEXT,Reviews,SQ2-1095,rake SQ2-1365" "$(titles "$DB")"

echo "-- --help"
check "help exits 0"          0 "$("$CLI" --help >/dev/null 2>&1; echo $?)"
check "help mentions usage"   0 "$("$CLI" --help 2>/dev/null | grep -q 'Usage: chrome-tab-groups'; echo $?)"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
