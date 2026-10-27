---
name: pingpong
description: >
  Use when the user says pingpong, /pingpong, "ping and pong", or asks two relay panes to work through a
  list of small, well-defined, sequential tasks unattended, handing off between panes so context stays
  fresh, merging each task before the next. Requires HERDR_ENV=1 and a task source (markdown checklist, Linear,
  Jira). Not for parallel work or a dependency graph left unmerged: use multi-task.
metadata:
  short-description: Two-pane relay loop over a task list
---

# Pingpong

Two orchestrator panes, `ping` and `pong`, same agent kind and model. The kind's reset command comes from `../references/model-levels.md` (Session commands). A kind with no reset command: stop before setup. One is active and runs one task end to end. The other is standby. At task end the active pane writes the handoff, resets the standby, prompts it, and becomes standby itself. The loop ends when the task source has no open task.

**REQUIRED BACKGROUND:** `herdr --skill` (pane and agent commands, states, prompt gating). Not repeated here.

## Invocation

```
/pingpong <task source> [--merge pr|ask|local] [--profile cheap|standard|premium]
```

- Task source: a markdown file with `- [ ]` tasks, or a Linear/Jira query the project's tooling can read. Each task carries acceptance criteria. No criteria, write them into the task before starting it.
- `--merge` default `pr`. `--profile` default `standard`; passed to every `dev-team` delegation.
- `<base>` is the remote's default branch: `git fetch origin`, then `git symbolic-ref --short refs/remotes/origin/HEAD`. Fetch fails: stop and ask.
- Options persist in the handoff header. Never ask for them again mid-loop.

## Setup, first invocation only

```bash
test "${HERDR_ENV:-}" = 1 || { echo "not inside Herdr"; exit 1; }
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] || { echo "run from the main checkout"; exit 1; }
git symbolic-ref --short HEAD                           # must equal <base>, else stop
herdr agent rename "$HERDR_PANE_ID" ping                # agent name is the prompt/wait target; pane label is cosmetic
herdr pane rename "$HERDR_PANE_ID" ping
herdr agent get "$HERDR_PANE_ID"                        # kind only; no model field
herdr pane split --current --direction right --cwd "$PWD" --no-focus   # new id in .result.pane.pane_id
herdr pane rename <pane_id> pong
herdr agent start pong --kind <kind> --pane <pane_id> -- <model args>
ex="$(git rev-parse --git-common-dir)/info/exclude"; mkdir -p .handoff
for p in .handoff/ .worktrees/ .evidence/; do grep -qx "$p" "$ex" || echo "$p" >> "$ex"; done
```

`agent start` returning `agent_not_ready`: read the pane, answer the startup dialog, wait idle, then `herdr agent rename <pane_id> pong`, because a blocked startup drops the name.

Model args: `pong` runs at your level. Find your level and its args in `../references/model-levels.md` (sections "Your own level" and "Main pick"). Workers this loop starts through `dev-team` take their level from the role and the loop's `--profile`.

`herdr agent list` already shows `ping` and `pong` live: skip setup. Only one of them live: you are it; start the missing partner as above, rename included. You are the name `herdr agent list` shows for `$HERDR_PANE_ID`.

Then branch on the handoff file:

- `.handoff/pingpong.md` exists: read it and continue from `Next`.
- It does not exist: this is the first run, and that is expected, not an error. Take source, `--merge` and `--profile` from the invocation arguments, `<base>` from the remote. Write the handoff (format below) with `State: running`, `Progress: 0/<open tasks>`, `Branch: none`, `Last task: none`, and `Next` set to the first open task. Then run the first task cycle yourself. Do not prompt the partner first; it stays idle until step 7.
- It does not exist and the invocation has no task source: stop and ask for one.

## One task cycle, active pane

1. **Pick** the first open task. Read its acceptance criteria. That is the whole scope.
2. **Worktree**: `git fetch origin`, then a worktree on branch `task/<slug>` from `origin/<base>`. Slug: the task's tracker ID lowercased (`sq2-2183`) when it has one, else lowercase hyphenated words, 4 max. Use the project's worktree command when its instructions name one and it accepts a start point; otherwise `git worktree add <repo root>/.worktrees/<slug> -b task/<slug> origin/<base>`. The main checkout stays on `<base>`.
3. **Build**: in the worktree, apply the `implement-task` skill (`../implement-task/SKILL.md`) to the task, with these overrides: this loop owns status and integration, so implement-task commits on `task/<slug>`, does not update the source or tracker, and does not push. Single agent by default. Inside implement-task, split the implementation with `dev-team` when the task spans 3+ files by role; its `review` pane then replaces implement-task's reviewer subagent. Not validated (state pending or blocked): stop as below, do not integrate.
4. **Mark done** in the source before integrating. Markdown: flip `- [ ]` to `- [x]` on the task branch, same commit series. Linear/Jira: set the done status right after the merge. Under `ask`, the pane that resumes confirms the PR merged, marks done, then runs step 6 before picking the next task.
5. **Integrate** per `--merge`:
   - `pr`: open PR against base, with implement-task's evidence per criterion (criterion, proof, result) in the body, because the evidence directory goes with the worktree. Wait for CI with `gh pr checks --watch`. `no checks reported`: retry every 30s, 3 times; still none, the repo has no CI, treat as passed. Then merge the repo's way (squash unless the repo says otherwise), delete remote and local branch.
   - `ask`: open PR with the same evidence body, write its link in the handoff, stop with `State: blocked`. Do not merge. Unattended then means one task per run; the user merges and prompts `continue the pingpong loop`.
   - `local`: merge into base in the main checkout, push if base tracks a remote. Keep the evidence summary in the handoff's `Last task`.
