"""ComfyUI REST/WebSocket client for local image and animation generation.

Connects to ComfyUI at localhost:8188 (default). Uses the REST API to queue
workflows, poll for completion, and retrieve output images.

Based on the companion_ai_ml ComfyUI provider patterns.
"""

import json
import time
import uuid
from pathlib import Path

import requests

COMFYUI_URL = "http://localhost:8188"

# Default checkpoint — override via --checkpoint flag.
# This is the SD1.5/SDXL/Pony-style fallback for the legacy workflow builders
# (build_txt2img_workflow etc). The PRIMARY path is Z-Image-Turbo (see
# build_zit_txt2img_workflow below) which uses separate UNETLoader / CLIPLoader
# / VAELoader nodes.
DEFAULT_CHECKPOINT = "ponyRealism_v21MainVAE.safetensors"
DEFAULT_NEGATIVE = "worst quality, low quality, blurry, deformed, ugly, bad anatomy, watermark, text, signature"

# --- Z-Image-Turbo defaults (primary model on this rig) ---
# Filenames match the user's installed setup (extra_model_paths.yaml maps
# D:/AI/comfyui_github_models/{diffusion_models,text_encoders,vae}/ into the
# corresponding ComfyUI folders).
ZIT_UNET = "z-image-turbo-fp8-aio.safetensors"
ZIT_CLIP = "zImageTurbo_textEncoder.safetensors"
ZIT_CLIP_TYPE = "lumina2"  # Z-Image-Turbo's text encoder is loaded as lumina2
ZIT_VAE = "zImageTurbo_vae.safetensors"
ZIT_PIXEL_LORA = "pixel_art_style_z_image_turbo.safetensors"
# ZIT is "optimized for exactly 8 steps" per the apatero pixel-art guide.
# CFG 4-5 is the safe range; higher introduces artifacts. FluxGuidance is the
# embedded value (1.0 default), distinct from KSampler's classifier-free CFG.
ZIT_STEPS = 8
ZIT_CFG = 4.5
ZIT_SAMPLER = "euler"
ZIT_SCHEDULER = "simple"
ZIT_FLUX_GUIDANCE = 1.0
ZIT_NEGATIVE = "blurry, anti-aliased, smooth gradient, photo, 3D render, jpeg artifacts, deformed, watermark"


def is_available(base_url: str = COMFYUI_URL) -> bool:
    """Check if ComfyUI server is running."""
    try:
        r = requests.get(f"{base_url}/system_stats", timeout=3)
        return r.status_code == 200
    except (requests.ConnectionError, requests.Timeout):
        return False


def queue_prompt(workflow: dict, base_url: str = COMFYUI_URL) -> str:
    """Queue a generation job. Returns prompt_id."""
    client_id = str(uuid.uuid4())
    payload = {"prompt": workflow, "client_id": client_id}
    r = requests.post(f"{base_url}/prompt", json=payload)
    r.raise_for_status()
    return r.json()["prompt_id"]


