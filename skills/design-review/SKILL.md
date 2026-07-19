# Design Review

A **UI/UX quality gate** for everything with a surface — the Studio web app
(Next.js/React) *and* in-game UI (Godot `Control` nodes). It turns "looks fine to
me" into a repeatable review against our own design law: the right context up
front, discipline-by-discipline critique, a hard pre-ship audit, and a
reality-test with hostile data. Use it before you call a screen done.

> **Taste isn't a checklist, but the absence of a checklist is how taste rots
> into drift.** This skill is our own build of a phase-based design methodology
> (informed by public practice — Bakaus/Impeccable's phase loop, Refactoring UI,
> WCAG). No third-party tooling or proprietary content is used; every rule below
> is grounded in *our* design law, [`docs/design/ui-ux-map.md`](../../../Noxdev-Studio/docs/design/ui-ux-map.md).

## Our design law is the source of truth

Before reviewing anything, load the context that already exists — do not invent
new aesthetics:

- **Studio web UI** → `Noxdev-Studio/docs/design/ui-ux-map.md`. The tokens, the
  Nox voice, the five screen patterns, the "what NOT to do" list (§12), the
  accessibility baseline (§9). This is our `PRODUCT.md` + `DESIGN.md` in one.
- **In-game UI** → the `ui-theme`, `ui-screens`, `ui-elements`, and `game-feel`
  skills, plus the game's own `style-anchor`. Game UI answers to the game's art
  direction, not the Studio palette.
- **Accessibility** → the `accessibility` skill owns the WCAG mechanics; this
  skill just makes sure the gate is actually run.

One line, memorized: **"endearing, not an eyesore. Personality as the accent,
restraint as the default."**

## Two modes — decide which you're reviewing

The audit weights differently depending on the work. Name the mode first.

| Mode | What it is | Optimize for |
|---|---|---|
| **Product** | Studio app screens, in-game HUD/menus, tools — repeatable components, real data, many states | Density, semantic states, consistency, keyboard/a11y, information hierarchy. *Distinctiveness is secondary to legibility.* |
| **Brand** | Marketing surfaces, title screens, store pages, key art, the wordmark moment | Committed type, a distinctive palette, image-led composition, one memorable idea. *Consistency is secondary to impact* — but never breaks a11y. |

Reviewing a Studio settings form as if it were a title screen (or vice-versa) is
the most common category error. Pick the lane.

## The loop — Shape → Craft → Polish → Maintain

Not every review runs all four; match the phase to where the work is.

### 1. Shape (before pixels)
- Who is this for, what's the one job of this screen, what does "done" look like?
- Is there a **hi-fi reference** — a concrete destination — or just a prose brief?
  Prefer the reference. "Like the Concepts board but denser" beats three
  paragraphs.
- Which of the **five screen patterns** (Dashboard / Inbox / Board / Library /
  Form-Doc) does this reuse? If it's a sixth pattern, justify it — 47 modules stay
  sane precisely because they reuse five shapes.

### 2. Craft (discipline by discipline)
Review these as separate passes — a screen can nail color and butcher spacing.

- **Typography** — two type *personalities* max (§2). Base 14/20, scale is
  8px-derived. No third display face sneaking in.
- **Layout & spacing** — everything on the 8px grid. Reading width ≤72ch on
  content surfaces; dense rows (24–32px) on data surfaces. Alignment is
  deliberate, not accidental.
- **Color** — dark-first tokens only (`--color-bg → surface → surface-2`,
  borders carry weight not shadows). No gradients, glows, neon, or "purple fog"
  (§12). Warm accent used *sparingly*.
- **Motion** — 120–180ms ease-out, fade+slide. The 200ms save-flash is the *only*
  delight animation. Never bouncy, never scroll-jacked, never auto-carousel.
- **Voice** — empty states, errors, and confirmations in the Nox voice (§1);
  form labels and primary UI copy stay plain. "Saved." not "Operation completed
  successfully."

### 3. Polish (the pre-ship audit — the hard gate)
Run **every** dimension. A miss here is a ship-blocker, not a nit.

