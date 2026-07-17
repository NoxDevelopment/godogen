"""Local Hunyuan3D image→GLB backend (ComfyUI-backed) — the free, on-device,
style-anchored alternative to the Tripo3D cloud API.

Mirrors tripo3d.image_to_glb so mesh_gen.py can pick a backend at runtime. Talks
to a running ComfyUI (default 127.0.0.1:8188) with the kijai ComfyUI-Hunyuan3DWrapper
node + the validated graphs from ml-workbench (hunyuan3d-image-to-mesh /
hunyuan3d-textured-mesh):

  - shape mode (default): LoadImage -> Hy3DModelLoader -> GenerateMesh -> VAEDecode
    -> PostprocessMesh -> ExportMesh. No CUDA build needed. ~1-2 min on a 3090.
  - textured mode: adds UV-unwrap -> delight -> multiview render -> paint sample ->
    bake -> inpaint -> apply, exporting a PBR-textured .glb. Needs the compiled
    custom_rasterizer + differentiable_renderer extensions. ~4 min.

ComfyUI's /history doesn't surface the exported mesh path, so we write to a unique
filename_prefix and copy the newest matching .glb out of ComfyUI's output dir
(COMFYUI_OUTPUT_DIR, default the localllm_poc install). Cost: $0 (local GPU).
"""
from __future__ import annotations

import json
import os
import shutil
import time
import urllib.request
import urllib.error
from pathlib import Path

DEFAULT_HOST = os.environ.get("COMFYUI_HOST", "127.0.0.1:8188")
DEFAULT_OUTPUT_DIR = os.environ.get(
    "COMFYUI_OUTPUT_DIR", r"C:/code/ai/localllm_poc/ComfyUI/output"
)
SHAPE_MODEL = os.environ.get(
    "HUNYUAN3D_SHAPE_MODEL", "hy3dgen\\hunyuan3d-dit-v2-0-fp16.safetensors"
)


def _http_json(url: str, payload: dict | None = None, timeout: int = 60) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers)
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def is_available(host: str = DEFAULT_HOST, timeout: int = 4) -> bool:
    """True if a ComfyUI with the Hunyuan3D shape node is reachable."""
    try:
        info = _http_json(f"http://{host}/object_info/Hy3DGenerateMesh", timeout=timeout)
        return "Hy3DGenerateMesh" in info
    except Exception:
        return False


def _upload_image(image_path: Path, host: str) -> str:
    """Upload an image to ComfyUI's input dir; return the server-side filename."""
    boundary = "----godogenHy3D"
    body = bytearray()
    body += f"--{boundary}\r\n".encode()
    body += (
        f'Content-Disposition: form-data; name="image"; filename="{image_path.name}"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode()
    body += image_path.read_bytes()
    body += f"\r\n--{boundary}\r\n".encode()
    body += 'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n'.encode()
    body += f"--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        f"http://{host}/upload/image",
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    resp = json.loads(urllib.request.urlopen(req, timeout=60).read())
    name = resp["name"]
    if resp.get("subfolder"):
        name = f"{resp['subfolder']}/{name}"
    return name


def _shape_graph(image_name: str, prefix: str, max_faces: int, steps: int,
                 octree: int) -> dict:
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "2": {"class_type": "Hy3DModelLoader",
              "inputs": {"model": SHAPE_MODEL, "attention_mode": "sdpa"}},
        "3": {"class_type": "Hy3DGenerateMesh",
              "inputs": {"pipeline": ["2", 0], "image": ["1", 0], "mask": ["1", 1],
                         "guidance_scale": 5.5, "steps": steps, "seed": 42,
                         "scheduler": "FlowMatchEulerDiscreteScheduler",
                         "force_offload": True}},
        "4": {"class_type": "Hy3DVAEDecode",
              "inputs": {"vae": ["2", 1], "latents": ["3", 0], "box_v": 1.01,
                         "octree_resolution": octree, "num_chunks": 8000,
                         "mc_level": 0.0, "mc_algo": "mc", "enable_flash_vdm": True,
                         "force_offload": True}},
        "5": {"class_type": "Hy3DPostprocessMesh",
              "inputs": {"trimesh": ["4", 0], "remove_floaters": True,
                         "remove_degenerate_faces": True, "reduce_faces": True,
                         "max_facenum": max_faces, "smooth_normals": False}},
        "6": {"class_type": "Hy3DExportMesh",
              "inputs": {"trimesh": ["5", 0], "filename_prefix": prefix,
                         "file_format": "glb", "save_file": True}},
    }


