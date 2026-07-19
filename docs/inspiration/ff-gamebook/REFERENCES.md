# ff-gamebook — References & Build Notes

Compiled 2026-07-19. Three parts:
- **(A)** Reference GDDs / design writing for Fighting-Fantasy-style gamebooks.
- **(B)** Where/how to register these docs into the Nox Dev Studio web app.
- **(C)** The fantasy-illustrated art-style LoRA + how our image pipeline loads it.

---

## (A) Reference GDDs, design breakdowns, dev talks

Real, publicly available documents relevant to Fighting-Fantasy / choose-your-own-adventure /
branching-narrative RPG / interactive-fiction / digital-tabletop design. Every URL below was
verified live during research (the one exception is flagged).

### ink scripting language (inkle) — core narrative tech
1. **ink — inkle's narrative scripting language** — https://www.inklestudios.com/ink/
   Landing page for inkle's open-source branching-narrative language and the Inky editor.
   *Relevance:* the de-facto tool for choice-based prose games; strong candidate for authoring our branching passages + combat text.
2. **Writing with ink (official manual)** — https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md
   Full language reference: knots, diverts, weave, variables/logic, conditionals, functions, lists, tunnels, threads.
   *Relevance:* maps directly onto gamebook needs — stat tracking (SKILL/STAMINA/LUCK), conditional sections, paragraph-number flow.
3. **ink source + "Running Your ink" integration docs** — https://github.com/inkle/ink
   Runtime and C#/Unity integration docs.
   *Relevance:* wiring ink into an engine, plus how session state persists (save/load, multiplayer sync).

### inkle design talks & postmortems (Sorcery!, 80 Days, Heaven's Vault)
4. **Jon Ingold — "Narrative Sorcery: Coherent Storytelling in an Open World" (GDC 2017)** — https://archive.org/details/narrative-sorcery-coherent-storytelling-in-an-open-world (video mirror: https://www.youtube.com/watch?v=HZft_U4Fc-U)
   How Sorcery! grew from a linear FF-style gamebook into a persistent open story via "defensive logic."
   *Relevance:* keeping branching narrative coherent regardless of path order — core to our build.
5. **"Ink: The Narrative Scripting Language Behind '80 Days' and 'Sorcery!'" (GDC Vault)** — https://gdcvault.com/play/1023221/Ink-The-Narrative-Scripting-Language
   Ingold/Humfrey on the language design behind their shipped gamebook-lineage titles.
   *Relevance:* rationale for the tooling we'd adopt.
6. **"80 DAYS Post-mortem: Letting the Game Tell the Story" (GDC Vault)** — https://gdcvault.com/play/1021666/80-DAYS-Post-mortem-Letting
   Blending systemic (board-game/resource) mechanics with adaptive narrative.
   *Relevance:* the same tension we have between dice/stat combat and branching prose.
