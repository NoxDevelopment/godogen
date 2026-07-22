#!/usr/bin/env python3
"""validate_adventure.py — offline validator for ff-gamebook adventure packages.

Validates an ADVENTURE_FORMAT.md package (folder or .zip) or a bare legacy
scenario .json, mirroring the in-engine authoring validator
(addons/nox_if_engine/if_adventure_validator.gd) plus package-level concerns:

  1. book.json schema  — required fields, supported formatVersion, difficulty 1..5,
     id shape, cover slot resolvable;
  2. adventure.json    — start exists; every goto target exists (choice gotos,
     check-outcome gotos, goto-effects); reachability from start; dead-ends;
     a victory ending reachable;
  3. state consistency — conditions that read a flag/codeword/var/item nothing
     ever writes (error), codewords set but never tested (warning);
  4. assets            — every slot file exists (relative -> package root,
     res:// -> --project-root);
  5. FF conventions    — combat sections carry _onwin/_ondeath outcome choices,
     luck tests carry _onlucky/_onunlucky, skill/stamina tests _onsuccess/_onfailure.

Usage:
    python tools/validate_adventure.py <package-dir | package.zip | scenario.json>
           [--project-root <skeleton-dir>]

Exit code 0 = valid (warnings allowed), 1 = errors found, 2 = bad invocation.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
import zipfile
from pathlib import Path

SUPPORTED_FORMAT_VERSION = 1
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
BOOK_REQUIRED = ["id", "title", "author", "blurb", "cover"]


# --------------------------------------------------------------------------- io


def read_json(path: Path, errors: list[str]) -> dict | None:
    try:
        with path.open(encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{path.name}: cannot read/parse — {exc}")
        return None
    if not isinstance(data, dict):
        errors.append(f"{path.name}: top level is not a JSON object")
        return None
    return data


# ------------------------------------------------------------------- book.json


def validate_manifest(man: dict, errors: list[str], warnings: list[str]) -> None:
    for key in BOOK_REQUIRED:
        if not str(man.get(key, "")).strip():
            errors.append(f"book.json: missing required field '{key}'")
    fmt = man.get("formatVersion")
    if not isinstance(fmt, int) or fmt <= 0:
        errors.append("book.json: missing/invalid 'formatVersion' (positive int)")
    elif fmt > SUPPORTED_FORMAT_VERSION:
        errors.append(
            f"book.json: formatVersion {fmt} is newer than supported {SUPPORTED_FORMAT_VERSION}")
    book_id = str(man.get("id", ""))
    if book_id and not ID_RE.match(book_id):
        errors.append(f"book.json: id '{book_id}' must match [a-z0-9-] (lowercase)")
    diff = man.get("difficulty", 3)
    if not isinstance(diff, int) or not 1 <= diff <= 5:
        errors.append(f"book.json: difficulty {diff!r} must be an int 1..5")
    slots = man.get("slots", {})
    if slots and not isinstance(slots, dict):
        errors.append("book.json: 'slots' must be an object of slotId -> file path")
    cover = str(man.get("cover", ""))
    if cover and isinstance(slots, dict) and cover not in slots:
        warnings.append(
            f"book.json: cover slot '{cover}' is not in this package's slots "
            "(must resolve through the game's global manifest)")


def validate_assets(man: dict, package_root: Path, project_root: Path | None,
                    errors: list[str], warnings: list[str]) -> None:
    slots = man.get("slots", {})
    if not isinstance(slots, dict):
        return
    for slot_id, rel in slots.items():
        rel = str(rel)
        if rel.startswith("res://"):
            if project_root is None:
                warnings.append(
                    f"slot '{slot_id}': res:// path not checked (no --project-root)")
                continue
            target = project_root / rel[len("res://"):]
        elif rel.startswith("user://"):
            warnings.append(f"slot '{slot_id}': user:// path not checkable offline")
            continue
        else:
            target = package_root / rel
        if not target.is_file():
            errors.append(f"slot '{slot_id}': file not found — {target}")


# --------------------------------------------------------------- scenario graph


def _iter_effects(effects) -> list[dict]:
    return [e for e in (effects or []) if isinstance(e, dict)]


def _goto_of_effect(eff: dict) -> str:
    if str(eff.get("kind", "")) != "goto":
        return ""
    return str(eff.get("value", eff.get("target", "")) or "")


def _check_targets(check) -> list[str]:
    out: list[str] = []
    if not isinstance(check, dict):
        return out
    for outcome in (check.get("outcomes") or {}).values():
        if not isinstance(outcome, dict):
            continue
        goto = str(outcome.get("goto", "") or "")
        if goto:
            out.append(goto)
        for eff in _iter_effects(outcome.get("effects")):
            g = _goto_of_effect(eff)
            if g:
                out.append(g)
    return out


def successors(passage: dict) -> list[str]:
    out: list[str] = []
    for eff in _iter_effects(passage.get("onEnter")):
        g = _goto_of_effect(eff)
        if g:
            out.append(g)
    out += _check_targets(passage.get("check"))
    for choice in passage.get("choices") or []:
        if not isinstance(choice, dict):
            continue
        goto = str(choice.get("goto", "") or "")
        if goto:
            out.append(goto)
        for eff in _iter_effects(choice.get("effects")):
            g = _goto_of_effect(eff)
            if g:
                out.append(g)
        out += _check_targets(choice.get("check"))
    return out


def validate_scenario(scen: dict, errors: list[str], warnings: list[str]) -> None:
    passages = {str(p.get("id", "")): p
                for p in scen.get("passages", []) if isinstance(p, dict)}
    passages.pop("", None)
    if not passages:
        errors.append("adventure.json: no passages")
        return
    start = str(scen.get("start", ""))
    if not start:
        errors.append("adventure.json: no start passage")
    elif start not in passages:
        errors.append(f"adventure.json: start passage '{start}' missing")
    if not str(scen.get("ruleset", "")):
        errors.append("adventure.json: no ruleset id")

    # dangling routes
    for pid, p in passages.items():
        for target in successors(p):
            if target not in passages:
                errors.append(f"passage '{pid}': route -> missing '{target}'")

    # reachability
    reachable: set[str] = set()
    if start in passages:
        stack = [start]
        while stack:
            pid = stack.pop()
            if pid in reachable:
                continue
            reachable.add(pid)
            for nxt in successors(passages[pid]):
                if nxt in passages and nxt not in reachable:
                    stack.append(nxt)
    for pid in sorted(set(passages) - reachable):
        errors.append(f"unreachable section '{pid}' (no path from start '{start}')")

    # dead-ends + winnability
    victory = False
    for pid in sorted(reachable):
        p = passages[pid]
        ending = p.get("ending")
        if isinstance(ending, dict):
            if str(ending.get("kind", "")) == "victory":
                victory = True
            continue
        if not [t for t in successors(p) if t in passages]:
            errors.append(f"dead-end section '{pid}' — not an ending, but has no way out")
    if not victory:
        errors.append("unwinnable — no victory ending is reachable from the start")

    # FF event conventions
    for pid in sorted(reachable):
        p = passages[pid]
        event = str(p.get("event", ""))
        cids = {str(c.get("id", "")) for c in p.get("choices") or [] if isinstance(c, dict)}
        need: list[str] = []
        if event == "combat":
            need = ["_onwin", "_ondeath"]
            if not isinstance(p.get("encounter"), dict) or not p["encounter"].get("enemies"):
                errors.append(f"passage '{pid}': combat event without encounter.enemies")
        elif event == "luck_test":
            need = ["_onlucky", "_onunlucky"]
        elif event in ("skill_test", "stamina_test"):
            need = ["_onsuccess", "_onfailure"]
        for outcome in need:
            if outcome not in cids:
                errors.append(f"passage '{pid}': event '{event}' missing outcome choice '{outcome}'")

    # flag/codeword/var/item consistency
    written: dict[str, set[str]] = {"flag": set(), "codeword": set(), "var": set(), "item": set()}
    init = scen.get("init", {}) if isinstance(scen.get("init"), dict) else {}
    written["var"] |= set(map(str, (init.get("vars") or {}).keys()))
    written["item"] |= set(map(str, (init.get("items") or {}).keys()))
    written["flag"] |= set(map(str, (init.get("flags") or {}).keys()))

    def collect_effects(effects) -> None:
        for eff in _iter_effects(effects):
            kind, key = str(eff.get("kind", "")), str(eff.get("key", ""))
            if key and kind in written:
                written[kind].add(key)

    def collect_check(check) -> None:
        if isinstance(check, dict):
            for outcome in (check.get("outcomes") or {}).values():
                if isinstance(outcome, dict):
                    collect_effects(outcome.get("effects"))

    reads: dict[str, set[str]] = {"flag": set(), "codeword": set(), "var": set(), "item": set()}

    def collect_condition(cond) -> None:
        if isinstance(cond, list):
            for c in cond:
                collect_condition(c)
            return
        if not isinstance(cond, dict):
            return
        kind = str(cond.get("kind", "var"))
        if kind in ("any", "all"):
            for c in cond.get("of") or []:
                collect_condition(c)
        elif kind == "not":
            collect_condition(cond.get("of"))
        elif kind in reads:
            key = str(cond.get("key", ""))
            if key:
                reads[kind].add(key)

    for p in passages.values():
        collect_effects(p.get("onEnter"))
        collect_check(p.get("check"))
        for choice in p.get("choices") or []:
            if not isinstance(choice, dict):
                continue
            collect_effects(choice.get("effects"))
            collect_check(choice.get("check"))
            collect_condition(choice.get("conditions"))

    # warning-level, matching the in-engine IFAdventureValidator (an unopenable
    # gate may be intentional never-true flavor, e.g. grey-tithe's rope offer)
    for domain, keys in reads.items():
        if domain == "var":
            continue  # engine vars (gold, resources) may be system-written
        for key in sorted(keys - written[domain]):
            warnings.append(
                f"condition reads {domain} '{key}' that no effect or init ever sets "
                "(a gate that can never open)")
    for key in sorted(written["codeword"] - reads["codeword"]):
        warnings.append(f"codeword '{key}' is set but never tested by any condition")


# ------------------------------------------------------------------------ main


def validate_package(root: Path, project_root: Path | None,
                     errors: list[str], warnings: list[str]) -> str:
    """Validate a package folder. Returns a display title."""
    man = read_json(root / "book.json", errors)
    title = root.name
    scen_name = "adventure.json"
    if man is not None:
        validate_manifest(man, errors, warnings)
        validate_assets(man, root, project_root, errors, warnings)
        title = str(man.get("title", title))
        scen_name = str(man.get("entry", "adventure.json"))
        folder = root.name
        if str(man.get("id", "")) and folder != str(man.get("id")):
            warnings.append(f"package folder '{folder}' != book id '{man.get('id')}'")
    scen_path = root / scen_name
    if not scen_path.is_file():
        errors.append(f"entry scenario '{scen_name}' not found in package")
        return title
    scen = read_json(scen_path, errors)
    if scen is not None:
        validate_scenario(scen, errors, warnings)
        if man is not None:
            m_rs, s_rs = str(man.get("ruleset", "")), str(scen.get("ruleset", ""))
            if m_rs and s_rs and m_rs != s_rs:
                errors.append(f"ruleset mismatch: book.json '{m_rs}' vs adventure.json '{s_rs}'")
    return title


def guess_project_root(target: Path) -> Path | None:
    """Walk up looking for the skeleton root (has project.godot)."""
    for cand in [target, *target.parents]:
        if (cand / "project.godot").is_file():
            return cand
    return None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("target", help="package dir, package .zip, or bare scenario .json")
    ap.add_argument("--project-root", type=Path, default=None,
                    help="skeleton dir for resolving res:// slot paths (default: auto-detect)")
    args = ap.parse_args(argv)

    target = Path(args.target)
    if not target.exists():
        print(f"ERROR: {target} does not exist", file=sys.stderr)
        return 2
    project_root = args.project_root or guess_project_root(target.resolve())

    errors: list[str] = []
    warnings: list[str] = []
    title = target.name

    if target.is_dir():
        title = validate_package(target, project_root, errors, warnings)
    elif target.suffix.lower() == ".zip":
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            with zipfile.ZipFile(target) as zf:
                for member in zf.namelist():  # zip-slip guard
                    if member.startswith(("/", "\\")) or ".." in member:
                        errors.append(f"zip: unsafe member path '{member}'")
                        break
                else:
                    zf.extractall(tmp_path)
            root = tmp_path
            if not (root / "book.json").is_file():
                inner = [d for d in root.iterdir() if d.is_dir() and (d / "book.json").is_file()]
                if len(inner) == 1:
                    root = inner[0]
            if not errors:
                title = validate_package(root, project_root, errors, warnings)
    elif target.suffix.lower() == ".json":
        scen = read_json(target, errors)
        if scen is not None:
            title = str(scen.get("name", title))
            warnings.append("bare legacy scenario (no book.json) — shelved with a synthesized manifest")
            validate_scenario(scen, errors, warnings)
    else:
        print(f"ERROR: {target} is neither a directory, .zip, nor .json", file=sys.stderr)
        return 2

    print(f"== validate_adventure: {title} ==")
    for w in warnings:
        print(f"  WARN : {w}")
    for e in errors:
        print(f"  ERROR: {e}")
    print(f"result: {'VALID' if not errors else 'INVALID'} "
          f"({len(errors)} error(s), {len(warnings)} warning(s))")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
