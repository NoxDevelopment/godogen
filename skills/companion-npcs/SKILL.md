# Companion NPCs

Bake deep NPCs from **companion_ai_core** — the 240k-line pure-Dart companion
generator (12,000+ attributes per companion: personality, culture, memories,
emotions, relationships, physical characteristics, quirks, skills, occupations) —
into Godot game templates. This is Tier-1 "design-time baking" from the ecosystem
roadmap (Noxdev-Studio `docs/ECOSYSTEM_AUDIT_AND_GENERATION_ROADMAP_2026-07.md`
§5.3): companion JSON in, game-template data out, **zero runtime dependency** on
the companion library.

> ## ⚠️ Living integration — read this before touching anything
>
> 1. **The source library is READ-ONLY.** `C:\code\ai\localllm_poc\**`
>    (companion_ai_core, otium_reborn, everything) is Jesus's active personal
>    project. You may read it to understand structures; you may **never**
>    create, modify, or delete anything under it. All companion-npcs work lives
>    here in godogen.
> 2. **The mapping is a point-in-time projection.** companion_ai_core is under
>    active development — the interchange schema and every field mapping in
>    `schema/FIELD_MAPPINGS.md` **will need updating as the library evolves**.
>
>    **Last mapped: 2026-07-11 against `localllm_poc@1eb530af`.**
>
>    **Re-mapping procedure:** re-run the read-only exploration of
>    `companion_ai_core/lib/src/domain/companion/complete_companion_entity.dart`
>    (class `CompleteCompanionEntity` + its `toJson()`), diff against
>    FIELD_MAPPINGS.md, bump `interchangeVersion` on breaking changes, and keep
>    the `extensions` passthrough as the forward-compat valve for anything the
>    schema doesn't model yet.

## When to use

- Populating an RPG / VN / isometric / farming-sim template with NPCs that have
  believable trait scores, culture, occupations, secrets, and relationships —
  Stardew-townsfolk depth without hand-authoring 12k attributes.
- Turning a Studio-generated (or hand-authored) companion export into Pandora
  entities, Dialogue Manager personas, and portrait plans in one command.
- Authoring persona context so an LLM can write in-character dialogue against a
  stable, data-backed character sheet.

Not for: runtime companion behavior (emotions ticking, memory, conversation) —
that is Tier 2 (see bottom).

## Files

```
skills/companion-npcs/
├── SKILL.md                                  this file
├── schema/
│   ├── companion-interchange.schema.json     versioned projection schema (v1)
│   └── FIELD_MAPPINGS.md                     Dart entity → interchange mapping (point-in-time)
├── tools/
│   └── companion_import.py                   importer (stdlib-only; jsonschema optional)
└── fixtures/
    └── example_companion.json                rich SFW reference fixture (cafe owner NPC)
```

## The import flow

```bash
# 1. Obtain interchange JSON (single companion object or array).
#    Today: hand-authored to the schema, or projected from a
#    CompleteCompanionEntity.toJson() dump. Future: exported by Studio.

# 2. Validate + import into your game project:
python skills/companion-npcs/tools/companion_import.py my_npcs.json \
  --out game/data --validate

# 3. Self-test (runs the bundled fixture end-to-end, verifies all outputs):
python skills/companion-npcs/tools/companion_import.py --self-test
```

Output layout per companion:

```
<out>/npcs/<slug>/
├── pandora.json            Pandora-importable entity (+ NPC category & property defs)
├── character.dialogue.md   Dialogue Manager persona stub (comment header + greeting title)
├── portrait_plan.json      asset-plan for the portrait pipeline
└── companion.json          normalized interchange copy (single object, extensions intact)
<out>/npcs/index.json       manifest of everything imported
```

## How templates consume each output

### pandora.json → Pandora addon (bitbrain/pandora)

Matches Pandora's on-disk format exactly (verified against `godot-4.x` source:
`{"_entity_data": {"_categories", "_entities", "_properties"}, "_id_generator"}`;
array properties are index-keyed `{type, value}` dicts). Import via the Pandora
editor's **Import** action, or merge `_entity_data` into the project's
`data.pandora` (top-level dict-merge per section). IDs are deterministic strings
(`companion-npcs` category, `companion-npcs.prop.<name>` properties,
`companion-npc.<slug>` entities), so:

- importing several NPC files is **idempotent** for the shared category/properties
  and additive for entities;
