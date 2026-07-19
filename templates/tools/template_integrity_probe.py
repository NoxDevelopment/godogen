#!/usr/bin/env python3
"""Template integrity probe - catches the clone-trap class in CI.

A "clone-trap" is a template that references a resource by a committed path
(`res://...`) whose target file is NOT committed. On a fresh clone the reference
dangles: Godot throws "Could not find base class", an unresolved autoload, or a
missing ext_resource - even though it opened fine on the author's machine where
the file existed (gitignored, or a since-deleted addon). This is exactly how the
8 addon clone-traps + 2 dangling asset refs shipped broken (fixed 2026-07-19).

The probe scans every committed .tscn/.tres/.godot in each Godot template
skeleton for `res://<path>` and `res://addons/<name>/...` references and asserts
each resolves to a committed file. It does NOT need Godot - it reasons over the
git index, which is what a `git clone` actually delivers.

Excluded (regenerated on first import, never committed):
  - res://.godot/...            (import cache - Godot rebuilds it)
Allowlisted known-benign (upstream addon example content, not in any play path):
  - bullet-hell BulletUpHell ExampleScenes -> res://icon.png

Usage:  python template_integrity_probe.py [--templates <genres dir>] [--json]
Exit 0 = every committed res:// reference resolves; non-zero = dangling refs
(prints fails=N with the offending template/source/reference).
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GENRES = os.path.normpath(os.path.join(HERE, "..", "genres"))
REF = re.compile(r'(?:path|source_file)\s*=\s*"(res://[^"]+)"')

# (template, source-substring, referenced res://) tuples that are known-benign:
# content that lives inside a vendored addon's own example/demo scenes and is
# never loaded by the template's main scene.
ALLOWLIST = {
    ("bullet-hell", "addons/BulletUpHell/ExampleScenes", "res://icon.png"),
}


def committed_set(genres_dir):
    """Files git would deliver on clone, under the templates/genres tree."""
    root = os.path.dirname(os.path.dirname(genres_dir))  # repo-ish root
    rel = os.path.relpath(genres_dir, root).replace("\\", "/")
    out = subprocess.run(
        ["git", "ls-files", rel], cwd=root, capture_output=True, text=True
    ).stdout
    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only"], cwd=root,
        capture_output=True, text=True,
    ).stdout
    files = set(l for l in out.split("\n") if l)
    files |= set(l for l in staged.split("\n") if l and l.startswith(rel))
    return files, root


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--templates", default=DEFAULT_GENRES)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    genres = os.path.abspath(args.templates)
    committed, root = committed_set(genres)
    if not committed:
        print("fails=1  (no committed files under %s - wrong path?)" % genres)
        return 1

    report = {}
    scanned = 0
    for name in sorted(os.listdir(genres)):
        skel = os.path.join(genres, name, "skeleton")
        proj = os.path.join(skel, "project.godot")
        if not os.path.isfile(proj):
            continue  # Godot templates only (Unity handled separately)
        scanned += 1
        dangling = []
        for dirpath, _dirs, filenames in os.walk(skel):
            for fn in filenames:
                if not fn.endswith((".tscn", ".tres", ".godot")):
                    continue
                fpath = os.path.join(dirpath, fn)
                rel = os.path.relpath(fpath, root).replace("\\", "/")
                if rel not in committed:
                    continue  # only what a clone gets
                try:
                    text = open(fpath, encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                srcrel = os.path.relpath(fpath, skel).replace("\\", "/")
                for ref in REF.findall(text):
                    if ref.startswith("res://.godot/"):
                        continue  # regenerated import cache
                    target = os.path.relpath(
                        os.path.join(skel, ref[len("res://"):]), root
                    ).replace("\\", "/")
                    if target in committed:
                        continue
                    if any(a[0] == name and a[1] in srcrel and a[2] == ref
                           for a in ALLOWLIST):
                        continue
                    dangling.append((srcrel, ref))
        if dangling:
            report[name] = dangling

    if args.json:
        print(json.dumps(report, indent=2))
    total = sum(len(v) for v in report.values())
    if report:
        print("fails=%d  (%d templates with dangling committed res:// refs, "
              "of %d scanned)" % (total, len(report), scanned))
        for t, refs in sorted(report.items()):
            print("  %s:" % t)
            for src, ref in sorted(refs):
                print("     %s  ->  %s" % (src, ref))
        return 1
    print("fails=0  (all committed res:// references resolve across %d Godot "
          "templates; clone-trap class clear)" % scanned)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
