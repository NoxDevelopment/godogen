# Provider Preflight

Run **before** any long-running asset batch. Verifies every external provider the godogen pipeline depends on is reachable, configured, and within budget — so a 50-asset batch doesn't half-succeed because the ComfyUI server was down or a LoRA file went missing.

Pure-CLI; no model dependencies. Probes the actual services with cheap health checks (no asset generation).

## TL;DR

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py {check|mlworkbench|comfyui|loras|disk|budget|mcps|all} [opts]
```

The `all` subcommand runs the full battery and exits non-zero if any **required** provider fails. Optional providers (no LoRA file for a style the user isn't trying to use) emit warnings only.

## Why this skill exists

Long batches fail at the worst time. A 50-frame animation run that aborts at frame 23 because ComfyUI was killed:

- Wastes ~12 minutes of wall time the user already spent
- Leaves an inconsistent partial output (some frames new, some old)
- Forces the agent to figure out *which* frames were re-done and which weren't

The skill emits one-page JSON reports the agent can read to decide "go" vs "stop and tell the user." It's the unglamorous prerequisite to using `image-pipeline`, `animation-pipeline`, `character-sheet`, `scene-art`, and `3d-asset-pipeline` reliably.

## Subcommands

### check — Lightweight quick-check (default everything required)

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py check
```

Equivalent to `all --skip mcps,disk` — the fast path for an agent about to kick off a single image generation. Probes ml-workbench's `/v1/workflows` and ComfyUI's `/system_stats`, confirms the default ZIT checkpoint + pixel-art LoRA are present, returns. Sub-second normally.

### mlworkbench — Verify the ml-workbench workflow library is reachable

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py mlworkbench \
  --url http://localhost:8787
```

Hits `GET /v1/workflows` — the same probe `asset_gen.py` uses (and caches) for its **primary** backend, the validated workflow library (`zit-pixel-art`, `qwen-icon`, `zit-txt2img`, `qwen-edit-instruct`, ...). Defaults to `$MLWB_URL` / `$ML_WORKBENCH_URL` or `http://localhost:8787`. Reports:

- `ok`: bool (reachable + responded with a workflow list)
- `workflow_count`: int
- `workflow_ids`: sorted list — check the ids your batch will route to are present
- `error`: string if ok=false

Standalone, exits non-zero if unreachable. **Inside `all`/`check` it is a soft check**: ml-workbench down demotes to a warning (asset_gen falls back to ComfyUI-direct), so a batch isn't blocked — but the workflow-library routing (server-side pixelize, qwen icons, reference edits) is lost for that run.

### comfyui — Verify ComfyUI is reachable

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py comfyui \
  --url http://127.0.0.1:8188
```

Hits `GET /system_stats` (a free endpoint that returns GPU/RAM info). Defaults to the URL in `image-pipeline`'s config. Reports:

- `ok`: bool (reachable + responded 200)
- `latency_ms`: int
- `gpu`: short string (e.g., `"NVIDIA RTX 3090 (24GB)"`)
- `vram_free_mb`: int (parsed from system_stats — useful for "will this fit?")
- `error`: string if ok=false

Exits non-zero if unreachable.

### loras — Verify required LoRA files exist

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py loras \
  --required pixel_art_style_z_image_turbo.safetensors \
  --required-style zx-spectrum \
  --lora-dir D:\AI\Loras\ZIT
```

For `--required <filename>` checks the file exists in `--lora-dir` (default reads from `image-pipeline`'s `zit_styles.py` `LORA_ROOT`). For `--required-style <key>` resolves the LoRA filename(s) from the styles registry — supports multi-LoRA styles automatically.

Returns per-file `{filename, found, size_mb, mtime_iso}` and a summary count. Exits non-zero if any required LoRA is missing.

`--all-styles` checks every LoRA used by the styles registry — useful for verifying a fresh LoRA-pack install before a big run.

### disk — Verify output dir is writable + has headroom

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py disk \
  --output-dir assets/ \
  --min-free-gb 2
```

Writes-and-deletes a small probe file under `--output-dir` to confirm write permission. Then checks free disk space against `--min-free-gb`. Useful before a `--variations 20` batch.

### budget — Check paid-provider budget

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py budget \
  --provider tripo3d \
  --estimated-calls 10 \
  --cost-per-call-usd 0.50
```

Reads the budget file at `~/.godogen/budget.json` (shared with `3d-asset-pipeline`'s `set_budget` command), checks that the projected spend (`estimated_calls * cost_per_call_usd`) doesn't exceed the remaining budget. Exits non-zero if it would.

Adding new paid providers (or per-project caps): point `--budget-file` at a project-local JSON instead of the default user-level one.

### mcps — Check MCP server health (when applicable)

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py mcps \
  --check spritecook-mcp \
  --check tripo3d-mcp
```

Runs `npx <name> --health` (or the configured health command) for each MCP server name. Reports up/down per server. MCPs are optional in the godogen flow — this check is only relevant if the agent has been told to use one. Default `--check`s is empty (no MCPs assumed).

### all — Full battery

```bash
python3 .claude/skills/provider-preflight/tools/preflight.py all \
  --comfyui-url http://127.0.0.1:8188 \
  --required-style default-pixel \
  --output-dir assets/ \
  --min-free-gb 2
```

Runs every subcommand, returns a single JSON report. Use this as the **first** call in any long batch script. Exit code 0 = green-light to proceed; non-zero = bail out and report to the user.

## Output format

Every subcommand emits a JSON object on stdout:

```json
{
  "subcommand": "comfyui",
  "ok": true,
  "duration_ms": 142,
  "details": { … subcommand-specific … },
  "warnings": [],
  "errors": []
}
```

The `all` subcommand wraps individual results:

```json
{
  "subcommand": "all",
  "ok": true,
  "duration_ms": 1843,
  "results": {
    "mlworkbench": { … },
    "comfyui": { … },
    "loras": { … },
    "disk": { … },
    "budget": { … },
    "mcps": { … }
  },
  "warnings": [ "…", "…" ],
  "errors": []
}
```

## Cardinal rules

- **Run preflight before any batch larger than ~3 assets.** Single one-off generations don't need it; a `--variations 20` or `animation-pipeline cycle walk` absolutely does.
- **Treat warnings as soft signals.** Missing-LoRA-for-an-unused-style is a warning, not an error. The agent shouldn't bail on warnings — only on errors.
- **Re-run preflight if the user pauses for >10 minutes.** ComfyUI might have been restarted; disk might have filled. Cheap to re-check.
- **Don't probe paid providers by generating a free dummy asset.** That defeats the purpose. The budget subcommand reads the local budget file — no API calls.

## Files

- `tools/preflight.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **image-pipeline / character-sheet / animation-pipeline / scene-art** — call `preflight.py all` before any multi-asset batch. The styles-aware `--required-style` flag pairs with their `--style` flag.
- **3d-asset-pipeline** — call `preflight.py budget --provider tripo3d` before any `mesh` or `batch` call. The budget file is the same one `3d-asset-pipeline.set_budget` writes.
- **asset-manifest** — preflight does *not* read the manifest; it's about *upstream* readiness, not downstream tracking.
- **playtest** — playtest's checkpoint hook can call preflight `comfyui` to confirm the dev environment is still hot.
