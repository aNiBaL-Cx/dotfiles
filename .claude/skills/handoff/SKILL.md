---
name: handoff
description: "Summarize current work into a handoff file for another agent or a future session to continue. Creates a structured markdown briefing with context, progress, next steps, and key decisions. Ticket work saves into the ticket's vault folder as <ID>-handoff-*.md; non-ticket work into .handoff/ in the repo. Use when: handoff, hand off, pass to next agent, agent handoff, save context, continue later, pick up later."
---

# Handoff

Capture the current state of work into a structured markdown file so another
agent (or a future session) can pick up exactly where you left off — with zero
context from this conversation.

Adapted from leandronsp/dotfiles; save location fitted to the FullFabric notes
vault.

## Usage

- `/handoff` - summarize current work into a handoff file
- `/handoff <description>` - handoff with a specific focus or note

## Process

1. **Analyze the current session.** Review what was discussed, what changed, what was decided.

2. **Check git state.** Run `git status`, `git diff`, and `git log --oneline -10` to capture the actual state of the codebase.

3. **Identify open threads.** What was in progress? What's blocked? What needs human input?

4. **Write the handoff file** (format below) to the save location (below).

5. **Print the file path** so the user can share it with the next agent.

## Save location

Detect the active ticket (SQ2-/DEV- id) from the branch name, worktree
directory, or conversation context.

1. **Ticket work** → save to the ticket folder in the vault as
   `<ID>-handoff-{timestamp}.md`
   (`/Users/anibal/MEGA/A - FullFabric/Notes/Projects/Tickets/<ID>*/`; the
   folder-per-ticket convention means it exists — create it if the ticket
   predates the convention and only has a flat note, leaving the flat note
   where it is). Tickets span several repos, so the vault centralizes the
   handoff; note the repo(s) and branch(es) in the file.
2. **Non-ticket work** → save to `.handoff/{timestamp}-{slug}.md` in the repo
   root (create the dir; it is scratch, not committed).

`{timestamp}` is `YYYYMMDD-HHMM`; `{slug}` is short kebab-case (e.g.
`verification-upload`).

## Handoff file format

```markdown
# Handoff: {brief title}

**Created:** {YYYY-MM-DD HH:MM}
**Repo/Branch:** {repo: current git branch — one line per repo if several}
**Ticket:** {Linear id + link, if any}
**Status:** {in-progress | blocked | ready-for-review | paused}

## Goal

{What is being accomplished, in 1-3 sentences. Include the issue/PR URL if one exists.}

## What was done

{Bullet list of completed work. Be specific: file paths, function names, test results.}

## Current state

{Where things stand right now. Include:}
- Files modified (with paths)
- Tests passing/failing
- Any uncommitted changes
- Build/compile status

## Key decisions

{Decisions made during the session and WHY. Another agent needs this context to avoid re-debating or reversing them. Name rejected alternatives.}

## What's next

{Ordered list of remaining work. Be concrete: "add validation to `Accounts.create_user`", not "finish the feature".}

## Blockers / Open questions

{Anything that needs human input or external resolution before continuing.}

## How to continue

{Specific instructions for the next agent. Example:}
1. Read this handoff file
2. Check out branch `{branch}` (or cd into the worktree)
3. Run `{specific command}` to verify current state
4. Start with "{next concrete step}"

## Key files

{List the most important files for context, with one-line descriptions:}
- `path/to/file.rb` - {what it does / why it matters}
```

## Rules

- Be concrete and specific. File paths, function names, line numbers. Vague summaries are useless.
- Include the WHY behind decisions. The next agent has zero context from this conversation.
- Don't editorialize or pad. State facts.
- If there are uncommitted changes, say so explicitly and list them.
- If tests are failing, include the failure output or at least the test name and reason.
- The handoff must be self-contained. The next agent should NOT need to read this conversation.
- Boundary rule still applies: status/AC live in Linear, the diff in GitHub — link them, don't copy them.

## Instructing the next agent

After creating the handoff file, tell the user:

```
To continue this work in a new session, start with:
> Read {path} and continue from "What's next".
```