def _textured_graph(image_name: str, prefix: str, max_faces: int, steps: int,
                    octree: int, texture_size: int, paint_steps: int) -> dict:
    g = _shape_graph(image_name, prefix, max_faces, steps, octree)
    # replace the export (node 6) with the paint chain + textured export
    del g["6"]
    g.update({
        "6": {"class_type": "Hy3DMeshUVWrap", "inputs": {"trimesh": ["5", 0]}},
        "7": {"class_type": "DownloadAndLoadHy3DDelightModel",
              "inputs": {"model": "hunyuan3d-delight-v2-0"}},
        "8": {"class_type": "Hy3DDelightImage",
              "inputs": {"delight_pipe": ["7", 0], "image": ["1", 0], "steps": 50,
                         "width": 512, "height": 512, "cfg_image": 1.0, "seed": 0}},
        "9": {"class_type": "Hy3DRenderMultiView",
              "inputs": {"trimesh": ["6", 0], "render_size": 1024,
                         "texture_size": texture_size}},
        "10": {"class_type": "DownloadAndLoadHy3DPaintModel",
               "inputs": {"model": "hunyuan3d-paint-v2-0"}},
        "11": {"class_type": "Hy3DSampleMultiView",
               "inputs": {"pipeline": ["10", 0], "ref_image": ["8", 0],
                          "normal_maps": ["9", 0], "position_maps": ["9", 1],
                          "view_size": 512, "steps": paint_steps, "seed": 1024}},
        "12": {"class_type": "Hy3DBakeFromMultiview",
               "inputs": {"images": ["11", 0], "renderer": ["9", 2]}},
        "13": {"class_type": "Hy3DMeshVerticeInpaintTexture",
               "inputs": {"texture": ["12", 0], "mask": ["12", 1], "renderer": ["12", 2]}},
        "14": {"class_type": "Hy3DApplyTexture",
               "inputs": {"texture": ["13", 0], "renderer": ["13", 2]}},
        "15": {"class_type": "Hy3DExportMesh",
               "inputs": {"trimesh": ["14", 0], "filename_prefix": prefix,
                          "file_format": "glb", "save_file": True}},
    })
    return g


def _poll(host: str, prompt_id: str, timeout: int) -> None:
    start = time.time()
    while time.time() - start < timeout:
        time.sleep(4)
        hist = _http_json(f"http://{host}/history/{prompt_id}", timeout=30)
        if prompt_id in hist:
            status = hist[prompt_id].get("status", {})
            s = status.get("status_str")
            if status.get("completed") or s == "success":
                return
            if s == "error":
                msgs = status.get("messages", [])
                raise RuntimeError(f"ComfyUI reported error: {msgs[-3:]}")
    raise TimeoutError(f"Hunyuan3D generation timed out after {timeout}s")


def image_to_glb(
    image_path: Path,
    output_path: Path,
    textured: bool = False,
    max_faces: int = 40000,
    shape_steps: int = 30,
    octree_resolution: int = 384,
    texture_size: int = 2048,
    paint_steps: int = 25,
    host: str = DEFAULT_HOST,
    output_dir: str | None = None,
    timeout: int = 600,
) -> Path:
    """Convert an image to a GLB via a LOCAL Hunyuan3D (ComfyUI). Cost: $0.

    Args mirror tripo3d.image_to_glb where they overlap (max_faces ~ face_limit,
    textured ~ pbr). Returns the path to the copied GLB.
    """
    image_path = Path(image_path)
    output_path = Path(output_path)
    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")
    out_dir = Path(output_dir or DEFAULT_OUTPUT_DIR)

    # unique prefix (no random/time-of-day dependence beyond the mono clock is fine here)
    uid = f"godogen3d/hy3d_{int(time.time() * 1000) % 10_000_000}"
    server_name = _upload_image(image_path, host)

    if textured:
        graph = _textured_graph(server_name, uid, max_faces, shape_steps,
                                octree_resolution, texture_size, paint_steps)
    else:
        graph = _shape_graph(server_name, uid, max_faces, shape_steps, octree_resolution)

    try:
        resp = _http_json(f"http://{host}/prompt", {"prompt": graph})
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"ComfyUI rejected the graph: {e.read().decode()[:600]}")
    prompt_id = resp["prompt_id"]
    _poll(host, prompt_id, timeout)

    # ComfyUI writes <out_dir>/<uid>_00001_.glb ; grab the newest match.
    search_dir = out_dir / Path(uid).parent
    stem = Path(uid).name
    candidates = sorted(
        search_dir.glob(f"{stem}_*.glb"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    if not candidates:
        raise FileNotFoundError(
            f"Generation succeeded but no GLB found in {search_dir} (prefix {stem}). "
            "Set COMFYUI_OUTPUT_DIR if ComfyUI writes elsewhere."
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidates[0], output_path)
    return output_path
