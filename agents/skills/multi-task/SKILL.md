---
name: multi-task
description: "Coordinate a list of development tasks: resolve precedence, start one implement-task agent per task in its own worktree, chain dependent tasks on the finished dependency's branch, and keep the state file current. The coordinator never implements or reviews code. Uses Herdr panes when HERDR_ENV=1, subagents otherwise. Use when: multi-task, implement these tasks, run this task list, /multi-task."
metadata:
  short-description: Dependency-aware fan-out of implement-task agents over worktrees
---

# Multi-task

One coordinator, one worker per task, one worktree per task. The coordinator parses the list, orders it, starts workers, tracks state, and starts dependents when their dependencies are implemented. It does not write code, review diffs, or merge.

Each worker runs the `implement-task` skill (the `SKILL.md` next to this one). Its rules apply inside the worktree.

**Announce at start:** "I'm using the multi-task skill."

## Invocation

```text
/multi-task <task list> [--profile cheap|standard|premium] [--parallel 3] [--gate human]
```

- `<task list>`: a Markdown file with `- [ ]` items, issue IDs the project's tooling can read, or pasted text. Every task needs acceptance criteria; a task without them is `blocked: no acceptance criteria` from the start.
- `--profile` default `standard`. Sets worker model level (Start workers).
- `--parallel` default 3. Workers running at once. Workers share local infrastructure (test databases, dev server ports, memory); the project's rules on running suites side by side cap real parallelism.

## 0. Preconditions

The coordinator runs from the main checkout, on the base branch. Workers run in worktrees.

```bash
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]   # false: started in a worktree, stop
git fetch origin                                                        # fails: stop and ask
git symbolic-ref --short refs/remotes/origin/HEAD                       # origin/<base>, e.g. origin/master
git symbolic-ref --short HEAD                                           # must equal <base>, else stop
```

`<base>` is the remote's default branch, read above. Never fall back to a local ref silently. Repo root is `git rev-parse --show-toplevel` here; `.worktrees/` and `.handoff/` live under it.

## 1. Build the graph

1. Read project instructions (`AGENTS.md`, `CLAUDE.md`, rules dir). They win over this skill.
2. Give every task a slug: its tracker ID lowercased (`task-139`, `sq2-2183`) when it has one, else lowercase hyphenated words, 4 max. Slug = branch suffix = worktree dir = agent name = pane label.
3. Edges, two kinds:
   - **depends on**: explicit markers in the task (`depends on`, `after`, `blocked by`, `needs`) or tracker relations. The dependent branches from the dependency's commit and waits for it to be `implemented`.
   - **conflicts with**: two tasks whose criteria name the same files. Not a dependency. They do not run at the same time. The later one starts when the earlier one has finished in any state: from `task/<earlier>` when that is `implemented`, so the user does not inherit a certain merge conflict, else from `<base>`. Starting from `task/<earlier>` carries its commits, so the edge then becomes `depends on <earlier>` in the state file: a later block of the earlier task propagates, and `Merge order` puts it first.
   - Criteria rarely name files, so most real conflicts are missed here. The end-of-run check (Stops) catches them.
   - Nothing else is inferred. Same feature, same area, list order: no edge.
4. Reject cycles. Stop and ask.
5. Write the state file (below) with every task `pending` and the edge list. Show the graph in the pane and continue; do not wait. The user may edit the edges in the file at any time; the coordinator rereads it before every start and immediately before every rewrite, so a user edit is merged, not overwritten.

Tasks with no edge between them run in parallel.

## 2. Worktrees

Use the project's worktree command when its instructions name one and it accepts a start point. Otherwise, or when it cannot start from `<start>`:

```bash
git worktree add <repo root>/.worktrees/<slug> -b task/<slug> <start>
```

Record `<start>` in the state file; the delivery check needs it.

`<start>`:

- No dependencies: `origin/<base>`.
- One dependency: `task/<dep-slug>`, the dependency's branch as committed by its worker.
- Several: `task/<first-dep-slug>`, then `git merge task/<other-dep-slug>` for each remaining one inside the new worktree. This is the one merge the coordinator performs: a preparation merge, no conflict resolution. A conflict is `blocked: merge conflict <a>+<b>`. The combined tree is untested; the dependent's worker runs its baseline checks on it first (implement-task step 1), and a baseline failure caused by the combination is that worker's `BLOCKED` delivery, not something to patch.

