#!/usr/bin/env python3
"""companion_import.py — bake companion-interchange JSON into game-template data.

Reads a companion-interchange document (single companion object or array, see
schema/companion-interchange.schema.json) and emits, per companion:

  npcs/<slug>/pandora.json           Pandora (bitbrain/pandora) importable data
  npcs/<slug>/character.dialogue.md  Dialogue Manager (nathanhoad) persona stub
  npcs/<slug>/portrait_plan.json     Portrait asset-plan for asset_gen / workflow library
  npcs/<slug>/companion.json         Normalized single-companion interchange copy

plus npcs/index.json listing everything imported.

Formats verified against bitbrain/pandora @ godot-4.x (2026-07-11):
  data.pandora = {"_entity_data": {"_entities", "_categories", "_properties"},
                  "_id_generator": {"_ids_by_context": {...}}}
  entity   keys: _id, _name, _category_id, _icon_color, _index, _property_overrides
  property keys: _id, _name, _type, _default_value, _category_id
  override value: {"type": <type_name>, "value": <written>}
  array written as index-keyed dict: {"0": {"type": "string", "value": "..."}, ...}

NOTE: the interchange projection is a point-in-time mapping of companion_ai_core
(last mapped 2026-07-11 @ localllm_poc@1eb530af, re-verified 2026-07-18 @ 7d140eb4 —
see schema/FIELD_MAPPINGS.md).
This importer only consumes interchange JSON; it never reads the Dart library.

Usage:
  python companion_import.py <interchange.json> --out <dir> [--validate]
  python companion_import.py --self-test
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import textwrap
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
SCHEMA_PATH = SKILL_DIR / "schema" / "companion-interchange.schema.json"
FIXTURE_PATH = SKILL_DIR / "fixtures" / "example_companion.json"

INTERCHANGE_VERSION = 1

# Pandora category shared by every emitted file. Deterministic string ids mean
# re-importing the same NPC (or several NPC files) into one project is
# idempotent for the category/properties and additive for entities —
# Pandora's import_data() skips ids it already has.
CATEGORY_ID = "companion-npcs"
CATEGORY_NAME = "NPCs"
ICON_COLOR = "ffffffff"


# ---------------------------------------------------------------------------
# Loading + validation
# ---------------------------------------------------------------------------

class InterchangeError(ValueError):
    """Raised when the interchange document is structurally invalid."""


def load_interchange(path: Path) -> list[dict]:
    """Load an interchange file; return a list of companion dicts."""
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    if isinstance(doc, dict):
        companions = [doc]
    elif isinstance(doc, list):
        companions = doc
    else:
        raise InterchangeError(
            f"{path}: top level must be an object or array, got {type(doc).__name__}")
    if not companions:
        raise InterchangeError(f"{path}: empty companion array")
    for i, comp in enumerate(companions):
        _check_companion(comp, f"{path}[{i}]")
    return companions


def _check_companion(comp: object, where: str) -> None:
    """Structural validation of the load-bearing invariants (stdlib-only).

    Full JSON-Schema validation is available via --validate when the
    `jsonschema` package is installed; this check keeps the importer safe
    without any dependency.
    """
    if not isinstance(comp, dict):
        raise InterchangeError(f"{where}: companion must be an object")
    version = comp.get("interchangeVersion")
    if version != INTERCHANGE_VERSION:
        raise InterchangeError(
            f"{where}: interchangeVersion must be {INTERCHANGE_VERSION}, got {version!r}. "
            "If the source library evolved, re-map per schema/FIELD_MAPPINGS.md.")
    identity = comp.get("identity")
    if not isinstance(identity, dict):
        raise InterchangeError(f"{where}: missing required object 'identity'")
    for key in ("id", "name"):
        val = identity.get(key)
        if not isinstance(val, str) or not val.strip():
            raise InterchangeError(f"{where}: identity.{key} must be a non-empty string")
    meta = comp.get("meta")
    if not isinstance(meta, dict) or not isinstance(meta.get("source"), str):
        raise InterchangeError(f"{where}: meta.source (string) is required")
    big_five = _dig(comp, "personality", "bigFive")
    if big_five is not None:
        required = {"openness", "conscientiousness", "extraversion",
                    "agreeableness", "neuroticism"}
        missing = required - set(big_five)
        if missing:
            raise InterchangeError(
                f"{where}: personality.bigFive missing traits: {sorted(missing)}")
        for trait, score in big_five.items():
            if not isinstance(score, (int, float)) or not 0.0 <= float(score) <= 1.0:
                raise InterchangeError(
                    f"{where}: personality.bigFive.{trait} must be a number in [0,1], "
                    f"got {score!r}")
    exts = comp.get("extensions")
    if exts is not None and not isinstance(exts, dict):
        raise InterchangeError(f"{where}: extensions must be an object")


def validate_against_schema(companions: list[dict]) -> None:
    """Optional strict validation using the bundled JSON Schema (needs jsonschema)."""
    try:
        import jsonschema  # type: ignore
    except ImportError:
        print("note: `jsonschema` not installed — skipping strict schema validation "
              "(structural checks already passed)", file=sys.stderr)
        return
    with open(SCHEMA_PATH, "r", encoding="utf-8") as fh:
        schema = json.load(fh)
    for comp in companions:
        jsonschema.validate(instance=comp, schema=schema)
    print(f"schema validation OK ({len(companions)} companion(s))", file=sys.stderr)


def _dig(obj: dict, *keys: str, default=None):
    cur: object = obj
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def slugify(name: str) -> str:
    norm = unicodedata.normalize("NFKD", name)
    ascii_name = norm.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_name.lower()).strip("-")
    return slug or "npc"


# ---------------------------------------------------------------------------
# Pandora projection
# ---------------------------------------------------------------------------

def _pandora_array(values: list) -> dict:
    """Serialize a list the way Pandora's array type write_value() does:
    an index-keyed dict of {"type": ..., "value": ...} entries."""
    out = {}
    for i, value in enumerate(values):
        if isinstance(value, bool):
            type_name = "bool"
        elif isinstance(value, int):
            type_name = "int"
        elif isinstance(value, float):
            type_name = "float"
        else:
            type_name, value = "string", str(value)
        out[str(i)] = {"type": type_name, "value": value}
    return out


def _prop_id(name: str) -> str:
    return f"{CATEGORY_ID}.prop.{name}"


# (property_name, pandora_type, default) — defined once on the NPC category.
PANDORA_PROPERTIES: list[tuple[str, str, object]] = [
    ("source_id", "string", ""),
    ("display_name", "string", ""),
    ("age", "int", 0),
    ("gender", "string", ""),
    ("pronouns", "string", ""),
    ("culture", "string", ""),
    ("ethnicity", "string", ""),
    ("nationality", "string", ""),
    ("languages", "array", {}),
    ("location", "string", ""),
    ("archetype", "string", ""),
    ("mbti", "string", ""),
    ("enneagram", "string", ""),
    ("attachment_style", "string", ""),
    ("openness", "float", 0.5),
    ("conscientiousness", "float", 0.5),
    ("extraversion", "float", 0.5),
    ("agreeableness", "float", 0.5),
    ("neuroticism", "float", 0.5),
    ("quirks", "array", {}),
    ("occupation", "string", ""),
    ("values", "array", {}),
    ("skills", "array", {}),
    ("hobbies", "array", {}),
    ("interests", "array", {}),
    ("affiliations", "array", {}),
    ("social_class", "string", ""),
    ("wealth", "float", 0.5),
    ("reputation", "float", 0.5),
    ("goals_short_term", "array", {}),
    ("goals_long_term", "array", {}),
    ("secrets", "array", {}),
    ("fears", "array", {}),
    ("voice_pitch", "string", ""),
    ("voice_pace", "string", ""),
    ("voice_accent", "string", ""),
    ("speech_style", "string", ""),
    ("baseline_valence", "float", 0.0),
    ("baseline_arousal", "float", 0.5),
    ("baseline_dominance", "float", 0.5),
    ("mood_stability", "float", 0.5),
    ("relationships", "array", {}),
    ("backstory", "string", ""),
    ("portrait_path", "string", ""),
]

_PANDORA_TYPES = {name: ptype for name, ptype, _ in PANDORA_PROPERTIES}


def _fmt_level(value: float) -> str:
    """Dreyfus stage from a 0-1 proficiency (mirrors CompanionSkillProficiency)."""
    if value < 0.15:
        return "novice"
    if value < 0.30:
        return "advanced beginner"
    if value < 0.50:
        return "competent"
    if value < 0.70:
        return "proficient"
    if value < 0.85:
        return "expert"
    return "master"


def _collect_overrides(comp: dict) -> dict:
    """Project interchange fields onto Pandora property overrides."""
    identity = comp.get("identity", {})
    personality = comp.get("personality", {})
    social = comp.get("social", {})
    narrative = comp.get("narrative", {})
    voice = comp.get("voice", {})
    baseline = comp.get("emotionalBaseline", {})
    culture = identity.get("culture", {}) or {}

    overrides: dict[str, object] = {
        "source_id": identity.get("id"),
        "display_name": identity.get("name"),
        "age": identity.get("age"),
        "gender": identity.get("gender"),
        "pronouns": identity.get("pronouns"),
        "ethnicity": culture.get("ethnicity"),
        "nationality": culture.get("nationality"),
        "archetype": personality.get("archetype"),
        "mbti": personality.get("mbti"),
        "enneagram": personality.get("enneagram"),
        "attachment_style": personality.get("attachmentStyle"),
        "social_class": social.get("socialClass"),
        "wealth": social.get("wealth"),
        "reputation": social.get("reputation"),
        "voice_pitch": voice.get("pitch"),
        "voice_pace": voice.get("pace"),
        "voice_accent": voice.get("accent"),
        "speech_style": voice.get("speechStyle"),
        "baseline_valence": baseline.get("valence"),
        "baseline_arousal": baseline.get("arousal"),
        "baseline_dominance": baseline.get("dominance"),
        "mood_stability": baseline.get("moodStability"),
        "backstory": narrative.get("backstorySummary"),
    }

    primary = culture.get("primary")
    secondary = culture.get("secondary") or []
    if primary:
        overrides["culture"] = " / ".join([primary, *secondary])
    if culture.get("languages"):
        overrides["languages"] = list(culture["languages"])

    location = identity.get("location") or {}
    loc_bits = [location.get(k) for k in ("city", "region", "country")]
    loc_str = ", ".join(b for b in loc_bits if b)
    if loc_str:
        overrides["location"] = loc_str

    big_five = personality.get("bigFive") or {}
    for trait in ("openness", "conscientiousness", "extraversion",
                  "agreeableness", "neuroticism"):
        if trait in big_five:
            overrides[trait] = float(big_five[trait])

    if personality.get("quirks"):
        overrides["quirks"] = list(personality["quirks"])

    occupation = social.get("occupation") or {}
    occ_bits = [occupation.get("title"), occupation.get("workplace")]
    occ_str = " @ ".join(b for b in occ_bits if b)
    if occ_str:
        overrides["occupation"] = occ_str

    values = social.get("values") or {}
    if values:
        ranked = sorted(values.items(), key=lambda kv: -float(kv[1]))
        overrides["values"] = [f"{name} ({float(w):.2f})" for name, w in ranked]

    skills = social.get("skills") or []
    if skills:
        overrides["skills"] = [
            f"{s['name']} ({_fmt_level(float(s['proficiency']))})"
            if isinstance(s, dict) and s.get("proficiency") is not None
            else (s["name"] if isinstance(s, dict) else str(s))
            for s in skills
        ]

    hobbies = social.get("hobbies") or []
    if hobbies:
        overrides["hobbies"] = [
            f"{h['name']} ({_fmt_level(float(h['skillLevel']))})"
            if isinstance(h, dict) and h.get("skillLevel") is not None
            else (h["name"] if isinstance(h, dict) else str(h))
            for h in hobbies
        ]

    interests = social.get("interests") or {}
    if interests:
        ranked = sorted(interests.items(), key=lambda kv: -float(kv[1]))
        overrides["interests"] = [f"{name} ({float(w):.2f})" for name, w in ranked]

    if social.get("affiliations"):
        overrides["affiliations"] = list(social["affiliations"])

    goals = narrative.get("goals") or {}
    if goals.get("shortTerm"):
        overrides["goals_short_term"] = list(goals["shortTerm"])
    long_term = list(goals.get("longTerm") or []) + list(goals.get("life") or [])
    if long_term:
        overrides["goals_long_term"] = long_term

    secrets = narrative.get("secrets") or []
    if secrets:
        overrides["secrets"] = [
            f"[{s.get('severity', 'unrated')}] {s['description']}"
            if isinstance(s, dict) else str(s)
            for s in secrets
        ]

    if narrative.get("fears"):
        overrides["fears"] = list(narrative["fears"])

    rels = comp.get("relationships") or []
    if rels:
        overrides["relationships"] = [
            f"{r.get('targetName') or r['target']}: {r['type']}"
            + (f" (closeness {float(r['closeness']):.2f})" if r.get("closeness") is not None else "")
            for r in rels
        ]

    return {k: v for k, v in overrides.items() if v is not None and v != "" and v != []}


def build_pandora(comp: dict, slug: str) -> dict:
    """Build a Pandora-importable document (matches data.pandora / import format)."""
    properties = {}
    for name, ptype, default in PANDORA_PROPERTIES:
        properties[_prop_id(name)] = {
            "_id": _prop_id(name),
            "_name": name,
            "_type": ptype,
            "_default_value": default,
            "_category_id": CATEGORY_ID,
        }

    property_overrides = {}
    for name, value in _collect_overrides(comp).items():
        ptype = _PANDORA_TYPES[name]
        if ptype == "array":
            written = _pandora_array(value)
        elif ptype == "float":
            written = float(value)
        elif ptype == "int":
            written = int(value)
        else:
            written = str(value)
        property_overrides[name] = {"type": ptype, "value": written}

    entity_id = f"companion-npc.{slug}"
    return {
        "_entity_data": {
            "_categories": {
                CATEGORY_ID: {
                    "_id": CATEGORY_ID,
                    "_name": CATEGORY_NAME,
                    "_category_id": "",
                    "_icon_color": ICON_COLOR,
                    "_index": 0,
                },
            },
            "_properties": properties,
            "_entities": {
                entity_id: {
                    "_id": entity_id,
                    "_name": _dig(comp, "identity", "name"),
                    "_category_id": CATEGORY_ID,
                    "_icon_color": ICON_COLOR,
                    "_index": 0,
                    "_property_overrides": property_overrides,
                },
            },
        },
        "_id_generator": {"_ids_by_context": {"default": 0}},
    }


# ---------------------------------------------------------------------------
# Dialogue Manager persona stub
# ---------------------------------------------------------------------------

def _first_name(name: str) -> str:
    return name.split()[0] if name.split() else name


def _state_name(slug: str) -> str:
    return "".join(part.capitalize() for part in slug.split("-")) + "State"


def _trait_word(score: float, low: str, mid: str, high: str) -> str:
    if score < 0.35:
        return low
    if score < 0.65:
        return mid
    return high


def _personality_summary(personality: dict) -> str:
    big_five = personality.get("bigFive") or {}
    if not big_five:
        return personality.get("archetype", "balanced")
    bits = [
        _trait_word(big_five.get("openness", 0.5),
                    "conventional, prefers the familiar",
                    "moderately curious",
                    "openly curious and imaginative"),
        _trait_word(big_five.get("conscientiousness", 0.5),
                    "spontaneous, loose with plans",
                    "reasonably organized",
                    "meticulous and dependable"),
        _trait_word(big_five.get("extraversion", 0.5),
                    "quiet, recharges alone",
                    "socially flexible",
                    "outgoing and energized by people"),
        _trait_word(big_five.get("agreeableness", 0.5),
                    "blunt and competitive",
                    "fair-minded",
                    "warm, accommodating, conflict-averse"),
        _trait_word(big_five.get("neuroticism", 0.5),
                    "unflappable",
                    "even-keeled with occasional worry",
                    "sensitive, prone to worry"),
    ]
    return "; ".join(bits)


def build_dialogue_stub(comp: dict, slug: str) -> str:
    identity = comp.get("identity", {})
    personality = comp.get("personality", {})
    social = comp.get("social", {})
    narrative = comp.get("narrative", {})
    voice = comp.get("voice", {})
    culture = identity.get("culture", {}) or {}

    name = identity["name"]
    first = _first_name(name)
    state = _state_name(slug)

    def line(text: str = "") -> str:
        return f"# {text}".rstrip()

    header: list[str] = []
    bar = "# " + "=" * 72
    header.append(bar)
    header.append(line(f"PERSONA: {name}  (companion-interchange v{INTERCHANGE_VERSION}, id: {identity['id']})"))
    header.append(bar)

    demo_bits = []
    if identity.get("age"):
        demo_bits.append(f"{identity['age']}")
    if identity.get("gender"):
        demo_bits.append(identity["gender"])
    if identity.get("pronouns"):
        demo_bits.append(f"({identity['pronouns']})")
    cultures = " / ".join([culture.get("primary", "")] + (culture.get("secondary") or [])).strip(" /")
    if cultures:
        demo_bits.append(cultures)
    occupation = social.get("occupation") or {}
    if occupation.get("title"):
        occ = occupation["title"]
        if occupation.get("workplace"):
            occ += f" at {occupation['workplace']}"
        demo_bits.append(occ)
    if demo_bits:
        header.append(line(f"WHO: {', '.join(demo_bits)}"))

    if personality.get("archetype"):
        arch = personality["archetype"]
        if personality.get("mbti"):
            arch += f" ({personality['mbti']}"
            if personality.get("enneagram"):
                arch += f", {personality['enneagram']}"
            arch += ")"
        header.append(line(f"ARCHETYPE: {arch}"))
    header.append(line(f"PERSONALITY: {_personality_summary(personality)}"))

    quirks = personality.get("quirks") or []
    if quirks:
        header.append(line(f"QUIRKS: {'; '.join(quirks[:6])}"))

    speech_bits = []
    for key, label in (("tone", "tone"), ("pace", "pace"), ("timbre", "timbre"),
                       ("accent", "accent"), ("speechStyle", None)):
        if voice.get(key):
            speech_bits.append(f"{label}: {voice[key]}" if label else voice[key])
    for tag in voice.get("styleTags") or []:
        speech_bits.append(tag)
    if speech_bits:
        header.append(line(f"SPEECH: {'; '.join(speech_bits)}"))

    langs = culture.get("languages") or []
    if len(langs) > 1:
        header.append(line(f"LANGUAGES: {', '.join(langs)} (may code-switch when emotional)"))

    values = social.get("values") or {}
    if values:
        ranked = [k for k, _ in sorted(values.items(), key=lambda kv: -float(kv[1]))]
        header.append(line(f"VALUES: {', '.join(ranked[:6])}"))

    goals = narrative.get("goals") or {}
    goal_bits = list(goals.get("shortTerm") or [])[:2] + list(goals.get("longTerm") or [])[:2]
    if goal_bits:
        header.append(line(f"CURRENT GOALS: {'; '.join(goal_bits)}"))

    fears = narrative.get("fears") or []
    if fears:
        header.append(line(f"FEARS (drives avoidance, never stated outright): {'; '.join(fears[:4])}"))

    secrets = narrative.get("secrets") or []
    if secrets:
        header.append(line("SECRETS (never revealed in casual dialogue; gate behind high trust):"))
        for secret in secrets[:4]:
            if isinstance(secret, dict):
                header.append(line(f"  - [{secret.get('severity', 'unrated')}] {secret['description']}"))
            else:
                header.append(line(f"  - {secret}"))

    if narrative.get("backstorySummary"):
        header.append(line("BACKSTORY:"))
        for chunk in narrative["backstorySummary"].splitlines():
            for wrapped in textwrap.wrap(chunk, width=76):
                header.append(line(f"  {wrapped}"))

    rels = comp.get("relationships") or []
    if rels:
        rel_bits = [f"{r.get('targetName') or r['target']} ({r['type']})" for r in rels[:5]]
        header.append(line(f"RELATIONSHIPS: {'; '.join(rel_bits)}"))

    header.append(line())
    header.append(line("LLM AUTHORING NOTES:"))
    header.append(line(f"  - Write {first}'s lines in the voice above; keep quirks occasional, not constant."))
    header.append(line(f"  - Suggested state autoload: {state} (met_before: bool, affection: int)."))
    header.append(line(f"  - Gate secrets/vulnerable lines behind {state}.affection thresholds."))
    header.append(line("  - Full data: companion.json (same folder); Pandora entity: pandora.json."))
    header.append(bar)

    body = f"""
