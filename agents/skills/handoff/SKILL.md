---
name: handoff
description: "Rewrite a handoff file in the repo's local .handoff/ folder so another agent or a future session can continue with zero context. One file per piece of work, .handoff/<slug>.md at the repo root, overwritten in place. Never writes to the notes vault. Use when: handoff, local handoff, hand off, hand off here, pass to next agent, save context, continue later, pick up later."
---

# Handoff

A transfer note: read once, by one reader, soon, then dead. It holds the state now and the next three actions, points at what the index already records, and lists what should outlive the task. Everything else is a link.

**Announce at start:** "I'm using the handoff skill."

## Usage

- `/handoff` - rewrite the handoff for the current work
- `/handoff <description>` - same, with a specific focus

## One file, overwritten

- Path: `<repo root>/.handoff/<slug>.md`. Repo root is `git rev-parse --show-toplevel` (a worktree's own root, not the main checkout).
- Slug: the ticket ID when the branch or task has one (`TASK-1927.md`), else a short kebab-case name for the work.
- Create `.handoff/` if missing. Do not commit it; if it is not ignored, say so instead of editing `.gitignore`.
- Rewrite the whole file. No timestamped names, no `-2`, no "since last handoff" section.
- Read the current file first. Keep only what is still "now".
- Never write to the notes vault or any other location.

## Process

1. Read the current `.handoff/<slug>.md` if any.
2. Check git state: `git status`, `git log --oneline -10`, PR checks (`gh pr checks`) when a PR exists.
3. Write the file (format below). Hard cap 30 lines. Over the cap: cut `Episodic` to links first, never `Working`.
4. Print the path.

## Format

```markdown
# Handoff: {slug}, {short title}

**Ticket:** {ID + link, or "none"}
**Worktree:** {absolute path} — one per repo
**Branch:** {repo: branch} — one per repo
**Updated:** {YYYY-MM-DD HH:MM} by {agent or session}
**PR:** {link, open/draft, checks state on head sha} — one per repo
**State:** {in-progress | blocked | ready-for-review | paused}: {one clause: uncommitted / pushed / green / reviewed}

## Working
Goal: {one sentence. What this delivers.}
Next:
1. {concrete step: file, command, or check}
2. {…}
3. {…}
Dirty: {uncommitted files, failing tests, what must be re-checked before running anything; or "clean"}
Open: {needs a human: who, what, since when; or "nothing"}

## Episodic
- {dead end or decision since the index was last updated}: in the index {yes | NO, write it before stopping}

## Promote at close
- semantic: {durable fact about the domain or the system}
- procedural: {rule or trap that stays true after this task}

## Links
- {PR, tracker issue, index, related files}
```

Each section holds one kind of memory, and each kind has one fate:

- **Working** is the state now. It dies when the task closes. Nothing in it is copied anywhere.
- **Episodic** is pointers only. The text of a dead end or a decision lives in the task index; this section says whether it is there yet. With no index, one line each.
- **Promote at close** is candidates, not content: one line each, no explanation. The project's close-out process turns each line into a proposed change to the reference notes (semantic) or to the agent instructions, a rule file or a skill (procedural). Leave the section out when there is nothing.

## What does NOT go here

- Decisions and why: PR body, and the ticket index in the notes vault when the work has one.
- What was done: git log, and the index's `Interactions`.
- Inventories, script outputs, test matrices: a separate file next to it in `.handoff/`, linked from `Links`.
- A trap that stays true after the task closes: it is a `Promote at close` line, not working state.
- Customer or tenant data (names, emails, ids, exports): never, not even as an example.

## Rules

- Concrete: file paths, commands, shas. "Finish the feature" is not a next step.
- State facts. No narrative.
- Uncommitted changes and failing tests go in `Dirty`: name them.
- Self-contained: the reader must not need this conversation.

## Instructing the next agent

After writing the file, tell the user:

```
To continue this work in a new session, start with:
> Read {absolute path} and continue from "Next".
```
