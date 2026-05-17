"""Video Pipeline — LTX 2.3 on 8 GB VRAM, via Deno's reference workflows.

Bundles Deno's saved ComfyUI workflows as the source-of-truth graphs, and
provides a Python wrapper to patch user-facing knobs (prompt, resolution,
length, fps, output filename, input image for i2v) without forcing the
caller to edit JSON by hand.

Subcommands
-----------
t2v        Text-to-video. Patches prompt + dims into the base workflow.
           With --run, also submits to ComfyUI.
i2v        Image-to-video. Uploads --image to ComfyUI input dir, wires it
           into the MultiImageLoader, otherwise like t2v.
bundle     Copy Deno's reference workflow JSON to an editable path.
inject     Patch widgets in a saved workflow file; do not run.
run        Submit a saved-format workflow to ComfyUI (converts to API
           format), poll, optionally copy output + record to manifest.
models     Verify required LTX 2.3 model files exist in ComfyUI's models dir.
presets    List bundled workflows.

Bundled workflows are by Deno (Extension-Yard1918). This wrapper packages
+ parameterizes them; it does not modify the node graph.
"""

from __future__ import annotations

import argparse
import json
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
SKILL_ROOT = THIS_DIR.parent
SKILLS_ROOT = SKILL_ROOT.parent
WORKFLOWS_DIR = SKILL_ROOT / "workflows"
IMAGE_PIPELINE_TOOLS = SKILLS_ROOT / "image-pipeline" / "tools"
ASSET_MANIFEST_TOOLS = SKILLS_ROOT / "asset-manifest" / "tools"

if str(IMAGE_PIPELINE_TOOLS) not in sys.path:
    sys.path.insert(0, str(IMAGE_PIPELINE_TOOLS))

try:
    from comfyui_client import COMFYUI_URL  # type: ignore
except Exception:
    COMFYUI_URL = "http://localhost:8188"


# ---------------------------------------------------------------------------
# Bundled workflow presets
# ---------------------------------------------------------------------------

PRESETS = {
    "base":       "ltx23_8gb_base.json",
    "with-audio": "ltx23_8gb_with_audio.json",
}


# Node IDs known to be present in Deno's workflow (verified by inspection).
# If Deno renumbers in a future release, re-inspect with `inject --in <file>
# --dump-ids` and update these constants.
NODE_PROMPT_GUIDE      = 5317  # DenoLTXPromptGuide:        widgets[1]=positive, [5]=negative
NODE_EMPTY_LATENT_VID  = 3059  # EmptyLTXVLatentVideo:      widgets[0..3]=w,h,length,batch
NODE_EMPTY_LATENT_AUD  = 3980  # LTXVEmptyLatentAudio:      widgets[1]=fps
NODE_RESOLUTION_SETUP  = 5283  # DenoResolutionSetup:       widgets[3..5]=megapix,w,h
NODE_MULTI_IMAGE_LOAD  = 5281  # DenoMultiImageLoader:      widgets[0]=image1 path/name
NODE_VIDEO_COMBINE_FIN = 4995  # VHS_VideoCombine "Final":  dict widgets, key "filename_prefix"

REQUIRED_MODELS = [
    "LTX-2.3-22B-distilled-1.1-Q4_K_M.gguf",
    "LTX23_video_vae_bf16.safetensors",
    "LTX23_audio_vae_bf16.safetensors",
    "gemma_3_12B_it_fp4_mixed.safetensors",
    "ltx-2.3_text_projection_bf16.safetensors",
]
OPTIONAL_MODELS = ["flownet.pkl"]  # RIFE


# ---------------------------------------------------------------------------
# Workflow patching
# ---------------------------------------------------------------------------

