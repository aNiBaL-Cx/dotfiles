---
name: notes
description: The workflow for investigating a ticket and recording its development or fix in the project's notes vault — create, resume and archive the ticket's note folder, keep its index as the development record, link it in the daily note, and place or find any vault note. Triggers on "create task note", "start TASK-001", "resume <task>", "archive <task>", "where does this note go", "find note".
---

# Notes

The workflow for investigating a ticket and recording how it was developed or fixed. The ticket's folder in the vault holds the record: what was found, what was decided, what was tried and abandoned, who reviewed it, whether QA passed. The skill covers the folder's lifecycle (create, resume, archive), daily-note linking, and placement or lookup of any vault note.

The vault's own docs and templates are the source of truth. This skill states the conventions that hold in every vault and points to the vault for the rest, so the two cannot drift.

**Announce at start:** "I'm using the notes skill."

## Setup

The vault is `notes/` at the project root, usually a symlink to the vault folder. No `notes/` → stop and ask where the vault is.

Read what the operation needs:

- `notes/README.md`: the folder structure and placement rules. Always read it: folder names vary between vaults.
- `notes/AGENTS.md` (or `notes/CLAUDE.md` when the vault has only that): templates and the vault's specifics for this skill. It wins over this file.
- The task template, an exemplar note if the vault has one, and the daily-note template, as that file names them.

### Folder layout

Resolve every folder from `notes/README.md`, never from the names below. The roles are fixed; the names are not:

- **Projects:** `Projects/`, or numbered for sort order (`10_Projects/`). It may hold one subfolder per project (`10_Projects/SomeProject/`); task folders then live inside that project's folder. Pick the project from the repo you are in, or ask.
- **Archive:** `Archive/` or `40_Archive/`, mirroring the projects layout, including the per-project subfolder.
- **Resources:** `Resources/` or `30_Resources/`. Grouped by topic, never by project.
- **Daily notes:** `Daily-Notes/` or `00_Daily/`.

Below, `<tasks>` is the folder that holds task folders (`Projects/Tickets/`, `10_Projects/SomeProject/Tasks/`), `<archive>` is its archive counterpart, and `<daily>` is the daily-notes folder.

Task IDs are whatever the project's tracker uses (`TASK-001` below). Which tracker that is, and how to read it, comes from the project's memory and instructions, not from this skill.

## Core rules

- **The main note is the index.** `<tasks>/<ID>/<ID>-index.md`, always that name. It is the task's collection point: when work started, what the sub-notes hold, what was decided, what changed in scope, who reviewed it, whether QA ran and passed. A folder with a dozen files needs one file you can open without looking.
- **Link, don't copy.** The tracker owns status, acceptance criteria and discussion. The code host owns the diff. The index owns the development record: reasoning, dead ends, links. If the tracker or the code host can hold it, link it.
- **Anti-bloat.** No code blocks, curl or file lists in the index; link the PR. A section you cannot scan in 30 seconds goes to a sub-note or gets cut. This holds even with no PR to link: runbooks, console recipes and shell blocks go in `<ID>-runbook.md`, with a one-line pointer from the index.
- **Folder per task from the start.** Index, sub-notes and artifacts (handoffs, test results) live in `<ID>/`. Never promote a flat note to a folder later: it breaks links and makes duplicates.
- **ID in every note name.** Sub-notes are `<ID>-<what>.md`: `TASK-001-investigation.md`, `TASK-001-qa-plan.md`, `TASK-001-handoff.md`. A note must be identifiable from its filename alone.
- **Older notes stay put.** Notes named before a convention keep their name until archived. Renaming outside Obsidian breaks wikilinks.
- **Frontmatter:** `tags: ticket`, unless the vault says otherwise.
- **Register.** Match the voice and density of the vault's exemplar note when it has one.

### The index is the contact point between agents

Several agents and sessions touch one task. The index is where they meet: it is fresher than any transcript and it is the only shared state.

- **Read the index first**, before the code and the conversation. Then `<ID>-handoff.md` if present: one per task, rewritten in place, possibly fresher still.
- **Write back before you finish.** Append one dated line to the section that is yours (`Review`, `QA`, `Scope changes`, `Interactions`) and update `**Status:**` so it is still true.
- **Never rewrite another agent's line.** Add a dated line that supersedes it and say what changed.
- **Conclusions in the index, evidence in the sub-note.** File:line goes to `<ID>-investigation.md`. Screenshots and per-scenario results go to `test_results/`, which is disposable: deleted at archive, and nothing outside it links to its files. Each QA run is one or two lines in the index's `QA` section: date, environment, build, counts.
- **`<ID>-qa-plan.md` holds the scenarios and the demo script**, never a separate note.

