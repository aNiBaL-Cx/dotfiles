---
name: cheap-dev-team
description: >
  Use when the user says cheap-dev-team, /cheap-dev-team, "use the herdr panes", or asks to delegate a task
  across cheap Herdr worker agents in the current workspace, open or not. Requires HERDR_ENV=1.
metadata:
  short-description: Delegate to existing cheap Herdr panes
---

# Cheap dev team

Coordinator stays in the current pane and keeps its context small. Workers are cheap agents in sibling panes: reuse the ones already running, start the ones the task needs. Do not open workspaces or internal subagents, and do not change a running worker's model.

**REQUIRED BACKGROUND:** `herdr --skill`. Read it if not already in context. It defines `HERDR_ENV`, agent states, prompt gating, and safety rules. This skill does not repeat them.

## Find or create the panes

```bash
test "${HERDR_ENV:-}" = 1 || { echo "not inside Herdr"; exit 1; }
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

A worker is a pane whose `label` equals a role, or a role plus `-N` (`ui`, `dev-2`). Fall back to the agent name. Skip `$HERDR_PANE_ID`. Agent name must equal the label: an adopted pane whose agent carries an auto name (`opus-1`) gets `herdr agent rename <pane_id> <label>` first. From then on target workers by name, never by sidebar position.

| Label    | Default ownership                                                                                            |
| -------- | ------------------------------------------------------------------------------------------------------------ |
| `ui`     | Stylesheets, visible copy, static assets                                                                     |
| `dev`    | Behavior, data wiring, small pure helpers                                                                    |
| `test`   | Test files                                                                                                   |
| `review` | None. Read-only notes on the current diff, when the coordinator asks for a second opinion before integrating |

A `-N` suffix shares the parent role. No fifth role unless the user names it.

Defaults are a starting point. The prompt names the exact files each pane owns. A component file that mixes markup and behavior goes to one pane. Leave `blocked` or `working` panes alone; a blocked approval is the user's.

Start only the roles this task needs. Missing role: take a free shell pane, or split one from the coordinator; same kind as the coordinator, model by role below.

```bash
herdr agent get "$HERDR_PANE_ID"                      # coordinator kind
herdr pane split --current --direction right --cwd "$PWD" --no-focus   # down when the pane is tall; id in .result.pane.pane_id
herdr pane rename <pane_id> dev
herdr agent start dev --kind <kind> --pane <pane_id> -- <model-args>   # agent name = label
```

Model by role, as a tier: `ui` and `test` take cheap; `dev` takes mid, cheap only for a mechanical edit, top when the task touches state, concurrency, or data contracts; `review` takes top.

| Kind   | Args after `--` | Cheap        | Mid           | Top                                            |
| ------ | --------------- | ------------ | ------------- | ---------------------------------------------- |
| claude | `--model <id>`  | `haiku`      | `sonnet`      | `opus`                                         |
| codex  | `-m <id>`       | `gpt-6-luna` | `gpt-6.1-sol` | `gpt-6.1-sol -c model_reasoning_effort=medium` |
| grok   | `-m <id>`       | `grok-4.5`   | `grok-4.6`    | `grok-4.7`                                     |

Never start codex on `gpt-6-astra`, not even as a fallback; only when the user names it. A model the user names wins over the table. A table id the CLI rejects: list current ids (`~/.codex/models_cache.json`, `~/.grok/models_cache.json`), take the same tier, tell the user. Other kinds: read `<kind> --help` and ask once for the tiers. Agent name = label; names are unique among live agents, so a second `dev` is `dev-2`. Leave started panes open for the next task; close them only when the user asks.

## One task at a time

Task note: the file the user points at, or the repo's task folder (`docs/tasks/` in repos that have one). Read it, the acceptance criteria, and `git status`. Preserve unrelated dirty files.

Coordinator decides architecture, scope, contracts, and file ownership. One writer per file. Parallel prompts only when file sets do not overlap. Record a decision in the task note before any pane implements on top of it. A test that needs a production export: coordinator assigns that edit to the production owner, or transfers the file to `test` after the owner reports done.

Write each prompt to a temp file outside the repo, then send its contents inline:

```bash
herdr agent prompt dev "$(cat /abs/tmp/prompt-dev.md)" --wait --timeout 900000
```

`--wait` already gates on observed `working` and returns on the first settled `idle`, `done`, or `blocked`. Check the returned state. On `blocked`, stop and tell the user. On `agent_prompt_stalled` or `timeout`, run `herdr agent get` and `herdr agent read --source recent-unwrapped` before resending.

Prompt shape:

```text
Objective:
Context: task note path and the decided contract. No chat history.
Ownership: files you may edit.
Out of bounds: files and behaviors to leave alone. Architecture, scope, and contract choices are the coordinator's: on an unresolved one, pause that part and report evidence.
Acceptance: command you must run.
Stop: do not commit, push, or start another task.
Delivery: changed files, checks with results, unresolved issues. Keep your context until the coordinator confirms integration.
```

## Integrate

Review the diff yourself. Fix a small integration bug in place when explaining it costs more than the edit. Run the repo test and build once on the integrated tree. Write the real result in the task note.

Commit only when the user asked. Stage only this task's files. Commit on the branch the user named. Push only when asked.

When the user says they will review the UI, skip visual verification and say so in the report.

After integration, or when the task is explicitly stopped: copy delivery reports and open issues into the task note, then send each worker that ran its compact command and nothing else: `herdr agent prompt <role> "/compact" --wait --timeout 120000` on Claude Code and Codex; check the kind in `herdr agent list` for others. Compact keeps a summary for the next task; use the clear command only when the user asks for a cold start.

## Report

Which pane did which task, commits, checks run, what still needs the user. No worker transcripts.
