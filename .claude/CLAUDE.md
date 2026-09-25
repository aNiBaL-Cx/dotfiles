# Note Writing Guidelines

## Writing style for tasks and notes

Write as a senior engineer with the discipline of a technical writer.

Reader: a senior dev who knows the stack but not this task, skimming in 30 seconds to decide relevance.

Structure task and explanatory notes functionally-first (reference notes lead with the fact itself):
1. Lead with the problem or concept in plain language — what needs to happen and why, understandable without reading code.
2. Add a "Technical details" section only when it earns its place (non-obvious implementation, constraints, gotchas, decisions).

Rules:
- Every sentence must carry a fact, decision, or instruction — delete any that doesn't. Cut hedging and filler.
- One idea per sentence. Prefer short sentences over qualified ones.
- Don't assume shared context that isn't in the text.
- Task notes state what "done" looks like and how to verify it.
- Decisions name the rejected alternatives in one line.
- Plain language never replaces exact identifiers — keep precise names, error strings, and versions in the technical details.
- List actions / next steps when action is required.
- Prefer bullets for lists of 3+; make it scannable in 30 seconds.
- Use plain words and active voice.

## Formatting
- Never hard-wrap prose (notes are read in Obsidian, which does not reflow manual breaks). Write each paragraph, bullet, and `**Label:** value` line as one unbroken line; no trailing-two-space line breaks. Code blocks and tables keep their own lines.
- Use `**bold**` for one key phrase per paragraph.
- Add blank lines between paragraphs, sections, and consecutive `**Label:** value` lines. Never between items of one list: a blank line makes the list "loose" and Obsidian renders every item with paragraph spacing.
- Keep nested bullets to max 2 levels.
- Use callouts only for important warnings/tips:
  - `> [!NOTE]`
  - `> [!WARNING]`
  - `> [!TIP]`

## Tables
- Avoid tables when cells contain long unbreakable values (paths, URLs, code, IDs).
- In those cases, use:
  - `### Heading`
  - `**Label:** value`
- Tables are fine for short textual comparisons.

## Final checks before sending
- Leads with the problem/concept in plain language.
- One idea per sentence; no filler.
- "Technical details" present only when it earns its place.
- Task notes include done-criteria / how to verify.
- Actions / next steps are listed when action is required.
- No long paths/URLs/code inside table cells (use `Label: value` instead).
- Long text? Edit-down pass: rewrite at half the length, keep all identifiers and decisions.

## Tone
- Write like a clear message to your future self.
- Use "you" in instructional notes.
- Prefer concrete examples over abstract statements.

## Personal Preferences

**Response style**
- Direct, no emotional padding or unnecessary filler phrases
- Minimal solutions — don't propose architecture where a simple fix will do

**Anti-overengineering rule**
Prefer the minimal solution that solves the current task. Don't introduce abstractions for anticipated future needs.
