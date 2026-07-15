# Skill Router

A **preflight for the skill registry.** We have ~40 skills and the number keeps
growing. Reading all of them to decide which one fits a task is wasteful, and
*not* reading them means reinventing what a skill already does. The router fixes
both: a compact auto-generated catalog ([`INDEX.md`](./INDEX.md)) you scan first,
then load only the 1–5 SKILL.md files that actually apply.

> **Discover before you build.** Most "I'll just write a quick helper" moments are
> a skill you forgot exists. This is our own lean build of overdrive's skill-router
> idea — **no npx installer, no shell hooks rewriting your config, no downloaded
> binaries.** It's an index plus a reading habit: transparent, auditable, and
> entirely inside this repo.

## TL;DR

On any **non-trivial** task, before diving in:

1. Read [`INDEX.md`](./INDEX.md) — every skill, its domains, and a one-line
   purpose. One file, ~40 rows.
2. Pick the **1–5** skills whose domain + purpose match the task.
3. Read only those `../<skill>/SKILL.md` files. Skip the rest.
4. If nothing fits, that's a real signal — build it (and it becomes a new skill).

Regenerate the catalog whenever a skill is added, removed, or its opening lines
change:

```bash
python skill-router/tools/router_index.py          # rewrites INDEX.md
python skill-router/tools/router_index.py --print   # also dumps to stdout
```

## When to route (and when not to)

**Route** on non-trivial requests that could touch a specialized area: "make this
template multiplayer" (→ `netcode`), "the pixel art looks fake" (→ `pixel-perfect`,
`style-anchor`), "review this screen" (→ `design-review`, `accessibility`), "should
we ship X or Y next" (→ `council`), "generate a character's sprites"
(→ `character-sheet`, `image-pipeline`, `style-anchor`).

**Skip the router** for the trivially obvious — a one-line edit, a file read, a
task where the skill is already named and open. The router is a cheap filter, not
a toll booth; don't perform it for its own sake.

## How selection works

The catalog tags each skill with coarse **domains** (`art/2d`, `art/3d`,
`animation`, `audio`, `ui/ux`, `narrative`, `gameplay`, `engine`, `pipeline`,
`meta/process`). Match the task's shape to domains first, then read the one-line
purpose to disambiguate within a domain. Example:

| Task | Domains | Candidate skills to open |
|---|---|---|
| "Add hit-stop and screen shake" | gameplay, ui/ux | `game-feel` |
| "Forest clearing scene, runnable" | art/3d, engine | `scene-populate`, `scene-art`, `asset-reuse` |
| "Convert this Ink dialogue for Godot" | narrative | `narrative`, `if-engine` |
| "Is our worldbuilder too broad?" | meta/process | `council` |
| "Pre-ship check on the HUD" | ui/ux | `design-review`, `accessibility`, `ui-theme` |
| "Batch of 50 assets, don't half-fail" | pipeline | `provider-preflight`, `asset-manifest` |

Prefer **fewer, more-specific** skills. Loading five when two apply reintroduces
the context cost the router exists to avoid.

## Why ours, not theirs

overdrive is Apache-2.0 and its router idea is genuinely good — but installing it
means running `npx`, letting shell scripts rewrite the agent config, and pulling
160 third-party skills (plus optional binary downloads and browser automation)
from a non-US maintainer. Per our "vet, then build our own" rule, we took the
*idea* and dropped the attack surface:

- **No installer.** The catalog is a committed markdown file in this repo.
- **No third-party skills auto-imported.** Every skill in the index is one we
  wrote and can read end-to-end.
- **No hidden state.** Regeneration is one deterministic Python script, stdlib
  only, no network.

### Capability gaps worth noting (not built — your call)

overdrive's 160-skill catalog spans a few domains we don't cover yet. If any are
worth a clean-room build later, they're candidates — **we'd author our own, not
import theirs**:

- `security-review` / dependency-audit passes for shipped code
- `seo` + store-listing optimization (adjacent to our Publishing modules)
- `prompt-master` — prompt-quality linting for our ComfyUI/LLM prompt library
- `react-doctor` — Studio-specific React/Next perf + correctness review

None are urgent; flagged so the map is honest about what we chose not to adopt.

## House rules

- **The index is generated — never hand-edit `INDEX.md`.** Reword the skill's own
  SKILL.md opening, then re-run the script.
- **Re-run after every skill change** so the catalog doesn't drift from reality.
- **A no-match is data.** If the router finds nothing for a recurring task, that's
  the strongest signal to write a new skill — don't keep solving it ad hoc.
