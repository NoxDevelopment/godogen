"""ZIT style registry — named style keys → LoRA stack + prompt scaffolding.

Each StyleSpec captures everything the dispatcher needs to apply a style:
the LoRA file(s) to load (with strength), trigger words to inject after the
asset-type prefix, a descriptor appended after the subject, and any negative
addons. The base_model field gates compatibility — `zimage` styles run on the
ZIT workflow; `sdxl` styles fall through to the SDXL workflow path instead.

Strengths follow the apatero guide range (0.6–1.0); 0.8 is the safe default.
LoRA stacking is supported (chain in the order listed in `loras`); per the
apatero guide, complementary style LoRAs combine well, but realistic LoRAs
cancel pixel-art ones — keep stacks within a single aesthetic family.

Trigger sources, in order of authority used to populate this registry:
  1. ss_tag_frequency in safetensors metadata (most authoritative).
  2. ss_output_name when it reads as a word/phrase (the trainer's chosen handle).
  3. CivitAI page text for the model.
  4. Educated inference from filename + URL slug (flagged in `notes`).

Ambiguous entries are flagged in `notes`; the smoketest is the source of
truth for whether a given trigger actually activates the LoRA.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class LoraEntry:
    """A single LoRA in a stack."""
    name: str
    strength_model: float = 0.8
    strength_clip: float = 0.8


@dataclass(frozen=True)
class StyleSpec:
    """A named style. Composes 1+ LoRAs with prompt scaffolding."""
    key: str
    name: str
    loras: tuple[LoraEntry, ...]
    triggers: tuple[str, ...] = ()
    descriptor: str = ""
    negative_addons: str = ""
    base_model: str = "zimage"
    notes: str = ""


# Re-exported by `get_style("default")` and used as the asset_gen.py fallback
# when no --style flag is passed. Matches the historical behavior before the
# styles registry existed.
DEFAULT_STYLE_KEY = "default-pixel"


STYLES: dict[str, StyleSpec] = {
    "default-pixel": StyleSpec(
        key="default-pixel",
        name="Default pixel art (ZIT baseline)",
        loras=(LoraEntry("pixel_art_style_z_image_turbo.safetensors", 0.8, 0.8),),
        triggers=("Pixel art style.",),
        descriptor="",
        notes="Original baseline LoRA from the working smoketest. Always-on; reliable default.",
    ),

    # ------------------------------------------------------------------
    # Retro era / platform styles
    # ------------------------------------------------------------------
    "zx-spectrum": StyleSpec(
        key="zx-spectrum",
        name="ZX Spectrum 8-bit",
        loras=(LoraEntry("ZIT-ZXSpectrum.safetensors", 0.8, 0.8),),
        triggers=("ZX Spectrum",),
        descriptor="ZX Spectrum 8-bit micro graphics, attribute clash, two-color cells, bright pixel palette",
        notes="UK 1980s micro. Trigger from ss_tag_frequency.",
    ),
    "pc98": StyleSpec(
        key="pc98",
        name="PC-98 anime/VGA",
        loras=(LoraEntry("pc98-zit_000002400.safetensors", 0.8, 0.8),),
        triggers=("pc98 style",),
        descriptor="PC-98 anime aesthetic, dithered VGA, cyan/magenta palette, 16-color limit",
        notes="Japanese 80s/90s PC-98 graphics. Trigger inferred from output_name; validate via smoketest.",
    ),
    "16bit-game": StyleSpec(
        key="16bit-game",
        name="16-bit console era",
        loras=(LoraEntry("16bitgame.safetensors", 0.8, 0.8),),
        triggers=("16bitgame",),
        descriptor="16-bit era game graphics, SNES/Genesis aesthetic, mode-7 capable composition",
        notes="Always-on style; trigger matches output_name.",
    ),

    # ------------------------------------------------------------------
    # Pixel-art density / hardness variants
    # ------------------------------------------------------------------
    "pixel-hard": StyleSpec(
        key="pixel-hard",
        name="Hard-edge pixel art",
        loras=(LoraEntry("z-image-pixel-hard_000002400.safetensors", 0.8, 0.8),),
        triggers=("hard edge pixel art",),
        descriptor="hard-edged pixel art, sharp 1px outlines, no anti-aliasing, crisp edges",
        notes="From civitai 681332/hard-edge-pixel-art.",
    ),
    "soft-pixel-8x": StyleSpec(
        key="soft-pixel-8x",
        name="Soft pixel art (8x dataset)",
        loras=(LoraEntry("z-image-soft-pixel-8x-v1_000002200.safetensors", 0.8, 0.8),),
        triggers=("soft pixel art",),
        descriptor="soft pixel art, gentle shading, smooth gradients within pixel grid",
        notes="8x-upscaled dataset variant of soft-pixel-art (civitai 685038).",
    ),
    "soft-pixel-512": StyleSpec(
        key="soft-pixel-512",
        name="Soft pixel art (512px dataset)",
        loras=(LoraEntry("soft512_000002250.safetensors", 0.8, 0.8),),
        triggers=("soft pixel art",),
        descriptor="soft pixel art, smooth shading, painterly within pixel grid",
        notes="512px companion to soft-pixel-8x. Stacks well with it at 0.5/0.5.",
    ),
    "pixel-6x6": StyleSpec(
        key="pixel-6x6",
        name="Pixel 6x6 grid",
        loras=(LoraEntry("pixel_6x6.safetensors", 1.0, 1.0),),
        triggers=("pixel_6x6",),
        descriptor="6x6 pixel grid alignment, deliberate pixel-perfect output",
        notes="Trained on 6x6-upscaled dataset. Civitai 2224440. "
              "Strength bumped to 1.0 — at 0.8 the 6x6 grid effect was washed out.",
    ),
    "pixelart-perfect": StyleSpec(
        key="pixelart-perfect",
        name="Pixel art perfect",
        loras=(LoraEntry("PixelArt_Perfect_ZIT_M_V1_epoch_2.safetensors", 1.0, 1.0),),
        triggers=(),
        descriptor="perfect pixel art, sharp pixel grid, clean palette",
        notes="Always-on style; ss_tag_frequency was empty. Civitai 2481158. "
              "Strength bumped to 1.0 — at 0.8 the style was indistinguishable from default-pixel.",
    ),
    "pixel-pix-ce": StyleSpec(
        key="pixel-pix-ce",
        name="Pixel Pix (CreativeEdge)",
        loras=(LoraEntry("PixelPix01_CE_ZIMGT_AIT4k.safetensors", 0.8, 0.8),),
        triggers=("pixelated",),
        descriptor="pixelated style, generic pixel-art aesthetic",
        notes="Author CreativeEdge. Trigger 'pixelated' inferred from civitai 773599 description.",
    ),
    "elusarca-detailed": StyleSpec(
        key="elusarca-detailed",
        name="Elusarca detailed pixel art",
        loras=(LoraEntry("elusarca-pixel-art.safetensors", 1.0, 1.0),),
        triggers=(),
        descriptor="detailed pixel art, rich color depth, intricate per-pixel work",
        notes="Always-on. Civitai 2190363/elusarcas-detailed-pixel-art-lora-for-z-image. "
              "Strength bumped to 1.0 — at 0.8 the style was barely distinguishable from default.",
    ),

    # ------------------------------------------------------------------
    # Author / collection styles
    # ------------------------------------------------------------------
    "aziib-pixel": StyleSpec(
        key="aziib-pixel",
        name="Aziib pixel style",
        loras=(LoraEntry("aziib_pixel_style_zit.safetensors", 0.8, 0.8),),
        triggers=("aziib_pixel_style",),
        descriptor="aziib-style pixel art",
        notes="Trigger from ss_tag_frequency. Civitai 672328.",
    ),
    "tartarus-pixel": StyleSpec(
        key="tartarus-pixel",
        name="Tartarus pixel (shrekman collection)",
        loras=(LoraEntry("TartarusPixel.safetensors", 0.8, 0.8),),
        triggers=("TARPIXV1", "pixel art"),
        descriptor="dark fantasy pixel art, gothic palette, brooding atmosphere",
        notes="From the z-image-turbo-styles-collection-by-shrekman bundle (civitai 2214000). "
              "Triggers TARPIXV1 + 'pixel art' per the collection page.",
    ),
    "skyhill": StyleSpec(
        key="skyhill",
        name="Skyhill (concept)",
        loras=(LoraEntry("skyhill_zimagedeturbo.safetensors", 0.5, 0.5),),
        triggers=("skyhill",),
        descriptor="skyhill aesthetic",
        notes="⚠ Concept/identity LoRA — at full strength it overrides the user's subject "
              "(smoketest produced a sky scene rather than a knight). Strength reduced to 0.5 "
              "to color the output without dominating it. Civitai 1747432. Trigger from ss_tag_frequency.",
    ),
    "desimulate": StyleSpec(
        key="desimulate",
        name="Desimulate style",
        loras=(LoraEntry("Desimulate_LoRA_Z_Image_Turbo.safetensors", 0.8, 0.8),),
        triggers=("Desimulate",),
        descriptor="desimulate style aesthetic",
        notes="Civitai 2210184. Trigger from ss_tag_frequency.",
    ),
    "carrtoon-cute": StyleSpec(
        key="carrtoon-cute",
        name="Cute pixel girl (carrtoon)",
        loras=(LoraEntry("carrtoon_8b.safetensors", 0.5, 0.5),),
        triggers=("cute pixel girl",),
        descriptor="cute mini pixel game character, chibi proportions",
        notes="⚠ Concept/identity LoRA — biased toward feminine chibi forms; at 0.8 it forces the "
              "subject into a cute girl regardless of prompt (knight prompt yielded a cute girl with "
              "blue hair). Strength reduced to 0.5. Training name carrtoon_8b. Likely maps to "
              "pixel-cute-gril-style (civitai 261183).",
    ),
    "trippy-pixel": StyleSpec(
        key="trippy-pixel",
        name="Trippy psychedelic pixel art",
        loras=(LoraEntry("Trippy_pixel_art_zimage_turbo_512.safetensors", 0.8, 0.8),),
        triggers=("trippy pixel art",),
        descriptor="psychedelic pixel art, surreal colors, kaleidoscope distortions",
        notes="512px training. Civitai 691071.",
    ),
    "kof-portrait": StyleSpec(
        key="kof-portrait",
        name="King of Fighters victory portrait",
        loras=(LoraEntry("k0f_p0rt@it_zimage_512.safetensors", 0.8, 0.8),),
        triggers=("kof victory portrait",),
        descriptor="King of Fighters character victory portrait, vivid neogeo palette, dramatic pose",
        notes="Filename has @ char (file system fine, ComfyUI passes through). 512px training. "
              "Civitai 1050935.",
    ),
    "experimental-pixel": StyleSpec(
        key="experimental-pixel",
        name="Experimental pixel art (Luisap)",
        loras=(LoraEntry("zimage_experimental_pixelart.safetensors", 0.8, 0.8),),
        triggers=("experimental pixel art",),
        descriptor="experimental pixel art aesthetic, refined detail",
        notes="Likely Luisap pixel-art refiner (civitai 10706). ss_output_name 'zimage_experimental_ou'.",
    ),

    # ------------------------------------------------------------------
    # Body/concept LoRA — not a pixel-art style proper, included because the
    # user batch-downloaded it. Use only when the asset explicitly calls for it.
    # ------------------------------------------------------------------
    "sues-body": StyleSpec(
        key="sues-body",
        name="Sue's body (NSFW body shape)",
        loras=(LoraEntry("SuesZBodyBikiniFLUXLora.safetensors", 0.5, 0.5),),
        triggers=("sue body",),
        descriptor="defined body shape, swimwear",
        negative_addons="",
        notes="⚠ Concept/body-shape LoRA — NOT a pixel-art style. NSFW-leaning training set; "
              "at 0.8 it overrides the subject (knight prompt yielded a bikini figure on red bg). "
              "Strength reduced to 0.5. Filename says FLUX but metadata confirms z_image base. "
              "Stack with a real pixel-art style at full strength if you actually want pixel-art "
              "body shaping. Civitai 2253443.",
    ),

    # ------------------------------------------------------------------
    # Cross-base styles (must NOT load via ZIT workflow)
    # ------------------------------------------------------------------
    "new-pixel-core-ill": StyleSpec(
        key="new-pixel-core-ill",
        name="New Pixel Core (Illustrious / SDXL)",
        loras=(LoraEntry("new_pixel_core-ILL.safetensors", 0.8, 0.8),),
        triggers=("newpixelcore", "pixel", "many details"),
        descriptor="detailed pixel-art character",
        base_model="sdxl",
        notes="⚠ SDXL/Illustrious base — INCOMPATIBLE with ZIT workflow. "
              "Dispatcher must route to SDXL path. Top training tags include "
              "1girl/solo/looking at viewer/breasts — character-default biases. "
              "Civitai 2114925.",
    ),
}


def list_styles(base_model: str | None = None) -> list[str]:
    """Return all style keys, optionally filtered by base model."""
    if base_model is None:
        return list(STYLES.keys())
    return [k for k, s in STYLES.items() if s.base_model == base_model]


def get_style(key: str) -> StyleSpec:
    """Return the StyleSpec for a key. Raises KeyError on unknown key."""
    if key not in STYLES:
        raise KeyError(
            f"Unknown style key: {key!r}. "
            f"Known keys: {sorted(STYLES.keys())}"
        )
    return STYLES[key]


def style_trigger_string(spec: StyleSpec) -> str:
    """Render the style's triggers as a comma-joined string for prompt insertion."""
    return ", ".join(spec.triggers)


def style_lora_files(spec: StyleSpec) -> list[str]:
    """Return just the LoRA filenames for the style (for logging/debug)."""
    return [le.name for le in spec.loras]
