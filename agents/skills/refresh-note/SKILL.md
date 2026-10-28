---
name: refresh-note
description: Use when a living reference note must be brought up to date with what changed outside the vault — a landscape of tools, plugins, models or vendors whose verdicts go stale. Triggers on "/refresh-note", "refresh <note>", "refresh the due notes", or a scheduled run with no note named. Not for ticket notes (use notes) or for compiling capture notes into a wiki (use compile-wiki).
---

# Refresh note

A living note answers one standing question ("which Obsidian AI tools are worth using here?") and goes stale as the world moves. A refresh researches what changed since the last refresh and updates the note's verdicts. It never acts on them: no installs, no config changes, no edits outside the note.

## Which notes

A note opts in through its frontmatter and one section:

```yaml
refresh: monthly      # monthly | quarterly
refreshed: 2026-10-28 # date of the last refresh
```

- `## How to refresh` — the note's contract: the question, what to search, the adoption criterion, and which sections hold the verdicts. The contract wins over this file.
- `## Refresh log` — one dated line per refresh.

**Input:**
- A note path → refresh that note, due or not.
- No path → find notes in the vault (the working directory) whose frontmatter has `refresh:`, and refresh each one that is due. Count in calendar months, not days: a note is due from the 1st of the month that is `refreshed`'s month plus the period (1 or 3). Example: `refreshed: 2026-10-28`, `refresh: monthly` → due from 2026-11-01. None due → reply "nothing due" and stop.

## Opt a note in

A path to a note with no `refresh:` frontmatter or no `## How to refresh` section:

- **Interactive session:** draft the contract from the note itself: the question (from the title or first paragraph), what to search, the adoption criterion, the verdict sections it already has, and `refresh: monthly`. Show the draft and ask. On a yes, add the frontmatter, `## How to refresh` and an empty `## Refresh log`, then run the first refresh. On a no, stop with nothing edited.
- **Non-interactive run (`claude -p`):** reply "no refresh contract: <path>" and stop with nothing edited.

## Refresh one note

1. Read the whole note. The current setup and the earlier verdicts are the baseline.
2. Research what the contract names, limited to what is new or changed since `refreshed`. Check every item already listed for releases, pricing, status or license changes. Prefer primary sources (the project's repo, release notes, docs) over roundups.
3. Judge each new item against the note's adoption criterion. An item that matches nothing in the criterion is not a candidate; say why in one line.
4. Edit the note:
   - `TL;DR`: add a new dated line on top; keep older lines.
   - Verdict sections the contract names: update in place. A changed verdict keeps its old text struck through or adds a dated line saying what changed.
   - `Candidates`: add or close checkboxes.
   - `Refresh log`: one dated line — what was searched, what changed. Write it also when nothing changed.
   - `Sources`: add each new URL used.
   - Frontmatter: set `refreshed:` to today.
5. Reply with one line per note: the path and what changed, or "no change".

## Output contract

The only file that changes is the note being refreshed. Every edit is either a new dated line or an in-place verdict update the contract allows. Follow the vault's writing rules (`AGENTS.md` or `CLAUDE.md`).

## Common mistakes

- **Rewriting the whole note.** Readers diff it in git; a full rewrite hides what changed.
- **Restating last month's findings as new.** Compare against the `Refresh log` and `Sources` before writing.
- **Acting on a verdict.** "Adopt X" goes in `Candidates`; installing X is the user's call.
- **Skipping the log line when nothing changed.** The line is the proof the refresh ran.
