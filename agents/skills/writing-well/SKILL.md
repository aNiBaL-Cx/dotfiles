---
name: writing-well
description: Use when writing, rewriting, editing or reviewing prose meant for a human reader — notes, documents, tutorials, guides, articles, book chapters, emails, READMEs. Triggers on "improve this text", "rewrite", "edit this", "review my writing", "melhora este texto", "revê a escrita", "escreve um capítulo/tutorial", "/writing-well". Not for code comments or commit messages.
---

# Writing well

Good text says what the author means, to a named reader, in the fewest clear words. The baseline is any writing rules already in your loaded instructions (`CLAUDE.md` / `AGENTS.md`); project rules win over global ones. This skill adds what those rules miss: fidelity to the source, a mode per genre, and a fixed output shape.

## 1. Fix the reader and the mode first

Name the reader in one line before writing. Then pick the mode:

| Mode | Reader goal | Shape |
|------|-------------|-------|
| **Note** | Decide relevance in 30s | Loaded note rules as written; if none: problem first, bullets, `**Label:** value`, done-criteria only for task notes |
| **Doc / guide** | Find and use one fact | Headings that answer questions, one topic per section, examples next to the rule |
| **Tutorial** | Learn by doing | Goal, then numbered steps; each step = one action + expected result; runnable examples; "you" voice |
| **Long-form** (article, book chapter, essay) | Follow an argument | Paragraphs, not bullets; one claim per paragraph, opening with it; transitions carry the logic; vary sentence length; concrete scenes and examples over abstraction |

Long-form breaks note rules on purpose: no fragments, few bullets, rhythm matters. Keep the cuts (filler, hedging, passive voice) and keep one idea per paragraph.

## 2. Fidelity rules (rewrites and edits)

- **Add no facts.** Any claim, step, number, name or example the source does not support goes in as `[?: what is missing]`, not as invented text.
- **Keep the author's certainty.** Delete hedge words, but keep real doubt once, stated plainly where the claim first appears: "Likely cause (not confirmed): …". Never turn "might be" into a fact, even in the lead sentence.
- **Flag only gaps that change meaning or block the reader.** A missing ticket ID or a nice-to-have detail is not a gap.
- **Do not promise content the text does not deliver.** An intro that says "you will learn X" needs X later in the text.
- **Keep identifiers exact:** names, flags, error strings, versions.
- **Keep the author's language and voice.** Portuguese stays Portuguese; a personal voice stays personal.
- Turning a vague intent into a concrete proposal ("add a warning or something" → a specific warning) is a suggestion: mark it `[suggested]`.

## 3. Output shape

1. The rewritten text, in full.
2. `**Gaps:**` each `[?]` and `[suggested]` marker from the text, one line each, at most 5. Omit the section when there are none.
3. `**Changes:**` 3–5 bullets naming the main edits.

For a review without a rewrite: list problems as `quote → problem → fix`, worst first.

## Final pass

- Read the first sentence of each paragraph alone. They should tell the whole story.
- Cut the text by a third. Keep every fact and identifier.
- Read it as the named reader: what would they ask first? Answer it or mark `[?]`.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Note format applied to a tutorial or chapter | Pick the mode from the table |
| Invented done-criteria, examples or benefits | `[?]` or `[suggested]` |
| Hedge removed together with real uncertainty | Keep doubt once, explicitly |
| Short intro inflated into a full article | Match the source length unless asked to expand |