A dependent worktree is created only after every dependency is `implemented`, never ahead of time.

`.worktrees/` not ignored: report it, do not edit `.gitignore`.

## 3. Start workers

### Herdr (`HERDR_ENV=1`)

**REQUIRED BACKGROUND:** `herdr --skill`. Pane and agent commands, states, prompt gating. Not repeated here.

```bash
herdr agent get "$HERDR_PANE_ID"                                              # coordinator kind
herdr pane split --current --direction right --cwd "<worktree abs path>" --no-focus   # id in .result.pane.pane_id
herdr pane rename <pane_id> <slug>
herdr agent start <slug> --kind <kind> --pane <pane_id> -- <model args>
herdr agent prompt <slug> "$(cat /abs/tmp/prompt-<slug>.md)"                  # no --wait
```

Worker level: senior when the task touches state, concurrency or data contracts; junior for a mechanical edit; otherwise by `--profile`: `cheap` junior, `standard` mid, `premium` senior. Args for that level and the coordinator's kind: `../dev-team/references/model-levels.md`. A model the user names wins.

`agent start` returning `agent_not_ready`: read the pane, answer the startup dialog, wait idle, rename again.

Waiting, round-robin over running workers with a short timeout, so a worker that finishes first is not stuck behind one still working:

```bash
herdr agent wait <slug> --timeout 60000        # timeout: next worker, come back later
herdr agent read <slug> --source recent-unwrapped   # on idle or done: the delivery
```

`blocked`: record it and move on. No worker settled after a full round: wait again. Nothing to wait on and nothing ready to start: Stops.

### Subagents (no Herdr)

One background `Agent` call per ready task, general-purpose type. Model from the level: senior `opus`, mid `sonnet`, junior `haiku`. Never `isolation: "worktree"`: it starts from HEAD, not from the dependency's commit; the coordinator already built the worktree. The prompt is the same file. Completion notifications drive the loop. Never predict a pending result.

A subagent worker usually cannot start subagents of its own, so implement-task's plan challenge and diff review fall back to self-review. Prefer Herdr when independent review matters. In subagent mode, set `**Review:** self only` in the state file and repeat it in the report.

### Worker prompt

Write it to a temp file outside the repo. Shape:

```text
Read <abs path to implement-task/SKILL.md> and apply it to the task below. Work only inside <worktree abs path>, on branch task/<slug>.
Task: <id, title, full text and acceptance criteria, or the file path>
Base branch: task/<dep-slug> | <base>. Changes from <dep-slug> are already on this branch; do not redo them.
Evidence directory: <worktree>/.evidence/<slug>/
Commits: commit every task change on task/<slug> before reporting. Dependent tasks branch from this commit. Never push.
Status: the coordinator owns it. Do not update the task source or tracker; report only.
Shared infrastructure: start no long-running servers on default ports; follow the project's rules for test suites running in parallel.
Stop: do not start another task, do not touch other worktrees.
Delivery, last message: State (VALIDATED | PENDING | BLOCKED), commit sha, changed files, evidence path, human validation needed, blockers.
```

Start every `pending` task whose dependencies are all `implemented` and whose conflict partners are not `running`, up to `--parallel`.

## 4. Loop

On each worker delivery:

1. Parse State, sha and evidence path.
2. Operational checks, in the worktree, before anything else:

   ```bash
   git -C <worktree> rev-parse --verify task/<slug>        # branch exists
   git -C <worktree> rev-parse HEAD                        # equals the reported sha, differs from <start>
   git -C <worktree> status --porcelain                    # empty, apart from .evidence/ and .handoff/
   test -d <evidence path>
   ```

   Any check fails: `blocked: delivery mismatch <which>`. Do not read the diff, rerun tests or reinterpret the evidence; that is review, which implement-task already did.
3. `VALIDATED`: task becomes `implemented`. `PENDING` with no blockers and a non-empty human validation list: task becomes `implemented (human pending)` and unblocks dependents; this is this skill's policy, chosen so a manual check never stalls the chain, and every such task is listed under `Human validation` and repeated in the report. `--gate human` turns it off: those tasks stay `pending human` and hold dependents until the user marks them in the state file.
4. `PENDING` for any other reason, or `BLOCKED`: task becomes `blocked: <reason>`. Every task downstream becomes `blocked: upstream <slug>`. Do not fix, do not re-prompt with a hint. One retry only when the worker itself names a transient cause (lock, network). Second failure stays blocked.
5. For every task now ready, build its worktree (step 2) and start it (step 3).
6. Rewrite the state file.