- re-importing the same NPC never duplicates it.

Game code reads it like any Pandora entity:

```gdscript
var naomi = Pandora.get_entity("companion-npc.naomi-tanaka-oliveira")
var warmth: float = naomi.get_float("agreeableness")
var quirks: Array = naomi.get_array("quirks")
```

`portrait_path` is an intentionally-empty string property — write the generated
portrait's path into it once the portrait pipeline has run.

### character.dialogue.md → Dialogue Manager (nathanhoad)

A `.dialogue`-adjacent stub: a `#`-comment persona header (who/personality/
quirks/speech style/values/goals/fears/secrets/backstory/relationships + LLM
authoring notes) followed by a valid example greeting title (`~ <slug>_greeting`)
that demonstrates `if`/`set` against a suggested `<Name>State` autoload. Use it
two ways:

- **LLM authoring context:** paste/attach the header when asking an LLM to write
  dialogue for this character — the persona block is the system prompt.
- **Seed dialogue:** copy the title block into the template's `.dialogue` file,
  create the state autoload, and grow from there. Secrets are annotated with
  severity and explicitly flagged "gate behind high trust" so conditions write
  themselves (`if NaomiState.affection > 60`).

### portrait_plan.json → portrait pipeline → character LoRA loop

Consumable by asset_gen / the workflow library (`zit-txt2img`, type `portrait`):

- `prompt` is composed from the structured appearance projection (hair/eyes/
  skin/face/features/outfit + a personality-derived expression) and contains the
  literal `{style}` placeholder — resolve it via the **style-anchor** skill (or
  let asset_gen handle it). `negative` is prefilled.
- `lora_slots["0"]` = style LoRA (router auto-loads pixel-art LoRA for pixel
  types). `lora_slots["1"]` = **character-identity LoRA slot**: leave null for
  first renders; after 8-12 approved portraits of the NPC, train an identity
  LoRA (**character-sheet** skill loop, ai-toolkit Z-Image preset) and pin it so
  every later asset keeps the same face.
- If the template has a `reference.png` style anchor, asset_gen's router
  switches portraits to identity-preserving img2img automatically — desirable.
- Register results in `assets/manifest.json` (**asset-manifest** skill), then
  write the path back into the Pandora `portrait_path` property and the plan's
  `produced_asset` field.

### companion.json

The untouched interchange record (including the `extensions` passthrough, which
may carry the full 12k-attribute entity dump). Keep it in the repo next to the
baked outputs — it is the source of truth for re-baking after schema upgrades,
and the input for future Tier-2 runtime hydration.

## Schema notes (v1)

- Versioned via `"interchangeVersion": 1`. **Breaking** changes bump it;
  additive optional fields inside groups do not (group objects tolerate unknown
  members; the top level is strict except `extensions`).
- Groups: `identity`, `personality` (FFM scores + archetype + quirks),
  `appearance` (+ `portraitPrompt`), `voice` (pitch/pace/tone/timbre/accent/
  styleTags — feeds VoiceDesign-style TTS and speech-style authoring), `social`
  (values/occupation/top-N skills/hobbies/interests), `narrative` (backstory
  summary/secrets/goals/fears), `relationships` (typed links incl. `player`),
  `emotionalBaseline` (Russell circumplex valence/arousal/dominance), `meta`
  (source + sourceCommit + seed), `extensions` (lossless passthrough).
- `meta.contentRating` defaults to `sfw`; the v1 projection never maps the
  library's intimacy attribute groups into named fields (extensions-only, and
  only for `mature` exports). Game templates get SFW data by default.
- Field-by-field provenance (which Dart field, which file, which line): see
  `schema/FIELD_MAPPINGS.md`.

## Future: companion-server (Tier 2)

Roadmap §5.3 Tier 2 upgrades these same NPCs from baked data to a **live brain**:
`companion-server`, a Dart HTTP/WebSocket wrapper over companion_ai_core (same
pattern as ml-workbench's `bin/api_server`), native-compiled and shipped next to
desktop games — generate / converse / life-sim tick / emotional-state + memory
queries over localhost, supervised via Studio services. The interchange `identity.id`
is the join key: a template that baked `companion.json` today can hydrate the
same NPC into the runtime service later. Preconditions (compile status of
companion_ai_core, stable subset to expose) are tracked in the roadmap — do not
start Tier 2 from this skill.