6. **Clean up**: close every pane listed under `Workers` in the handoff with `herdr pane close <pane_id>`, whichever relay pane opened it, then set `Workers: none`. Remove the worktree, pull base in the main checkout.
7. **Hand off**: rewrite `.handoff/pingpong.md`, pass to the partner (below), print one short report (task, merge sha or PR, partner prompted), end your turn.

One task at a time. Parallel tasks belong to `multi-task`.

## Handoff file

One file, `.handoff/pingpong.md`, whole rewrite every time, hard cap 40 lines. Not committed.

```markdown
# Pingpong handoff

**Updated:** YYYY-MM-DD HH:MM by ping|pong
**Source:** docs/tasks.md | <linear/jira query>
**Base:** master   **Merge:** pr   **Profile:** standard
**Branch:** task/<slug> | none   (and its worktree path)
**Progress:** 3/6 done
**State:** running | complete | blocked: <one clause>
**Partner context:** cleared | kept: <why it still matters>
**Workers:** none | <name pane_id>, ...   (every pane the loop opened except ping and pong; add each one the moment it opens)

## Last task
<id or title>: merged <PR link or sha>, marked done.

## Next
1. <task id or title>, acceptance criteria in source
2. <concrete first step if known>

## Traps
- <uncommitted files, failing test, flaky step, repo quirk learned this task>

## Open
- <needs a human: what, since when>
```

## Pass to partner

```bash
herdr agent prompt <partner> "<reset>"        # the kind's reset command
herdr agent wait <partner> --timeout 30000
herdr agent prompt <partner> "Read .handoff/pingpong.md and continue the pingpong loop."
```

No `--wait` on the last prompt. A waiting pane shows `working` and the partner cannot prompt it back. End your turn after sending.

`agent wait` times out: `herdr agent get <partner>`. `blocked` or still `working` after one more wait, write `State: blocked: partner not idle` and stop.

On wake from that prompt: `State: complete` or `blocked`, report the handoff in the pane and stop. `State: running`, run the next task cycle.

Skip the reset only when the partner's context still matters for the next task, and record `Partner context: kept: <why>` in the handoff. Default is clear.

## Reset me

Trigger, mid-task only: the harness warns about context or compacts. Commit work in progress on the task branch, rewrite the handoff with `State: running`, the branch, and the exact next step, then:

```bash
herdr agent prompt <partner> "Reset me: herdr agent wait <my name> --timeout 60000, then the reset command, wait idle, then prompt me 'Read .handoff/pingpong.md and continue the pingpong loop.' End your turn."
```

End your turn. The partner waits for you to settle first, else the reset lands on your running turn. Then it performs the pass above, targeted at you, and goes back to standby.

## Stops

Every stop closes the `Workers` panes first, as in step 6. Their edits stay in the working tree.

- No open task left: handoff `State: complete`, report the merged list in the pane. Do not prompt the partner.
- CI red: reproduce locally on the branch. Passes locally, rerun CI once; red again, blocked. Fails locally, fix it inside the task; three failed fixes, blocked.
- `--merge ask` at merge time, an approval dialog, a precondition the repo lacks: handoff `State: blocked: <reason>`, stop. Do not route around it. Do not prompt the partner.
- The user resumes by prompting either pane with `continue the pingpong loop`.

## Rules

- Invoking `/pingpong` is the permission to commit, push, and merge under `--merge`. The loop pushes and merges; implement-task only commits. Inside `dev-team`, that overrides its commit-only-when-asked rule; its "task note" is the task's markdown entry, or `.handoff/pingpong.md` for a Linear/Jira source; step 6 closes its worker panes, overriding its leave-open rule.

- Agent name equals pane label, always both (`ping`, `pong`, and every `dev-team` worker). Target by name, never by sidebar position.
- Commit only this task's files. Preserve unrelated dirty files.
- Repo rules win where stricter: an instructions file (`CLAUDE.md`, `AGENTS.md`, rules dir) that requires human approval per merge turns `--merge pr` into `ask`.
- Close only panes listed under `Workers`, never one the loop did not open. `ping` and `pong` stay open until the user closes them.
- Reset is the default. Keep the partner warm only with a written reason.
