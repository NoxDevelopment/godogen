---
name: visual-judge
description: The visual parity acceptance gate — an adversarial, multi-sample, side-by-side-vs-the-bar verdict for ANY rendered visual artifact (map, game screen, UI, key art, 3D render, sprite/stamp set). Forces looking with your own eyes across multiple samples at the competitor's scale, refuses to trust a generator's self-report or green tests, and returns SHIP / ITERATE / REJECT with specific ranked gaps. Use before any visual artifact earns "done", "clears the bar", ships to the showcase, or gets swapped into a template.
---

# Visual Judge — you do not get to grade your own homework

**The failure mode this skill exists to kill:** looking at *one* generator-produced hero render, letting the generator's own favorable write-up frame it, calling it "a real jump / clears the bar," and shipping it — while green tests (`tsc 0 / N pass`) stand in for visual quality. That is grading the homework by reading the student's cover letter. This skill replaces it with a repeatable, adversarial gate.

> **A verdict is evidence, not vibes.** Every SHIP must be defensible with: the samples you looked at, the competitor you compared against at the same scale, and the specific reasons it clears the bar. If you can't produce that, the verdict is ITERATE.

## When to run it (mandatory gates)
Run before ANY of these:
- Declaring a visual artifact "done" / "clears the bar" / "at parity."
- Shipping a render to the showcase or a store/marketing surface.
- Swapping a generated asset/render into a template or the Studio.
- Accepting an image/asset agent's output as final.

This is the visual sibling of [`parity-build/STANDARDS.md`](../parity-build/STANDARDS.md) (which gates whole games). Reuse it inside `parity-build`, `godogen`, `image-pipeline`, `scene-art`, `cartography`, and any template's art pass.

## How it differs from the neighbors (don't duplicate — compose)
- **[design-review](../design-review/SKILL.md)** judges a surface against *our internal design law* (tokens, screen patterns, a11y). Visual-judge judges against an *external competitor/reference bar* and enforces the anti-self-deception protocol. Run design-review for "is this on-brand + usable"; run visual-judge for "does this beat the competitor and is the evidence real."
- **[style-anchor](../style-anchor/SKILL.md)** asks "does this asset match `reference.png`?" (cohesion). Visual-judge asks "is it good enough vs the bar, proven across samples?" (quality + evidence).
- **[council](../council/SKILL.md)** is the parallel-advisor *engine* — visual-judge's panel mode reuses it: independent critics, anonymous peer review, chairman synthesis, wired to real sub-agents.
- **[playtest](../playtest/SKILL.md)** captures the screenshots; visual-judge decides if they pass.

## The Five Anti-Self-Deception Rules (non-negotiable)
1. **Look with your own eyes.** `Read` the actual image(s). Never issue a verdict from a text description, a filename, or the agent's report. If you have not viewed the pixels, you have no verdict.
2. **Multiple samples, never one hero shot.** Generators look fine on a lucky seed/state and fall apart elsewhere. Require **≥3 samples** (seeds for procedural output; distinct states/screens for UI; multiple angles/prompts for art). One-of is REJECT by default.
3. **Side-by-side, same scale, against the real bar.** Put the artifact next to the actual competitor/reference exemplar at the *same size and zoom*. "It looks good" in isolation is not a comparison. Name the bar (Wonderdraft, Inkarnate, the reference screen, the AAA exemplar).
4. **Real context, not just the bake.** View it where the user will (in the live editor, at the user's zoom, on the target screen), not only as an isolated export. A render that only works cropped-and-baked hasn't shipped.
5. **Green ≠ good.** `tsc`, unit tests, lint, and "no errors" prove the code runs, not that the output looks right. They are necessary, never sufficient. The generator's self-graded before/after is a claim to verify, not evidence to repeat.

## The rubric (score each 0–3; default to the lower score when unsure)
Generic dimensions — a domain skill (e.g. [cartography CRITIQUE_CHECKLIST](../cartography/CRITIQUE_CHECKLIST.md)) adds its own on top.

| # | Dimension | 0 (reject) → 3 (exceeds bar) |
|---|---|---|
| 1 | **Idiom coherence** | One consistent visual language/palette/line-weight everywhere → vs. multiple styles fighting. |
| 2 | **Composition & hierarchy** | Clear focal order, the eye knows what matters → vs. flat, everything-equal noise. |
| 3 | **Restraint / negative space** | Intentional emptiness, breathing room → vs. wall-to-wall carpet ("density ≠ detail"). |
| 4 | **Craft detail** | Edges, shadows, texture, finish hold up at 100% → vs. amateur/placeholder tells. |
| 5 | **Believability / logic** | The content makes sense (geography, anatomy, lighting, physics) → vs. random/impossible. |
| 6 | **Parity vs the named bar** | Matches or beats the competitor exemplar side-by-side → vs. visibly behind. |
| 7 | **Robustness across samples** | Holds up across ≥3 seeds/states → vs. one lucky sample, falls apart otherwise. |
| 8 | **Context fit** | Works in the live/target context at real zoom → vs. only as a cropped bake. |

**Verdict thresholds:** any dimension at **0 → REJECT**. All ≥2 and parity (#6) ≥2 across all samples → **SHIP**. Otherwise → **ITERATE** with the ranked gaps. When genuinely uncertain, ITERATE — never SHIP on a maybe.

## Two modes

### Solo mode (fast gate, single artifact)
You (the lead) run the Five Rules + rubric yourself: gather ≥3 samples, `Read` them, `Read` the competitor exemplar, score, write the verdict + ranked gaps. Cheap; use for routine passes.

### Panel mode (high-stakes / disputed / "is this really parity")
Reuse the [council](../council/SKILL.md) engine: dispatch **N independent visual critics** as real sub-agents, each given the same samples + competitor exemplar but a **distinct lens** (idiom-coherence, composition/hierarchy, restraint, craft-detail, vs-competitor-parity). Each is instructed to **try to fail the artifact** (adversarial — default to the harsher score when torn). Then anonymous peer review, then a chairman synthesizes one verdict + the single most important fix. Majority REJECT/ITERATE on any critical dimension blocks SHIP. Use for showcase/store art, template sign-off art, and anything you're tempted to call "clears the bar."

## Output format (always)
```
VERDICT: SHIP | ITERATE | REJECT
Bar compared against: <competitor/reference exemplar + where it is>
Samples viewed: <n> (<seeds/states>)   Context checked: <live editor / target screen / bake-only>
Scores: idiom _/3  comp _/3  restraint _/3  craft _/3  believ _/3  parity _/3  robust _/3  context _/3
Top gaps (ranked, specific, grounded in what you saw):
  1. ...
  2. ...
Why this verdict (defensible in one paragraph): ...
```

## The lead's standing rule
No visual artifact this project produces earns "done" on the generator's word. It earns it by passing this gate. If a past verdict was issued without the Five Rules (as the P9 map render was), it is not a verdict — re-run the gate.
