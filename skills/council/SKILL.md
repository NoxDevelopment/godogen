# Council

A **decision skill**. Run a hard, open-ended call — a roadmap ordering, an engine
choice, a scope cut, a naming decision, a "should we even build this" — through a
**council of five independent advisors** who each analyze it from a different
angle, then peer-review each other **anonymously**, then a chairman synthesizes a
single verdict with the one next action. It surfaces consensus, exposes the
disagreements, and names the blind spots before you commit.

> **When a decision is genuinely two-sided and expensive to reverse, don't
> single-thread it through one train of thought.** Five independent passes catch
> the fatal flaw that one pass rationalizes away. This is our own build of the
> "LLM Council" pattern (method credit: Andrej Karpathy) — wired to *real*
> parallel sub-agents, not five voices role-played in one context.

## When to use it (and when NOT to)

**Use it for:** strategic/design forks with real trade-offs — "Godot vs Unity for
this template," "ship the board-game lane or the AI-DM lane next," "is Nox Loom's
worldbuilder trying to do too much," pricing, positioning, a risky architecture
bet, a naming decision, a pivot.

**Do NOT use it for** (it's overkill and slower):

- Factual lookups with one right answer ("what port is ComfyUI on")
- Mechanical work ("scaffold the template," "fix this test")
- Creative generation ("write the store copy") — generate, then *maybe* council
  the shortlist
- Anything where you already know the answer and just want a rubber stamp

If the question isn't a real fork, answer it directly. Don't convene the council.

## TL;DR

Preferred path — **real parallel council via the Workflow tool** (5 advisors +
5 anonymized reviewers + 1 chairman, all as independent sub-agents):

```
Workflow({ script: <the council script below>, args: { question: "…", context: "…" } })
```

No Workflow tool available? Fall back to **sequential `Agent` calls** (one per
advisor), then synthesize yourself. Quick/cheap call with low stakes? A
**single-context role-play** of the five seats is fine — but say which mode you
used so the confidence is legible.

## The five seats

Each advisor gets the question + context and **only their lens**. They do not see
each other's answers in round 1.

| Seat | Lens | Charged to ask |
|---|---|---|
| **The Designer** | Player experience, fun, game feel, genre literacy | Does this make the game *better to play*? What's the moment-to-moment? |
| **The Architect** | Tech feasibility on our stack (Godot-first, Dart companion core is consume-only, ComfyUI/ZIT, Studio Next.js/Prisma) | Can we build+maintain this without a mess? What's the real complexity cost? |
| **The Market** | Audience, scope realism, competition, monetization, indie constraints | Who's it for, does it beat the alternative, can a small studio actually ship it? |
| **The Red Team** | Adversarial. Attack the premise, steelman the *opposite*, find the fatal flaw | Why is this the wrong call? What breaks it? What are we not saying out loud? |
| **The Outsider** | First principles. Ignore convention, sunk cost, and how we do it today | If we started from zero today, would we build *this*? What's the obvious thing we're too close to see? |

## The protocol

1. **Scan for context first.** Before framing anything, read the relevant
   `CLAUDE.md`, `docs/PROGRESS.md`, `docs/ECOSYSTEM_*`, memory pointers, and any
   files the question names. A council fed no context produces confident noise.
2. **Round 1 — independent analysis.** Each of the five seats answers the
   question through its lens only. Concrete, opinionated, ~150–300 words. Ends
   with that seat's one-line recommendation.
3. **Round 2 — anonymized peer review.** Relabel the five answers A–E (shuffle so
   position ≠ author). Five reviewer passes each read all five and name: the
   strongest argument, the weakest/most-hand-wavy, and any blind spot shared
   across answers. Anonymity is the point — it kills deference to "the Architect
   said so."
4. **Round 3 — chairman synthesis.** One final pass produces the verdict (schema
   below). It weighs the peer review, not just round 1.

## The verdict (always this shape)

```
## Council verdict — <question>

**Recommendation:** <the call, stated plainly>
**Confidence:** <low | medium | high> — <why>

**Where they agreed:** <consensus zones>
**Where they split:** <the real disagreements, with which seat held which line>
**Blind spots they flagged:** <what the peer review surfaced>

**The one next action:** <single concrete thing to do next>
```

Report the verdict in chat as markdown. **Do not** generate HTML for it.

## Decision log (our convention)

When the council settles a decision that shapes the roadmap or architecture,
persist it as a lightweight ADR so future-you knows *why*:

```
docs/decisions/DECISION-<slug>.md
```

Include: the question, the date (ask the harness / use the known current date —
never fabricate one), the recommendation, the key disagreement, and the next
action. Cross-link it from `docs/PROGRESS.md` if it changes the plan. This is the
same docs-discipline we hold everywhere — a council call that changes course and
leaves no trace is a call we'll re-litigate in a month.

## The Workflow script (real parallel council)

Drop this into the `Workflow` tool. It runs the five advisors concurrently, does
one anonymized review round, and a chairman synthesis — genuine independent
sub-agents, so the passes can't contaminate each other.

```javascript
export const meta = {
  name: 'council',
  description: 'Five independent advisors analyze a decision, peer-review anonymously, chairman synthesizes',
  phases: [{ title: 'Advise' }, { title: 'Review' }, { title: 'Chair' }],
}

const q = args.question
const ctx = args.context ?? '(no extra context provided — scan the repo first)'
const SEATS = [
  { key: 'designer',  lens: 'player experience, fun, game feel, genre literacy' },
  { key: 'architect', lens: 'tech feasibility on a Godot-first / Dart-companion-core / ComfyUI-ZIT / Next.js stack; complexity and maintenance cost' },
  { key: 'market',    lens: 'audience, scope realism, competition, monetization, small-indie-studio constraints' },
  { key: 'redteam',   lens: 'adversarial — attack the premise, steelman the opposite, name the fatal flaw' },
  { key: 'outsider',  lens: 'first principles — ignore convention and sunk cost; design from zero' },
]

const VERDICT = {
  type: 'object',
  properties: {
    recommendation: { type: 'string' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    agreed: { type: 'string' },
    split: { type: 'string' },
    blindSpots: { type: 'string' },
    nextAction: { type: 'string' },
  },
  required: ['recommendation', 'confidence', 'agreed', 'split', 'blindSpots', 'nextAction'],
}

// Round 1 — five independent advisors, concurrent
phase('Advise')
const advice = await parallel(SEATS.map(s => () =>
  agent(
    `You are "${s.key}" on a decision council. Your lens ONLY: ${s.lens}.\n\n` +
    `QUESTION:\n${q}\n\nCONTEXT:\n${ctx}\n\n` +
    `Analyze in 150-300 words through your lens, concrete and opinionated. ` +
    `End with one line: "Recommendation: …". Do not hedge to neutrality.`,
    { label: `advise:${s.key}`, phase: 'Advise' }
  ).then(text => ({ seat: s.key, text }))
))
const valid = advice.filter(Boolean)

// Round 2 — anonymized peer review. Relabel A–E by index (deterministic, no RNG in scripts).
phase('Review')
const labeled = valid.map((a, i) => `--- Answer ${String.fromCharCode(65 + i)} ---\n${a.text}`).join('\n\n')
const reviews = await parallel(valid.map((_, i) => () =>
  agent(
    `Anonymous peer review of a decision council. The five answers below are ` +
    `unlabeled by author. Name (1) the single strongest argument across them, ` +
    `(2) the weakest / most hand-wavy, (3) any blind spot shared by most of them.\n\n${labeled}`,
    { label: `review:${i + 1}`, phase: 'Review' }
  )
))

// Round 3 — chairman synthesis
phase('Chair')
const verdict = await agent(
  `You are the council chairman. Synthesize a final verdict. Weigh the peer ` +
  `review, not just the raw advice.\n\nQUESTION:\n${q}\n\n` +
  `ADVISOR ANSWERS:\n${labeled}\n\nPEER REVIEW:\n${reviews.filter(Boolean).join('\n\n')}`,
  { label: 'chairman', phase: 'Chair', schema: VERDICT }
)
return { verdict, seatCount: valid.length }
```

Then format `verdict` into the standard verdict block above for the user, note
the mode ("real parallel council, 5 seats"), and — if it changed the plan — write
the decision log.

## House rules

- **Independence is the whole value.** If you role-play all five in one context,
  they'll converge on your prior. Prefer real sub-agents; when you can't, at least
  write each seat's answer fully *before* reading the next.
- **The Red Team is not optional.** The seat most likely to save you is the one
  arguing you're wrong. Never soften it.
- **Name the confidence.** "High — all five converged" and "low — the council
  split 3/2 on the core assumption" are different products. Say which.
- **Don't council to avoid deciding.** The output is a recommendation and one
  next action, not a menu. Land the plane.
