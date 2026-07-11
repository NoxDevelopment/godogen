"""Provider Preflight — verify upstream services + assets are ready before
a long-running asset batch.

Subcommands
-----------
mlworkbench  Verify ml-workbench workflow library is reachable (GET /v1/workflows).
comfyui      Verify ComfyUI is reachable (GET /system_stats).
loras        Verify required LoRA files exist on disk.
disk         Verify output dir is writable + has minimum free space.
budget       Check projected paid-provider spend against budget file.
mcps         Health-check named MCP servers.
all          Full battery (mlworkbench + comfyui + loras + disk).
check        Fast path = `all --skip mcps,budget`.

All subcommands emit a JSON report on stdout. Exit code 0 = green-light.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

# Reuse image-pipeline constants where possible
SKILL_DIR = Path(__file__).resolve().parent.parent
SKILLS_ROOT = SKILL_DIR.parent
IMAGE_PIPELINE_TOOLS = SKILLS_ROOT / "image-pipeline" / "tools"

if str(IMAGE_PIPELINE_TOOLS) not in sys.path:
    sys.path.insert(0, str(IMAGE_PIPELINE_TOOLS))

# Optional imports — preflight should still partly work if image-pipeline
# isn't installed (e.g. in a consumer that only has provider-preflight).
try:
    from zit_styles import STYLES, DEFAULT_STYLE_KEY  # type: ignore
except Exception:
    STYLES = {}
    DEFAULT_STYLE_KEY = "default-pixel"

try:
    from comfyui_client import COMFYUI_URL  # type: ignore
except Exception:
    COMFYUI_URL = "http://localhost:8188"

# ml-workbench serves the validated workflow library asset_gen.py uses as its
# PRIMARY backend (image-pipeline SKILL.md, "Backend selection").
MLWB_URL = (
    os.environ.get("MLWB_URL") or os.environ.get("ML_WORKBENCH_URL")
    or "http://localhost:8787"
).rstrip("/")


DEFAULT_LORA_DIR_CANDIDATES = [
    "D:/AI/Loras/ZIT",
    "D:\\AI\\Loras\\ZIT",
    os.path.expanduser("~/AI/Loras/ZIT"),
    "/AI/Loras/ZIT",
]


def _resolve_lora_dir(arg: str | None) -> Path:
    if arg:
        return Path(arg)
    for cand in DEFAULT_LORA_DIR_CANDIDATES:
        p = Path(cand)
        if p.exists():
            return p
    # Fall back to the first candidate; subsequent file checks will fail
    # informatively rather than silently looking in cwd.
    return Path(DEFAULT_LORA_DIR_CANDIDATES[0])


def _wrap_result(subcommand: str, started_ms: float, ok: bool,
                 details: dict[str, Any] | None = None,
                 errors: list[str] | None = None,
                 warnings: list[str] | None = None) -> dict:
    return {
        "subcommand": subcommand,
        "ok": ok,
        "duration_ms": int((time.monotonic() - started_ms) * 1000),
        "details": details or {},
        "errors": errors or [],
        "warnings": warnings or [],
    }


# ---------------------------------------------------------------------------
# mlworkbench
# ---------------------------------------------------------------------------

def check_mlworkbench(url: str = MLWB_URL, timeout: float = 5.0) -> dict:
    """Probe the ml-workbench workflow library (GET /v1/workflows).

    Reports the served workflow ids so a batch script can verify the ids it
    plans to route to (zit-pixel-art, qwen-icon, ...) actually exist."""
    started = time.monotonic()
    errors: list[str] = []
    details: dict[str, Any] = {"url": url, "reachable": False}
    try:
        req = urllib.request.Request(f"{url.rstrip('/')}/v1/workflows")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
        workflows = data.get("workflows") or []
        details["reachable"] = True
        details["workflow_count"] = len(workflows)
        details["workflow_ids"] = sorted(w.get("id") for w in workflows if w.get("id"))
        return _wrap_result("mlworkbench", started, ok=True, details=details)
    except (urllib.error.URLError, socket.timeout, ConnectionError) as e:
        errors.append(f"ml-workbench unreachable at {url}: {e}")
    except (json.JSONDecodeError, ValueError) as e:
        errors.append(f"ml-workbench returned non-JSON / unparseable response: {e}")
        details["reachable"] = True
        details["parse_failed"] = True
    except Exception as e:
        errors.append(f"Unexpected error: {type(e).__name__}: {e}")
    return _wrap_result("mlworkbench", started, ok=False, details=details, errors=errors)


def cmd_mlworkbench(args) -> dict:
    return check_mlworkbench(url=args.url, timeout=args.timeout)


# ---------------------------------------------------------------------------
# comfyui
# ---------------------------------------------------------------------------

def check_comfyui(url: str = COMFYUI_URL, timeout: float = 5.0) -> dict:
    started = time.monotonic()
    errors: list[str] = []
    details: dict[str, Any] = {"url": url}
    try:
        req = urllib.request.Request(f"{url.rstrip('/')}/system_stats")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            data = json.loads(body)
        # Best-effort parse — ComfyUI's /system_stats schema varies by version.
        devices = data.get("devices") or []
        if devices:
            d0 = devices[0]
            details["gpu"] = d0.get("name", "?")
            details["vram_total_mb"] = int(d0.get("vram_total", 0) // (1024 * 1024))
            details["vram_free_mb"] = int(d0.get("vram_free", 0) // (1024 * 1024))
        sys_info = data.get("system") or {}
        if sys_info:
            details["os"] = sys_info.get("os", "?")
            details["python_version"] = sys_info.get("python_version", "?")
            details["comfyui_version"] = sys_info.get("comfyui_version", "?")
        details["reachable"] = True
        return _wrap_result("comfyui", started, ok=True, details=details)
    except (urllib.error.URLError, socket.timeout, ConnectionError) as e:
        errors.append(f"ComfyUI unreachable at {url}: {e}")
        details["reachable"] = False
    except (json.JSONDecodeError, ValueError) as e:
        errors.append(f"ComfyUI returned non-JSON / unparseable response: {e}")
        details["reachable"] = True
        details["parse_failed"] = True
    except Exception as e:
        errors.append(f"Unexpected error: {type(e).__name__}: {e}")
    return _wrap_result("comfyui", started, ok=False, details=details, errors=errors)


def cmd_comfyui(args) -> dict:
    return check_comfyui(url=args.url, timeout=args.timeout)


# ---------------------------------------------------------------------------
# loras
# ---------------------------------------------------------------------------

def _resolve_style_loras(style_key: str) -> list[str]:
    """Return the list of LoRA filenames a style requires."""
    style = STYLES.get(style_key)
    if style is None:
        return []
    # zit_styles.STYLES[key] has a .loras tuple of LoraEntry
    out: list[str] = []
    for entry in getattr(style, "loras", []) or []:
        # LoraEntry may be a NamedTuple, dataclass, or dict
        if hasattr(entry, "filename"):
            out.append(entry.filename)
        elif isinstance(entry, (tuple, list)) and entry:
            out.append(entry[0])
        elif isinstance(entry, dict):
            out.append(entry.get("filename") or entry.get("name", ""))
    return [f for f in out if f]


def check_loras(required_files: list[str], required_styles: list[str],
                lora_dir: Path, all_styles: bool = False) -> dict:
    started = time.monotonic()
    errors: list[str] = []
    warnings: list[str] = []
    details: dict[str, Any] = {"lora_dir": str(lora_dir),
                               "files": [], "missing": [],
                               "by_style": {}}

    if not lora_dir.exists():
        errors.append(f"LoRA dir does not exist: {lora_dir}")
        return _wrap_result("loras", started, ok=False, details=details, errors=errors)

    # Expand --required-style and --all-styles into a flat filename set.
    wanted_files: set[str] = set(required_files)
    style_keys = required_styles[:]
    if all_styles:
        style_keys = list(STYLES.keys())
    for sk in style_keys:
        files_for_style = _resolve_style_loras(sk)
        if not files_for_style:
            warnings.append(f"style '{sk}' resolves to no LoRA files (or not in registry)")
        wanted_files.update(files_for_style)
        details["by_style"][sk] = files_for_style

    for fn in sorted(wanted_files):
        fp = lora_dir / fn
        if fp.exists():
            stat = fp.stat()
            details["files"].append({
                "filename": fn, "found": True,
                "size_mb": round(stat.st_size / (1024 * 1024), 1),
                "mtime": int(stat.st_mtime),
            })
        else:
            details["files"].append({"filename": fn, "found": False})
            details["missing"].append(fn)

    if details["missing"]:
        errors.append(f"missing {len(details['missing'])} LoRA file(s): {details['missing'][:3]}"
                      + ("…" if len(details['missing']) > 3 else ""))
        return _wrap_result("loras", started, ok=False, details=details,
                            errors=errors, warnings=warnings)
    return _wrap_result("loras", started, ok=True, details=details, warnings=warnings)


def cmd_loras(args) -> dict:
    return check_loras(
        required_files=args.required or [],
        required_styles=args.required_style or [],
        lora_dir=_resolve_lora_dir(args.lora_dir),
        all_styles=args.all_styles,
    )


# ---------------------------------------------------------------------------
# disk
# ---------------------------------------------------------------------------

def check_disk(output_dir: Path, min_free_gb: float) -> dict:
    started = time.monotonic()
    errors: list[str] = []
    warnings: list[str] = []
    details: dict[str, Any] = {"output_dir": str(output_dir),
                               "writable": False,
                               "free_gb": None,
                               "min_free_gb": min_free_gb}
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
        probe = output_dir / ".preflight_probe.tmp"
        probe.write_bytes(b"preflight")
        probe.unlink()
        details["writable"] = True
    except OSError as e:
        errors.append(f"output_dir not writable: {e}")
        return _wrap_result("disk", started, ok=False, details=details, errors=errors)

    try:
        usage = shutil.disk_usage(output_dir)
        free_gb = usage.free / (1024 ** 3)
        details["free_gb"] = round(free_gb, 2)
        details["total_gb"] = round(usage.total / (1024 ** 3), 2)
        if free_gb < min_free_gb:
            errors.append(f"free space {free_gb:.2f} GB < min {min_free_gb} GB")
            return _wrap_result("disk", started, ok=False, details=details, errors=errors)
    except OSError as e:
        warnings.append(f"could not check free space: {e}")

    return _wrap_result("disk", started, ok=True, details=details, warnings=warnings)


def cmd_disk(args) -> dict:
    return check_disk(Path(args.output_dir), args.min_free_gb)


# ---------------------------------------------------------------------------
# budget
# ---------------------------------------------------------------------------

DEFAULT_BUDGET_FILE = Path(os.path.expanduser("~/.godogen/budget.json"))


def check_budget(provider: str, estimated_calls: int, cost_per_call_usd: float,
                 budget_file: Path) -> dict:
    started = time.monotonic()
    errors: list[str] = []
    warnings: list[str] = []
    details: dict[str, Any] = {
        "provider": provider, "estimated_calls": estimated_calls,
        "cost_per_call_usd": cost_per_call_usd,
        "projected_spend_usd": round(estimated_calls * cost_per_call_usd, 4),
        "budget_file": str(budget_file),
    }

    if not budget_file.exists():
        warnings.append(f"budget file not found: {budget_file}. "
                        f"Treating as unlimited — set up with 3d-asset-pipeline's set_budget command.")
        details["budget_remaining_usd"] = None
        return _wrap_result("budget", started, ok=True, details=details, warnings=warnings)

    try:
        budget_data = json.loads(budget_file.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        errors.append(f"failed to read budget file: {e}")
        return _wrap_result("budget", started, ok=False, details=details, errors=errors)

    # Budget file shape: { "<provider>": { "remaining_usd": <float>, … }, … }
    p_entry = budget_data.get(provider, {})
    remaining = p_entry.get("remaining_usd")
    details["budget_remaining_usd"] = remaining

    if remaining is None:
        warnings.append(f"no budget entry for provider '{provider}'. Treating as unlimited.")
        return _wrap_result("budget", started, ok=True, details=details, warnings=warnings)

    if details["projected_spend_usd"] > remaining:
        errors.append(
            f"projected spend ${details['projected_spend_usd']:.2f} exceeds "
            f"remaining budget ${remaining:.2f} for '{provider}'.")
        return _wrap_result("budget", started, ok=False, details=details, errors=errors)

    return _wrap_result("budget", started, ok=True, details=details, warnings=warnings)


def cmd_budget(args) -> dict:
    return check_budget(
        provider=args.provider,
        estimated_calls=args.estimated_calls,
        cost_per_call_usd=args.cost_per_call_usd,
        budget_file=Path(args.budget_file) if args.budget_file else DEFAULT_BUDGET_FILE,
    )


# ---------------------------------------------------------------------------
# mcps
# ---------------------------------------------------------------------------

def check_mcps(server_names: list[str], timeout: float = 10.0) -> dict:
    started = time.monotonic()
    errors: list[str] = []
    warnings: list[str] = []
    details: dict[str, Any] = {"servers": []}
    if not server_names:
        warnings.append("no MCP servers passed via --check; nothing to verify.")
        return _wrap_result("mcps", started, ok=True, details=details, warnings=warnings)

    for name in server_names:
        entry: dict[str, Any] = {"name": name, "ok": False}
        try:
            proc = subprocess.run(
                ["npx", name, "--health"],
                capture_output=True, text=True, timeout=timeout,
            )
            entry["exit_code"] = proc.returncode
            entry["stdout_head"] = (proc.stdout or "")[:200]
            entry["stderr_head"] = (proc.stderr or "")[:200]
            entry["ok"] = proc.returncode == 0
            if not entry["ok"]:
                errors.append(f"MCP {name} health check failed (exit {proc.returncode})")
        except FileNotFoundError:
            entry["error"] = "npx not on PATH"
            errors.append(f"npx not available — cannot probe MCP servers.")
        except subprocess.TimeoutExpired:
            entry["error"] = f"timed out after {timeout}s"
            errors.append(f"MCP {name} health check timed out.")
        except Exception as e:
            entry["error"] = f"{type(e).__name__}: {e}"
            errors.append(f"MCP {name} probe error: {e}")
        details["servers"].append(entry)

    ok = all(e.get("ok") for e in details["servers"])
    return _wrap_result("mcps", started, ok=ok, details=details,
                        errors=errors, warnings=warnings)


def cmd_mcps(args) -> dict:
    return check_mcps(args.check or [], timeout=args.timeout)


# ---------------------------------------------------------------------------
# all + check
# ---------------------------------------------------------------------------

ALL_SUBCOMMANDS = ["mlworkbench", "comfyui", "loras", "disk", "budget", "mcps"]


def cmd_all(args) -> dict:
    started = time.monotonic()
    skip = set((args.skip or "").split(",")) if args.skip else set()
    results: dict[str, dict] = {}
    aggregate_warnings: list[str] = []
    aggregate_errors: list[str] = []

    if "mlworkbench" not in skip:
        results["mlworkbench"] = check_mlworkbench(
            url=getattr(args, "mlwb_url", MLWB_URL), timeout=args.timeout)
    if "comfyui" not in skip:
        results["comfyui"] = check_comfyui(url=args.comfyui_url, timeout=args.timeout)
    if "loras" not in skip:
        req_styles = ([args.required_style] if args.required_style else
                      [DEFAULT_STYLE_KEY])
        results["loras"] = check_loras(
            required_files=[], required_styles=req_styles,
            lora_dir=_resolve_lora_dir(args.lora_dir), all_styles=False)
    if "disk" not in skip:
        results["disk"] = check_disk(Path(args.output_dir), args.min_free_gb)
    if "budget" not in skip and args.budget_provider:
        results["budget"] = check_budget(
            provider=args.budget_provider,
            estimated_calls=args.budget_calls,
            cost_per_call_usd=args.budget_cost,
            budget_file=Path(args.budget_file) if args.budget_file else DEFAULT_BUDGET_FILE)
    if "mcps" not in skip and args.mcp_check:
        results["mcps"] = check_mcps(args.mcp_check, timeout=args.timeout)

    # ml-workbench down is a SOFT failure: asset_gen falls back to
    # ComfyUI-direct (losing the workflow-library routing, not the batch).
    # Demote its errors to warnings and exclude it from the overall gate.
    mlwb_result = results.get("mlworkbench")
    if mlwb_result and not mlwb_result.get("ok"):
        aggregate_warnings.append(
            "[mlworkbench] workflow library unreachable — asset_gen will fall "
            "back to ComfyUI-direct (no zit-pixel-art/qwen-icon routing).")
        aggregate_warnings.extend(f"[mlworkbench] {e}" for e in mlwb_result.get("errors", []))

    overall_ok = all(
        r.get("ok") for name, r in results.items() if name != "mlworkbench"
    ) if results else True
    for name, r in results.items():
        aggregate_warnings.extend(f"[{r['subcommand']}] {w}" for w in r.get("warnings", []))
        if name != "mlworkbench":
            aggregate_errors.extend(f"[{r['subcommand']}] {e}" for e in r.get("errors", []))

    return {
        "subcommand": args.cmd,
        "ok": overall_ok,
        "duration_ms": int((time.monotonic() - started) * 1000),
        "results": results,
        "warnings": aggregate_warnings,
        "errors": aggregate_errors,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _emit(result: dict) -> None:
    print(json.dumps(result, indent=2))
    if not result.get("ok"):
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="provider-preflight: verify upstream services before a long batch")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("mlworkbench",
                       help="Check ml-workbench workflow library reachability")
    p.add_argument("--url", default=MLWB_URL)
    p.add_argument("--timeout", type=float, default=5.0)
    p.set_defaults(func=lambda a: _emit(cmd_mlworkbench(a)))

    p = sub.add_parser("comfyui", help="Check ComfyUI reachability")
    p.add_argument("--url", default=COMFYUI_URL)
    p.add_argument("--timeout", type=float, default=5.0)
    p.set_defaults(func=lambda a: _emit(cmd_comfyui(a)))

    p = sub.add_parser("loras", help="Check LoRA files exist")
    p.add_argument("--required", action="append",
                   help="Required LoRA filename (repeatable)")
    p.add_argument("--required-style", action="append",
                   help="Style key whose LoRAs must exist (repeatable)")
    p.add_argument("--all-styles", action="store_true",
                   help="Verify every LoRA used by the styles registry")
    p.add_argument("--lora-dir", help="LoRA root dir (default: D:/AI/Loras/ZIT)")
    p.set_defaults(func=lambda a: _emit(cmd_loras(a)))

    p = sub.add_parser("disk", help="Check output dir writable + free space")
    p.add_argument("--output-dir", required=True)
    p.add_argument("--min-free-gb", type=float, default=1.0)
    p.set_defaults(func=lambda a: _emit(cmd_disk(a)))

    p = sub.add_parser("budget", help="Check paid-provider budget headroom")
    p.add_argument("--provider", required=True)
    p.add_argument("--estimated-calls", type=int, required=True)
    p.add_argument("--cost-per-call-usd", type=float, required=True)
    p.add_argument("--budget-file", help=f"Default: {DEFAULT_BUDGET_FILE}")
    p.set_defaults(func=lambda a: _emit(cmd_budget(a)))

    p = sub.add_parser("mcps", help="Health-check MCP servers")
    p.add_argument("--check", action="append", help="MCP server name (repeatable)")
    p.add_argument("--timeout", type=float, default=10.0)
    p.set_defaults(func=lambda a: _emit(cmd_mcps(a)))

    p = sub.add_parser("all", help="Run full battery")
    p.add_argument("--mlwb-url", default=MLWB_URL)
    p.add_argument("--comfyui-url", default=COMFYUI_URL)
    p.add_argument("--required-style", help="Style key whose LoRAs must exist")
    p.add_argument("--lora-dir")
    p.add_argument("--output-dir", default="assets/")
    p.add_argument("--min-free-gb", type=float, default=1.0)
    p.add_argument("--budget-provider")
    p.add_argument("--budget-calls", type=int, default=0)
    p.add_argument("--budget-cost", type=float, default=0.0)
    p.add_argument("--budget-file")
    p.add_argument("--mcp-check", action="append")
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--skip", help="Comma-separated subcommand names to skip")
    p.set_defaults(func=lambda a: _emit(cmd_all(a)))

    p = sub.add_parser("check", help="Fast path: mlworkbench + comfyui + loras + disk")
    p.add_argument("--mlwb-url", default=MLWB_URL)
    p.add_argument("--comfyui-url", default=COMFYUI_URL)
    p.add_argument("--required-style", help="Style key (default: default-pixel)")
    p.add_argument("--lora-dir")
    p.add_argument("--output-dir", default="assets/")
    p.add_argument("--min-free-gb", type=float, default=1.0)
    p.add_argument("--timeout", type=float, default=5.0)

    def _check_proxy(a):
        a.skip = "budget,mcps"
        a.budget_provider = None
        a.budget_calls = 0
        a.budget_cost = 0.0
        a.budget_file = None
        a.mcp_check = []
        _emit(cmd_all(a))
    p.set_defaults(func=_check_proxy)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
