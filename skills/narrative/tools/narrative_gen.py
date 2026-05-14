"""Narrative — dialogue trees, quest schemas, lore templates, NPC voice batches.

The skill handles **structure and format**, not content generation. Author
the JSON tree / quest spec / lore outline in your prompt session (the
agent's own LLM does the writing); pass the structured input here to
convert to engine-ready formats.

Subcommands
-----------
dialogue  Convert a JSON tree of dialogue nodes to Ink / Yarn / Dialogic.
quest     Validate a quest JSON spec and emit Godot .tres resource OR
          Unity ScriptableObject JSON sidecar.
lore      Scaffold a structured markdown world-bible template the agent
          can fill in (setting / factions / magic / timeline / glossary).
voice     Batch-render NPC voice lines via audio-pipeline (chains the
          speech subcommand once per line).
list      Show supported output formats and the JSON shapes required.

Input JSON shape — dialogue tree:
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

Input JSON shape — quest:
{
  "id": "q_001_lost_amulet",
  "name": "The Lost Amulet",
  "description": "Recover Mira's family heirloom from the swamp.",
  "objective": "Retrieve the amulet from the swamp shrine",
  "steps": [
    {"id": "step_1", "text": "Speak to Mira", "trigger": "talk_to:mira"},
    {"id": "step_2", "text": "Find the swamp shrine", "trigger": "enter:swamp_shrine"},
    {"id": "step_3", "text": "Defeat the shrine guardian", "trigger": "defeat:shrine_guardian"},
    {"id": "step_4", "text": "Return to Mira", "trigger": "talk_to:mira"}
  ],
  "rewards": {"gold": 250, "xp": 500, "items": ["enchanted_charm"]},
  "prerequisites": ["q_intro_complete"]
}
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
SKILL_ROOT = THIS_DIR.parent
SKILLS_ROOT = SKILL_ROOT.parent
AUDIO_PIPELINE_TOOLS = SKILLS_ROOT / "audio-pipeline" / "tools"


# ---------------------------------------------------------------------------
# Dialogue format converters
# ---------------------------------------------------------------------------

def _to_ink(tree: dict) -> str:
    """Convert dialogue tree → Ink script.

    Each node becomes a knot (=== name ===). Choices use `+ [text] -> next_node`.
    Speaker lines use `# speaker: Name` tags Ink ignores at runtime but
    parsers / Inky display.
    """
    lines: list[str] = [f"// {tree.get('title', 'dialogue')}"]
    start = tree.get("start")
    if start:
        lines.append(f"-> {start}")
        lines.append("")
    for node_id, node in tree.get("nodes", {}).items():
        lines.append(f"=== {node_id} ===")
        speaker = node.get("speaker", "")
        text = node.get("text", "")
        if speaker:
            lines.append(f"# speaker: {speaker}")
        if text:
            lines.append(text)
        choices = node.get("choices") or []
        if choices:
            for ch in choices:
                lines.append(f"+ [{ch['text']}] -> {ch['next']}")
        elif node.get("next"):
            lines.append(f"-> {node['next']}")
        elif node.get("end"):
            lines.append("-> END")
        else:
            lines.append("-> END")
        lines.append("")
    return "\n".join(lines)


def _to_yarn(tree: dict) -> str:
    """Convert to Yarn Spinner 2.x script.

    Each node becomes a `title: name` block separated by `===`. Choices use
    `-> text` blocks ending with `<<jump next>>`.
    """
    blocks: list[str] = []
    for node_id, node in tree.get("nodes", {}).items():
        lines: list[str] = []
        lines.append(f"title: {node_id}")
        lines.append("---")
        speaker = node.get("speaker", "")
        text = node.get("text", "")
        if text:
            if speaker:
                lines.append(f"{speaker}: {text}")
            else:
                lines.append(text)
        choices = node.get("choices") or []
        if choices:
            for ch in choices:
                lines.append(f"-> {ch['text']}")
                lines.append(f"    <<jump {ch['next']}>>")
        elif node.get("next"):
            lines.append(f"<<jump {node['next']}>>")
        elif node.get("end"):
            lines.append("<<stop>>")
        lines.append("===")
        blocks.append("\n".join(lines))
    header = f"// {tree.get('title', 'dialogue')}\n"
    return header + "\n".join(blocks)


def _to_dialogic(tree: dict) -> dict:
    """Convert to Dialogic 2.x compatible JSON (timeline events array)."""
    events: list[dict] = []
    # Dialogic uses a flat timeline; we walk the tree linearly from start,
    # converting nested branches to ConditionalChoice events.
    start = tree.get("start")
    nodes = tree.get("nodes", {})
    visited: set[str] = set()

    def walk(node_id: str) -> None:
        if node_id in visited or node_id not in nodes:
            return
        visited.add(node_id)
        node = nodes[node_id]
        if node.get("text"):
            events.append({
                "event_id": "dialogic_text_event",
                "character": node.get("speaker", ""),
                "text": node["text"],
                "node_id": node_id,
            })
        choices = node.get("choices") or []
        if choices:
            for ch in choices:
                events.append({
                    "event_id": "dialogic_choice_event",
                    "text": ch["text"],
                    "next": ch["next"],
                })
                walk(ch["next"])
        elif node.get("next"):
            walk(node["next"])
        elif node.get("end"):
            events.append({"event_id": "dialogic_end_event"})

    if start:
        walk(start)
    return {
        "title": tree.get("title", "dialogue"),
        "type": "DialogicTimeline",
        "events": events,
    }


def cmd_dialogue(args):
    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"Input not found: {in_path}")
    tree = json.loads(in_path.read_text())

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if args.format == "ink":
        out_path.write_text(_to_ink(tree), encoding="utf-8")
    elif args.format == "yarn":
        out_path.write_text(_to_yarn(tree), encoding="utf-8")
    elif args.format == "dialogic":
        out_path.write_text(json.dumps(_to_dialogic(tree), indent=2), encoding="utf-8")
    else:
        raise SystemExit(f"--format must be ink/yarn/dialogic, got {args.format!r}")

    print(json.dumps({
        "ok": True, "subcommand": "dialogue", "format": args.format,
        "output": str(out_path),
        "node_count": len(tree.get("nodes", {})),
        "title": tree.get("title"),
    }, indent=2))


# ---------------------------------------------------------------------------
# Quest schema validation + emission
# ---------------------------------------------------------------------------

REQUIRED_QUEST_FIELDS = ["id", "name", "description", "objective", "steps"]


def _validate_quest(spec: dict) -> list[str]:
    """Return a list of validation errors (empty if valid)."""
    errors: list[str] = []
    for f in REQUIRED_QUEST_FIELDS:
        if f not in spec:
            errors.append(f"missing required field: {f}")
    steps = spec.get("steps") or []
    if not isinstance(steps, list) or len(steps) == 0:
        errors.append("steps must be a non-empty list")
    else:
        for i, step in enumerate(steps):
            if "id" not in step:
                errors.append(f"steps[{i}]: missing id")
            if "text" not in step:
                errors.append(f"steps[{i}]: missing text")
    rewards = spec.get("rewards") or {}
    if rewards and not isinstance(rewards, dict):
        errors.append("rewards must be a dict")
    return errors


def _quest_to_godot_tres(spec: dict) -> str:
    """Emit a Godot 4 .tres custom resource. The user's project should
    define a `QuestData` class_name that matches these fields.
    """
    lines: list[str] = []
    lines.append('[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3]')
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/QuestData.gd" id="1"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1")')
    lines.append(f'quest_id = "{spec["id"]}"')
    lines.append(f'quest_name = "{spec["name"]}"')
    lines.append(f'description = "{_escape(spec["description"])}"')
    lines.append(f'objective = "{_escape(spec["objective"])}"')
    # Steps as a flat array of dicts.
    steps_pairs = []
    for step in spec.get("steps", []):
        # Godot 4 inline dict literal in .tres
        items = ", ".join(f'"{k}": "{_escape(str(v))}"' for k, v in step.items())
        steps_pairs.append(f"{{{items}}}")
    lines.append(f"steps = [{', '.join(steps_pairs)}]")
    rewards = spec.get("rewards") or {}
    if rewards:
        rew_items = []
        for k, v in rewards.items():
            if isinstance(v, list):
                vstr = "[" + ", ".join(f'"{x}"' for x in v) + "]"
            elif isinstance(v, (int, float)):
                vstr = str(v)
            else:
                vstr = f'"{_escape(str(v))}"'
            rew_items.append(f'"{k}": {vstr}')
        lines.append(f"rewards = {{{', '.join(rew_items)}}}")
    prereqs = spec.get("prerequisites") or []
    if prereqs:
        plist = "[" + ", ".join(f'"{p}"' for p in prereqs) + "]"
        lines.append(f"prerequisites = {plist}")
    lines.append("")
    return "\n".join(lines)


def cmd_quest(args):
    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"Input not found: {in_path}")
    spec = json.loads(in_path.read_text())
    errors = _validate_quest(spec)
    if errors:
        print(json.dumps({"ok": False, "subcommand": "quest", "errors": errors}, indent=2))
        sys.exit(1)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if args.format == "godot":
        out_path.write_text(_quest_to_godot_tres(spec), encoding="utf-8")
    elif args.format == "unity":
        # Unity ScriptableObject JSON sidecar. The user creates a
        # QuestData ScriptableObject in their project; this JSON is for
        # JsonUtility.FromJsonOverwrite or a custom importer.
        out_path.write_text(json.dumps(spec, indent=2), encoding="utf-8")
    else:
        raise SystemExit(f"--format must be godot/unity, got {args.format!r}")

    print(json.dumps({
        "ok": True, "subcommand": "quest", "format": args.format,
        "output": str(out_path),
        "quest_id": spec["id"], "step_count": len(spec.get("steps", [])),
    }, indent=2))


# ---------------------------------------------------------------------------
# Lore template scaffolder
# ---------------------------------------------------------------------------

LORE_TEMPLATE = """# {title}