~ {slug.replace('-', '_')}_greeting

if {state}.met_before
\t{first}: Back again! Good — I was hoping you'd show up today.
\t{first}: The usual? Or are we being adventurous?
else
\t{first}: Oh — welcome in! I don't think I've seen you before.
\t{first}: I'm {first}. Sit wherever you like, I'll be right with you.
\tset {state}.met_before = true

=> END
"""
    return "\n".join(header) + "\n" + body


# ---------------------------------------------------------------------------
# Portrait asset-plan
# ---------------------------------------------------------------------------

NEGATIVE_PROMPT = (
    "deformed face, asymmetric eyes, extra fingers, bad hands, blurry, "
    "low quality, watermark, text, signature, oversaturated, plastic skin"
)


def compose_portrait_prompt(comp: dict) -> str:
    """Compose a portrait prompt from the appearance projection.

    Uses appearance.portraitPrompt verbatim when the exporter supplied one;
    otherwise builds one from structured fields. Always contains the literal
    {style} placeholder for the template's style anchor (style-anchor skill).
    """
    appearance = comp.get("appearance", {}) or {}
    supplied = appearance.get("portraitPrompt")
    if supplied:
        return supplied if "{style}" in supplied else "{style} " + supplied

    identity = comp.get("identity", {})
    personality = comp.get("personality", {})
    social = comp.get("social", {})
    culture = identity.get("culture", {}) or {}
    face = appearance.get("face", {}) or {}

    subject_bits = []
    if identity.get("age"):
        subject_bits.append(f"{identity['age']}-year-old")
    if culture.get("ethnicity"):
        subject_bits.append(culture["ethnicity"])
    elif culture.get("primary"):
        subject_bits.append(culture["primary"])
    if identity.get("gender"):
        subject_bits.append(identity["gender"])
    subject = " ".join(subject_bits) or "adult"

    detail_bits = []
    if appearance.get("hairColor"):
        detail_bits.append(appearance["hairColor"] + " hair")
    if appearance.get("hairStyle"):
        detail_bits.append(appearance["hairStyle"])
    if appearance.get("eyeColor"):
        eyes = f"{appearance['eyeColor']} eyes"
        if face.get("eyeShape"):
            eyes = f"{face['eyeShape']} {eyes}"
        detail_bits.append(eyes)
    if appearance.get("skinTone"):
        detail_bits.append(f"{appearance['skinTone']} skin")
    if face.get("faceShape"):
        detail_bits.append(f"{face['faceShape']} face")
    if face.get("facialHair") and face["facialHair"] not in ("none", "clean-shaven"):
        detail_bits.append(face["facialHair"])
    for feature in appearance.get("distinguishingFeatures") or []:
        detail_bits.append(feature)
    if appearance.get("typicalOutfit"):
        detail_bits.append(f"wearing {appearance['typicalOutfit']}")

    big_five = personality.get("bigFive") or {}
    agree = big_five.get("agreeableness", 0.5)
    extra = big_five.get("extraversion", 0.5)
    neuro = big_five.get("neuroticism", 0.5)
    if agree >= 0.65 and extra >= 0.5:
        expression = "warm approachable smile"
    elif agree >= 0.65:
        expression = "gentle reserved smile"
    elif neuro >= 0.6:
        expression = "guarded thoughtful expression"
    elif extra >= 0.65:
        expression = "confident open expression"
    else:
        expression = "calm neutral expression"
    detail_bits.append(expression)
    if appearance.get("presence"):
        detail_bits.append(appearance["presence"])

    occupation = social.get("occupation") or {}
    context = f", {occupation['title']}" if occupation.get("title") else ""

    return (f"{{style}} character portrait of a {subject}{context}, "
            + ", ".join(detail_bits)
            + ", head and shoulders, looking at viewer, detailed face")


def build_portrait_plan(comp: dict, slug: str) -> dict:
    identity = comp.get("identity", {})
    return {
        "version": 1,
        "npc_id": identity.get("id"),
        "npc_slug": slug,
        "npc_name": identity.get("name"),
        "asset_kind": "portrait",
        "asset_gen_type": "portrait",
        "workflow": "zit-txt2img",
        "prompt": compose_portrait_prompt(comp),
        "negative": NEGATIVE_PROMPT,
        "size": [1024, 1024],
        "style_placeholders": ["{style}"],
        "lora_slots": {
            "0": {
                "role": "style",
                "value": None,
                "note": "Style LoRA. asset_gen's router auto-loads the pixel-art LoRA "
                        "for pixel types; for painterly/realistic templates resolve "
                        "via the style-anchor skill and pin it here.",
            },
            "1": {
                "role": "character",
                "value": None,
                "note": "Character-identity LoRA slot. Leave null for the first "
                        "renders; once 8-12 portraits of this NPC are approved, "
                        "train an identity LoRA (character-sheet skill loop, "
                        "ai-toolkit Z-Image preset) and pin it here so every future "
                        "asset of this NPC keeps the same face.",
            },
        },
        "reference_asset": None,
        "notes": [
            "Replace {style} with the template's style anchor before submitting "
            "(style-anchor skill), or pass the prompt through asset_gen which "
            "handles it.",
            "If reference.png exists in the template's style dir, the asset_gen "
            "router switches to qwen-edit-instruct img2img automatically for "
            "portrait types — that is desirable for style continuity.",
            "Register the result in assets/manifest.json (asset-manifest skill) "
            "and write the path back into the Pandora entity's portrait_path "
            "property and this plan's produced_asset field.",
        ],
        "produced_asset": None,
    }


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def import_companions(interchange_path: Path, out_dir: Path,
                      strict_validate: bool = False) -> list[dict]:
    companions = load_interchange(interchange_path)
    if strict_validate:
        validate_against_schema(companions)

    index_entries = []
    used_slugs: set[str] = set()
    for comp in companions:
        base_slug = slugify(comp["identity"]["name"])
        slug = base_slug
        n = 2
        while slug in used_slugs:
            slug = f"{base_slug}-{n}"
            n += 1
        used_slugs.add(slug)

        npc_dir = out_dir / "npcs" / slug
        npc_dir.mkdir(parents=True, exist_ok=True)

        outputs = {
            "pandora.json": build_pandora(comp, slug),
            "portrait_plan.json": build_portrait_plan(comp, slug),
            "companion.json": comp,
        }
        for filename, payload in outputs.items():
            with open(npc_dir / filename, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, indent=2, ensure_ascii=False)
                fh.write("\n")
        with open(npc_dir / "character.dialogue.md", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(build_dialogue_stub(comp, slug))

        index_entries.append({
            "slug": slug,
            "id": comp["identity"]["id"],
            "name": comp["identity"]["name"],
            "pandora_entity_id": f"companion-npc.{slug}",
            "dir": f"npcs/{slug}",
            "source": _dig(comp, "meta", "source"),
        })
        print(f"imported: {comp['identity']['name']}  ->  {npc_dir}")

    index_path = out_dir / "npcs" / "index.json"
    index = {
        "interchangeVersion": INTERCHANGE_VERSION,
        "importedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "npcs": index_entries,
    }
    with open(index_path, "w", encoding="utf-8") as fh:
        json.dump(index, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print(f"index: {index_path}")
    return index_entries


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def self_test() -> int:
    """Run the importer against the bundled fixture and verify every output."""
    import tempfile

    failures: list[str] = []

    def check(cond: bool, what: str) -> None:
        status = "ok" if cond else "FAIL"
        print(f"  [{status}] {what}")
        if not cond:
            failures.append(what)

    print(f"self-test: fixture = {FIXTURE_PATH}")
    with tempfile.TemporaryDirectory(prefix="companion_import_test_") as tmp:
        out_dir = Path(tmp)
        entries = import_companions(FIXTURE_PATH, out_dir, strict_validate=True)
        check(len(entries) == 1, "one companion imported")
        slug = entries[0]["slug"]
        npc_dir = out_dir / "npcs" / slug

        for filename in ("pandora.json", "portrait_plan.json", "companion.json"):
            path = npc_dir / filename
            check(path.is_file(), f"{filename} exists")
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)  # raises on invalid JSON
            check(isinstance(data, dict), f"{filename} parses as JSON object")

        with open(npc_dir / "pandora.json", "r", encoding="utf-8") as fh:
            pandora = json.load(fh)
        entity_data = pandora.get("_entity_data", {})
        check(set(entity_data) == {"_categories", "_entities", "_properties"},
              "pandora _entity_data has _categories/_entities/_properties")
        check(CATEGORY_ID in entity_data["_categories"], "NPC category present")
        entities = entity_data["_entities"]
        check(len(entities) == 1, "exactly one pandora entity")
        entity = next(iter(entities.values()))
        check(entity["_category_id"] == CATEGORY_ID, "entity belongs to NPC category")
        overrides = entity["_property_overrides"]
        for prop in ("display_name", "age", "openness", "quirks", "secrets",
                     "voice_pitch", "baseline_valence", "occupation"):
            check(prop in overrides, f"override present: {prop}")
        check(all(set(v) == {"type", "value"} for v in overrides.values()),
              "every override is a {type, value} pair")
        quirks = overrides["quirks"]["value"]
        check(isinstance(quirks, dict) and "0" in quirks
              and quirks["0"].get("type") == "string",
              "array override uses Pandora index-keyed {type,value} encoding")
        prop_names = {p["_name"] for p in entity_data["_properties"].values()}
        check(set(overrides).issubset(prop_names),
              "every override has a matching property definition")
        check(all(p["_category_id"] == CATEGORY_ID
                  for p in entity_data["_properties"].values()),
              "all properties defined on the NPC category")
        check("_id_generator" in pandora, "pandora _id_generator present")

        with open(npc_dir / "portrait_plan.json", "r", encoding="utf-8") as fh:
            plan = json.load(fh)
        check("{style}" in plan["prompt"], "portrait prompt contains {style} placeholder")
        check(plan["workflow"] == "zit-txt2img", "portrait plan targets zit-txt2img")
        check(bool(plan["negative"]), "portrait plan has a negative prompt")
        check(plan["lora_slots"]["1"]["role"] == "character",
              "portrait plan reserves the character-LoRA slot")

        dialogue_path = npc_dir / "character.dialogue.md"
        check(dialogue_path.is_file(), "character.dialogue.md exists")
        dialogue = dialogue_path.read_text(encoding="utf-8")
        check("PERSONA:" in dialogue, "dialogue stub has persona header")
        check("\n~ " in dialogue, "dialogue stub has a Dialogue Manager title (~)")
        check("=> END" in dialogue, "dialogue stub ends the flow (=> END)")
        check("set " in dialogue and "if " in dialogue,
              "dialogue stub demonstrates state (if/set)")
        check("SECRETS" in dialogue, "persona header carries secrets guidance")

        with open(npc_dir / "companion.json", "r", encoding="utf-8") as fh:
            comp = json.load(fh)
        with open(FIXTURE_PATH, "r", encoding="utf-8") as fh:
            fixture = json.load(fh)
        check(comp == fixture, "companion.json round-trips the interchange verbatim")
        check(comp.get("extensions") == fixture.get("extensions"),
              "extensions passthrough preserved verbatim")

        with open(out_dir / "npcs" / "index.json", "r", encoding="utf-8") as fh:
            index = json.load(fh)
        check(index["npcs"][0]["slug"] == slug, "index.json lists the npc")

    if failures:
        print(f"self-test: {len(failures)} FAILURE(S)")
        return 1
    print("self-test: all checks passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Import companion-interchange JSON into game-template data "
                    "(Pandora entity, Dialogue Manager persona stub, portrait plan).")
    parser.add_argument("interchange", nargs="?", type=Path,
                        help="Path to interchange JSON (single companion or array)")
    parser.add_argument("--out", type=Path, default=Path("."),
                        help="Output root; NPCs land in <out>/npcs/<slug>/ (default: .)")
    parser.add_argument("--validate", action="store_true",
                        help="Also validate against the bundled JSON Schema "
                             "(requires the `jsonschema` package)")
    parser.add_argument("--self-test", action="store_true",
                        help="Run the importer against the bundled fixture and "
                             "verify all outputs")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.interchange is None:
        parser.error("interchange file required (or use --self-test)")
    try:
        import_companions(args.interchange, args.out, strict_validate=args.validate)
    except InterchangeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
