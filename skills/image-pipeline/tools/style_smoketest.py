#!/usr/bin/env python3
"""Style-comparison smoketest — run the same prompt through every ZIT style.

For every entry in `zit_styles.STYLES` whose `base_model == "zimage"`, this
runs `asset_gen.py image --type sprite --style <key>` with a fixed test
prompt and writes the output PNG to
`assets/style_smoketest/<key>.png`. After all styles are processed it
assembles a labeled contact sheet (`assets/style_smoketest/_contact_sheet.png`)
and writes a JSON report (`_report.json`) with per-style success/failure +
timing.

SDXL-flagged styles (e.g. `new-pixel-core-ill`) are skipped here since they
require a separate workflow path; their keys appear in the report under
`skipped_sdxl`.

Usage:
    python style_smoketest.py
    python style_smoketest.py --prompt "your test subject"
    python style_smoketest.py --only pc98,zx-spectrum,16bit-game

The smoketest is non-destructive — it overwrites only files inside
`assets/style_smoketest/`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

THIS_DIR = Path(__file__).parent
REPO_ROOT = THIS_DIR.parent  # C:/code/ai/godogen/skills/image-pipeline
DEFAULT_OUT_DIR = REPO_ROOT / "assets" / "style_smoketest"
DEFAULT_PROMPT = "a knight in plate armor with a crimson cape, side view"

# Make sibling modules importable
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))


def main():
    parser = argparse.ArgumentParser(
        description="Smoketest every ZIT style with a fixed prompt."
    )
    parser.add_argument("--prompt", default=DEFAULT_PROMPT,
                        help="Test prompt sent to every style.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR),
                        help="Directory for per-style PNGs and the contact sheet.")
    parser.add_argument("--type", default="sprite",
                        help="Asset type passed to asset_gen.py (default: sprite).")
    parser.add_argument("--size", default="1K",
                        choices=["512", "1K", "2K", "4K"],
                        help="Generation size (default: 1K).")
    parser.add_argument("--only", default="",
                        help="Comma-separated style keys to run (default: all zimage styles).")
    parser.add_argument("--skip-contact-sheet", action="store_true",
                        help="Skip the PIL contact-sheet assembly step.")
    parser.add_argument("--timeout", type=int, default=180,
                        help="Per-style timeout in seconds (default: 180).")
    args = parser.parse_args()

    from zit_styles import STYLES, list_styles

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Filter style set
    zimage_keys = list_styles(base_model="zimage")
    if args.only:
        requested = [k.strip() for k in args.only.split(",") if k.strip()]
        unknown = [k for k in requested if k not in STYLES]
        if unknown:
            print(f"Unknown style key(s): {unknown}", file=sys.stderr)
            sys.exit(2)
        keys = [k for k in requested if k in zimage_keys]
        skipped_non_zimage = [k for k in requested if k not in zimage_keys]
    else:
        keys = zimage_keys
        skipped_non_zimage = []

    skipped_sdxl = list_styles(base_model="sdxl")

    print(f"[smoketest] prompt: {args.prompt}", file=sys.stderr)
    print(f"[smoketest] {len(keys)} styles to test, "
          f"{len(skipped_sdxl)} skipped (SDXL): {skipped_sdxl}",
          file=sys.stderr)

    asset_gen = THIS_DIR / "asset_gen.py"
    results: list[dict] = []

    for i, key in enumerate(keys, 1):
        spec = STYLES[key]
        out_path = out_dir / f"{key}.png"
        cmd = [
            sys.executable, str(asset_gen), "image",
            "--type", args.type,
            "--size", args.size,
            "--prompt", args.prompt,
            "--style", key,
            "-o", str(out_path),
            "--timeout", str(args.timeout),
        ]
        print(f"[smoketest] [{i}/{len(keys)}] {key} ...", file=sys.stderr)
        start = time.time()
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=args.timeout + 30,
            )
            elapsed = time.time() - start
            stdout_payload = None
            try:
                stdout_payload = json.loads(proc.stdout.strip().splitlines()[-1])
            except Exception:
                pass
            ok = (
                proc.returncode == 0
                and out_path.exists()
                and out_path.stat().st_size > 0
                and (stdout_payload is None or stdout_payload.get("ok"))
            )
            results.append({
                "key": key,
                "name": spec.name,
                "loras": [le.name for le in spec.loras],
                "triggers": list(spec.triggers),
                "ok": ok,
                "elapsed_s": round(elapsed, 1),
                "output": str(out_path) if ok else None,
                "returncode": proc.returncode,
                "stderr_tail": proc.stderr.strip().splitlines()[-3:] if proc.stderr else [],
                "stdout_payload": stdout_payload,
            })
            tag = "OK" if ok else "FAIL"
            print(f"[smoketest]   {tag} ({elapsed:.1f}s)", file=sys.stderr)
            if not ok and proc.stderr:
                for ln in proc.stderr.strip().splitlines()[-3:]:
                    print(f"[smoketest]     {ln}", file=sys.stderr)
        except subprocess.TimeoutExpired:
            elapsed = time.time() - start
            results.append({
                "key": key,
                "name": spec.name,
                "loras": [le.name for le in spec.loras],
                "ok": False,
                "elapsed_s": round(elapsed, 1),
                "output": None,
                "error": "timeout",
            })
            print(f"[smoketest]   TIMEOUT ({elapsed:.1f}s)", file=sys.stderr)

    report = {
        "prompt": args.prompt,
        "type": args.type,
        "size": args.size,
        "out_dir": str(out_dir),
        "total": len(keys),
        "passed": sum(1 for r in results if r["ok"]),
        "failed": sum(1 for r in results if not r["ok"]),
        "skipped_sdxl": skipped_sdxl,
        "skipped_non_zimage_in_only": skipped_non_zimage,
        "results": results,
    }
    report_path = out_dir / "_report.json"
    report_path.write_text(json.dumps(report, indent=2))
    print(f"[smoketest] report: {report_path}", file=sys.stderr)
    print(
        f"[smoketest] passed={report['passed']}/{report['total']} "
        f"failed={report['failed']}",
        file=sys.stderr,
    )

    if not args.skip_contact_sheet:
        try:
            sheet_path = build_contact_sheet(
                results, out_dir / "_contact_sheet.png", title=args.prompt
            )
            if sheet_path:
                print(f"[smoketest] contact sheet: {sheet_path}", file=sys.stderr)
        except Exception as e:
            print(f"[smoketest] contact sheet build failed: {e}", file=sys.stderr)

    # Final JSON to stdout for callers
    print(json.dumps({
        "ok": report["failed"] == 0,
        "passed": report["passed"],
        "failed": report["failed"],
        "report": str(report_path),
    }))
    sys.exit(0 if report["failed"] == 0 else 1)


def build_contact_sheet(results: list[dict], out_path: Path, title: str = "") -> Path | None:
    """Assemble a labeled grid of all successful outputs."""
    from PIL import Image, ImageDraw, ImageFont

    successes = [r for r in results if r["ok"] and r.get("output")]
    if not successes:
        return None

    cols = 4
    cell_size = 256        # downscale outputs to 256px tiles for the sheet
    label_h = 36
    gap = 8
    rows = (len(successes) + cols - 1) // cols
    title_h = 48 if title else 0

    sheet_w = cols * cell_size + (cols + 1) * gap
    sheet_h = title_h + rows * (cell_size + label_h + gap) + gap

    sheet = Image.new("RGB", (sheet_w, sheet_h), color=(20, 20, 26))
    draw = ImageDraw.Draw(sheet)

    try:
        font = ImageFont.truetype("arial.ttf", 14)
        title_font = ImageFont.truetype("arial.ttf", 20)
    except (IOError, OSError):
        font = ImageFont.load_default()
        title_font = ImageFont.load_default()

    if title:
        draw.text((gap, gap), f"prompt: {title}", fill=(220, 220, 230), font=title_font)

    for idx, r in enumerate(successes):
        row, col = divmod(idx, cols)
        x = gap + col * (cell_size + gap)
        y = title_h + gap + row * (cell_size + label_h + gap)
        try:
            img = Image.open(r["output"]).convert("RGB")
            img.thumbnail((cell_size, cell_size), Image.NEAREST)
            # Center within cell
            offset_x = (cell_size - img.width) // 2
            offset_y = (cell_size - img.height) // 2
            sheet.paste(img, (x + offset_x, y + offset_y))
        except Exception:
            draw.rectangle([x, y, x + cell_size, y + cell_size],
                           outline=(180, 60, 60), width=2)
            draw.text((x + 8, y + 8), "load fail", fill=(220, 80, 80), font=font)
        # Label
        label_y = y + cell_size + 4
        draw.text((x, label_y), r["key"], fill=(230, 230, 235), font=font)
        draw.text((x, label_y + 16), f"{r['elapsed_s']}s", fill=(150, 150, 160), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)
    return out_path


if __name__ == "__main__":
    main()
