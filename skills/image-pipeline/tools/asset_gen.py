#!/usr/bin/env python3
"""Asset Generator (image-pipeline) — ComfyUI-first, Gemini fallback.

This replaces the old single-path Gemini-only asset_gen.py. Routes by asset
type to the right ComfyUI workflow:

  - portrait / character / avatar → img2img with reference.png as IPAdapter-style
                                     conditioning + face-LoRA + pixel post-process
  - sprite                        → txt2img + pixel-LoRA + pixelize/palette lock
  - tile / tileset                → seamless tiling workflow + palette lock
  - item / icon                   → txt2img with item prompt prefix + transparent crop
  - landscape / environment       → txt2img wide aspect + palette lock
  - general (default)             → txt2img base
  - spritesheet                   → batch generation + sheet assembly
  - reference (visual-target)     → txt2img wide → save as reference.png anchor

ComfyUI runs locally (free, no budget), so most calls cost nothing. If
ComfyUI is unreachable we fall back to Gemini's image API (paid, budgeted)
to keep godogen functional even on a fresh machine.

CLI surface stays compatible with the old asset_gen.py — adding --type and
--reference flags. Existing godogen prompts continue to work; the agent is
encouraged to use --type for the quality routing.

Subcommands:
  image        Generate a PNG (asset-type aware)
  spritesheet  4x4 sprite sheet (template-aided when on Gemini, batch on ComfyUI)
  glb          PNG → GLB via Tripo3D (unchanged from old)
  set_budget   Set Gemini budget cap

Output: JSON to stdout. Progress to stderr.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

THIS_DIR = Path(__file__).parent
PRESETS_DIR = THIS_DIR.parent / "presets"
BUDGET_FILE = Path("assets/budget.json")

# Make sibling tools importable when invoked as a script.
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))
# Make presets/ importable too (pixel_art_presets lives there).
if str(PRESETS_DIR) not in sys.path:
    sys.path.insert(0, str(PRESETS_DIR))


def _load_pixel_presets():
    """Lazy import of presets/pixel_art_presets.PIXEL_STYLE_PRESETS so the
    rest of the script doesn't pay the cost when no --preset flag is used.
    Cached on the function object.
    """
    cached = getattr(_load_pixel_presets, "_cache", None)
    if cached is not None:
        return cached
    try:
        import pixel_art_presets as _p
    except ImportError as e:
        raise SystemExit(
            f"asset_gen: --preset requires presets/pixel_art_presets.py "
            f"(import failed: {e})"
        )
    _load_pixel_presets._cache = _p.PIXEL_STYLE_PRESETS
    return _p.PIXEL_STYLE_PRESETS


def _apply_preset(args) -> dict | None:
    """Resolve --preset against PIXEL_STYLE_PRESETS and mutate args in place.

    Order of precedence: explicit CLI flags win over preset defaults. So
    --palette / --target-size / --colors set by the user are NOT overridden
    by the preset's suggestions; only unset values get filled in.

    The preset's prompt_prefix is prepended to args.prompt so the existing
    type-prefix + style + user-prompt assembly still works downstream.

    Returns the resolved preset dict (or None if --preset not used) so
    callers can stash the negative_extra for late application.
    """
    name = getattr(args, "preset", "") or ""
    if not name:
        return None
    presets = _load_pixel_presets()
    if name not in presets:
        raise SystemExit(
            f"asset_gen: unknown --preset '{name}'. "
            f"Run 'asset_gen.py list-presets' to see options."
        )
    p = presets[name]
    prefix = (p.get("prompt_prefix") or "").rstrip(", ")
    if prefix:
        args.prompt = f"{prefix}, {args.prompt}".strip(", ")
    if not args.palette and p.get("suggested_palette"):
        args.palette = p["suggested_palette"]
    if not args.target_size and p.get("suggested_resolution"):
        args.target_size = int(p["suggested_resolution"])
    # All pixel-art presets imply pixelize post-process.
    args.pixelize = True
    # Stash negative_extra for _comfy_generate to append after the
    # type-aware negative is resolved by _resolve_style.
    args.preset_negative_extra = (p.get("negative_extra") or "").strip()
    return p

# ---------------------------------------------------------------------------
# Asset-type routing config
# ---------------------------------------------------------------------------

ASSET_TYPES = [
    "general",
    "reference",       # the visual-target anchor image
    "portrait",
    "character",
    "avatar",
    "sprite",
    "tile",
    "tileset",
    "item",
    "icon",
    "landscape",
    "environment",
    "ui",
]

# Z-Image-Turbo trigger words (per the apatero pixel-art LoRA guide).
# The pixel-art LoRA reacts to one of three triggers — sprite / scene /
# portrait — and the surrounding prompt template is:
#   "pixel art {trigger}, {subject}, {style descriptor}"
ZIT_TYPE_PROMPT_PREFIX = {
    "portrait":    "pixel art portrait,",
    "avatar":      "pixel art portrait,",
    "character":   "pixel art sprite,",
    "sprite":      "pixel art sprite,",
    "item":        "pixel art sprite,",
    "icon":        "pixel art sprite,",
    "tile":        "pixel art tile, seamless tileable, edge-aligned,",
    "tileset":     "pixel art tile, seamless tileable, edge-aligned,",
    "landscape":   "pixel art scene, wide composition,",
    "environment": "pixel art scene,",
    "ui":          "pixel art ui element, transparent background,",
    "reference":   "pixel art scene, in-game screenshot, HUD visible,",
    "general":     "pixel art,",
}

# Generic SD-style prefixes (used when checkpoint is NOT a Z-Image-Turbo).
# Subtle nudges; the agent's prompt still leads.
SD_TYPE_PROMPT_PREFIX = {
    "portrait":    "detailed character portrait, clear face features, expressive eyes,",
    "character":   "full-body character sprite, clean silhouette, consistent style,",
    "avatar":      "clean centered avatar, head-and-shoulders framing, sharp facial features,",
    "sprite":      "game sprite, transparent background, pixel-perfect edges,",
    "tile":        "seamless tileable pattern, edge-aligned, no visible seams,",
    "tileset":     "tileable pattern, repeating edge-aligned, top-down,",
    "item":        "centered game item icon, simple background, clean silhouette,",
    "icon":        "clean icon, centered subject, simple background,",
    "landscape":   "scenic environment background, wide composition,",
    "environment": "game environment scene, depth-cued composition,",
    "ui":          "clean UI element, flat shading, transparent background,",
    "reference":   "in-game screenshot perspective, HUD-aware composition,",
    "general":     "",
}

# Per-type negative prompts (added on top of the model-specific global negative)
TYPE_NEGATIVE_PREFIX = {
    "portrait":    "deformed eyes, asymmetric face, extra fingers, blurry face,",
    "character":   "deformed limbs, inconsistent proportions,",
    "avatar":      "deformed face, asymmetric eyes,",
    "sprite":      "anti-aliased edges, smooth gradient, photo, 3D render, jpeg artifacts,",
    "tile":        "seam, border, visible edge,",
    "tileset":     "visible seam, edge artifact,",
    "icon":        "background clutter, multiple subjects,",
    "ui":          "shadows, gradients, busy background,",
    "general":     "",
}

# Asset types that should be post-processed through pixelize/palette lock by default
PIXEL_ART_TYPES = {"sprite", "tile", "tileset", "item", "icon"}

# Asset types that auto-load the pixel-art LoRA on Z-Image-Turbo. Excludes
# `reference` (which should be a clean screenshot, not LoRA-stylized) and
# `general` (caller-driven).
ZIT_PIXEL_LORA_TYPES = {
    "portrait", "avatar", "character", "sprite", "item", "icon",
    "tile", "tileset", "landscape", "environment", "ui",
}

# Asset types that benefit from img2img against reference.png if it exists
IMG2IMG_AGAINST_REFERENCE = {"portrait", "character", "avatar"}

# Asset types that auto-trigger the face_detailer.json second pass after the
# base txt2img completes. SAM+YOLO mask detection + inpaint via Z-Image-Turbo
# fixes the wonky-face problem the base model produces on character work.
# Gated on use_zit because face_detailer.json hard-codes z_image_turbo_bf16.
FACE_DETAILER_TYPES = {"portrait", "character", "avatar"}


def _load_budget():
    if not BUDGET_FILE.exists():
        return None
    return json.loads(BUDGET_FILE.read_text())


def _spent_total(budget):
    return sum(v for entry in budget.get("log", []) for v in entry.values())


def check_budget(cost_cents: int):
    """Check remaining budget. Exit with error JSON if insufficient."""
    budget = _load_budget()
    if budget is None:
        return
    spent = _spent_total(budget)
    remaining = budget.get("budget_cents", 0) - spent
    if cost_cents > remaining:
        result_json(
            False,
            error=f"Budget exceeded: need {cost_cents}¢ but only {remaining}¢ remaining "
                  f"({spent}¢ of {budget['budget_cents']}¢ spent)",
        )
        sys.exit(1)


def record_spend(cost_cents: int, service: str):
    """Append a generation record to the budget log."""
    budget = _load_budget()
    if budget is None:
        return
    budget.setdefault("log", []).append({service: cost_cents})
    BUDGET_FILE.write_text(json.dumps(budget, indent=2) + "\n")


def result_json(ok, path=None, cost_cents=0, error=None, **extra):
    d = {"ok": ok, "cost_cents": cost_cents}
    if path:
        d["path"] = str(path)
    if error:
        d["error"] = error
    d.update(extra)
    print(json.dumps(d))


# ---------------------------------------------------------------------------
# ComfyUI primary path
# ---------------------------------------------------------------------------

def _comfy_available() -> bool:
    """Cheap check: skip importing requests if env says no ComfyUI."""
    if os.environ.get("ASSET_GEN_BACKEND") == "gemini":
        return False
    try:
        from comfyui_client import is_available
    except ImportError:
        return False
    base_url = os.environ.get("COMFYUI_URL", "http://localhost:8188")
    return is_available(base_url)


def _resolve_comfy_dimensions(size: str, aspect_ratio: str) -> tuple[int, int]:
    """Map size+aspect strings to (width, height) for ComfyUI."""
    from comfyui_client import resolve_dimensions
    return resolve_dimensions(size, aspect_ratio)


def _resolve_style(
    *,
    style_key: str,
    use_zit: bool,
    type_prefix: str,
    user_prompt: str,
    type_negative_prefix: str,
    base_negative: str,
    legacy_lora_name: str,
    legacy_lora_strength: float,
    auto_default_lora: str,
) -> tuple[list, str, str, str]:
    """Resolve --style / --lora into (loras_list, prompt, negative, label).

    Precedence:
      1. --style <key> — load the StyleSpec; gate on base_model compatibility
         with the active checkpoint; assemble prompt as
         "<type_prefix> <triggers>, <user_prompt>, <descriptor>".
      2. --lora <file> — single-LoRA legacy path.
      3. Auto-default — when the asset type warrants it on ZIT, load
         ZIT_PIXEL_LORA. SD path uses no auto-default.

    Returns:
      loras: list of {name, strength_model, strength_clip} dicts (empty if no LoRA)
      prompt: full positive prompt
      negative: full negative prompt
      label: short string for the [asset_gen] log line
    """
    if style_key and legacy_lora_name:
        raise SystemExit(
            f"asset_gen: --style {style_key!r} and --lora {legacy_lora_name!r} are "
            "mutually exclusive. Pick one."
        )

    # Default: type prefix + user prompt joined by a space (preserves original behavior)
    full_prompt = (type_prefix + " " + user_prompt).strip()
    negative = (type_negative_prefix + " " + base_negative).strip()

    if style_key:
        from zit_styles import get_style, style_lora_files
        spec = get_style(style_key)

        # Compatibility gate
        if use_zit and spec.base_model != "zimage":
            raise SystemExit(
                f"asset_gen: style {style_key!r} requires base_model={spec.base_model!r} "
                f"but the active checkpoint is Z-Image-Turbo. Pass --checkpoint <{spec.base_model} model> "
                "to use this style."
            )
        if (not use_zit) and spec.base_model == "zimage":
            raise SystemExit(
                f"asset_gen: style {style_key!r} requires Z-Image-Turbo (zimage) but the "
                "active checkpoint is SD-class. Pass --checkpoint z-image-turbo-fp8-aio.safetensors "
                "(or unset --checkpoint to use the ZIT default)."
            )

        # Assemble prompt: "<type_prefix> <triggers>, <user_prompt>, <descriptor>"
        # Strip any trailing comma from type_prefix so the join is clean.
        parts: list[str] = []
        tp = type_prefix.strip().rstrip(",").strip()
        if tp:
            parts.append(tp)
        parts.extend(t for t in spec.triggers if t)
        parts.append(user_prompt.strip())
        if spec.descriptor:
            parts.append(spec.descriptor)
        full_prompt = ", ".join(p for p in parts if p)

        # Negative addons
        if spec.negative_addons:
            negative = negative + ", " + spec.negative_addons

        loras = [
            {
                "name": le.name,
                "strength_model": le.strength_model,
                "strength_clip": le.strength_clip,
            }
            for le in spec.loras
        ]
        label = f"style={spec.key}({len(loras)}L:{','.join(style_lora_files(spec))[:80]})"
        return loras, full_prompt, negative, label

    # No --style: legacy --lora or auto-default
    chosen_lora = legacy_lora_name or auto_default_lora
    if chosen_lora:
        loras = [{
            "name": chosen_lora,
            "strength_model": legacy_lora_strength,
            "strength_clip": legacy_lora_strength,
        }]
        return loras, full_prompt, negative, chosen_lora
    return [], full_prompt, negative, "-"


def _comfy_generate(args, asset_type: str) -> Path:
    """Run a ComfyUI workflow tuned for the asset type. Returns output path."""
    from comfyui_client import (
        COMFYUI_URL,
        DEFAULT_NEGATIVE,
        ZIT_NEGATIVE,
        ZIT_PIXEL_LORA,
        ZIT_UNET,
        build_img2img_with_lora_workflow,
        build_tiling_workflow,
        build_txt2img_with_lora_workflow,
        build_zit_img2img_workflow,
        build_zit_txt2img_workflow,
        download_image,
        get_output_images,
        is_zit_checkpoint,
        poll_completion,
        queue_prompt,
        run_face_detailer,
        upload_image,
    )

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    base_url = os.environ.get("COMFYUI_URL", COMFYUI_URL)
    width, height = _resolve_comfy_dimensions(args.size, args.aspect_ratio)

    # Pick model: explicit --checkpoint wins; else env COMFYUI_CHECKPOINT;
    # else default to Z-Image-Turbo (the primary model on this rig).
    checkpoint = args.checkpoint or os.environ.get("COMFYUI_CHECKPOINT", "") or ZIT_UNET
    use_zit = is_zit_checkpoint(checkpoint)

    # Pick prompt prefix from the model-specific table
    type_prefix = (ZIT_TYPE_PROMPT_PREFIX if use_zit else SD_TYPE_PROMPT_PREFIX).get(asset_type, "")
    base_neg = ZIT_NEGATIVE if use_zit else DEFAULT_NEGATIVE
    type_neg_prefix = TYPE_NEGATIVE_PREFIX.get(asset_type, "")

    # Resolve style/LoRA → loras list + assembled prompt + negative
    loras, full_prompt, negative, lora_label = _resolve_style(
        style_key=getattr(args, "style", "") or "",
        use_zit=use_zit,
        type_prefix=type_prefix,
        user_prompt=args.prompt,
        type_negative_prefix=type_neg_prefix,
        base_negative=base_neg,
        legacy_lora_name=args.lora or "",
        legacy_lora_strength=args.lora_strength,
        auto_default_lora=ZIT_PIXEL_LORA if (use_zit and asset_type in ZIT_PIXEL_LORA_TYPES) else "",
    )

    # Append preset's negative_extra (if --preset was used).
    preset_neg = getattr(args, "preset_negative_extra", "") or ""
    if preset_neg:
        negative = f"{negative}, {preset_neg}".strip(", ")

    # Steps/CFG: caller's args.steps default is 25 (SD-tuned). When dispatching
    # to ZIT, drop to its 8-step / cfg 4.5 sweet spot unless user explicitly
    # raised the step count.
    if use_zit and args.steps == 25:
        steps = 8
    else:
        steps = args.steps
    if use_zit and args.cfg == 7.0:
        cfg = 4.5
    else:
        cfg = args.cfg

    print(
        f"[asset_gen] ComfyUI {asset_type} {width}x{height} "
        f"backend={'zit' if use_zit else 'sd'} model={checkpoint} "
        f"lora={lora_label} steps={steps} cfg={cfg}",
        file=sys.stderr,
    )

    # img2img reference: use --reference path or fall back to reference.png
    # for character-style asset types (the visual target anchor)
    ref_path = args.reference
    if not ref_path and asset_type in IMG2IMG_AGAINST_REFERENCE:
        candidate = Path("reference.png")
        if candidate.exists():
            ref_path = str(candidate)

    # SD-path workflow builders haven't been refactored for multi-LoRA stacking yet —
    # they take a single lora_name. If the resolved style stacks more than one LoRA
    # and we're on SD, fail loud instead of silently dropping LoRAs.
    if (not use_zit) and len(loras) > 1:
        raise SystemExit(
            f"asset_gen: style stacks {len(loras)} LoRAs but the SD workflow path "
            "only supports a single LoRA. Refactor SD builders or pick a single-LoRA style."
        )
    sd_lora_name = loras[0]["name"] if loras else ""
    sd_lora_strength = loras[0]["strength_model"] if loras else 0.8

    if use_zit:
        if ref_path:
            ref_filename = upload_image(Path(ref_path), base_url)
            workflow = build_zit_img2img_workflow(
                image_filename=ref_filename,
                prompt=full_prompt,
                negative=negative,
                loras=loras,
                denoise=args.denoise,
                steps=steps,
                cfg=cfg,
            )
        else:
            workflow = build_zit_txt2img_workflow(
                prompt=full_prompt,
                negative=negative,
                loras=loras,
                width=width,
                height=height,
                steps=steps,
                cfg=cfg,
            )
    else:
        if ref_path:
            ref_filename = upload_image(Path(ref_path), base_url)
            workflow = build_img2img_with_lora_workflow(
                image_filename=ref_filename,
                prompt=full_prompt,
                negative=negative,
                checkpoint=checkpoint,
                lora_name=sd_lora_name,
                lora_strength=sd_lora_strength,
                denoise=args.denoise,
                steps=steps,
                cfg=cfg,
            )
        elif asset_type in {"tile", "tileset"}:
            workflow = build_tiling_workflow(
                prompt=full_prompt,
                negative=negative,
                checkpoint=checkpoint,
                lora_name=sd_lora_name,
                lora_strength=sd_lora_strength,
                width=width,
                height=height,
                steps=steps,
                cfg=cfg,
            )
        else:
            workflow = build_txt2img_with_lora_workflow(
                prompt=full_prompt,
                negative=negative,
                checkpoint=checkpoint,
                lora_name=sd_lora_name,
                lora_strength=sd_lora_strength,
                width=width,
                height=height,
                steps=steps,
                cfg=cfg,
            )

    prompt_id = queue_prompt(workflow, base_url)
    history = poll_completion(prompt_id, base_url, timeout=args.timeout)
    images = get_output_images(history)
    if not images:
        raise RuntimeError("ComfyUI returned no images")

    download_image(images[0], output, base_url)

    # Face/body detailer second pass. SAM+YOLO mask the face, then Z-Image
    # inpaints with ColorMatch blending. Fixes wonky base-model faces before
    # any pixelize step (so the cleaner face geometry survives downsample).
    # When the asset is pixel-art, override the workflow's "ultra realistic
    # face" prompt so the inpaint doesn't clash with the surrounding LoRA.
    if (
        use_zit
        and asset_type in FACE_DETAILER_TYPES
        and not getattr(args, "no_face_detailer", False)
    ):
        is_pixel = args.pixelize or asset_type in PIXEL_ART_TYPES
        prompt_override = (
            "clean symmetric pixel-art face, defined eyes, sharp features, "
            "no anti-aliasing, no smooth gradients"
            if is_pixel
            else None
        )
        try:
            print(
                f"[asset_gen] face-detailer pass on {asset_type}"
                f"{' (pixel-art prompt)' if is_pixel else ''}",
                file=sys.stderr,
            )
            run_face_detailer(
                output, output, base_url,
                prompt_override=prompt_override,
                timeout=args.timeout,
            )
        except FileNotFoundError as e:
            print(f"[asset_gen] face-detailer skipped: {e}", file=sys.stderr)
        except Exception as e:
            print(f"[asset_gen] face-detailer failed (non-fatal): {e}", file=sys.stderr)

    # Post-process for pixel-art asset types — nearest-neighbor downscale +
    # palette quantization. Per the apatero guide, NEVER use AI upscalers
    # for pixel art (they introduce anti-aliasing).
    if args.pixelize or asset_type in PIXEL_ART_TYPES:
        from PIL import Image as PILImage
        from pixel_art_toolkit import pixelize as _pixelize
        target_size = args.target_size or 64
        palette = args.palette or ""
        print(
            f"[asset_gen] post-process pixelize → {target_size}px "
            f"palette={palette or 'auto'}",
            file=sys.stderr,
        )
        img = PILImage.open(output).convert("RGBA")
        result = _pixelize(img, target_size, args.colors, palette, args.dither)
        result.save(output)

    return output


# ---------------------------------------------------------------------------
# Gemini fallback path (kept compatible with the old asset_gen.py CLI)
# ---------------------------------------------------------------------------

GEMINI_IMAGE_MODEL = "gemini-3.1-flash-image-preview"
GEMINI_IMAGE_COSTS = {"512": 5, "1K": 7, "2K": 10, "4K": 15}


def _gemini_generate(args, asset_type: str) -> Path:
    """Fall back to Gemini when ComfyUI is unavailable."""
    from google import genai
    from google.genai import types

    cost = GEMINI_IMAGE_COSTS.get(args.size, 7)
    check_budget(cost)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    prefix = TYPE_PROMPT_PREFIX.get(asset_type, "")
    full_prompt = (prefix + " " + args.prompt).strip()

    config = types.GenerateContentConfig(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(
            image_size=args.size,
            aspect_ratio=args.aspect_ratio,
        ),
    )
    print(
        f"[asset_gen] Gemini fallback {args.size} {args.aspect_ratio} "
        f"({asset_type}) — cost {cost}¢",
        file=sys.stderr,
    )
    client = genai.Client()
    response = client.models.generate_content(
        model=GEMINI_IMAGE_MODEL,
        contents=[full_prompt],
        config=config,
    )

    if response.parts is None:
        reason = "unknown"
        if response.candidates and response.candidates[0].finish_reason:
            reason = response.candidates[0].finish_reason
        raise RuntimeError(f"Generation blocked (reason: {reason})")

    for part in response.parts:
        if part.inline_data is not None:
            output.write_bytes(part.inline_data.data)
            record_spend(cost, "gemini")

            # Post-process for pixel-art asset types
            if args.pixelize or asset_type in PIXEL_ART_TYPES:
                from PIL import Image as PILImage
                from pixel_art_toolkit import pixelize as _pixelize
                target_size = args.target_size or 64
                palette = args.palette or ""
                img = PILImage.open(output).convert("RGBA")
                result = _pixelize(img, target_size, args.colors, palette, args.dither)
                result.save(output)
            return output

    raise RuntimeError("No image returned")


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_list_presets(args):
    presets = _load_pixel_presets()
    rows = sorted(presets.items(), key=lambda kv: (kv[1].get("tier", ""), kv[0]))
    print(f"{len(presets)} pixel-art presets available:")
    for k, v in rows:
        tier = v.get("tier", "")
        pal = v.get("suggested_palette") or "-"
        res = v.get("suggested_resolution") or "-"
        print(f"  {k:24s} [{tier:5s}] palette={pal:12s} res={res}")


def cmd_image(args):
    asset_type = args.type
    if asset_type not in ASSET_TYPES:
        result_json(False, error=f"Unknown --type {asset_type}; choose one of {ASSET_TYPES}")
        sys.exit(1)

    # Resolve --preset before anything reads args.prompt / args.palette / etc.
    preset = _apply_preset(args)
    if preset:
        print(
            f"[asset_gen] preset='{preset.get('name', '?')}' "
            f"palette={args.palette or '-'} target_size={args.target_size or '-'} "
            f"pixelize={args.pixelize}",
            file=sys.stderr,
        )

    backend = "comfyui" if _comfy_available() else "gemini"
    try:
        if backend == "comfyui":
            output = _comfy_generate(args, asset_type)
            result_json(True, path=output, cost_cents=0, backend="comfyui", asset_type=asset_type)
        else:
            output = _gemini_generate(args, asset_type)
            cost = GEMINI_IMAGE_COSTS.get(args.size, 7)
            result_json(True, path=output, cost_cents=cost, backend="gemini", asset_type=asset_type)
    except Exception as e:
        result_json(False, error=f"{backend}: {e}", backend=backend, asset_type=asset_type)
        sys.exit(1)


def cmd_spritesheet(args):
    """Spritesheet: prefer ComfyUI batch when available, else Gemini template path."""
    backend = "comfyui" if _comfy_available() else "gemini"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    if backend == "comfyui":
        from comfyui_client import (
            COMFYUI_URL,
            DEFAULT_NEGATIVE,
            ZIT_NEGATIVE,
            ZIT_PIXEL_LORA,
            ZIT_UNET,
            build_batch_frames_workflow,
            build_zit_batch_frames_workflow,
            download_image,
            get_output_images,
            is_zit_checkpoint,
            poll_completion,
            queue_prompt,
        )
        from PIL import Image as PILImage
        from pixel_art_toolkit import make_spritesheet
        base_url = os.environ.get("COMFYUI_URL", COMFYUI_URL)

        checkpoint = args.checkpoint or os.environ.get("COMFYUI_CHECKPOINT", "") or ZIT_UNET
        use_zit = is_zit_checkpoint(checkpoint)

        prefix_table = ZIT_TYPE_PROMPT_PREFIX if use_zit else SD_TYPE_PROMPT_PREFIX
        type_prefix = prefix_table.get("sprite", "")
        base_neg = ZIT_NEGATIVE if use_zit else DEFAULT_NEGATIVE
        type_neg_prefix = TYPE_NEGATIVE_PREFIX.get("sprite", "")

        loras, prompt, negative, lora_label = _resolve_style(
            style_key=getattr(args, "style", "") or "",
            use_zit=use_zit,
            type_prefix=type_prefix,
            user_prompt=args.prompt,
            type_negative_prefix=type_neg_prefix,
            base_negative=base_neg,
            legacy_lora_name=args.lora or "",
            legacy_lora_strength=args.lora_strength,
            auto_default_lora=ZIT_PIXEL_LORA if use_zit else "",
        )

        if (not use_zit) and len(loras) > 1:
            raise SystemExit(
                f"asset_gen: style stacks {len(loras)} LoRAs but the SD spritesheet "
                "path supports only a single LoRA."
            )
        sd_lora_name = loras[0]["name"] if loras else ""
        sd_lora_strength = loras[0]["strength_model"] if loras else 0.8

        steps = 8 if use_zit and args.steps == 25 else args.steps
        cfg = 4.5 if use_zit and args.cfg == 7.0 else args.cfg

        print(
            f"[asset_gen] ComfyUI batch sprite sheet ({args.frames} frames) "
            f"backend={'zit' if use_zit else 'sd'} lora={lora_label}",
            file=sys.stderr,
        )

        if use_zit:
            workflow = build_zit_batch_frames_workflow(
                prompt=prompt,
                negative=negative,
                loras=loras,
                batch_size=args.frames,
                width=args.frame_size,
                height=args.frame_size,
                steps=steps,
                cfg=cfg,
            )
        else:
            workflow = build_batch_frames_workflow(
                prompt=prompt,
                negative=negative,
                checkpoint=checkpoint,
                lora_name=sd_lora_name,
                lora_strength=sd_lora_strength,
                batch_size=args.frames,
                width=args.frame_size,
                height=args.frame_size,
                steps=steps,
                cfg=cfg,
            )
        prompt_id = queue_prompt(workflow, base_url)
        history = poll_completion(prompt_id, base_url, timeout=args.timeout)
        images = get_output_images(history)
        if not images:
            result_json(False, error="ComfyUI returned no frames")
            sys.exit(1)

        # Download every frame and assemble into a sheet
        tmp_dir = output.parent / f".{output.stem}_frames"
        tmp_dir.mkdir(parents=True, exist_ok=True)
        frames = []
        for i, info in enumerate(images):
            fp = tmp_dir / f"frame_{i:02d}.png"
            download_image(info, fp, base_url)
            frames.append(PILImage.open(fp).convert("RGBA"))
        sheet = make_spritesheet(frames, columns=args.columns)
        sheet.save(output)
        # Optional palette lock on the assembled sheet
        if args.palette or args.pixelize:
            from pixel_art_toolkit import reduce_palette
            from PIL import Image as PILImage  # noqa: F811
            sheet = PILImage.open(output).convert("RGBA")
            sheet = reduce_palette(sheet, args.colors or 16, args.palette, args.dither)
            sheet.save(output)
        # Cleanup intermediates
        shutil.rmtree(tmp_dir, ignore_errors=True)
        result_json(
            True, path=output, cost_cents=0, backend="comfyui",
            frames=len(frames), columns=args.columns,
        )
        return

    # Gemini template path — single image generation matching the old behavior
    from google import genai
    from google.genai import types
    cost = GEMINI_IMAGE_COSTS["1K"]
    check_budget(cost)

    template_script = THIS_DIR / "spritesheet_template.py"
    if not template_script.exists():
        # Older godogen install — template script lives in the godogen skill dir
        template_script = THIS_DIR.parent.parent / "godogen" / "tools" / "spritesheet_template.py"
    if not template_script.exists():
        result_json(False, error=f"spritesheet_template.py not found near {THIS_DIR}")
        sys.exit(1)

    import subprocess
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        tmp = f.name
    subprocess.run(
        [sys.executable, str(template_script), "-o", tmp, "--bg", args.bg],
        check=True, capture_output=True,
    )
    template_bytes = Path(tmp).read_bytes()
    Path(tmp).unlink()

    system = (
        "Using the attached template image as an exact layout guide: generate a sprite sheet. "
        "The image is a 4x4 grid of 16 equal cells separated by red lines. "
        "Replace each numbered cell with the corresponding content, reading left-to-right, "
        "top-to-bottom (cell 1 = first, cell 16 = last). Rules: KEEP the red grid lines exactly "
        "where they are; each cell's content must be CENTERED in its cell and must NOT cross "
        f"into adjacent cells; CRITICAL: fill ALL empty space in every cell with flat solid {args.bg} "
        "— no gradients, no scenery, no patterns, just the plain color; maintain consistent "
        "style, lighting direction, and proportions across all 16 cells; CRITICAL: do NOT draw "
        "the numbered circles from the template onto the output — replace them entirely with "
        "the actual drawing content"
    )

    print(f"[asset_gen] Gemini sprite sheet (bg={args.bg}) — cost {cost}¢", file=sys.stderr)
    client = genai.Client()
    response = client.models.generate_content(
        model=GEMINI_IMAGE_MODEL,
        contents=[
            types.Part.from_bytes(data=template_bytes, mime_type="image/png"),
            args.prompt,
        ],
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            system_instruction=system,
            image_config=types.ImageConfig(image_size="1K", aspect_ratio="1:1"),
        ),
    )

    if response.parts is None:
        reason = "unknown"
        if response.candidates and response.candidates[0].finish_reason:
            reason = response.candidates[0].finish_reason
        result_json(False, error=f"Generation blocked (reason: {reason})")
        sys.exit(1)

    for part in response.parts:
        if part.inline_data is not None:
            output.write_bytes(part.inline_data.data)
            record_spend(cost, "gemini")
            result_json(True, path=output, cost_cents=cost, backend="gemini")
            return

    result_json(False, error="No image returned")
    sys.exit(1)


def cmd_glb(args):
    """Tripo3D image → GLB. Unchanged from the old asset_gen.py."""
    from tripo3d import MODEL_V3, image_to_glb

    presets = {
        "lowpoly": dict(face_limit=5000, smart_low_poly=True, texture_quality="standard", geometry_quality="standard", cost_cents=40),
        "medium":  dict(face_limit=20000, smart_low_poly=False, texture_quality="standard", geometry_quality="standard", cost_cents=30),
        "high":    dict(face_limit=None, smart_low_poly=False, texture_quality="detailed", geometry_quality="standard", cost_cents=40),
        "ultra":   dict(face_limit=None, smart_low_poly=False, texture_quality="detailed", geometry_quality="detailed", cost_cents=60),
    }
    preset = presets.get(args.quality, presets["medium"])
    check_budget(preset["cost_cents"])

    image_path = Path(args.image)
    if not image_path.exists():
        result_json(False, error=f"Image not found: {image_path}")
        sys.exit(1)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    print(f"[asset_gen] Tripo3D quality={args.quality}", file=sys.stderr)
    try:
        image_to_glb(
            image_path, output, model_version=MODEL_V3,
            face_limit=preset["face_limit"],
            smart_low_poly=preset["smart_low_poly"],
            texture_quality=preset["texture_quality"],
            geometry_quality=preset["geometry_quality"],
        )
    except Exception as e:
        result_json(False, error=str(e))
        sys.exit(1)

    record_spend(preset["cost_cents"], "tripo3d")
    result_json(True, path=output, cost_cents=preset["cost_cents"])


def cmd_set_budget(args):
    BUDGET_FILE.parent.mkdir(parents=True, exist_ok=True)
    budget = {"budget_cents": args.cents, "log": []}
    if BUDGET_FILE.exists():
        old = json.loads(BUDGET_FILE.read_text())
        budget["log"] = old.get("log", [])
    BUDGET_FILE.write_text(json.dumps(budget, indent=2) + "\n")
    spent = _spent_total(budget)
    print(json.dumps({
        "ok": True, "budget_cents": args.cents,
        "spent_cents": spent, "remaining_cents": args.cents - spent,
    }))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Asset Generator — ComfyUI-first, Gemini fallback. "
                    "Routes by --type for asset-specific quality."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # image
    p = sub.add_parser("image", help="Generate a PNG image (free on ComfyUI; 5-15¢ on Gemini)")
    p.add_argument("--prompt", required=True)
    p.add_argument(
        "--type", default="general", choices=ASSET_TYPES,
        help="Asset type for routing. Drives prompt prefix, workflow, and post-processing.",
    )
    p.add_argument("--size", default="1K", choices=["512", "1K", "2K", "4K"])
    p.add_argument(
        "--aspect-ratio", default="1:1",
        choices=["1:1", "16:9", "9:16", "3:2", "2:3", "4:3", "3:4", "21:9", "1:4", "4:1", "8:1", "1:8", "4:5", "5:4"],
    )
    p.add_argument("-o", "--output", required=True)
    # ComfyUI tuning
    p.add_argument("--checkpoint", default="", help="ComfyUI checkpoint name (overrides default)")
    p.add_argument("--lora", default="", help="Optional LoRA filename (single-LoRA path; mutually exclusive with --style)")
    p.add_argument("--lora-strength", type=float, default=0.8)
    p.add_argument("--style", default="",
                   help="Named style from zit_styles.STYLES (e.g. 'pc98', 'zx-spectrum', 'soft-pixel-8x'). "
                        "Loads the style's LoRA stack, injects trigger words after the type prefix, "
                        "and appends the style descriptor. Mutually exclusive with --lora.")
    p.add_argument("--steps", type=int, default=25)
    p.add_argument("--cfg", type=float, default=7.0)
    p.add_argument("--denoise", type=float, default=0.6, help="img2img denoise (0..1)")
    p.add_argument("--reference", default="", help="Optional reference image path for img2img")
    p.add_argument("--timeout", type=int, default=300)
    # Pixel art post-process
    p.add_argument("--pixelize", action="store_true",
                   help="Force pixel-art post-process (auto-on for sprite/tile/item types)")
    p.add_argument("--target-size", type=int, default=0,
                   help="Pixelize target dimension (default 64 when post-processing)")
    p.add_argument("--colors", type=int, default=0,
                   help="Max colors after palette reduction (0=auto k-means elbow)")
    p.add_argument("--palette", default="",
                   help="Built-in palette name (pico8, nes, gameboy, endesga32, sweetie16, ...)")
    p.add_argument("--dither", action="store_true")
    p.add_argument("--no-face-detailer", action="store_true",
                   help="Skip the auto face-detailer second pass on "
                        "portrait/character/avatar (ZIT path only).")
    p.add_argument("--preset", default="",
                   help="Pixel-art preset name (e.g. fantasy_rpg, gameboy, "
                        "scifi, nes_retro). Applies prompt prefix, negative "
                        "extras, palette, and target resolution from "
                        "presets/pixel_art_presets.py. Forces --pixelize. "
                        "Run 'asset_gen.py list-presets' to enumerate.")
    p.set_defaults(func=cmd_image)

    # list-presets (own subcommand so --prompt/--type aren't required)
    p = sub.add_parser("list-presets",
                       help="List pixel-art presets from presets/pixel_art_presets.py")
    p.set_defaults(func=cmd_list_presets)

    # spritesheet
    p = sub.add_parser("spritesheet", help="Generate a sprite sheet")
    p.add_argument("--prompt", required=True)
    p.add_argument("--bg", default="#00FF00",
                   help="(Gemini path only) Background color hex; ignored on ComfyUI")
    p.add_argument("--frames", type=int, default=16,
                   help="(ComfyUI path) Number of frames in the sheet")
    p.add_argument("--columns", type=int, default=4,
                   help="(ComfyUI path) Sprite-sheet column count")
    p.add_argument("--frame-size", type=int, default=512,
                   help="(ComfyUI path) Frame width/height in px")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--checkpoint", default="")
    p.add_argument("--lora", default="")
    p.add_argument("--lora-strength", type=float, default=0.8)
    p.add_argument("--style", default="",
                   help="Named style from zit_styles.STYLES; mutually exclusive with --lora.")
    p.add_argument("--steps", type=int, default=25)
    p.add_argument("--cfg", type=float, default=7.0)
    p.add_argument("--timeout", type=int, default=600)
    p.add_argument("--pixelize", action="store_true")
    p.add_argument("--colors", type=int, default=0)
    p.add_argument("--palette", default="")
    p.add_argument("--dither", action="store_true")
    p.set_defaults(func=cmd_spritesheet)

    # glb
    p = sub.add_parser("glb", help="Convert PNG to GLB 3D model via Tripo3D (30-40¢)")
    p.add_argument("--image", required=True)
    p.add_argument("--quality", default="medium", choices=["lowpoly", "medium", "high", "ultra"])
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_glb)

    # set_budget
    p = sub.add_parser("set_budget", help="Set the Gemini-fallback budget cap (cents)")
    p.add_argument("cents", type=int)
    p.set_defaults(func=cmd_set_budget)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