- **Accessibility** — WCAG 2.2 AA contrast on every token pairing; focus ring on
  every interactive element; skip links; ARIA landmarks/roles/live-regions;
  icon-only buttons have `aria-label`; `prefers-reduced-motion` disables the flash
  and pane motion; full keyboard path. *(Delegate the mechanics to the
  `accessibility` skill; this gate just refuses to pass without it.)*
- **Responsive / adaptive** — from a narrow pane to a wide monitor; the Studio is
  used on a second monitor, so it must survive odd widths. Game UI: test target
  aspect ratios + safe areas.
- **Theming** — every color comes from a token; nothing hard-codes a hex. Dark
  theme is nailed before any light-theme work begins (§12).
- **States** — loading, empty, error, and the **save-moment** all designed. Empty
  state uses the shared template (§10), not "No items."
- **Provenance** — any AI-generated artifact shows model · prompt · seed · LoRA ·
  timestamp · backend (§8.4). Required for Steam AI disclosure and for
  regenerating months later. No AI output without provenance *and* undo.
- **Anti-patterns** — walk the §12 list explicitly: no stacking toasts, no
  hover-only destructive actions, no modal for a flow that deserves a full
  surface, no second display font, no scroll-jacking.
- **No placeholder/stand-in art** — refuse any screen shipping ColorRect fills,
  blocky/"good enough" stand-ins, or un-restyled kit grabs as final art. Real
  assets come via the reuse ladder (`skills/asset-reuse`); this is a ship-blocker
  per `skills/parity-build/STANDARDS.md` (Art & assets).

### 4. Maintain (catch drift before it sets)
- Did this screen invent a spacing value, a one-off color, a bespoke component
  that duplicates an existing one? Consolidate it back to the system *now* — drift
  is cheapest to fix the day it's introduced.
- If a genuinely new, good pattern emerged, promote it into `ui-ux-map.md` (or the
  relevant `ui-*` skill) so it becomes reusable law, not a snowflake.

## Reality-test — attack it with hostile data

Pretty on the happy path is not done. Before passing, throw the worst realistic
inputs at it:

- **Long text** — a 60-character project name, a German label ~2.3× the English,
  a Japanese string with no word breaks. Does it truncate gracefully or explode
  the layout?
- **Big numbers** — `$1,234,567,890`, a 6-digit task count, 999+ badges. Tabular
  nums, no overflow.
- **Zero / one / many** — the empty state, exactly one item, and 500 items
  (virtualize or paginate — don't render 2,520 cells raw; see §7.5).
- **Broken backends** — ComfyUI/Kokoro/Orpheus/Ollama offline. Health dots go
  grey, errors are the helpful Nox kind with a *retry that retries*, nothing
  spins forever.
- **Reduced motion + screen reader** — flip both on and walk the primary flow.
- **Slow/failed AI** — the `✨` inline action mid-stream, then failing. Undo still
  restores instantly?

If any of these breaks it, it isn't done — regardless of how good the happy path
looks.

## Output of a review

Report as markdown (never HTML for a review):

```
## Design review — <screen/component> · mode: <product|brand> · phase: <…>

**Verdict:** <ship | ship with fixes | not yet>

**Craft:**   <per-discipline notes — type / layout / color / motion / voice>
**Polish gate:** <a11y · responsive · theming · states · provenance · anti-patterns — pass/fail each>
**Reality-test:** <which hostile inputs passed / which broke>

**Blockers:** <ship-stoppers, if any>
**Nits:** <optional polish>
**One next fix:** <the highest-leverage single change>
```

## House rules

- **Grounded, not generic.** Cite our tokens/§-sections and the game's
  style-anchor — never hand out generic "add more whitespace" advice that ignores
  our system.
- **The polish gate is pass/fail, not advisory.** Accessibility and provenance
  are non-negotiable — "you cannot ship an Accessibility Audit module in an
  inaccessible tool."
- **One theme nailed beats two half-done.** Don't greenlight light-theme work
  while the dark system has gaps.
- **Reviewer ≠ redesigner.** Point to the highest-leverage fix and the law it
  serves; don't silently reskin the whole screen to your own taste.
