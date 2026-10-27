---
name: local-handoff
description: "Rewrite a handoff file in the repo's local .handoff/ folder so another agent or a future session can continue with zero context. One file per piece of work, .handoff/<slug>.md at the repo root, overwritten in place. Never writes to the notes vault. Use when: local handoff, handoff to .handoff, hand off here, pass to next agent, save context, continue later."
---

# Local handoff

A transfer note: read once, by one reader, soon, then dead. It holds the state now, the next three actions, and the traps. Everything else is a link.

**Announce at start:** "I'm using the local-handoff skill."

## Usage

- `/local-handoff` - rewrite the handoff for the current work
- `/local-handoff <description>` - same, with a specific focus

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
3. Write the file (format below). Hard cap 40 lines.
4. Print the path.

## Format

```markdown
# Handoff: {slug}, {short title}

**Updated:** {YYYY-MM-DD HH:MM} by {agent or session}
**Ticket:** {ID + link, or "none"}
**PR:** {link, open/draft, checks state on head sha} — one per repo
**Repo/Branch:** {repo: branch, worktree path} — one per repo
**State:** {in-progress | blocked | ready-for-review | paused}: {one clause: uncommitted / pushed / green / reviewed}

## Goal
{1-2 sentences. What this delivers.}

## Next
1. {concrete step: file, command, or check}
2. {…}
3. {…}

## Traps
- {what looks right and is wrong; what must be re-checked before running anything}

## Open
- {needs a human: who, what, since when}

## Links
- {PR, Linear issue, related files}
```

## What does NOT go here

- Decisions and why: PR body.
- What was done: git log.
- Inventories, script outputs, test matrices: a separate file next to it in `.handoff/`, linked from `Links`.

## Rules

- Concrete: file paths, commands, shas. "Finish the feature" is not a next step.
- State facts. No narrative.
- Uncommitted changes and failing tests are traps: name them.
- Self-contained: the reader must not need this conversation.

## Instructing the next agent

After writing the file, tell the user:

```
To continue this work in a new session, start with:
> Read {absolute path} and continue from "Next".
```