> World bible for {title}. Fill in each section; the agent (or you) can
> expand from sparse notes into full prose. Keep the section headings
> stable so cross-references work.

## Setting

**Genre**:
**Tone**:
**Tech / magic level**:
**One-sentence pitch**:

(A paragraph describing the world's hook — what makes this setting feel
distinct from others in the same genre.)

## Geography

### Major regions

- **Region A** —
- **Region B** —
- **Region C** —

### Key locations

- **Location 1** (in Region A) —
- **Location 2** (in Region B) —

## Factions

### Faction A
- **Goals**:
- **Resources**:
- **Methods**:
- **Internal tensions**:

### Faction B
- **Goals**:
- **Resources**:
- **Methods**:
- **Relationship to Faction A**:

## Magic / Technology System

**Source**:
**Cost**:
**Rules** (what it CAN'T do — limits create tension):
**Common practitioners**:
**Forbidden practices**:

## Cultures

### Culture A
- **Values**:
- **Naming conventions**:
- **Daily life**:
- **Death and rites**:

## Timeline

- **Year -200**: Founding event
- **Year -100**:
- **Year 0** (present):

## Glossary

- **Term 1** —
- **Term 2** —
- **Term 3** —

## Open questions

(List unresolved worldbuilding decisions to revisit before they become
load-bearing.)

- ?
- ?
"""


def cmd_lore(args):
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(LORE_TEMPLATE.format(title=args.title), encoding="utf-8")
    print(json.dumps({
        "ok": True, "subcommand": "lore",
        "output": str(out_path), "title": args.title,
        "sections": [
            "Setting", "Geography", "Factions", "Magic / Technology System",
            "Cultures", "Timeline", "Glossary", "Open questions",
        ],
    }, indent=2))


# ---------------------------------------------------------------------------
# NPC voice batch — chain audio-pipeline speech for many lines
# ---------------------------------------------------------------------------

def cmd_voice(args):
    """Read a JSON list of voice line specs, render each via audio-pipeline.

    Input JSON shape:
    [
      {"character": "Vex", "voice": "am_adam", "emotion": "fearful",
       "text": "We won't make it out alive!", "output": "vex_panic.wav"},
      ...
    ]
    """
    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"Input not found: {in_path}")
    lines = json.loads(in_path.read_text())
    if not isinstance(lines, list):
        raise SystemExit("Input must be a JSON list of voice-line specs")

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    audio_cli = AUDIO_PIPELINE_TOOLS / "audio_gen.py"
    if not audio_cli.exists():
        raise SystemExit(f"audio-pipeline tool not found at {audio_cli}")

    results: list[dict] = []
    for entry in lines:
        text = entry.get("text", "")
        voice = entry.get("voice", "af_bella")
        emotion = entry.get("emotion", "neutral")
        out_name = entry.get("output") or f'{_sanitize(entry.get("character", "line"))}_{len(results):03d}.wav'
        out_path = out_dir / out_name
        cmd = [
            sys.executable, str(audio_cli), "speech",
            "--text", text, "--voice", voice, "-o", str(out_path),
        ]
        if emotion and emotion != "neutral":
            cmd += ["--emotion", emotion, "--backend", "orpheus"]
        if args.dry_run:
            results.append({"ok": True, "dry_run": True, "command": cmd, "output": str(out_path)})
            continue
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            results.append({
                "ok": True, "output": str(out_path),
                "character": entry.get("character"), "voice": voice, "emotion": emotion,
            })
        else:
            results.append({
                "ok": False, "output": str(out_path),
                "error": proc.stderr.strip()[:200],
            })

    print(json.dumps({
        "ok": all(r.get("ok") for r in results),
        "subcommand": "voice",
        "line_count": len(lines),
        "successes": sum(1 for r in results if r.get("ok")),
        "failures": sum(1 for r in results if not r.get("ok")),
        "dry_run": args.dry_run,
        "results": results,
    }, indent=2))


# ---------------------------------------------------------------------------
# list — show supported formats and schema reminders
# ---------------------------------------------------------------------------

def cmd_list(args):
    print("Narrative skill subcommands:")
    print("  dialogue  formats: ink, yarn, dialogic")
    print("  quest     formats: godot (.tres), unity (.json)")
    print("  lore      output:  markdown world-bible template")
    print("  voice     output:  N WAV files via audio-pipeline (Orpheus/Kokoro/EdgeTTS)")
    print()
    print("See narrative_gen.py docstring at the top of the file for required")
    print("input JSON shapes for each subcommand.")


def _escape(s: str) -> str:
    return s.replace('\\', '\\\\').replace('"', '\\"')


def _sanitize(s: str) -> str:
    return "".join(c if c.isalnum() else "_" for c in s).strip("_") or "line"


def main():
    parser = argparse.ArgumentParser(description="narrative: dialogue / quest / lore / voice")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("dialogue", help="Convert dialogue tree JSON to ink/yarn/dialogic")
    p.add_argument("--input", required=True, help="Dialogue tree JSON path")
    p.add_argument("--format", required=True, choices=["ink", "yarn", "dialogic"])
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_dialogue)

    p = sub.add_parser("quest", help="Validate + emit quest spec")
    p.add_argument("--input", required=True, help="Quest spec JSON path")
    p.add_argument("--format", required=True, choices=["godot", "unity"])
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_quest)

    p = sub.add_parser("lore", help="Scaffold a markdown world-bible template")
    p.add_argument("--title", required=True, help="World title (used in heading)")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_lore)

    p = sub.add_parser("voice", help="Batch-render NPC voice lines via audio-pipeline")
    p.add_argument("--input", required=True, help="JSON list of voice-line specs")
    p.add_argument("--output-dir", required=True)
    p.add_argument("--dry-run", action="store_true",
                   help="Print the audio-pipeline commands but don't execute")
    p.set_defaults(func=cmd_voice)

    p = sub.add_parser("list", help="Show formats + input schemas")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