def poll_completion(prompt_id: str, base_url: str = COMFYUI_URL,
                    timeout: int = 300, interval: float = 1.0) -> dict:
    """Poll until job completes. Returns history entry."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(f"{base_url}/history/{prompt_id}")
            r.raise_for_status()
            data = r.json()
            if prompt_id in data:
                entry = data[prompt_id]
                status = entry.get("status", {})
                if status.get("completed", False) or status.get("status_str") == "success":
                    return entry
                if status.get("status_str") == "error":
                    raise RuntimeError(f"ComfyUI generation failed: {status}")
        except requests.RequestException:
            pass
        time.sleep(interval)
    raise TimeoutError(f"ComfyUI generation timed out after {timeout}s")


def get_output_images(history_entry: dict) -> list[dict]:
    """Extract output image info from history entry."""
    images = []
    for node_id, node_output in history_entry.get("outputs", {}).items():
        for img in node_output.get("images", []):
            images.append(img)
    return images


def download_image(image_info: dict, output_path: Path,
                   base_url: str = COMFYUI_URL) -> Path:
    """Download a generated image from ComfyUI output folder."""
    filename = image_info["filename"]
    subfolder = image_info.get("subfolder", "")
    img_type = image_info.get("type", "output")
    params = {"filename": filename, "subfolder": subfolder, "type": img_type}
    r = requests.get(f"{base_url}/view", params=params)
    r.raise_for_status()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(r.content)
    return output_path


def upload_image(image_path: Path, base_url: str = COMFYUI_URL) -> str:
    """Upload an image to ComfyUI. Returns filename for workflow reference."""
    with open(image_path, "rb") as f:
        files = {"image": (image_path.name, f, "image/png")}
        r = requests.post(f"{base_url}/upload/image", files=files)
    r.raise_for_status()
    return r.json()["name"]


def list_checkpoints(base_url: str = COMFYUI_URL) -> list[str]:
    """List available checkpoint models."""
    try:
        r = requests.get(f"{base_url}/object_info/CheckpointLoaderSimple")
        r.raise_for_status()
        data = r.json()
        return data["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"][0]
    except Exception:
        return []


def list_loras(base_url: str = COMFYUI_URL) -> list[str]:
    """List available LoRA models."""
    try:
        r = requests.get(f"{base_url}/object_info/LoraLoader")
        r.raise_for_status()
        data = r.json()
        return data["LoraLoader"]["input"]["required"]["lora_name"][0]
    except Exception:
        return []


def build_txt2img_workflow(
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    width: int = 1024,
    height: int = 1024,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith",
) -> dict:
    """Build a standard txt2img ComfyUI workflow."""
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": checkpoint}
        },
        "2": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": prompt, "clip": ["1", 1]}
        },
        "3": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative, "clip": ["1", 1]}
        },
        "4": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": width, "height": height, "batch_size": 1}
        },
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": sampler,
                "scheduler": scheduler,
                "denoise": 1.0,
                "model": ["1", 0],
                "positive": ["2", 0],
                "negative": ["3", 0],
                "latent_image": ["4", 0],
            }
        },
        "6": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["5", 0], "vae": ["1", 2]}
        },
        "7": {
            "class_type": "SaveImage",
            "inputs": {"images": ["6", 0], "filename_prefix": filename_prefix}
        },
    }


def build_txt2img_with_lora_workflow(
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    lora_name: str = "",
    lora_strength: float = 0.8,
    width: int = 1024,
    height: int = 1024,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith",
) -> dict:
    """Build txt2img workflow with optional LoRA loader."""
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    workflow = {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": checkpoint}
        },
    }

    # Insert LoRA loader if specified
    model_ref = ["1", 0]
    clip_ref = ["1", 1]
    if lora_name:
        workflow["10"] = {
            "class_type": "LoraLoader",
            "inputs": {
                "lora_name": lora_name,
                "strength_model": lora_strength,
                "strength_clip": lora_strength,
                "model": ["1", 0],
                "clip": ["1", 1],
            }
        }
        model_ref = ["10", 0]
        clip_ref = ["10", 1]

    workflow.update({
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": clip_ref}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": clip_ref}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": 1.0,
                "model": model_ref, "positive": ["2", 0], "negative": ["3", 0],
                "latent_image": ["4", 0],
            }
        },
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": filename_prefix}},
    })
    return workflow


def build_img2img_workflow(
    image_filename: str,
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    denoise: float = 0.6,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith_i2i",
) -> dict:
    """Build img2img workflow — loads reference image, encodes, denoises."""
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint}},
        "2": {"class_type": "LoadImage", "inputs": {"image": image_filename}},
        "3": {"class_type": "VAEEncode", "inputs": {"pixels": ["2", 0], "vae": ["1", 2]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["1", 1]}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": ["1", 1]}},
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": denoise,
                "model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0],
                "latent_image": ["3", 0],
            }
        },
        "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage", "inputs": {"images": ["7", 0], "filename_prefix": filename_prefix}},
    }


def build_img2img_with_lora_workflow(
    image_filename: str,
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    lora_name: str = "",
    lora_strength: float = 0.8,
    denoise: float = 0.6,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith_i2i",
) -> dict:
    """Build img2img workflow with optional LoRA loader."""
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    workflow = {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint}},
        "2": {"class_type": "LoadImage", "inputs": {"image": image_filename}},
    }

    model_ref = ["1", 0]
    clip_ref = ["1", 1]
    if lora_name:
        workflow["10"] = {
            "class_type": "LoraLoader",
            "inputs": {
                "lora_name": lora_name,
                "strength_model": lora_strength,
                "strength_clip": lora_strength,
                "model": ["1", 0],
                "clip": ["1", 1],
            }
        }
        model_ref = ["10", 0]
        clip_ref = ["10", 1]

    workflow.update({
        "3": {"class_type": "VAEEncode", "inputs": {"pixels": ["2", 0], "vae": ["1", 2]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": clip_ref}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": clip_ref}},
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": denoise,
                "model": model_ref, "positive": ["4", 0], "negative": ["5", 0],
                "latent_image": ["3", 0],
            }
        },
        "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage", "inputs": {"images": ["7", 0], "filename_prefix": filename_prefix}},
    })
    return workflow


def build_inpaint_workflow(
    image_filename: str,
    mask_filename: str,
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    denoise: float = 0.8,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith_inpaint",
) -> dict:
    """Build inpainting workflow — edits masked region of an image."""
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint}},
        "2": {"class_type": "LoadImage", "inputs": {"image": image_filename}},
        "3": {"class_type": "LoadImage", "inputs": {"image": mask_filename}},
        "4": {"class_type": "VAEEncodeForInpaint", "inputs": {
            "pixels": ["2", 0], "vae": ["1", 2], "mask": ["3", 0], "grow_mask_by": 6,
        }},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["1", 1]}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": ["1", 1]}},
        "7": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": denoise,
                "model": ["1", 0], "positive": ["5", 0], "negative": ["6", 0],
                "latent_image": ["4", 0],
            }
        },
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["1", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": filename_prefix}},
    }


def build_upscale_workflow(
    image_filename: str,
    upscale_model: str = "4x-UltraSharp.pth",
    filename_prefix: str = "godotsmith_upscale",
) -> dict:
    """Build upscale workflow using an upscale model node."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": image_filename}},
        "2": {"class_type": "UpscaleModelLoader", "inputs": {"model_name": upscale_model}},
        "3": {"class_type": "ImageUpscaleWithModel", "inputs": {
            "upscale_model": ["2", 0], "image": ["1", 0],
        }},
        "4": {"class_type": "SaveImage", "inputs": {"images": ["3", 0], "filename_prefix": filename_prefix}},
    }


