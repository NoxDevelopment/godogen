# Narrative

Dialogue tree converters (Ink / Yarn / Dialogic), quest schema validation + emission (Godot `.tres` / Unity ScriptableObject JSON), markdown world-bible scaffolder, and NPC voice batch (chains `audio-pipeline`'s speech command).

**This skill handles structure and format, not content.** Author the JSON tree / quest spec / lore outline in the agent's own LLM context — pass the structured input here to convert to engine-ready formats.

## TL;DR

```bash
python3 .claude/skills/narrative/tools/narrative_gen.py {dialogue|quest|lore|voice|list} [opts]
```

## Subcommands

### dialogue — Convert dialogue tree to Ink / Yarn / Dialogic

Input JSON shape:
```json
{
  "title": "Mira_intro",
  "start": "node_001",
  "nodes": {
    "node_001": {
      "speaker": "Mira",
      "text": "Welcome to my shop, traveler.",
      "choices": [
        {"text": "Show me your wares.",   "next": "node_002"},
        {"text": "Just looking, thanks.", "next": "node_003"}
      ]
    },
    "node_002": {"speaker": "Mira", "text": "Anything catch your eye?", "next": "shop_ui"},
    "node_003": {"speaker": "Mira", "text": "Suit yourself.", "end": true}
  }
}
```

```bash
python3 .claude/skills/narrative/tools/narrative_gen.py dialogue \
  --input dialogues/mira_intro.json --format ink \
  -o assets/dialogue/mira_intro.ink
```

Output formats:
- `ink` — Ink script (Inkle, used by Inky editor + many engines via ink-runtime). Each node → `=== knot ===`; choices → `+ [text] -> next`.
- `yarn` — Yarn Spinner 2.x script (Unity/Godot via plugin). Each node → `title:` block; choices → `-> text` + `<<jump>>`.
- `dialogic` — Dialogic 2.x JSON timeline (Godot 4 plugin).

### quest — Validate + emit quest spec

Input JSON shape:
```json
{
  "id": "q_001_lost_amulet",
  "name": "The Lost Amulet",
  "description": "Recover Mira's family heirloom from the swamp.",
  "objective": "Retrieve the amulet from the swamp shrine",
  "steps": [
    {"id": "step_1", "text": "Speak to Mira",                "trigger": "talk_to:mira"},
    {"id": "step_2", "text": "Find the swamp shrine",        "trigger": "enter:swamp_shrine"},
    {"id": "step_3", "text": "Defeat the shrine guardian",   "trigger": "defeat:shrine_guardian"},
    {"id": "step_4", "text": "Return to Mira",               "trigger": "talk_to:mira"}
  ],
  "rewards": {"gold": 250, "xp": 500, "items": ["enchanted_charm"]},
  "prerequisites": ["q_intro_complete"]
}
```

```bash
python3 .claude/skills/narrative/tools/narrative_gen.py quest \
  --input quests/lost_amulet.json --format godot \
  -o assets/quests/lost_amulet.tres
```

Output formats:
- `godot` — `.tres` Resource referencing a `QuestData` script. Your project should define `res://scripts/QuestData.gd` with matching properties.
- `unity` — JSON sidecar for `JsonUtility.FromJsonOverwrite()` onto a ScriptableObject.

Validation surfaces missing fields with clear error messages before emission.

### lore — Markdown world-bible scaffolder

```bash
python3 .claude/skills/narrative/tools/narrative_gen.py lore \
  --title "Crimson Cape" -o docs/world.md
```

Drops a structured markdown template with Setting / Geography / Factions / Magic-Technology / Cultures / Timeline / Glossary / Open-questions sections. Fill it in iteratively; agent has stable headings for cross-referencing later asset / quest / dialogue generation.

### voice — NPC voice line batch render

Input JSON shape (a list, not a tree):
```json
[
  {"character": "Vex",   "voice": "am_adam",   "emotion": "fearful",
   "text": "We won't make it out of here alive!", "output": "vex_panic.wav"},
  {"character": "Mira",  "voice": "af_bella",  "emotion": "happy",
   "text": "I've been waiting for you, my friend.", "output": "mira_greeting.wav"}
]
```

```bash
python3 .claude/skills/narrative/tools/narrative_gen.py voice \
  --input dialogues/recording_list.json \
  --output-dir assets/audio/voice/
```

Chains to `audio-pipeline/tools/audio_gen.py speech` once per line. Falls back through the Orpheus → Kokoro → EdgeTTS provider chain. Emotions only apply when Orpheus is reachable.

`--dry-run` prints the commands without executing — useful for previewing what'll be rendered before paying for it.

### list — Show formats + schema reminders

```bash
python3 .claude/skills/narrative/tools/narrative_gen.py list
```

## Pipeline — full narrative pass

```bash
# 1. Agent drafts lore world-bible
narrative_gen.py lore --title "Crimson Cape" -o docs/world.md
# (agent fills in sections from world brief)

# 2. Agent drafts quest spec JSON in conversation
echo '{...}' > quests/lost_amulet.json
narrative_gen.py quest --input quests/lost_amulet.json --format godot \
  -o assets/quests/lost_amulet.tres

# 3. Agent drafts dialogue JSON for each NPC the quest touches
narrative_gen.py dialogue --input dialogues/mira_intro.json --format ink \
  -o assets/dialogue/mira_intro.ink

# 4. Extract voice lines from the dialogue, batch-render with audio-pipeline
narrative_gen.py voice --input dialogues/voice_lines.json \
  --output-dir assets/audio/voice/
```

## What NOT to do

- Don't hand-write Ink/Yarn/Dialogic by hand — author the JSON tree once, convert to all three. Lets you swap engines/plugins without rewriting dialogue.
- Don't put voice line generation inside the dialogue tree JSON — keep them separate. The dialogue tree is for the **script**, the voice list is for the **recording session**.
- Don't expect this skill to write the actual prose. It's the converter — the agent's own LLM is the writer.

## Verification

JSON to stdout includes node/step/line counts so you can sanity-check the conversion didn't drop content:

```json
{"ok": true, "subcommand": "dialogue", "format": "ink",
 "output": "...", "node_count": 12, "title": "mira_intro"}
```

For `voice`, `dry_run: true` reveals every audio-pipeline command before any TTS spend.