Loop until no task is `pending`, `pending human` or `running`.

Herdr: after recording a delivery, send that worker `/compact` (`herdr agent prompt <slug> "/compact" --wait --timeout 120000`; Claude Code and Codex, check the kind for others) and leave the pane open. Close panes only when the user asks.

## State file

`.handoff/multi-task.md`, whole rewrite on every change, not committed. Create `.handoff/` if missing; not ignored, report it.

```markdown
# Multi-task

**Updated:** YYYY-MM-DD HH:MM
**Source:** docs/tasks.md | <query> | pasted
**Base:** master   **Profile:** standard   **Runner:** herdr | subagents   **Gate:** none | human   **Review:** independent | self only
**State:** running | complete | blocked: <clause>

## Tasks
| slug | depends on | conflicts with | state | start | sha | agent/pane | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| task-139 | none | none | implemented (human pending) | origin/master | abc123 | task-139 / p12 | .worktrees/task-139/.evidence/task-139 |
| task-140 | task-139 | none | running | abc123 | | task-140 / p13 | |
| task-141 | none | task-139 | pending | | | | |

## Human validation
- task-139: <steps the worker listed>

## Blocked
- <slug>: <reason, since when>

## Merge order
task/task-139, task/task-140, task/task-141

## Predicted conflicts
- task-139 + task-141: config/routes.rb
```

States: `pending`, `running`, `implemented`, `implemented (human pending)`, `pending human` (only under `--gate human`), `blocked: <reason>`. Nothing else.

## Resume

A previous `.handoff/multi-task.md` exists and no worker is live: reconcile before anything else. The file is a record, not the truth.

For every task not `pending`:

1. `git worktree list` and `git rev-parse --verify task/<slug>`: branch exists, worktree missing, `git worktree add <repo root>/.worktrees/<slug> task/<slug>`; branch missing, state back to `pending`.
2. `running` with no live agent: restart a worker in the same worktree, same prompt plus "Work may already exist on this branch; read `git log` and `.evidence/` before continuing." Its delivery goes through the loop as usual.
3. `implemented` whose operational checks no longer pass (dirty worktree, HEAD moved): `blocked: delivery mismatch`, dependents not yet started stay `pending`.

Live workers from a previous coordinator (`herdr agent list` shows the slugs): adopt them, `herdr agent wait` on each, do not restart. Then continue the loop.

## Stops

Before any final report, predict integration conflicts. For every pair of `implemented` branches where neither is an ancestor of the other:

```bash
git merge-tree --write-tree --name-only task/<a> task/<b>    # exit 1: conflict, file names follow
```

List each conflicting pair under `Predicted conflicts`. This reads git only; it is not review.

- All tasks `implemented`: `State: complete`. Report.
- No task `pending` or `running` and at least one `blocked`: `State: blocked`. Report.
- Nothing `running`, only `pending human` left (`--gate human`): `State: blocked: awaiting human validation`. Report. The user marks those tasks `implemented` in the state file and prompts `continue the multi-task loop`.
- Cycle, or missing criteria for every task: stop and ask. A previous state file: Resume, above.
- User says stop: record `State: blocked: stopped by user`, leave workers and worktrees as they are.

## Limits

- The coordinator never edits code, runs the test suite, reviews a diff, performs functional validation, resolves a conflict, pushes or deploys. Its only merge is the preparation merge in step 2. Review and validation belong to implement-task; the coordinator checks that a delivery is what it claims, not that it is good.
- Workers never push. `task/<slug>` branches stay local until the user integrates them in `Merge order`.
- One worktree per task. Never reuse a worktree for a second task.
- Agent name = pane label = slug. Target workers by name, never by sidebar position.

## Report

Per task: slug, state, sha, evidence path, human validation needed. Then `Merge order`, `Predicted conflicts` and the blocked list. State plainly that every `task/<slug>` branch is local and unmerged: `complete` means implemented, not integrated. No worker transcripts.

When the project squash-merges, a chained branch still carries its dependency's original commits after that dependency lands. For each chained task, give the command to run once its dependency is merged:

```bash
git fetch origin && git rebase --onto origin/<base> task/<dep-slug> task/<slug>
```

Task source: list which items or issues to mark, from the state file. The coordinator does not edit the source; the main checkout stays clean on `<base>`.