def _load_preset(preset: str) -> dict:
    if preset not in PRESETS:
        raise SystemExit(f"unknown preset {preset!r}. Available: {list(PRESETS)}")
    path = WORKFLOWS_DIR / PRESETS[preset]
    if not path.exists():
        raise SystemExit(f"bundled workflow not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _find_node(workflow: dict, node_id: int) -> dict | None:
    for n in workflow.get("nodes", []):
        if n.get("id") == node_id:
            return n
    return None


def _patch_widgets_list(node: dict, updates: dict[int, object]) -> None:
    """Mutate a node whose widgets_values is a list. `updates` is {index: value}."""
    wv = node.get("widgets_values")
    if not isinstance(wv, list):
        raise RuntimeError(
            f"node id={node.get('id')} type={node.get('type')} expected list widgets, "
            f"got {type(wv).__name__}")
    for idx, val in updates.items():
        if idx >= len(wv):
            raise RuntimeError(
                f"node id={node.get('id')} widget index {idx} out of range "
                f"(len={len(wv)})")
        wv[idx] = val


def _patch_widgets_dict(node: dict, updates: dict[str, object]) -> None:
    wv = node.get("widgets_values")
    if not isinstance(wv, dict):
        raise RuntimeError(
            f"node id={node.get('id')} type={node.get('type')} expected dict widgets, "
            f"got {type(wv).__name__}")
    wv.update(updates)


def patch_workflow(workflow: dict, *,
                   prompt: str | None = None,
                   negative: str | None = None,
                   width: int | None = None,
                   height: int | None = None,
                   length: int | None = None,
                   fps: int | None = None,
                   output_prefix: str | None = None,
                   input_image_name: str | None = None) -> dict:
    """Mutate the workflow in place with the given user-facing overrides.
    Returns the same workflow dict for chaining."""
    if prompt is not None or negative is not None:
        n = _find_node(workflow, NODE_PROMPT_GUIDE)
        if n is None:
            raise SystemExit(f"prompt-guide node {NODE_PROMPT_GUIDE} not found — "
                             f"workflow may be from a different Deno version.")
        updates: dict[int, object] = {}
        if prompt is not None:
            updates[1] = prompt
        if negative is not None:
            updates[5] = negative
        _patch_widgets_list(n, updates)
    if width is not None or height is not None or length is not None:
        n = _find_node(workflow, NODE_EMPTY_LATENT_VID)
        if n is None:
            raise SystemExit(f"empty-latent-video node {NODE_EMPTY_LATENT_VID} not found")
        updates = {}
        if width is not None:  updates[0] = str(width)
        if height is not None: updates[1] = str(height)
        if length is not None: updates[2] = str(length)
        _patch_widgets_list(n, updates)
        # Also update DenoResolutionSetup so its preview dims match
        r = _find_node(workflow, NODE_RESOLUTION_SETUP)
        if r is not None:
            r_updates: dict[int, object] = {}
            if width is not None:  r_updates[3] = str(width)
            if height is not None: r_updates[4] = str(height)
            _patch_widgets_list(r, r_updates)
    if fps is not None:
        n = _find_node(workflow, NODE_EMPTY_LATENT_AUD)
        if n is not None:
            _patch_widgets_list(n, {1: str(fps)})
    if output_prefix is not None:
        n = _find_node(workflow, NODE_VIDEO_COMBINE_FIN)
        if n is not None:
            _patch_widgets_dict(n, {"filename_prefix": output_prefix})
    if input_image_name is not None:
        n = _find_node(workflow, NODE_MULTI_IMAGE_LOAD)
        if n is None:
            raise SystemExit(f"multi-image-loader node {NODE_MULTI_IMAGE_LOAD} not found "
                             f"— i2v requires the base workflow that includes it.")
        # Widget [0] is the image path/name slot. Set to the uploaded image filename.
        _patch_widgets_list(n, {0: input_image_name})
    return workflow


# ---------------------------------------------------------------------------
# Saved → API format conversion (so we can POST /prompt)
# ---------------------------------------------------------------------------

def saved_to_api(workflow: dict) -> dict:
    """Convert ComfyUI's 'saved' workflow format (with nodes/links) to the API
    format ({node_id: {class_type, inputs}}).

    Best-effort: walks node.inputs to figure out which are widgets (have
    'widget' key) vs links (have 'link' key). Widgets get values from
    widgets_values by walking name order; links get [src_node, src_slot]."""
    nodes_by_id = {n["id"]: n for n in workflow.get("nodes", [])}
    links_by_id = {l[0]: l for l in workflow.get("links", []) if isinstance(l, list) and len(l) >= 6}
    # link format: [link_id, src_node_id, src_slot_index, dst_node_id, dst_slot_index, type]

    api: dict[str, dict] = {}
    for node_id, node in nodes_by_id.items():
        class_type = node.get("type", "")
        # Skip layout-only nodes that ComfyUI doesn't execute
        if class_type in ("Note", "MarkdownNote", "Reroute", "GetNode", "SetNode",
                          "PrimitiveFloat", "PrimitiveBoolean", "PrimitiveInt",
                          "Fast Groups Bypasser (rgthree)"):
            continue
        if node.get("mode") == 4:  # bypassed
            continue

        api_inputs: dict[str, object] = {}
        node_inputs = node.get("inputs", []) or []
        widgets_values = node.get("widgets_values")
        widget_idx = 0

        # Walk the inputs list. The key insight: when an input slot has a
        # `widget` key, it IS in the widgets_values position regardless of
        # whether it's currently link-backed. So widget_idx must advance for
        # every widget-eligible slot. The widget value is only USED when no
        # link is present (otherwise the link takes priority).
        for inp in node_inputs:
            name = inp.get("name")
            if name is None:
                continue
            link_id = inp.get("link")
            is_widget_slot = "widget" in inp
            if link_id is not None and link_id in links_by_id:
                _, src_node, src_slot, _dst_node, _dst_slot, _type = links_by_id[link_id]
                api_inputs[name] = [str(src_node), int(src_slot)]
            elif is_widget_slot and isinstance(widgets_values, list):
                if widget_idx < len(widgets_values):
                    api_inputs[name] = widgets_values[widget_idx]
            if is_widget_slot:
                widget_idx += 1

        # If widgets_values is a dict (VHS_VideoCombine style), merge keys directly
        if isinstance(widgets_values, dict):
            for k, v in widgets_values.items():
                if k == "videopreview":
                    continue  # UI-only state, not an input
                if k not in api_inputs:
                    api_inputs[k] = v

        api[str(node_id)] = {"class_type": class_type, "inputs": api_inputs}
    return api


# ---------------------------------------------------------------------------
# ComfyUI submission
# ---------------------------------------------------------------------------

def _comfy_post(url: str, path: str, body: dict | None = None,
                files: dict | None = None) -> dict:
    full = f"{url.rstrip('/')}{path}"
    if files is not None:
        # multipart/form-data for /upload/image
        boundary = uuid.uuid4().hex
        parts = []
        for name, val in (body or {}).items():
            parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{val}\r\n")
        for name, (fname, fcontent, ctype) in files.items():
            parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{fname}\"\r\nContent-Type: {ctype}\r\n\r\n")
        head = "".join(parts).encode("utf-8")
        tail_parts = []
        # rebuild with files inline
        head = ""
        for name, val in (body or {}).items():
            head += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{val}\r\n"
        head_b = head.encode("utf-8")
        file_parts = b""
        for name, (fname, fcontent, ctype) in files.items():
            file_parts += (f"--{boundary}\r\nContent-Disposition: form-data; "
                           f"name=\"{name}\"; filename=\"{fname}\"\r\n"
                           f"Content-Type: {ctype}\r\n\r\n").encode("utf-8")
            file_parts += fcontent
            file_parts += b"\r\n"
        end = f"--{boundary}--\r\n".encode("utf-8")
        data = head_b + file_parts + end
        req = urllib.request.Request(full, data=data, method="POST")
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    else:
        data = json.dumps(body or {}).encode("utf-8")
        req = urllib.request.Request(full, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def _comfy_get(url: str, path: str) -> dict:
    full = f"{url.rstrip('/')}{path}"
    req = urllib.request.Request(full)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def upload_image(url: str, image_path: Path) -> str:
    """POST to /upload/image. Returns the filename ComfyUI assigned."""
    if not image_path.exists():
        raise SystemExit(f"image not found: {image_path}")
    with image_path.open("rb") as f:
        content = f.read()
    ctype = "image/png" if image_path.suffix.lower() == ".png" else "image/jpeg"
    resp = _comfy_post(url, "/upload/image",
                       body={"overwrite": "true", "type": "input"},
                       files={"image": (image_path.name, content, ctype)})
    return resp.get("name") or image_path.name


def queue_workflow(url: str, workflow_api: dict) -> str:
    client_id = uuid.uuid4().hex
    resp = _comfy_post(url, "/prompt", body={"prompt": workflow_api, "client_id": client_id})
    pid = resp.get("prompt_id")
    if not pid:
        raise SystemExit(f"queue failed; ComfyUI response: {resp}")
    return pid


def poll_history(url: str, prompt_id: str, timeout_sec: float = 1800.0,
                 poll_interval: float = 3.0) -> dict:
    deadline = time.monotonic() + timeout_sec
    while True:
        h = _comfy_get(url, f"/history/{prompt_id}")
        if prompt_id in h:
            return h[prompt_id]
        if time.monotonic() > deadline:
            raise SystemExit(f"poll timed out after {timeout_sec}s for prompt {prompt_id}")
        time.sleep(poll_interval)


def extract_output_videos(history_entry: dict) -> list[dict]:
    """VHS_VideoCombine writes outputs as either 'gifs' or 'videos' depending on
    format. Walk history_entry['outputs'] for any video-ish entries."""
    out: list[dict] = []
    for node_id, node_out in (history_entry.get("outputs") or {}).items():
        for key in ("gifs", "videos"):
            for v in node_out.get(key, []) or []:
                out.append({**v, "from_node": node_id, "kind": key})
    return out


def download_video(url: str, info: dict, dest_dir: Path) -> Path:
    """Download a VHS-output video referenced by /view?filename=…&type=…&subfolder=…"""
    qs = urllib.parse.urlencode({
        "filename": info["filename"],
        "type": info.get("type", "output"),
        "subfolder": info.get("subfolder", ""),
    })
    req = urllib.request.Request(f"{url.rstrip('/')}/view?{qs}")
    dest_dir.mkdir(parents=True, exist_ok=True)
    out = dest_dir / info["filename"]
    with urllib.request.urlopen(req, timeout=120) as resp, out.open("wb") as f:
        shutil.copyfileobj(resp, f)
    return out


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_presets(_args) -> None:
    out = []
    for name, fname in PRESETS.items():
        p = WORKFLOWS_DIR / fname
        out.append({
            "preset": name,
            "filename": fname,
            "exists": p.exists(),
            "size_bytes": p.stat().st_size if p.exists() else 0,
        })
    print(json.dumps({"presets": out}, indent=2))


def cmd_bundle(args) -> None:
    if args.preset not in PRESETS:
        raise SystemExit(f"unknown preset {args.preset!r}")
    src = WORKFLOWS_DIR / PRESETS[args.preset]
    dest = Path(args.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    print(json.dumps({"ok": True, "preset": args.preset,
                      "source": str(src), "wrote": str(dest)}, indent=2))


def cmd_inject(args) -> None:
    src = Path(args.input)
    wf = json.loads(src.read_text(encoding="utf-8"))
    if args.dump_ids:
        rows = []
        for n in wf.get("nodes", []):
            rows.append({"id": n["id"], "type": n.get("type"), "title": n.get("title", "")})
        print(json.dumps(rows, indent=2))
        return
    patch_workflow(wf,
                   prompt=args.prompt, negative=args.negative,
                   width=args.width, height=args.height, length=args.length,
                   fps=args.fps, output_prefix=args.output_prefix,
                   input_image_name=args.input_image_name)
    dest = Path(args.output) if args.output else src
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(wf, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"ok": True, "wrote": str(dest),
                      "patched": {k: bool(v) for k, v in {
                          "prompt": args.prompt, "negative": args.negative,
                          "width": args.width, "height": args.height,
                          "length": args.length, "fps": args.fps,
                          "output_prefix": args.output_prefix,
                          "input_image_name": args.input_image_name,
                      }.items() if v is not None}}, indent=2))