### Default sections

`**Status:**` · `**Next action:**` · `**Blocked on:**` · `**Started:** … **Shipped:**` · `Sub-notes` · `Decisions` · `Interactions` · `Review` · `QA` · `PRs` · `Attempted & abandoned`.

- **The four bold lines are one line each.** A `**Status:**` paragraph is the failure this guards against: one ran to 1,900 characters holding PR state, two QA runs and another task's finding, and was stale on two counts because no single line could be updated. `**Status:**` names the tracker state and where the code is (uncommitted / pushed / in review); "implemented" with no PR is the drift it prevents. `**Next action:**` is one verb phrase. `**Blocked on:**` is "nothing", or what and whose.
- **`Decisions` are one-liners:** the choice, the rejected alternative, and a link to the PR that holds the why. The PR body is the source of the reasoning, because it survives a squash merge and reviewers have no vault. Never copy its paragraphs back. No PR yet → link the investigation sub-note.
- **`Review` and `QA` stay even when empty**, as `**not reviewed**` / `**not run**`. The absence is the signal.
- `Sub-notes` is the folder's table of contents: one line per companion file, plus one shared unlinked line for disposable artifacts (handoff, `test_results/`).
- Add `Scope changes`, `Notes`, `Gotchas` or `Manual testing` only when there is something for them. `Scope changes` is dated: what changed, who asked, the effect on acceptance criteria or estimate.
- The process timeline goes to the tracker as comments, not the note.

## Sizing: three kinds of note

- **State**: read many times, rewritten, must be true now. The daily note, the index's four bold lines. Glanceable, no history, link instead of repeating.
- **Record**: append-only, read once later by someone with a question. PR body, `Decisions`, `Interactions`, investigation, meeting notes. Detail is fine. Repeat only where the reader cannot reach the other source: the PR repeats the vault (reviewers have no vault); the vault never repeats the PR.
- **Transfer**: read once by one reader in the next 30 minutes, then dead. `<ID>-handoff.md`: state, the next three actions, traps, 40 lines at most, one file overwritten in place.

## Operations

### Create a task note

Input: a task ID. Run one at a time for several IDs.

1. **Read the task from the tracker:** title, description, acceptance criteria, URL.
2. **A folder for the ID already exists** → read the index and update `**Status:**` only. Do not overwrite, and keep its filename even if it predates the `-index` convention.
3. **New** → create `<ID>/<ID>-index.md` from the task template. The H1 carries the task title in plain words; the filename carries only the ID. Fill `**Started:**` with today. Default sections only.
4. **Summarize** the task in 3 to 5 bullets: the ask, acceptance criteria, unknowns, first step.
5. **Link** it in today's daily note, if the vault keeps daily notes.

### Add a sub-note

Only when a section of the index overflows the 30-second scan, or deep research would pollute it.

1. Create `<ID>-investigation.md` or `<ID>-specification.md` in the task folder, from the matching template if the vault has one.
2. Replace the overflowing section with a one-line summary and a wikilink, and add the file to `Sub-notes`.

### Resume a task

Read `<ID>-index.md` and summarize: status, next action, blockers, whether it was reviewed and QA'd. Read `<ID>-handoff.md` if present for the exact resume state, and rewrite that file (never a second one) when you stop. Continue in the same index.

### Archive a task

When the tracker says done:

1. Run the vault's close-out process first, if the vault's agent instructions name one. Nothing in the index is rewritten or trimmed at archive time; it is the record as it stands.
2. Delete `<ID>-handoff.md` and `test_results/` if still there.
3. Move the folder to `<archive>/<YYYY>/`. Move it in Obsidian so links update.

### Link in the daily note

- Find today's note by filename (`find notes/<daily> -name "<YYYY-MM-DD-Weekday>.md"`). Never construct the path: a vault may move past months into subfolders.
- Missing → create it from the daily-note template, where the vault's daily-notes setting puts new notes.
- Add the task in the block format the vault's daily-note doc defines. Default: `- **[[<ID>-index|<ID>]]** — <short what-it-is>. ([tracker](<url>))`, with no status text in the line.

### Find or place a note

- **Find:** search `<tasks>` (including any backlog subfolder) by ID, and the resources folder by topic. Return the path and a one-line summary.
- **Place:** apply `notes/README.md`. Say where the note goes and why before creating it.
