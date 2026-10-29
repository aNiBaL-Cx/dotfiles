---
name: multi-task
description: "Coordinate a list of development tasks: resolve precedence, start one implement-task agent per task in its own worktree, chain dependent tasks on the finished dependency's branch, and keep the state file current. The coordinator never implements or reviews code. Uses Herdr panes when HERDR_ENV=1, subagents otherwise. Leaves every branch local and unmerged. Use when: multi-task, implement these tasks in parallel, run this task list with dependencies, /multi-task. Not for a list to merge task by task: use pingpong."
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

- `<task list>`: any mix of sources: a Markdown file with `- [ ]` items, issue IDs or a query the project's tooling can read (Linear, Jira, GitHub), or pasted text. Every task needs acceptance criteria; a task without them is `blocked: no acceptance criteria` from the start.
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

`<base>` is the remote's default branch, read above. Never fall back to a local ref silently. Repo root is `git rev-parse --show-toplevel` here; `.worktrees/` and `.handoff/` live under it. Keep both out of Git locally, never through `.gitignore`:

```bash
ex="$(git rev-parse --git-common-dir)/info/exclude"
for p in .worktrees/ .handoff/; do grep -qx "$p" "$ex" || echo "$p" >> "$ex"; done
```

## 1. Build the graph

1. Read project instructions (`AGENTS.md`, `CLAUDE.md`, rules dir). They win over this skill.
2. Give the run an ID, `<run>`: today's date, `YYYY-MM-DD`. A state file, branch or worktree already uses that date: append `-2`, `-3`, and so on.
3. Give every task an ID, `TASK-NNN`: three digits from `TASK-001`, in source order, whatever the source. IDs belong to this run only; they are never written to the source and never reused within the run.
4. Keep each task's source reference beside its ID, so the report maps back to where the task lives:
   - tracker issue: its key (`TASK-2183`, `PROJ-12`, `#123`);
   - Markdown checklist: `<file>:<line>` of the item;
   - pasted text: `pasted:<position>`.
5. Names derived from the ID, used everywhere below:
   - `<slug>`: the ID lowercased, `task-001`. Agent name = pane label = evidence directory name.
   - `<branch>`: `task/<run>/<slug>`, e.g. `task/2026-10-27/task-001`.
   - `<wt>`: `<repo root>/.worktrees/<run>/<slug>`.
6. Edges, two kinds, written with task IDs:
   - **depends on**: explicit markers in the task (`depends on`, `after`, `blocked by`, `needs`) or tracker relations. Translate a marker that names a source reference (`after TASK-2183`) into the task ID that carries it. A marker naming something outside the list is not an edge; record it under `Blocked` as `external: <reference>`. The dependent branches from the dependency's commit and waits for it to be `implemented`.
   - **conflicts with**: two tasks whose criteria name the same files. Not a dependency. They do not run at the same time. The later one starts when the earlier one has finished in any state: from the earlier task's branch when that is `implemented`, so the user does not inherit a certain merge conflict, else from `<base>`. Starting from the earlier branch carries its commits, so the edge then becomes `depends on <earlier ID>` in the state file: a later block of the earlier task propagates, and `Merge order` puts it first.
   - Criteria rarely name files, so most real conflicts are missed here. The end-of-run check (Stops) catches them.
   - Nothing else is inferred. Same feature, same area, list order: no edge.
7. Reject cycles. Stop and ask.
8. Write the state file (below) with every task `pending` and the edge list. Show the graph in the pane and continue; do not wait. The user may edit the edges in the file at any time; the coordinator rereads it before every start and immediately before every rewrite, so a user edit is merged, not overwritten.

Tasks with no edge between them run in parallel.

## 2. Worktrees

Use the project's worktree command when its instructions name one and it accepts a start point and a branch name. Otherwise, or when it cannot:

```bash
git worktree add <wt> -b <branch> <start>
```

Record `<start>` in the state file; the delivery check needs it.

`<start>`:

- No dependencies: `origin/<base>`.
- One dependency: the dependency's `<branch>`, as committed by its worker.
- Several: the first dependency's `<branch>`, then `git merge <other dependency branch>` for each remaining one inside the new worktree. This is the one merge the coordinator performs: a preparation merge, no conflict resolution. A conflict is `blocked: merge conflict TASK-<a>+TASK-<b>`. The combined tree is untested; the dependent's worker runs its baseline checks on it first (implement-task step 1), and a baseline failure caused by the combination is that worker's `BLOCKED` delivery, not something to patch.

