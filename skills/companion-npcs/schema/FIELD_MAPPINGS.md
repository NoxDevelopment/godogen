# Companion Interchange v1 — Field Mappings

Maps `companion-interchange.schema.json` fields to the real Dart structures in
`companion_ai_core` so a future exporter (Dart-side, Tier 2 companion-server, or a
one-off script over `CompleteCompanionEntity.toJson()` output) is mechanical.

> ## ⚠️ Point-in-time mapping — companion_ai_core is a moving target
>
> `companion_ai_core` (in `C:\code\ai\localllm_poc\`, **read-only from this side**) is
> under **active development by Jesus**. Everything below is a projection of the
> library **as observed on a specific day** and *will* drift.
>
> **Last mapped: 2026-07-11 against `localllm_poc@1eb530af`**
> ("feat(seed-spine): S1 — identity latent vector + analytic Gaussian sampler")
>
> **Re-verified: 2026-07-18 against `localllm_poc@7d140eb4` — projection HOLDS, no changes.**
> Diffed 134 commits (1eb530af..7d140eb4). Nearly all are the new **seed_spine**
> generation subsystem (identity latent vectors, covariance model, lock compiler,
> backstory DAG, psychology/religiosity derivers) — this is generation-time machinery
> that flows INTO the existing `physicalProfile` / `voiceProfile` / `personalityProfile`
> the tables below already map; it adds **no new `toJson()` keys** (verified: no
> spine/seed/latent/provenance/coherence/lock keys emitted by the entity). The only
> `complete_companion_entity.dart` change (+34 lines) is a **`fromJson` round-trip fix
> for `sexualCulturalProfile`** — an intimacy field we DELIBERATELY do not project — so
> it doesn't touch the interchange. No `interchangeVersion` bump; importer 37-check
> self-test + schema validation still pass.
>
> **Re-mapping procedure when the library evolves:**
> 1. Re-run the read-only exploration: start at
>    `companion_ai_core/lib/src/domain/companion/complete_companion_entity.dart`
>    (class `CompleteCompanionEntity`, ~32k lines) and diff its field list and
>    `toJson()` against the tables below.
> 2. Additive library changes → extend the optional fields inside existing groups
>    (no version bump) or let the data ride in `extensions`.
> 3. Breaking changes (renamed/retyped/removed fields we project) → bump
>    `interchangeVersion`, update this file's "Last mapped" line, and keep the
>    importer accepting the previous version.
> 4. The `extensions` passthrough object is the forward-compat valve: anything the
>    schema doesn't know about yet travels there losslessly, importers preserve it
>    verbatim and ignore unknown keys.

## Source of truth

- Entity: `companion_ai_core/lib/src/domain/companion/complete_companion_entity.dart`
  — `class CompleteCompanionEntity` (line ~738), full `toJson()` at line ~2744,
  `fromJson()` at ~1957. The entity is mid-migration ("Phase 10.3"): **profile
  objects** (`demographicProfile`, `personalityProfile`, ...) are the preferred
  source; deprecated **flat fields** (`age`, `gender`, `bigFiveTraits`, ...) are
  still emitted by `toJson()` as mirrors. Prefer profile objects, fall back to the
  flat mirror.
- The interchange consumes the **JSON produced by `toJson()`**, never Dart objects.

## Group-by-group mapping

### identity
| Interchange | Dart source (toJson key) | Notes |
|---|---|---|
| `identity.id` | `companionId` | required |
| `identity.name` | `name` | required |
| `identity.age` | `demographicProfile.age` (fallback flat `age`) | int |
| `identity.gender` | `demographicProfile.gender` (flat `gender`) | |
| `identity.pronouns` | `demographicProfile.pronouns` (flat `pronouns`) | |
| `identity.culture.primary` | `demographicProfile.primaryCulture` → `CulturalOrigin.displayName` (toJson emits enum `.name`, e.g. `"japanese"` — map to display `"Japanese"`) | enum in `domain/cultural/cultural_origin.dart` (70 origins) |
| `identity.culture.secondary` | `demographicProfile.secondaryCultures` / flat `secondaryCultures` | list of enum names |
| `identity.culture.ethnicity` | `demographicProfile.ethnicity` (flat `ethnicity`) | |
| `identity.culture.nationality` | `demographicProfile.nationality` | |
| `identity.culture.languages` | `demographicProfile.languages` | |
| `identity.culture.religion` | `culturalProfile.religion` (flat `religion`) | |
| `identity.culture.hofstede` | toJson `hofstedeDimensions` (always emitted; falls back to `culturalProfile.advancedCulturalDynamics.hofstede`) | keys: powerDistance, individualism, masculinity, uncertaintyAvoidance, longTermOrientation, indulgence |
| `identity.location` | `demographicProfile.currentLocation` (`GeographicLocation`: city/country/region, `domain/demographics/demographic_generator.dart`) | |

### personality
| Interchange | Dart source | Notes |
|---|---|---|
| `personality.archetype` | `archetype` (`CompanionArchetype` enum `.name`, `domain/companion/companion_types.dart`) | 12 Jungian values |
| `personality.complexity` | `complexity` (`CompanionComplexity.name`) | minimal/standard/complete/legendary |
| `personality.bigFive.*` | `personalityProfile.bigFive` (`BigFiveTraits`, `domain/personality/consolidated_personality_types.dart`) / flat `bigFiveTraits` | keys openness…neuroticism, 0-1 |
| `personality.mbti` | `personalityProfile.mbtiType` (flat `personalityType`) | |
| `personality.enneagram` | flat `enneagramType` (also `personalityProfile.enneagram` map of scores) | |
| `personality.attachmentStyle` | `psychologicalProfile.attachmentStyle` (flat `attachmentStyle`) | |
| `personality.quirks` | `mannerisms` — entity getter `quirks => mannerisms ?? []` (entity line ~3553); generation pools in `lib/src/data/quirks/comprehensive_quirks_data.dart` | take top ~8 |
| `personality.behaviorTendencies` | `behaviorTendencies` (Map<String,double>) | |
| `personality.moralFoundations` | flat `moralFoundations` | |
| `personality.hexaco` | not directly on entity at 1eb530af; waifu-archetype detection derives FFM/HEXACO — leave absent or project from `waifuArchetypeProfile` when present | optional |

### appearance
Source: `physicalProfile` = `ComprehensivePhysicalCharacteristics`
(`domain/physical/comprehensive_physical_characteristics.dart`, its `toJson()` at ~22756).

| Interchange | Dart source (physicalProfile.toJson key) |
|---|---|
| `heightCm` / `weightKg` | `height` / `weight` |
| `bodyType` | `bodyType` (also `kibbeBodyType`) |
| `fitnessLevel` | `fitnessLevel` |
| `hairColor` | `generatedHairColor` |
| `eyeColor` | `generatedEyeColor` (also `facial.eyeColor`) |
| `skinTone` | `generatedSkinTone` |
| `face.*` | `facial.{faceShape,eyeShape,eyebrowShape,noseShape,lipShape,jawline,cheekStructure,facialHair}` |
| `presence` | `aesthetic.presence` + `postureCharacteristics` |
| `distinguishingFeatures` | `asymmetries`, `bodyModifications`, Stage-2 `*Description` fields |
| `typicalOutfit` | `fashionStyleProfile` / `fullWardrobe` summary |
| `portraitPrompt` | composed at export/import time; must contain `{style}` token |

### voice
Source: `voiceProfile` Map, generated by
`Stage1InstantGenerator._generateVoiceProfile` (`domain/generation/stage1_instant_generator.dart` ~16356).

| Interchange | voiceProfile key | Notes |
|---|---|---|
| `pitchHz` | `pitch` | number, Hz (F0; Titze 1994 baselines) |
| `pitch` | bucketed from `pitch` Hz | very-low <110, low <165, medium <220, high <280, very-high ≥280 (importer buckets) |
| `pace` | `pace` | quick/moderate |
| `tone` | `tone` | warm/neutral |
| `timbre` | `timbre` | e.g. "warm and resonant" |
| `accent` | `accent` | CulturalOrigin displayName |
| `speechStyle` | `speech_pattern` + `voice_quality` | merged string |
| `volume` | `volume` | |
| `styleTags` | derived from `breathiness`/`nasality`/`roughness`/`resonance` + `speechPatterns` + `linguisticPatterns` | freeform |

### social
| Interchange | Dart source | Notes |
|---|---|---|
| `values` | `personalityProfile.values` (Map<String,double>) / flat `values` / `culturalValues` | |
| `occupation` | `demographicProfile.occupation` (string) or flat `occupation` (Map) | Map shape varies; normalize to {title, field, seniority, workplace} |
| `skills[]` | `skillProficiencies` (Map<name, `CompanionSkillProficiency`{name, source, proficiency, practiceHours}>, entity line ~191); fallback flat `skills` List<String> | export top-N by proficiency; `dreyfusLevel` is a computed getter — recompute (<0.15 novice, <0.30 advancedBeginner, <0.50 competent, <0.70 proficient, <0.85 expert, else master) |
| `hobbies[]` | `hobbyProficiencies` (Map<name, `HobbyProficiency`{name, skillLevel, estimatedHours}>) | |
| `interests` | `interestIntensityProfile` (Map<String,double>) | deep per-interest knowledge in `interestKnowledgeProfiles` → extensions |
| `affiliations` | `affiliations` | |
| `socialClass` | `socialClass` / `demographicProfile.socioeconomicClass` | |
| `wealth` / `reputation` | `wealth` / `reputation` | 0-1 |

### narrative
| Interchange | Dart source |
|---|---|
| `backstorySummary` | `backstory` (condense; full text → extensions) |
| `lifeEvents` | `lifeEvents` / `demographicProfile.significantLifeEvents` |
| `secrets[]` | `secrets` Map (complexity-scaled) → normalize to {description, severity} |
| `goals` | `goals` {shortTerm, longTerm, life} — same shape, pass through |
| `fears` | `psychologicalProfile.fears` / flat `fears` Map keys |
| `dreams` | `dreamsAspirations` |

### relationships
| Interchange | Dart source | Notes |
|---|---|---|
| `[].target/.type` | `relationshipData` (Map<entityId, typeString>) | direct |
| `[].closeness` | `socialNetwork` Dunbar-layer entries `{name, relationshipType, closeness, frequency, duration, quality}` | |
| player link | `relationships` (`RelationshipSystem` — user bond), `bondLevel` (0-10 → /10), `affection` (0-100) | only meaningful for companion-app saves; usually omitted for fresh NPCs |

### emotionalBaseline
Source: `emotionalState` (`EmotionalState`, `domain/emotions/emotional_state.dart` ~140)
and `emotionalSystems` Map.

| Interchange | Dart source |
|---|---|
| `valence` | `EmotionalState.valence` (-1..1) |
| `arousal` / `dominance` | `EmotionalState.arousal` / `.dominance` (0..1) |
| `dominantEmotions` | top entries of `EmotionalState.emotions` (Map<EmotionCategory,double>) |
| `moodStability` | derived: `1 - bigFive.neuroticism`, adjusted by `emotionalSystems.emotionRegulation` |

### meta
| Interchange | Dart source |
|---|---|
| `source` | constant `"companion_ai_core"` |
| `sourceVersion` | `generatorVersion` |
| `sourceCommit` | git HEAD of localllm_poc at export time |
| `generatedAt` | `generatedAt` (ISO 8601) |
| `generationSeed` | `generationSeed` |
| `qualityScore` / `attributeCount` | `qualityScore` / `attributeCount` |
| `contentRating` | policy: `sfw` unless deliberately exporting mature content |

### Deliberately NOT projected into v1 fields

Intimacy/sexuality groups (`kinkProfile`, `fetishProfile`, `fantasies`,
`sexualCulturalProfile`, `touchProfile`, `arousalProfile`, breast/genital
characteristics), full wardrobe inventories, runtime consciousness systems
(`consciousnessGrid`, `heartLayer`/`mindLayer`/`bodyLayer`/`spiritLayer`,
memory/dream systems, `immersionGuardian`), astrology, and medical history.
Game templates don't consume them at design time. If ever needed they travel in
`extensions` (intimacy groups only with `meta.contentRating: "mature"`).
