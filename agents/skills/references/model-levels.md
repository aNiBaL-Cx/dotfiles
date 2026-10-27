# Model levels

Single source for everything that differs by agent CLI kind: the model args each level gets, and the session commands. The skills that use it stay vendor-neutral. Used by `dev-team`, `multi-task` and `pingpong`. Each skill decides the level; this file turns a level into args. Rationale and costs: vault note `Resources/How-To/Tools/AI-Model-Levels.md`.

## Main pick

Args after `--`, per level and kind:

| Level  | claude                      | codex                                             | grok                          |
| ------ | --------------------------- | ------------------------------------------------- | ----------------------------- |
| staff  | `--model claude-fable-5-1`  | `-m gpt-6-astra`                                  | `-m grok-4.7 --effort high`   |
| senior | `--model claude-opus-5-5`   | `-m gpt-6.1-sol -c model_reasoning_effort=medium` | `-m grok-4.6 --effort xhigh`  |
| mid    | `--model claude-sonnet-5-5` | `-m gpt-6.1-sol -c model_reasoning_effort=low`    | `-m grok-4.6 --effort medium` |
| junior | `--model claude-haiku-5-5`  | `-m gpt-6-luna`                                   | `-m grok-4.5 --effort low`    |

## Rules

- Pass every arg in the row: full Claude IDs, because aliases drift on new releases; explicit grok effort, because grok defaults to `high`.
- `gpt-6-astra` is staff only, never a fallback.
- Staff starts only when the calling skill's profile allows it or the user names it.
- Fable on agent tooling or security-sensitive code refuses or stalls: restart that agent on senior.
- A model the user names wins over the table.
- Main pick refused, rejected by the CLI, or too costly: use the level's alternative and tell the user.

## Alternative

| Level  | claude                      | codex                                           | grok                          |
| ------ | --------------------------- | ----------------------------------------------- | ----------------------------- |
| staff  | `--model claude-opus-5-5`   | `-m gpt-6.1-sol -c model_reasoning_effort=high` | `-m grok-4.6 --effort xhigh`  |
| senior | `--model claude-sonnet-5-5` | `-m gpt-6-sol -c model_reasoning_effort=medium` | `-m grok-4.7 --effort medium` |
| mid    | `--model claude-haiku-5-5`  | `-m gpt-5.6-terra`                              | `-m grok-4.5 --effort medium` |
| junior | none                        | `-m gpt-5.6-luna`                               | none                          |

Alternative also rejected: list current ids (`~/.codex/models_cache.json`, `~/.grok/models_cache.json`), take the same level, tell the user. Other kinds: read `<kind> --help` and ask once for the levels.

## Session commands

Prompts sent to an idle agent to shrink or drop its context:

| Kind   | compact (keeps a summary) | reset (cold start) |
| ------ | ------------------------- | ------------------ |
| claude | `/compact`                | `/clear`           |
| codex  | `/compact`                | `/new`             |

Other kinds: find both in `<kind> --help` before relying on them; none exists, skip the compact and say so.

## Your own level

To run a partner at your level, find your level from your model in the main-pick table:

- **claude:** the model id in your system prompt.
- **codex:** `gpt-6-astra` staff, `gpt-6-luna` junior, `gpt-6.1-sol` senior unless the user said mid (the effort is not visible from inside).
- **grok:** `grok-4.7` staff, `grok-4.6` senior unless the user said mid, `grok-4.5` junior.

A model found only in the alternative table: ask the user once which level it stands for.
