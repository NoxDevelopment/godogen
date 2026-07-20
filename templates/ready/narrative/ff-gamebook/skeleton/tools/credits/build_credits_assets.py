#!/usr/bin/env python3
"""Export credits provenance from this template's asset manifest.

The `credits` skill's `credits_gen.py assemble` expects an assets-credits JSON in
the shape `asset-manifest export --format credits` emits (by_license / loras /
providers / unlicensed). This template does not use the standard flat
`assets/manifest.json` schema — it uses a Studio-owned SLOT manifest
(`assets.manifest.json`, read by AssetBinder) where every art/audio surface is a
stable-ID slot with nested `provenance`. This adapter reads that slot manifest and
emits both:

  * build/credits_assets.json  — the credits-skill assets feed (visual assets
    grouped by license, plus generation styles + pipelines + an unlicensed
    ship-blocker list), and
  * credits.extra.json         — the hand/auto merge file: roles, fonts and
    engine/tools are authored here; the AUDIO section is regenerated from the
    manifest's audio slots on every run so credits can never drift as tracks are
    swapped from the Studio.

Run this, then `credits_gen.py assemble`. Re-run after any asset drop.
"""
from __future__ import annotations

import json
from collections import OrderedDict
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKELETON = HERE.parent.parent           # .../skeleton
MANIFEST = SKELETON / "assets.manifest.json"
BUILD = HERE / "build"
EXTRA = HERE / "credits.extra.json"

# Hand-authored credit blocks the manifest doesn't carry (fonts are recorded by
# the `typography` skill; roles/engine/tools are project facts). Audio is added
# from the manifest below — do not hand-edit the audio list.
ROLES = [
    {"role": "Original world, text, rules & code", "names": ["NoxDev Studio"]},
]
FONTS = [
    {"name": "Cinzel", "license": "OFL-1.1", "author": "Natanael Gama"},
    {"name": "UncialAntiqua", "license": "OFL-1.1", "author": "Astigmatic"},
    {"name": "MedievalSharp", "license": "OFL-1.1", "author": "Wojciech Kalinowski"},
    {"name": "Montserrat", "license": "OFL-1.1", "author": "Julieta Ulanovsky"},
]
ENGINE = "Godot Engine (MIT)"
TOOLS = ["nox_if_engine (ff-2d6 ruleset)", "nox_ui shell", "ComfyUI", "Z-Image-Turbo"]
SPECIAL_THANKS = ["OpenGameArt & Kenney (CC0 asset commons)"]


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def build(manifest: dict) -> tuple[dict, list]:
    by_license: "OrderedDict[str, OrderedDict]" = OrderedDict()
    styles: "OrderedDict[str, None]" = OrderedDict()
    providers: "OrderedDict[str, None]" = OrderedDict()
    unlicensed: list[str] = []
    audio_by_pack: "OrderedDict[tuple, dict]" = OrderedDict()

    for slot in manifest.get("slots", []):
        prov = slot.get("provenance", {}) or {}
        slot_id = slot.get("slotId", "?")
        file = slot.get("file")
        kind = slot.get("kind", "")

        # --- audio → the "Music & Sound" section (extra.audio), from the manifest
        if kind == "audio":
            if file is None:
                continue
            lic = prov.get("license", "")
            if not lic:
                unlicensed.append(slot_id)
                continue
            pack = prov.get("pack", "?")
            key = (pack, lic)
            if key not in audio_by_pack:
                audio_by_pack[key] = {
                    "name": pack, "license": lic, "author": prov.get("author", ""),
                }
            continue

        # --- generated art → record its style + pipeline, group under its license
        gkind = prov.get("kind", "")
        if gkind == "generated" or slot.get("policy") == "generated" and prov.get("style"):
            style = prov.get("style")
            if style:
                styles.setdefault(
                    f"{style} — NoxDev-generated on {prov.get('baseModel', 'base model')} (no LoRA)", None
                )
            if prov.get("pipeline"):
                providers.setdefault(prov["pipeline"], None)
            lic = prov.get("license") or "NoxDev-generated"
            _add(by_license, lic, "veritas-gamebook (NoxDev-generated plates)", None)
            continue

        # --- placeholder plates: NoxDev-made stand-ins pending Phase-5 final art
        if gkind == "placeholder":
            _add(by_license, "NoxDev-generated (placeholder — pending Phase-5 art)",
                 "veritas-gamebook placeholder plates", None)
            continue

        # --- reused third-party assets → group by license, by pack
        lic = prov.get("license", "")
        if not lic:
            if file is not None:
                unlicensed.append(slot_id)
            continue
        _add(by_license, lic, prov.get("pack", "?"), prov.get("author"), prov.get("url"))

    assets = {
        "by_license": {k: list(v.values()) for k, v in by_license.items()},
        "loras": list(styles.keys()),
        "providers": list(providers.keys()),
        "unlicensed": unlicensed,
    }
    audio = list(audio_by_pack.values())
    return assets, audio


def _add(by_license, lic, source, author, url=None):
    bucket = by_license.setdefault(lic, OrderedDict())
    key = (source, author or "")
    if key not in bucket:
        bucket[key] = {"source": source, "author": author or "", "count": 0}
        if url:
            bucket[key]["url"] = url
    bucket[key]["count"] += 1


def write_extra(audio: list) -> None:
    extra = {
        "game_title": "THE GREY TITHE",
        "studio": "A NoxDev Studio production",
        "roles": ROLES,
        "fonts": FONTS,
        "audio": audio,
        "engine": ENGINE,
        "tools": TOOLS,
        "special_thanks": SPECIAL_THANKS,
    }
    EXTRA.write_text(json.dumps(extra, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    manifest = load_manifest()
    assets, audio = build(manifest)
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "credits_assets.json").write_text(
        json.dumps(assets, indent=2) + "\n", encoding="utf-8")
    write_extra(audio)
    print(json.dumps({
        "ok": True,
        "licenses": list(assets["by_license"].keys()),
        "audio_packs": [a["name"] for a in audio],
        "styles": assets["loras"],
        "providers": assets["providers"],
        "unlicensed_count": len(assets["unlicensed"]),
        "unlicensed": assets["unlicensed"],
    }, indent=2))


if __name__ == "__main__":
    main()