A dependent worktree is created only after every dependency is `implemented`, never ahead of time.

## 3. Start workers

### Herdr (`HERDR_ENV=1`)

**REQUIRED BACKGROUND:** `herdr --skill`. Pane and agent commands, states, prompt gating. Not repeated here.

```bash
herdr agent get "$HERDR_PANE_ID"                                              # coordinator kind
herdr pane split --current --direction right --cwd "<wt>" --no-focus          # id in .result.pane.pane_id
herdr pane rename <pane_id> <slug>
herdr agent start <slug> --kind <kind> --pane <pane_id> -- <model args>
herdr agent prompt <slug> "$(cat /abs/tmp/prompt-<run>-<slug>.md)"           # no --wait
```

A live agent already holds `<slug>` (another run): stop and ask; never target an agent this run did not start.

Worker level: senior when the task touches state, concurrency or data contracts; junior for a mechanical edit; otherwise by `--profile`: `cheap` junior, `standard` mid, `premium` senior. Args for that level and the coordinator's kind: `../references/model-levels.md`. A model the user names wins.

`agent start` returning `agent_not_ready`: read the pane, answer the startup dialog, wait idle, rename again.

Waiting, round-robin over running workers with a short timeout, so a worker that finishes first is not stuck behind one still working:

```bash
herdr agent wait <slug> --timeout 60000        # timeout: next worker, come back later
herdr agent read <slug> --source recent-unwrapped   # on idle or done: the delivery
```

`blocked`: record it and move on. No worker settled after a full round: wait again. Nothing to wait on and nothing ready to start: Stops.

### Subagents (no Herdr)

One background subagent per ready task, through the harness's own subagent mechanism, with full tool access. Level as above; the model comes from `../references/model-levels.md` for the coordinator's kind, mapped to whatever model choice the mechanism exposes. It exposes none: the subagent runs on the coordinator's model, and the state file says so. Never use the mechanism's own worktree isolation: it starts from the current HEAD, not from the dependency's commit; the coordinator already built the worktree. The prompt is the same file. Completion notifications drive the loop. Never predict a pending result.

Neither Herdr nor a subagent mechanism: stop and say so. The coordinator never implements tasks itself.

A subagent worker usually cannot start subagents of its own, so implement-task's plan challenge and diff review fall back to self-review. Prefer Herdr when independent review matters. In subagent mode, set `**Review:** self only` in the state file and repeat it in the report.

### Worker prompt

Write it to a temp file outside the repo. Shape:

```text
Read <abs path to implement-task/SKILL.md> and apply it to the task below. Work only inside <wt>, on branch <branch>.
Task: TASK-NNN, source <source reference>. <title, full text and acceptance criteria, or how to read them from the source>
Commit messages and anything the project names after a ticket use the source reference, never TASK-NNN.
Base branch: <dependency branch> | <base>. Changes from <dependency ID> are already on this branch; do not redo them.
Evidence directory: <wt>/.evidence/<slug>/
Commits: commit every task change on <branch> before reporting. Dependent tasks branch from this commit. Never push.
Status: the coordinator owns it. Do not update the task source or tracker; report only.
Shared infrastructure: start no long-running servers on default ports; follow the project's rules for test suites running in parallel. Lock exclusive resources as described in <abs path to multi-task/SKILL.md>, section "Shared resources".
Stop: do not start another task, do not touch other worktrees.
Delivery, last message: State (VALIDATED | PENDING | BLOCKED), commit sha, changed files, evidence path, human validation needed, blockers.
```

Start every `pending` task whose dependencies are all `implemented` and whose conflict partners are not `running`, up to `--parallel`.

## Shared resources

A shared resource holds state outside the worktree: a physical device, emulator, test database, staging environment, browser with an authenticated session, or external service with mutable state.

Lock one only when concurrent use can collide, change shared state or make results non-deterministic. Two workers running isolated tests on the same server need no lock. The project's instructions name exclusive resources; otherwise the worker decides by this rule.