7. **"Authored embellishments to procedural narrative" (Heaven's Vault, Game Developer)** — https://www.gamedeveloper.com/design/authored-embellishments-to-procedural-narrative
   inkle's "cupcake" method (authored icing over procedural sponge) + tunnels/threads for independently-written conversation packets.
   *Relevance:* reusable encounter content, and multiplayer where content is injected ad hoc.

### Tin Man Games — digital Fighting Fantasy gamebook practice
8. **"How Tin Man Games resurrected and reimagined adventure gamebooks" (Game Developer)** — https://www.gamedeveloper.com/design/how-tin-man-games-resurrected-and-reimagined-adventure-gamebooks
   Their Gamebook Adventures Engine philosophy: dice-roll combat, automated skill tracking, page-turn/paperback authenticity.
   *Relevance:* closest real-world precedent to exactly what we're building (they held the FF digital license).
9. **Tin Man Games developer blog** — https://tinmangames.com.au/blog/?tag=gamebook-adventures
   Ongoing dev posts on their engine, UI conventions (e.g. the comic-layout experiment in *Appointment with FEAR*), adaptation choices.
   *Relevance:* practical UI/UX conventions for a digital gamebook.

### Fighting Fantasy rules system (SKILL / STAMINA / LUCK)
10. **Titannica FF Wiki — Game System** — https://fightingfantasy.fandom.com/wiki/Game_System
    Canonical attribute generation (SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6), the 2d6+SKILL Attack Strength combat loop, Testing Luck, provisions.
    *Relevance:* our combat-math spec baseline (primary FF-rules citation).
11. **Fighting Fantasy Project — Rules** — http://www.ffproject.com/rules.htm
    Long-running fan reference reproducing the full ruleset.
    *Relevance:* secondary. NOTE: site is live but currently serves an **expired TLS certificate** — cite the Titannica wiki as primary.
12. **Advanced Fighting Fantasy (Wikipedia)** — https://en.wikipedia.org/wiki/Advanced_Fighting_Fantasy
    Overview of the tabletop RPG built on FF (Special Skills, no classes/levels), 2nd ed. by Graham Bottley.
    *Relevance:* expanding the gamebook stat model toward richer RPG mechanics.
13. **Advanced Fighting Fantasy — Arion Games (publisher)** — https://store.arion-games.com/Advanced_Fighting_Fantasy/cat2182565_1992412.aspx
    Current official publisher; core rulebook + Adventure Creation System.
    *Relevance:* authoring branching adventures within FF rules.

### Interactive fiction / branching-narrative craft
14. **Emily Short — "Storylets: You Want Them"** — https://emshort.blog/2019/11/29/storylets-you-want-them/
    Defines storylets (content + prerequisites + world-state effects) reproducing gauntlet/branch-and-bottleneck/sorting-hat structures robustly.
    *Relevance:* best architecture model for content that scales and supports multiplayer/DLC.
15. **Emily Short — "Beyond Branching: Quality-Based, Salience-Based, and Waypoint Narrative Structures"** — https://emshort.blog/2016/04/12/beyond-branching-quality-based-and-salience-based-narrative-structures/
    Taxonomy of non-linear structures beyond pure branching.
    *Relevance:* choose the right structure per section; avoid combinatorial explosion.
16. **Choice of Games — Introduction to ChoiceScript** — https://www.choiceofgames.com/make-your-own-games/choicescript-intro/
    Design + scripting model for stat-driven choice novels (`*choice`, variables, `*if`).
    *Relevance:* comparison point to ink; strong on choice/stat interplay.
17. **Twine Cookbook** — https://twinery.org/cookbook/ (reference: https://twinery.org/reference/en/)
    Recipes for non-linear stories across Twine formats (Harlowe/SugarCube): variables, conditional links, state.
    *Relevance:* rapid prototyping of branch maps before committing to ink.
18. **IFComp + IFWiki** — https://ifcomp.org/ · https://www.ifwiki.org/Main_Page
    Community hub + encyclopedia for IF craft, tools, postmortems.
    *Relevance:* deep well of narrative-design references and example works to study.

### Tabletop SRDs & GDD templates
19. **D&D 5e System Reference Document (official, CC-BY-4.0)** — https://media.wizards.com/2016/downloads/DND/SRD-OGL_V5.1.pdf (latest SRD 5.2.1 hub: https://www.dndbeyond.com/resources/1781-systems-reference-document-srd)
    Openly-licensed RPG rules (attributes, checks, combat, conditions).
    *Relevance:* legally safe reference for expanding combat depth beyond base FF.
20. **Game Design Document Template (narrative games) — Meiri (itch.io)** — https://meiri.itch.io/game-design-document-template
    A real downloadable GDD template for branching/route-based narrative games (VN/IF/character-driven): plot beats, branch mapping, choice consequences.
    *Relevance:* structural starting point for our own GDD.

---

## (B) Registering docs into Nox Dev Studio

**The Studio's docs collection is the "GDD Library" (Learn area).**

- **Route:** `/gdd-library` — URL path `apps/web/app/(studio)/gdd-library/`
- **Files:**
  - `apps/web/app/(studio)/gdd-library/data.ts` — the data source (the registry).
  - `apps/web/app/(studio)/gdd-library/page.tsx` — renders it (read-only cards/lists).
  - `apps/web/app/(studio)/gdd-library/CopyBlock.tsx` — copy-to-clipboard for template markdown.

### Data model / registration mechanism
It is a **static, curated TypeScript file — NOT a DB, NOT a scanned directory, NOT a JSON index.**
`data.ts` exports three typed arrays; `page.tsx` imports and renders them. To register a doc you
add an object to the right array and the card appears in the UI on next build/reload.

**1. `EXEMPLAR_DOCS: ExemplarDoc[]`** — real, public design docs worth reading whole.
```ts
type DocType = "design-bible" | "pitch-doc" | "puzzle-doc" | "vision-doc" | "technique" | "essay";
type ExemplarDoc = {
  title: string; author: string; year: string; type: DocType;
  blurb: string;      // what the document is
  takeaway: string;   // what a designer/writer should take from it ("Steal:")
  url?: string;       // stable canonical link when known
  find?: string;      // search hint when no stable URL (shown as "find: ...")
};
```

**2. `DOC_TEMPLATES: DocTemplate[]`** — copyable starter templates (markdown authored inline).
```ts
type DocTemplate = {
  slug: string; title: string;
  audience: string;   // who reaches for it
  when: string;       // one line on when to use it
  markdown: string;   // full body — rendered + copyable via CopyBlock
};
```

**3. `CRAFT_REFERENCES: CraftRef[]`** — narrative/design craft references.
```ts
type CraftRef = {
  title: string; author: string;
  kind: "narrative-structure" | "branching" | "game-writing" | "level-design";
  blurb: string; url?: string; find?: string;
};
```

### Concrete steps to add a new doc entry
1. Open `apps/web/app/(studio)/gdd-library/data.ts`.
2. Pick the array that fits: `EXEMPLAR_DOCS` (a real published GDD), `DOC_TEMPLATES` (a copyable
   template), or `CRAFT_REFERENCES` (a craft/theory reference).
3. Append a new object matching that array's type. Provide `url` if a stable link exists; otherwise
   provide `find` (a search hint) — the UI shows one or the other. Never fabricate deep links
   (the file's own "honesty rule").
4. Save. Next dev reload / build renders the new card; counts ("N public documents") update
   automatically from array length. No index/DB/migration step is required.
5. If a genuinely new `type`/`kind` value is needed, extend the union in `data.ts` and (for
   `EXEMPLAR_DOCS`) add a label in `DOC_TYPE_LABEL` in `page.tsx`.

**Note (the FF references in Part A):** most fit `EXEMPLAR_DOCS` (Doom Bible, Diablo pitch, etc.
are the existing exemplars) only if they are actual design docs; the ink/Emily-Short/Twine/Tin-Man
items are a better fit for `CRAFT_REFERENCES`, and the Meiri GDD template belongs in
`DOC_TEMPLATES` (or as an `ExemplarDoc` with a `find`/`url`). The FF rules (Titannica) fit
`CRAFT_REFERENCES` (kind `game-writing`) or `EXEMPLAR_DOCS`.

**Related surfaces (not the GDD Library, for context):**
- `/knowledge-base` (`app/(studio)/knowledge-base/`, dynamic `[slug]`) — separate KB area.
- `/education` (`app/(studio)/education/data.ts`) — lesson/curriculum content.
- Writers Room is a **project-scoped, DB-backed** surface: `lib/actions/writers.ts`,
  `writersTags.ts`, `writersTransfer.ts` (server actions) — that's per-project writing content,
  distinct from the studio-wide read-only GDD Library. The GDD Library is the correct place to
  "register GDDs and reference docs" studio-wide.

---

## (C) Fantasy-illustrated art-style LoRA

Jesus's "Fighting-Fantasy / fantasy illustrated art-style LoRA" is our **detailed-VGA painterly
lane** LoRA. There are two candidates depending on intent — one is the confirmed shipped default:

### Primary — `dark_fantasy_illustration_z_image_turbo.safetensors`  (the confirmed pick)
- **What it is:** the GPU-validated "gold-standard" painterly fantasy-illustration style LoRA —
  the confirmed default for **avatars (hero portraits)** and **backgrounds (scenes)**. Bake-off
  2026-07-15 confirmed it as the detailed-VGA (Lands-of-Lore/Westwood) winner.
- **Filename / on disk:** `dark_fantasy_illustration_z_image_turbo.safetensors` in `D:/AI/Loras/ZIT/`.
- **Trigger word / prompt anchor:** `dark_fantasy_illustration` (used as an in-prompt token, not an
  ai-toolkit trigger). Full baked prompt: *"highly detailed 256-color VGA pixel art …, Lands of Lore
  Westwood painterly style, dark_fantasy_illustration, rich warm fantasy palette, deep greens and
  earthy browns, muted grey stone, vivid magic glow blue purple red gold, lush color gradients,
  painterly shading, atmospheric lighting."*
- **Strength:** 0.8.
- **How the pipeline loads it:**
  - ComfyUI workflow `ml-workbench/workflows/zit-pixel-vga-lol.json` — node `"10"` is a
    `LoraLoaderModelOnly` with `lora_name: "dark_fantasy_illustration_z_image_turbo.safetensors"`,
    `strength_model: 0.8`, chained onto the Z-Image-Turbo base model (node `1`). ComfyUI resolves
    `lora_name` from its loras path (`D:/AI/Loras/ZIT/`).
  - Registered in `ml-workbench/workflows/manifest.json` as the **`pixel-detailed-vga`** tier
    workflow (requiredModels lists the `.safetensors`).
  - Baked as the Studio default in `apps/web/lib/assetTypeDefaults.ts`
    (`ASSET_TYPE_DEFAULTS`: avatars + backgrounds → this LoRA @0.8, tier `pixel-detailed-vga`),
    guarded by `apps/web/test/asset-type-defaults.test.ts`.
  - Decision record: `Noxdev-Studio/docs/ASSET_TYPE_LORA_RECOMMENDATIONS_2026-07.md`.
- **⚠ Gamebook trap (called out in the manifest + education content):** a separate
  `gamebook-illustration-zit` LoRA/preset collapses this tier to a ~16-bit look (wrong fidelity for
  256-color VGA). It is reserved for a **gamebook/storybook ASSET-TYPE preset** — which is exactly
  ff-gamebook's lane — *not* the VGA tier. If ff-gamebook wants the flatter storybook illustration
  look, use `gamebook-illustration-zit`; if it wants lush painterly VGA, use `dark_fantasy`.

### Secondary — `nxdv_knight_p0.safetensors`  (recurring-knight subject LoRA)
- **What it is:** our first in-house trained-and-validated LoRA — a fantasy **knight character
  subject** LoRA (full plate armor, gold star emblem), not a whole-scene style LoRA. Validated
  2026-07-11 (`_samples-2026-07-11/29_knight_lora_VALIDATED_novel_scene.png`).
- **Trigger word:** `nxdv_knight` (token baked into every training caption; ai-toolkit
  `trigger_word` is disabled because `cache_text_embeddings: true`).
- **Filename / on disk:** copy final `nxdv_knight_p0.safetensors` to `D:/AI/Loras/ZIT/` → usable in
  `zit-*` ComfyUI workflows (LoRA slot 0), same path every ZIT LoRA takes.
- **Training config:** `ml-workbench/training/nxdv-knight-p0.yaml` (ai-toolkit, Z-Image Turbo arch
  `zimage`, network dim/alpha 32, lr 1e-4, 600-step P0 run; production preset 2500 steps).
- **Use:** stack on top of `dark_fantasy` for a consistent recurring knight-class subject
  (per ASSET_TYPE_LORA_RECOMMENDATIONS, character+animation → alternatives).

### Related LoRA context (godogen/ml-workbench)
- **ZIT style registry:** `godogen/skills/image-pipeline/tools/zit_styles.py` — named style keys →
  LoRA stack + trigger scaffolding (all **pixel-art** styles, e.g. `TartarusPixel` = dark-fantasy
  pixel, trigger `TARPIXV1`; not the painterly fantasy-illustration LoRA).
- **Default auto-loaded pixel LoRA:** `pixel_art_style_z_image_turbo.safetensors` (dispatched for
  most `--type`s by `image-pipeline`; see `skills/image-pipeline/SKILL.md` §8 + `style-anchor/SKILL.md`).
- **LoRA training program plan:** `Noxdev-Studio/docs/LORA_TRAINING_PLAN_2026-07.md` — Sierra/retro
  style-LoRA queue (Lands-of-Lore `nxdv_lol`, LSL6/7, Shadowrun); the fantasy-RPG game-look
  `nxdv_lol` is the trained-scene counterpart to `dark_fantasy`.
- **FF ruleset asset already in repo:** `godogen/skills/if-engine/addon/nox_if_engine/data/rulesets/ff-2d6.json`
  (the 2d6 FF combat ruleset for the interactive-fiction engine).

### Bottom line for ff-gamebook art
- Painterly hero portraits / scene backdrops → **`dark_fantasy_illustration_z_image_turbo.safetensors` @0.8**, tier `pixel-detailed-vga`, prompt token `dark_fantasy_illustration` + Lands-of-Lore palette.
- Flatter storybook/gamebook illustration look → **`gamebook-illustration-zit`** preset.
- Recurring named hero (e.g. a knight protagonist across many frames) → stack **`nxdv_knight_p0`** (trigger `nxdv_knight`) on top.
- All resolve from `D:/AI/Loras/ZIT/` via ComfyUI `LoraLoader*` nodes in `ml-workbench/workflows/*.json`.
