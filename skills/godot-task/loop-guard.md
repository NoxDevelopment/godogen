# Loop guard — runaway-iteration limits for the task executor

The implement → screenshot → verify → VQA loop in `SKILL.md` has no fixed iteration cap. That's intentional — most tasks converge in 2-4 iterations and a hard cap would break the cases that legitimately need more. But "no cap" can degrade into spiraling without progress.

This file gives the executor explicit guards to recognize when a loop has stopped converging and break out before burning context.

## Routing

- Inside the godot-task loop → re-read this between iteration N and N+1 if N ≥ 4.
- Pre-emptively cite this when reporting failure to the orchestrator.
- Doesn't apply to single-pass tasks (no loop) — only when iterating.

## The signals

A loop is **converging** when:

- Each iteration's failure is different from the previous.
- The set of remaining issues is shrinking.
- Screenshots are visibly closer to the **Verify** target.

A loop is **stuck** when:

- The same kind of fix keeps appearing — "I added the missing import", three iterations in a row.
- The error message is identical (or near-identical) two iterations apart.
- Screenshots aren't getting closer to the goal; just different-shaped wrong.
- The agent is undoing prior fixes to try a different approach to the same root cause.

## Hard ceilings

| Iteration | Action |
|-----------|--------|
| 1-3 | Iterate freely. Most tasks land here. |
| 4 | Re-read this file. If converging, continue. If stuck, plan a different approach (different scaffold, simpler test, defer the task). |
| 5-6 | Continue only if iteration 4's plan is producing measurable progress. |
| 7+ | **Stop.** Report to the orchestrator with the full failure context. The orchestrator decides whether to replan, regenerate assets, or escalate to the user. |

These aren't arbitrary — they're chosen so context burn stays sane and the orchestrator gets called before the task has dragged on past where a fresh perspective helps.

## When to stop early (before iteration 7)

Even within the soft window, stop and report if:

- An external dependency is missing (Godot binary, asset, plugin) — no amount of code rewriting fixes a missing dependency.
- The architecture in STRUCTURE.md is wrong for the task — fix the architecture upstream, not the leaf.
- A new requirement emerged from the task that wasn't in **Requirements** — orchestrator needs to amend PLAN.md.
- The verify criteria are ambiguous — rather than guess at success, ask the orchestrator to clarify.

## What to report on stop

```
**Stopped after N iterations.**

Last attempt: <summary of what was tried>
Failure mode: <what's still wrong — be specific, name files/symbols>
Root cause hypothesis: <best guess>
Asks of the orchestrator:
- replan / regenerate assets / clarify requirement / accept partial / escalate to user
```

Don't dress this up. Don't apologize. The orchestrator is a colleague debugging with you.

## DO NOT

- Loop past 7 iterations without a fresh signal from the orchestrator or user.
- Loop while editing the same file 6 times in a row — that's a sign you're chasing symptoms.
- Mark a task `done (partial)` to escape the loop. Partial-done is a real status (some Verify criteria met) — don't use it as a graceful exit when you're really stuck.
- Reset the iteration counter by calling the loop "phase 2" — guards apply across nominal phase boundaries.

## Red flags

- "I'll just try one more thing" three times in a row.
- Each iteration adds a new fallback or try/except block. The bug isn't being fixed; it's being hidden.
- Screenshots stop being inspected — you're iterating on log output but not visually verifying.
- The user has gone idle waiting for progress; a stuck loop is also a UX failure.

## Healthy iteration patterns

Compare these to the red flags:

- Each iteration's diff is small and targeted.
- Screenshot comments name what changed and what's still wrong, specifically.
- Failed attempts get summarized in MEMORY.md — the next task benefits.
- Iteration 5-6 is rare; when it happens, the fix is novel (e.g., a Godot quirk discovered).

## Calibration

If you find yourself hitting 5+ iterations regularly across many tasks, the *plan* is wrong, not the executor. Surface it: tasks are too coarse, requirements are vague, or scaffold is missing prerequisites. The orchestrator should split tasks finer.