Hold the lock for the duration of use, not the whole task. `<locks>` is `$TASK_LOCKS_DIR` when set (a directory shared by several repositories that use the same device or environment), else `<git common dir>/locks`, which every worktree of this repository sees:

```bash
locks="${TASK_LOCKS_DIR:-$(git rev-parse --path-format=absolute --git-common-dir)/locks}"; mkdir -p "$locks"
token="<run>/<slug>/$(date +%s)"                                     # keep it; release needs it
mkdir "$locks/<resource>" &&                                         # atomic; fails: held, read owner
  printf 'resource=%s\nrun=%s\nworker=%s\ntoken=%s\nacquired=%s\n' \
    <resource> <run> <slug> "$token" "$(date -u +%FT%TZ)" > "$locks/<resource>/owner"
# use the resource
grep -qx "token=$token" "$locks/<resource>/owner" && rm -r "$locks/<resource>"   # release only your own lock
```

Each shell call is separate: a `trap` in one does not cover the next. Acquire and release explicitly, and release before delivering, on failure too.

Held: wait and retry. Waiting is not a failed attempt. Still held after 5 minutes, or the wait the project's instructions set: deliver `BLOCKED: resource <resource> busy (held by <owner>)`.

A lock prevents incompatible concurrent use. It is neither the retry budget nor the validation gate; both stay in implement-task.

Lock cleanup by the coordinator: only locks whose `run` is this run and whose `worker` is not live. A lock with no `owner` file yet is mid-acquisition: leave it. A lock from another run or repository: leave it and report it.

A lock prevents incompatible concurrent use. It is neither the retry budget nor the validation gate; both stay in implement-task.

## 4. Loop

On each worker delivery:

1. Parse State, sha and evidence path. The worker is no longer live: clean up its locks (Shared resources).
   `BLOCKED: resource <resource> busy`: task becomes `waiting: <resource>`. Not a block: dependents are untouched and no retry is consumed. Skip steps 2–4 for it.
2. Operational checks, in the worktree, before anything else:

   ```bash
   git -C <wt> rev-parse --verify <branch>        # branch exists
   git -C <wt> rev-parse HEAD                     # equals the reported sha, differs from <start>
   git -C <wt> status --porcelain                 # empty, apart from .evidence/ and .handoff/
   test -d <evidence path>
   ```

   Any check fails: `blocked: delivery mismatch <which>`. Do not read the diff, rerun tests or reinterpret the evidence; that is review, which implement-task already did.
3. `VALIDATED`: task becomes `implemented`. `PENDING` with no blockers and a non-empty human validation list: task becomes `implemented (human pending)` and unblocks dependents; this is this skill's policy, chosen so a manual check never stalls the chain, and every such task is listed under `Human validation` and repeated in the report. `--gate human` turns it off: those tasks stay `pending human` and hold dependents until the user marks them in the state file.
4. `PENDING` for any other reason, or `BLOCKED`: task becomes `blocked: <reason>`. Every task downstream becomes `blocked: upstream TASK-NNN`. Do not fix, do not re-prompt with a hint. One retry only when the worker itself names a transient cause (lock, network). Second failure stays blocked.
5. For every task now ready, build its worktree (step 2) and start it (step 3). A `waiting: <resource>` task is ready again once `<locks>/<resource>` is gone: restart it in the same worktree with the Resume prompt (Resume step 2).
6. Rewrite the state file.

Loop until no task is `pending`, `pending human`, `waiting` or `running`.

Herdr: after recording a delivery, send that worker its kind's compact command from `../references/model-levels.md` (`herdr agent prompt <slug> "<compact>" --wait --timeout 120000`) and leave the pane open. Close panes only when the user asks.

## State file

`.handoff/multi-task_<run>_<first ID>-<last ID>.md`, e.g. `.handoff/multi-task_2026-10-27_TASK-001-TASK-007.md`; a single task is `.handoff/multi-task_2026-10-27_TASK-001.md`. Whole rewrite on every change, not committed. Create `.handoff/` if missing. The name is fixed when the graph is built.