def build_upscale_simple_workflow(
    image_filename: str,
    width: int = 256,
    height: int = 256,
    method: str = "nearest-exact",
    filename_prefix: str = "godotsmith_upscale",
) -> dict:
    """Build simple resize/upscale workflow using nearest-neighbor (pixel-perfect)."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": image_filename}},
        "2": {"class_type": "ImageScale", "inputs": {
            "image": ["1", 0], "width": width, "height": height,
            "upscale_method": method, "crop": "disabled",
        }},
        "3": {"class_type": "SaveImage", "inputs": {"images": ["2", 0], "filename_prefix": filename_prefix}},
    }


def build_batch_frames_workflow(
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    lora_name: str = "",
    lora_strength: float = 0.8,
    width: int = 512,
    height: int = 512,
    batch_size: int = 4,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith_batch",
) -> dict:
    """Build workflow that generates multiple frames in one batch (for animation sheets)."""
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    workflow = {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint}},
    }

    model_ref = ["1", 0]
    clip_ref = ["1", 1]
    if lora_name:
        workflow["10"] = {
            "class_type": "LoraLoader",
            "inputs": {
                "lora_name": lora_name,
                "strength_model": lora_strength,
                "strength_clip": lora_strength,
                "model": ["1", 0],
                "clip": ["1", 1],
            }
        }
        model_ref = ["10", 0]
        clip_ref = ["10", 1]

    workflow.update({
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": clip_ref}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": clip_ref}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {
            "width": width, "height": height, "batch_size": batch_size,
        }},
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": 1.0,
                "model": model_ref, "positive": ["2", 0], "negative": ["3", 0],
                "latent_image": ["4", 0],
            }
        },
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": filename_prefix}},
    })
    return workflow


def build_tiling_workflow(
    prompt: str,
    negative: str = DEFAULT_NEGATIVE,
    checkpoint: str = DEFAULT_CHECKPOINT,
    lora_name: str = "",
    lora_strength: float = 0.8,
    width: int = 512,
    height: int = 512,
    steps: int = 25,
    cfg: float = 7.0,
    sampler: str = "dpmpp_2m",
    scheduler: str = "karras",
    seed: int | None = None,
    filename_prefix: str = "godotsmith_tile",
) -> dict:
    """Build seamless tiling workflow.
    Uses CircularVAEDecode if available, otherwise standard with tiling prompt hints.
    The prompt should include 'seamless tileable pattern' for best results.
    """
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    workflow = {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint}},
    }

    model_ref = ["1", 0]
    clip_ref = ["1", 1]
    if lora_name:
        workflow["10"] = {
            "class_type": "LoraLoader",
            "inputs": {
                "lora_name": lora_name,
                "strength_model": lora_strength,
                "strength_clip": lora_strength,
                "model": ["1", 0],
                "clip": ["1", 1],
            }
        }
        model_ref = ["10", 0]
        clip_ref = ["10", 1]

    # Prepend tiling hint to prompt
    tile_prompt = f"seamless tileable pattern, repeating texture, {prompt}"

    workflow.update({
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": tile_prompt, "clip": clip_ref}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": negative + ", seam, border, edge artifacts", "clip": clip_ref}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": 1.0,
                "model": model_ref, "positive": ["2", 0], "negative": ["3", 0],
                "latent_image": ["4", 0],
            }
        },
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": filename_prefix}},
    })
    return workflow


def list_upscale_models(base_url: str = COMFYUI_URL) -> list[str]:
    """List available upscale models."""
    try:
        r = requests.get(f"{base_url}/object_info/UpscaleModelLoader")
        r.raise_for_status()
        data = r.json()
        return data["UpscaleModelLoader"]["input"]["required"]["model_name"][0]
    except Exception:
        return []


def list_samplers(base_url: str = COMFYUI_URL) -> list[str]:
    """List available samplers."""
    try:
        r = requests.get(f"{base_url}/object_info/KSampler")
        r.raise_for_status()
        data = r.json()
        return data["KSampler"]["input"]["required"]["sampler_name"][0]
    except Exception:
        return ["euler", "euler_ancestral", "heun", "dpm_2", "dpm_2_ancestral",
                "lms", "dpm_fast", "dpm_adaptive", "dpmpp_2s_ancestral",
                "dpmpp_sde", "dpmpp_sde_gpu", "dpmpp_2m", "dpmpp_2m_sde",
                "dpmpp_2m_sde_gpu", "dpmpp_3m_sde", "dpmpp_3m_sde_gpu",
                "ddpm", "lcm", "ddim", "uni_pc", "uni_pc_bh2"]


def list_schedulers(base_url: str = COMFYUI_URL) -> list[str]:
    """List available schedulers."""
    try:
        r = requests.get(f"{base_url}/object_info/KSampler")
        r.raise_for_status()
        data = r.json()
        return data["KSampler"]["input"]["required"]["scheduler"][0]
    except Exception:
        return ["normal", "karras", "exponential", "sgm_uniform", "simple",
                "ddim_uniform", "beta"]


# Resolution presets matching common game asset sizes
RESOLUTION_PRESETS = {
    "512": (512, 512),
    "1K": (1024, 1024),
    "2K": (2048, 2048),
    "4K": (4096, 4096),
}

ASPECT_RATIOS = {
    "1:1": (1, 1),
    "16:9": (16, 9),
    "9:16": (9, 16),
    "3:2": (3, 2),
    "2:3": (2, 3),
    "4:3": (4, 3),
    "3:4": (3, 4),
    "21:9": (21, 9),
}


def resolve_dimensions(size: str, aspect_ratio: str) -> tuple[int, int]:
    """Convert size preset + aspect ratio to pixel dimensions."""
    base = RESOLUTION_PRESETS.get(size, (1024, 1024))[0]
    ar = ASPECT_RATIOS.get(aspect_ratio, (1, 1))
    w_ratio, h_ratio = ar
    max_dim = max(w_ratio, h_ratio)
    w = int(base * w_ratio / max_dim)
    h = int(base * h_ratio / max_dim)
    # Round to nearest 8 (required by most diffusion models)
    w = (w // 8) * 8
    h = (h // 8) * 8
    return w, h


def generate_image(
    prompt: str,
    output_path: Path,
    size: str = "1K",
    aspect_ratio: str = "1:1",
    checkpoint: str = DEFAULT_CHECKPOINT,
    negative: str = DEFAULT_NEGATIVE,
    steps: int = 25,
    cfg: float = 7.0,
    base_url: str = COMFYUI_URL,
) -> Path:
    """High-level: generate an image and save to output_path."""
    w, h = resolve_dimensions(size, aspect_ratio)
    workflow = build_txt2img_workflow(
        prompt=prompt,
        negative=negative,
        checkpoint=checkpoint,
        width=w, height=h,
        steps=steps, cfg=cfg,
    )
    prompt_id = queue_prompt(workflow, base_url)
    result = poll_completion(prompt_id, base_url)
    images = get_output_images(result)
    if not images:
        raise RuntimeError("ComfyUI returned no images")
    return download_image(images[0], output_path, base_url)


# ---------------------------------------------------------------------------
# Z-Image-Turbo workflows (primary path on this rig)
# ---------------------------------------------------------------------------
#
# Z-Image-Turbo is a Flux-class model: separate UNET / CLIP / VAE loaders,
# ModelSamplingFlux for shift conditioning, FluxGuidance for embedded
# guidance, and short-step sampling (8 steps @ cfg 4.5 in the apatero guide).
# Use these builders for any new generation; the older build_*_workflow
# functions above are retained for SD1.5/SDXL/Pony fallback.


def is_zit_checkpoint(name: str) -> bool:
    """Heuristic: looks like a Z-Image-Turbo UNET filename."""
    n = (name or "").lower()
    return "z_image" in n or "z-image" in n or "zimage" in n


def _normalize_loras(loras, lora_name: str, lora_strength: float) -> list:
    """Resolve the LoRA-list argument across the new and legacy call shapes.

    `loras` is the canonical input — a list of objects or dicts with
    name / strength_model / strength_clip. The legacy `lora_name`/
    `lora_strength` kwargs remain accepted; if they're passed and `loras`
    is None, they're folded into a single-element list.
    """
    if loras is not None:
        if lora_name:
            raise ValueError(
                "Cannot pass both `loras=` and `lora_name=` — pick one."
            )
        return list(loras)
    if lora_name:
        return [{
            "name": lora_name,
            "strength_model": lora_strength,
            "strength_clip": lora_strength,
        }]
    return []


def _lora_field(entry, key: str, default=None):
    """Read a field from a LoraEntry dataclass or a plain dict."""
    if isinstance(entry, dict):
        return entry.get(key, default)
    return getattr(entry, key, default)


def _chain_loras(workflow: dict, model_ref: list, clip_ref: list,
                 loras: list, id_prefix: str = "lora_") -> tuple[list, list]:
    """Append a LoraLoader chain to the workflow, in order.

    Each LoraLoader's MODEL+CLIP outputs feed the next; the final outputs
    become the model_ref/clip_ref returned to downstream nodes (KSampler,
    CLIPTextEncode). Mutates `workflow`. Returns (final_model_ref, final_clip_ref).
    """
    for idx, entry in enumerate(loras):
        node_id = f"{id_prefix}{idx}"
        workflow[node_id] = {
            "class_type": "LoraLoader",
            "inputs": {
                "lora_name": _lora_field(entry, "name"),
                "strength_model": _lora_field(entry, "strength_model", 0.8),
                "strength_clip": _lora_field(entry, "strength_clip", 0.8),
                "model": model_ref,
                "clip": clip_ref,
            },
        }
        model_ref = [node_id, 0]
        clip_ref = [node_id, 1]
    return model_ref, clip_ref


def build_zit_txt2img_workflow(
    prompt: str,
    negative: str = ZIT_NEGATIVE,
    unet: str = ZIT_UNET,
    clip: str = ZIT_CLIP,
    vae: str = ZIT_VAE,
    lora_name: str = "",
    lora_strength: float = 0.8,
    loras: list | None = None,
    width: int = 1024,
    height: int = 1024,
    steps: int = ZIT_STEPS,
    cfg: float = ZIT_CFG,
    sampler: str = ZIT_SAMPLER,
    scheduler: str = ZIT_SCHEDULER,
    flux_guidance: float = ZIT_FLUX_GUIDANCE,
    model_shift_max: float = 2.0,
    model_shift_base: float = 0.0,
    seed: int | None = None,
    filename_prefix: str = "godogen_zit",
) -> dict:
    """Z-Image-Turbo txt2img with optional LoRA stack. Mirrors the node graph
    used by face_detailer.json's generation half: UNETLoader →
    ModelSamplingFlux → (LoraLoader chain) → KSampler with separate CLIP/VAE.

    Pass `loras=[...]` for multi-LoRA stacking (each element is a LoraEntry or
    {"name", "strength_model", "strength_clip"} dict). The legacy
    `lora_name`/`lora_strength` single-LoRA path remains supported.
    """
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    lora_chain = _normalize_loras(loras, lora_name, lora_strength)

    workflow: dict = {
        "1": {
            "class_type": "UNETLoader",
            "inputs": {"unet_name": unet, "weight_dtype": "default"},
        },
        "2": {
            "class_type": "CLIPLoader",
            "inputs": {"clip_name": clip, "type": ZIT_CLIP_TYPE, "device": "default"},
        },
        "3": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": vae},
        },
        "4": {
            "class_type": "ModelSamplingFlux",
            "inputs": {
                "max_shift": model_shift_max,
                "base_shift": model_shift_base,
                "width": width,
                "height": height,
                "model": ["1", 0],
            },
        },
    }

    model_ref, clip_ref = _chain_loras(
        workflow, ["4", 0], ["2", 0], lora_chain, id_prefix="lora_"
    )

    workflow.update({
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": prompt, "clip": clip_ref},
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative, "clip": clip_ref},
        },
        "8": {
            "class_type": "FluxGuidance",
            "inputs": {"guidance": flux_guidance, "conditioning": ["6", 0]},
        },
        "9": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": width, "height": height, "batch_size": 1},
        },
        "10": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": sampler,
                "scheduler": scheduler,
                "denoise": 1.0,
                "model": model_ref,
                "positive": ["8", 0],
                "negative": ["7", 0],
                "latent_image": ["9", 0],
            },
        },
        "11": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["10", 0], "vae": ["3", 0]},
        },
        "12": {
            "class_type": "SaveImage",
            "inputs": {"images": ["11", 0], "filename_prefix": filename_prefix},
        },
    })
    return workflow


def build_zit_img2img_workflow(
    image_filename: str,
    prompt: str,
    negative: str = ZIT_NEGATIVE,
    unet: str = ZIT_UNET,
    clip: str = ZIT_CLIP,
    vae: str = ZIT_VAE,
    lora_name: str = "",
    lora_strength: float = 0.8,
    loras: list | None = None,
    denoise: float = 0.6,
    steps: int = ZIT_STEPS,
    cfg: float = ZIT_CFG,
    sampler: str = ZIT_SAMPLER,
    scheduler: str = ZIT_SCHEDULER,
    flux_guidance: float = ZIT_FLUX_GUIDANCE,
    model_shift_max: float = 2.0,
    model_shift_base: float = 0.0,
    seed: int | None = None,
    filename_prefix: str = "godogen_zit_i2i",
) -> dict:
    """Z-Image-Turbo img2img — encodes the reference image as the latent
    starting point. Lower `denoise` keeps closer to the reference; higher
    allows more creative deviation. Use for anchoring characters/portraits
    to reference.png style.

    Pass `loras=[...]` for multi-LoRA stacking; legacy `lora_name`/
    `lora_strength` single-LoRA path also supported.
    """
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    lora_chain = _normalize_loras(loras, lora_name, lora_strength)

    workflow: dict = {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": unet, "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": clip, "type": ZIT_CLIP_TYPE, "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
        "4": {"class_type": "LoadImage", "inputs": {"image": image_filename}},
        "5": {"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "6": {
            "class_type": "ModelSamplingFlux",
            "inputs": {
                "max_shift": model_shift_max,
                "base_shift": model_shift_base,
                "width": 1024,
                "height": 1024,
                "model": ["1", 0],
            },
        },
    }

    model_ref, clip_ref = _chain_loras(
        workflow, ["6", 0], ["2", 0], lora_chain, id_prefix="lora_"
    )

    workflow.update({
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": clip_ref}},
        "9": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": clip_ref}},
        "10": {"class_type": "FluxGuidance", "inputs": {"guidance": flux_guidance, "conditioning": ["8", 0]}},
        "11": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": sampler,
                "scheduler": scheduler,
                "denoise": denoise,
                "model": model_ref,
                "positive": ["10", 0],
                "negative": ["9", 0],
                "latent_image": ["5", 0],
            },
        },
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": filename_prefix}},
    })
    return workflow


def build_zit_batch_frames_workflow(
    prompt: str,
    negative: str = ZIT_NEGATIVE,
    unet: str = ZIT_UNET,
    clip: str = ZIT_CLIP,
    vae: str = ZIT_VAE,
    lora_name: str = "",
    lora_strength: float = 0.8,
    loras: list | None = None,
    width: int = 512,
    height: int = 512,
    batch_size: int = 4,
    steps: int = ZIT_STEPS,
    cfg: float = ZIT_CFG,
    sampler: str = ZIT_SAMPLER,
    scheduler: str = ZIT_SCHEDULER,
    flux_guidance: float = ZIT_FLUX_GUIDANCE,
    model_shift_max: float = 2.0,
    model_shift_base: float = 0.0,
    seed: int | None = None,
    filename_prefix: str = "godogen_zit_batch",
) -> dict:
    """Z-Image-Turbo batch generation — same KSampler call yields N latents
    at once → consistent style across animation frames. Used by the
    spritesheet command on ZIT.

    Pass `loras=[...]` for multi-LoRA stacking; legacy `lora_name`/
    `lora_strength` single-LoRA path also supported.
    """
    import random
    if seed is None:
        seed = random.randint(0, 2**32 - 1)

    lora_chain = _normalize_loras(loras, lora_name, lora_strength)

    workflow: dict = {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": unet, "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": clip, "type": ZIT_CLIP_TYPE, "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
        "4": {
            "class_type": "ModelSamplingFlux",
            "inputs": {
                "max_shift": model_shift_max,
                "base_shift": model_shift_base,
                "width": width,
                "height": height,
                "model": ["1", 0],
            },
        },
    }

    model_ref, clip_ref = _chain_loras(
        workflow, ["4", 0], ["2", 0], lora_chain, id_prefix="lora_"
    )

    workflow.update({
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": clip_ref}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": clip_ref}},
        "8": {"class_type": "FluxGuidance", "inputs": {"guidance": flux_guidance, "conditioning": ["6", 0]}},
        "9": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": width, "height": height, "batch_size": batch_size},
        },
        "10": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": scheduler, "denoise": 1.0,
                "model": model_ref, "positive": ["8", 0], "negative": ["7", 0],
                "latent_image": ["9", 0],
            },
        },
        "11": {"class_type": "VAEDecode", "inputs": {"samples": ["10", 0], "vae": ["3", 0]}},
        "12": {"class_type": "SaveImage", "inputs": {"images": ["11", 0], "filename_prefix": filename_prefix}},
    })
    return workflow
