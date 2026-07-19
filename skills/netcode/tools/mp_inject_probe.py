#!/usr/bin/env python3
"""Regression probe for the authority-turn MP injection.

The netcode_gen.py SessionState patch is anchored on ff-gamebook's session_state.gd
shape. When the template drifts, `inject` hard-fails silently (the bug the scout
found). This probe scaffolds a throwaway copy of ff-gamebook, runs the injection,
and asserts it applied — so anchor drift is caught in CI, not in production.

Usage:  python mp_inject_probe.py [--gamebook <skeleton dir>]
Exit 0 = injection clean; non-zero = drift/failure (prints fails=N).
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NETCODE_GEN = os.path.join(HERE, "netcode_gen.py")
DEFAULT_GAMEBOOK = os.path.normpath(
    os.path.join(HERE, "..", "..", "..", "templates", "genres", "ff-gamebook", "skeleton")
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gamebook", default=DEFAULT_GAMEBOOK)
    args = ap.parse_args()

    fails = []
    if not os.path.isfile(os.path.join(args.gamebook, "scripts", "session_state.gd")):
        print("fails=1  (ff-gamebook session_state.gd not found at %s)" % args.gamebook)
        return 1

    tmp = tempfile.mkdtemp(prefix="mp_inject_probe_")
    try:
        skel = os.path.join(tmp, "skel")
        shutil.copytree(args.gamebook, skel)
        r = subprocess.run(
            [sys.executable, NETCODE_GEN, "inject", "--project", skel, "--profile", "authority-turn"],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            fails.append("inject exit %d: %s" % (r.returncode, (r.stdout + r.stderr).strip()[:300]))
        ss = ""
        ssp = os.path.join(skel, "scripts", "session_state.gd")
        if os.path.isfile(ssp):
            ss = open(ssp, encoding="utf-8").read()
        for marker in ("NetBridge.intercept_advance", "NetBridge.intercept_choose",
                       "NetBridge.intercept_roll", "NetBridge.dm_push_passage",
                       "NetBridge.dm_override_roll"):
            if marker not in ss:
                fails.append("missing patch marker: %s" % marker)
        if not os.path.isdir(os.path.join(skel, "addons", "nox_netcode")):
            fails.append("nox_netcode addon not vendored")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if fails:
        print("fails=%d" % len(fails))
        for f in fails:
            print("  - " + f)
        return 1
    print("fails=0  (authority-turn MP injection applied cleanly: 5 guards + DM hooks + addon)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