```markdown
# Multi-task 2026-10-27

**Updated:** YYYY-MM-DD HH:MM
**Source:** docs/tasks.md | <query> | pasted | <mix>
**Base:** master   **Profile:** standard   **Runner:** herdr | subagents   **Gate:** none | human   **Review:** independent | self only
**State:** running | complete | blocked: <clause>

## Tasks
| id | source | title | depends on | conflicts with | state | start | sha | agent/pane | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-001 | TASK-2183 | Parental HE for CUKAS | none | none | implemented (human pending) | origin/master | abc123 | task-001 / p12 | .worktrees/2026-10-27/task-001/.evidence/task-001 |
| TASK-002 | docs/tasks.md:14 | Export button | TASK-001 | none | running | abc123 | | task-002 / p13 | |
| TASK-003 | pasted:3 | Fix footer copy | none | TASK-001 | pending | | | | |

## Human validation
- TASK-001: <steps the worker listed>

## Blocked
- TASK-NNN: <reason, since when>

## Merge order
task/2026-10-27/task-001, task/2026-10-27/task-002, task/2026-10-27/task-003

## Predicted conflicts
- TASK-001 + TASK-003: config/routes.rb
```

States: `pending`, `running`, `implemented`, `implemented (human pending)`, `pending human` (only under `--gate human`), `waiting: <resource>`, `blocked: <reason>`. Nothing else.

## Resume

A `.handoff/multi-task_*.md` whose `State` is not `complete` exists and no worker of that run is live: reconcile before anything else. Several such files: list them and ask which run to resume. The run ID, task IDs and names come from the file, never from a new graph. The file is a record, not the truth.

For every task not `pending`:

1. `git worktree list` and `git rev-parse --verify <branch>`: branch exists, worktree missing, `git worktree add <wt> <branch>`; branch missing, state back to `pending`.
2. `running` with no live agent: restart a worker in the same worktree, same prompt plus "Work may already exist on this branch; read `git log` and `.evidence/` before continuing." Its delivery goes through the loop as usual.
3. `implemented` whose operational checks no longer pass (dirty worktree, HEAD moved): `blocked: delivery mismatch`, dependents not yet started stay `pending`.
4. Locks: clean up as in Shared resources. Never remove a lock without checking its `run` and `worker`.

Live workers from a previous coordinator (`herdr agent list` shows the slugs): adopt them, `herdr agent wait` on each, do not restart. Then continue the loop.

## Stops

Before any final report, predict integration conflicts. For every pair of `implemented` branches where neither is an ancestor of the other:

```bash
git merge-tree --write-tree --name-only <branch a> <branch b>    # exit 1: conflict, file names follow
```

List each conflicting pair under `Predicted conflicts`. This reads git only; it is not review.

- All tasks `implemented`: `State: complete`. Report.
- No task `pending` or `running` and at least one `blocked`: `State: blocked`. Report.
- Nothing `running`, and every `waiting` task's lock is held by another run or repository: `State: blocked: awaiting resource <resource> (held by <owner>)`. Report. The user prompts `continue the multi-task loop` once it is free.
- Nothing `running`, only `pending human` left (`--gate human`): `State: blocked: awaiting human validation`. Report. The user marks those tasks `implemented` in the state file and prompts `continue the multi-task loop`.
- Cycle, or missing criteria for every task: stop and ask. A previous state file: Resume, above.
- User says stop: record `State: blocked: stopped by user`, leave workers and worktrees as they are.

## Limits

- The coordinator never edits code, runs the test suite, reviews a diff, performs functional validation, resolves a conflict, pushes or deploys. Its only merge is the preparation merge in step 2. Review and validation belong to implement-task; the coordinator checks that a delivery is what it claims, not that it is good.
- Workers never push. Branches stay local until the user integrates them in `Merge order`.
- One worktree per task. Never reuse a worktree for a second task.
- Agent name = pane label = slug. Target workers by name, never by sidebar position.

## Report

Per task: ID, source reference, state, branch, sha, evidence path, human validation needed. Then `Merge order`, `Predicted conflicts` and the blocked list. State plainly that every branch is local and unmerged: `complete` means implemented, not integrated. No worker transcripts.

When the project squash-merges, a chained branch still carries its dependency's original commits after that dependency lands. For each chained task, give the command to run once its dependency is merged:

```bash
git fetch origin && git rebase --onto origin/<base> <dependency branch> <branch>
```

Task source: list which items or issues to mark, by source reference, from the state file. The coordinator does not edit the source; the main checkout stays clean on `<base>`.