def cmd_t2v(args) -> None:
    """Patch the base workflow with prompt + dims, optionally submit."""
    wf = _load_preset(args.preset)
    patch_workflow(wf,
                   prompt=args.prompt, negative=args.negative,
                   width=args.width, height=args.height, length=args.length,
                   fps=args.fps, output_prefix=args.output_prefix)
    if args.workflow_out:
        Path(args.workflow_out).write_text(
            json.dumps(wf, indent=2, ensure_ascii=False), encoding="utf-8")
    if not args.run:
        # No execution — write a temp file and tell the user to load it in ComfyUI Web
        out = Path(args.workflow_out) if args.workflow_out else (Path("video_workflow_patched.json"))
        if not args.workflow_out:
            out.write_text(json.dumps(wf, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({
            "ok": True, "submitted": False,
            "workflow_path": str(out),
            "next": "Open in ComfyUI Web (drag-drop into the canvas), then click Queue.",
        }, indent=2))
        return
    _submit_and_collect(args, wf)


def cmd_i2v(args) -> None:
    """Upload input image, patch workflow with image filename + prompt + dims, submit."""
    if not args.image:
        raise SystemExit("--image is required for i2v")
    wf = _load_preset(args.preset)
    if args.run:
        uploaded_name = upload_image(args.comfyui_url, Path(args.image))
        print(f"[video-pipeline] uploaded {args.image} as {uploaded_name}", file=sys.stderr)
    else:
        # When not running, just bake the path into the workflow JSON; user will
        # need to upload via the ComfyUI UI when they queue.
        uploaded_name = Path(args.image).name
    patch_workflow(wf,
                   prompt=args.prompt, negative=args.negative,
                   width=args.width, height=args.height, length=args.length,
                   fps=args.fps, output_prefix=args.output_prefix,
                   input_image_name=uploaded_name)
    if args.workflow_out:
        Path(args.workflow_out).write_text(
            json.dumps(wf, indent=2, ensure_ascii=False), encoding="utf-8")
    if not args.run:
        out = Path(args.workflow_out) if args.workflow_out else (Path("video_workflow_patched.json"))
        if not args.workflow_out:
            out.write_text(json.dumps(wf, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({
            "ok": True, "submitted": False,
            "workflow_path": str(out),
            "next": (f"Upload {args.image} to ComfyUI's input dir, then load the workflow JSON."),
        }, indent=2))
        return
    _submit_and_collect(args, wf)


def _submit_and_collect(args, wf: dict) -> None:
    """Convert + submit + poll + (optionally) copy output and record to manifest."""
    api = saved_to_api(wf)
    prompt_id = queue_workflow(args.comfyui_url, api)
    print(f"[video-pipeline] queued prompt_id={prompt_id}; polling /history…", file=sys.stderr)
    history = poll_history(args.comfyui_url, prompt_id, timeout_sec=args.timeout)
    videos = extract_output_videos(history)
    if not videos:
        raise SystemExit("no video outputs found in history — check ComfyUI's console for errors")
    # Pick the final (highest-resolution) video — the one from the upscale branch.
    # Heuristic: largest filename (alphabetical last) usually wins because VHS
    # increments a counter and the last write is the final pass.
    final = sorted(videos, key=lambda v: v.get("filename", ""))[-1]
    print(f"[video-pipeline] final output: {final.get('filename')}", file=sys.stderr)

    result = {"ok": True, "prompt_id": prompt_id, "outputs": videos, "final": final}
    if args.copy_to:
        dest = download_video(args.comfyui_url, final, Path(args.copy_to))
        result["copied_to"] = str(dest)
        if args.manifest:
            _record_manifest(Path(args.manifest), dest, prompt=getattr(args, "prompt", ""),
                             width=args.width, height=args.height,
                             length=args.length, fps=args.fps)
    print(json.dumps(result, indent=2))


def _record_manifest(manifest_path: Path, video_path: Path,
                     prompt: str, width, height, length, fps) -> None:
    cli = ASSET_MANIFEST_TOOLS / "manifest.py"
    if not cli.exists():
        print(f"[video-pipeline] asset-manifest CLI not found at {cli} — skipping record",
              file=sys.stderr)
        return
    cmd = [
        sys.executable, str(cli), "add",
        "--manifest", str(manifest_path),
        "--path", str(video_path),
        "--kind", "other",
        "--provider", "video-pipeline.ltx23",
        "--labels", "video,ltx23",
        "--param", f"prompt={prompt or ''}",
    ]
    if width:  cmd += ["--param", f"width={width}"]
    if height: cmd += ["--param", f"height={height}"]
    if length: cmd += ["--param", f"length={length}"]
    if fps:    cmd += ["--param", f"fps={fps}"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"[video-pipeline] manifest add failed: {proc.stderr.strip()[:200]}",
              file=sys.stderr)


def cmd_models(args) -> None:
    """List required model filenames and check ComfyUI's model listing endpoints."""
    found: dict[str, dict] = {}
    errors: list[str] = []
    # ComfyUI exposes models per category via /object_info — but the simplest
    # check is to ask the user's running ComfyUI for the GGUF + checkpoint
    # listings and grep them.
    try:
        info = _comfy_get(args.comfyui_url, "/object_info")
    except Exception as e:
        errors.append(f"could not query ComfyUI /object_info: {e}")
        info = {}
    seen_filenames: set[str] = set()
    # Walk a few known node types whose first input lists available model files.
    interesting = {
        "UnetLoaderGGUF": ("unet_name",),
        "CheckpointLoaderSimple": ("ckpt_name",),
        "VAELoader": ("vae_name",),
        "CLIPLoader": ("clip_name",),
        "DualCLIPLoader": ("clip_name1", "clip_name2"),
    }
    for node_class, input_keys in interesting.items():
        spec = info.get(node_class, {})
        required = (spec.get("input", {}).get("required") or {}) if isinstance(spec, dict) else {}
        for k in input_keys:
            entry = required.get(k)
            if isinstance(entry, list) and entry and isinstance(entry[0], list):
                for fn in entry[0]:
                    seen_filenames.add(fn)
    for fn in REQUIRED_MODELS + OPTIONAL_MODELS:
        found[fn] = {
            "required": fn in REQUIRED_MODELS,
            "found": fn in seen_filenames,
        }
    missing_required = [fn for fn in REQUIRED_MODELS if not found[fn]["found"]]
    print(json.dumps({
        "ok": not missing_required and not errors,
        "models": found,
        "missing_required": missing_required,
        "errors": errors,
        "note": ("Pull missing models from Hugging Face; Deno's preset loader "
                 "also exposes a DenoLTXModelDownloader node that can fetch "
                 "them in-graph."),
    }, indent=2))
    if missing_required or errors:
        sys.exit(1)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _add_common_video_args(p, *, require_prompt: bool):
    p.add_argument("--prompt", required=require_prompt)
    p.add_argument("--negative", default=None)
    p.add_argument("--width", type=int)
    p.add_argument("--height", type=int)
    p.add_argument("--length", type=int, help="Total frames (default in workflow: 121)")
    p.add_argument("--fps", type=int)
    p.add_argument("--output-prefix", help="VHS filename_prefix (default: AnimateDiff)")
    p.add_argument("--preset", default="base", choices=list(PRESETS))
    p.add_argument("--workflow-out", help="Also write the patched workflow JSON here")


def _add_submit_args(p):
    p.add_argument("--run", action="store_true",
                   help="Submit to ComfyUI (otherwise just write the patched JSON)")
    p.add_argument("--comfyui-url", default=COMFYUI_URL)
    p.add_argument("--copy-to", help="Copy final MP4 to this dir after completion")
    p.add_argument("--manifest", help="Record output into this asset-manifest JSON")
    p.add_argument("--timeout", type=float, default=1800.0,
                   help="Poll timeout in seconds (default 1800 = 30 min)")


def main():
    parser = argparse.ArgumentParser(
        description="video-pipeline: LTX 2.3 on 8GB VRAM via Deno's workflow")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("t2v", help="Text-to-video")
    _add_common_video_args(p, require_prompt=True)
    _add_submit_args(p)
    p.set_defaults(func=cmd_t2v)

    p = sub.add_parser("i2v", help="Image-to-video")
    p.add_argument("--image", required=True, help="Input image path")
    _add_common_video_args(p, require_prompt=True)
    _add_submit_args(p)
    p.set_defaults(func=cmd_i2v)

    p = sub.add_parser("bundle", help="Copy a bundled workflow JSON to an editable path")
    p.add_argument("--preset", required=True, choices=list(PRESETS))
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_bundle)

    p = sub.add_parser("inject", help="Patch widgets in a saved workflow JSON")
    p.add_argument("--input", required=True, help="Source workflow JSON")
    p.add_argument("--output", help="Destination (default: overwrite --input)")
    p.add_argument("--prompt")
    p.add_argument("--negative")
    p.add_argument("--width", type=int)
    p.add_argument("--height", type=int)
    p.add_argument("--length", type=int)
    p.add_argument("--fps", type=int)
    p.add_argument("--output-prefix")
    p.add_argument("--input-image-name",
                   help="Filename (in ComfyUI's input dir) for i2v MultiImageLoader slot 1")
    p.add_argument("--dump-ids", action="store_true",
                   help="Print node ids+types and exit (for finding the right widget index)")
    p.set_defaults(func=cmd_inject)

    p = sub.add_parser("run", help="Submit a saved-format workflow JSON to ComfyUI")
    p.add_argument("--workflow", required=True)
    p.add_argument("--comfyui-url", default=COMFYUI_URL)
    p.add_argument("--copy-to")
    p.add_argument("--manifest")
    p.add_argument("--timeout", type=float, default=1800.0)
    p.set_defaults(func=lambda a: _run_saved_workflow(a))

    p = sub.add_parser("models", help="Verify required LTX 2.3 model files")
    p.add_argument("--comfyui-url", default=COMFYUI_URL)
    p.set_defaults(func=cmd_models)

    p = sub.add_parser("presets", help="List bundled workflows")
    p.set_defaults(func=cmd_presets)

    args = parser.parse_args()
    args.func(args)


def _run_saved_workflow(args) -> None:
    wf = json.loads(Path(args.workflow).read_text(encoding="utf-8"))
    api = saved_to_api(wf)
    prompt_id = queue_workflow(args.comfyui_url, api)
    print(f"[video-pipeline] queued prompt_id={prompt_id}", file=sys.stderr)
    history = poll_history(args.comfyui_url, prompt_id, timeout_sec=args.timeout)
    videos = extract_output_videos(history)
    if not videos:
        raise SystemExit("no video outputs in history")
    final = sorted(videos, key=lambda v: v.get("filename", ""))[-1]
    result = {"ok": True, "prompt_id": prompt_id, "outputs": videos, "final": final}
    if args.copy_to:
        dest = download_video(args.comfyui_url, final, Path(args.copy_to))
        result["copied_to"] = str(dest)
        if args.manifest:
            _record_manifest(Path(args.manifest), dest, prompt="", width=None,
                             height=None, length=None, fps=None)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
