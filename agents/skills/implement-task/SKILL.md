---
name: implement-task
description: "Implement one development task end to end with minimal human input: read the task, implement, test, validate, collect evidence per acceptance criterion, and update status only as the project's workflow permits. Tracker-agnostic (markdown file, issue tracker, pasted text). Use when: implement task, implement this ticket, do this task autonomously, /implement-task. Not for a list of tasks: use multi-task (parallel, dependency-aware, branches left unmerged) or pingpong (sequential, each task merged)."
metadata:
  short-description: Autonomous single-task implementation with evidence-gated completion
---

# Implement task

One task, finished and proven. "Done" means every required acceptance criterion has evidence, not merely that the code exists.

**Announce at start:** "I'm using the implement-task skill."

## Invocation

```text
/implement-task <task>
```

`<task>` identifies the work: an issue ID or URL accessible through project tooling, a Markdown file, a checklist item, or pasted text.

Unreadable or ambiguous source: stop and ask.

## 1. Prepare

1. Read project instructions (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, whichever exist). They override this skill.
2. Read the task in full: acceptance criteria, dependencies, constraints, linked material.
3. Every listed criterion is mandatory unless explicitly marked optional.
4. No acceptance criteria: derive them from the task, record them as assumed, and proceed only if unambiguous. Otherwise stop and ask.
5. Run `git status` and `git stash list`. Record pre-existing changes; never discard or overwrite them.
6. Already in a worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`): work on its current branch and create nothing. It holds uncommitted changes from other work: stop and ask. Otherwise, if the project requires a branch or worktree per task, create it before editing.
7. Run focused baseline checks covering the affected area. Record existing failures. Run the full suite only if required or inexpensive.

Do not edit code until the scope is clear.

## 2. Plan

- Read the affected components and trace the relevant behavior end to end.
- Reuse existing patterns, helpers and test infrastructure.
- Select the simplest implementation satisfying every mandatory criterion.
- Do not expand scope.

Write `plan.md` in the evidence directory (step 6), approximately 5–10 lines:

- Files expected to change.
- New or changed public signatures, without implementation bodies.
- Each criterion and its proof: test, command output, screenshot or inspection.
- Criteria requiring human validation.
- Least confident decisions.

A least confident decision would change the design if wrong: have one analysis subagent challenge it before you edit. Give it the plan and relevant code, not your reasoning. No such decision: skip the challenge.

If subagents are unavailable, record that limitation and continue.

## 3. Prove the gap

For every criterion with an automated proof, write the check first and run it.

It must fail for the reason the criterion names. Save the failure as **before evidence**.

**A check that passes before any change proves nothing. Fix the check, not the criterion.**

For visual changes, capture before screenshots and identify the expected visual difference. Use Storybook or automated screenshots where available.

For configuration or documentation changes, capture the previous state and define a verifiable expected result.

Do not manufacture failing tests for criteria better demonstrated through screenshots, inspection or command output.

## 4. Implement

- Implement every mandatory criterion.
- Preserve existing behavior and public interfaces unless the task requires changes.
- Write the minimum code that turns each failing check green.
- Add or update relevant tests.
- No unrelated refactors. Record adjacent bugs or improvements as follow-ups.
- Subagents may perform independent analysis, implementation or testing. The primary agent owns integration and validation.
- Coordinate parallel work to prevent conflicting file edits.

### Failure recovery

Classify every failure before acting on it:

- **Implementation defect:** the code is wrong. Fix the code.
- **Test defect:** concrete evidence of an error in the test, fixture, assertion or harness (obsolete selector, invalid fixture, broken synchronization, contradiction with the criterion's text). Record the evidence, then fix the check without weakening what it asserts about the criterion. No such evidence: the failure stays open as a possible implementation defect; change neither code nor test on a guess.
- **Environmental:** infrastructure, not code (service down, port taken, resource locked, network). Never change code for it. Fix the environment when it is within reach; otherwise report the blocker.

Retry budget: after two attempts on the same failure without progress, stop. Progress means the failure changed or narrowed. A further attempt needs a new hypothesis and a check that confirms or refutes it; record both. No new hypothesis: stop and report the blocker.

The task needs files or behavior the plan did not name: update `plan.md` when the change stays inside the acceptance criteria. Otherwise stop and report the scope gap.

A check added after implementation needs a mutation check: temporarily introduce the fault it covers, confirm the intended assertion fails, restore the code and confirm it passes.

### Local commits

Local commits are permitted as checkpoints after each criterion's check turns green.

- Follow project commit conventions.
- Commit only changes belonging to the task.
- Do not include unrelated pre-existing modifications.
- Do not commit generated evidence unless the project requires it.
- Do not amend or rewrite existing commits.

Never push, merge or deploy without explicit authorization.

## 5. Validate

Run the checks defined by the project:

- Unit and integration tests.
- Lint, typecheck and build.
- Task-specific verification.
- Storybook, visual regression and screenshot tests.
- Accessibility and responsive checks for affected UI.

**Validation depth follows the blast radius of the change.** Shared components and critical behavior require broader regression coverage than isolated changes.

Fix failures introduced by the task.

**Evidence reuse:** a passing check stays valid until something it depends on changes: the covered code, dependencies, configuration, environment or the check itself. Rerun only checks invalidated that way. Lint, typecheck and build, where the project has them, always run on the final state.

Compare against the baseline:

- **Introduced:** caused by the implementation; fix.
- **Pre-existing:** present before implementation; report.
- **Uncertain:** origin not demonstrated; investigate and keep open if acceptance is affected.

A pre-existing failure does not automatically block completion, but it cannot be used to excuse an unverified criterion.

Have one reviewer subagent inspect the complete diff with the task, acceptance criteria, project instructions and test evidence. It reports unmet criteria, regressions, evidence that does not support its criterion, and out-of-scope changes.

The implementer fixes confirmed findings and reruns the checks those fixes affect (evidence reuse, above). Record unresolved findings as residual risks.

If reviewer subagents are unavailable, perform self-review and report the limitation.

**Never weaken tests, skip mandatory checks, loosen criteria, alter baseline evidence or hide failures to obtain a positive result.**

## 6. Collect evidence

For every mandatory criterion record:

- **Criterion:** exact text from the task.
- **Implementation:** relevant `file:line`.
- **Before:** failing check, screenshot, previous state or `N/A` with reason.
- **After:** passing check or demonstrated expected result.
- **Artifact:** screenshot, log or output path, if one exists.

Evidence may be automated, visual or inspected. Match the proof to the criterion: a unit test does not demonstrate visual quality; a screenshot does not demonstrate business logic.

Store evidence where the project specifies.

Otherwise use:

```text
<repo-root>/.evidence/<task-slug>/
```

Do not commit the directory by default. Keep it out of Git locally, never through `.gitignore`:

```bash
ex="$(git rev-parse --git-common-dir)/info/exclude"; grep -qx '.evidence/' "$ex" || echo '.evidence/' >> "$ex"
```

A criterion without sufficient proof remains open.

## 7. Close

Implementation is validated only when:

1. Every mandatory criterion is implemented.
2. Every mandatory criterion has sufficient evidence.
3. Required checks pass, or baseline failures are demonstrated not to invalidate acceptance.
4. No unresolved blocker prevents completion.

**Implementation completion and tracker workflow status are separate decisions.**

The invoker says it owns status (for example `multi-task`): do not update the task source or tracker. Report only.

### Markdown

- Flip `- [ ]` to `- [x]` for each demonstrated criterion.
- Leave unproven criteria unchecked.
- Update the overall task status only when the project's workflow permits it.
- If completion requires merge or approval, leave the overall status pending.

### Issue tracker

- The work is reviewable (pushed branch or open PR): post the evidence as a comment when write access exists, and move the issue to the project's state for finished, unmerged work (for example, `In Review`).
- Not reviewable (local branch only), or no such state exists: leave the issue unchanged and report why. Local evidence paths mean nothing to other readers.
- Never move an issue to a state requiring merge, release or approval before that condition is satisfied.

### Pasted text

Report the result. Do not invent an external tracker.

### Incomplete work

Leave the task open and record exactly what remains.

Automated proof exists: do not request manual testing.

Human validation unavoidable: provide minimal steps and expected results.

## 8. Limits

- One task per invocation. Never start another automatically.
- Never modify acceptance criteria to make the task pass.

## 9. Final report

1. **State:** implementation validated, pending or blocked; tracker state separately. Blocked: name the proof that is blocked and the objective condition to continue (for example `staging DB reachable`, `emulator lock free`).
2. **Changes:** files modified and purpose.
3. **Checks:** commands, results and baseline comparison.
4. **Evidence:** criterion, implementation, before, after and artifact.
5. **Failures:** introduced, pre-existing or uncertain.
6. **Residual risks and follow-ups:** unresolved issues and out-of-scope findings.
7. **Human validation:** only checks that cannot be automated.

Report actual results, not intentions.

**Never declare completion while a mandatory criterion remains unproven.**
