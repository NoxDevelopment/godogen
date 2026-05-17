"""Skeleton Rig — emit stick-figure pose images for OpenPose-style
conditioning of img2img generation.

Subcommands
-----------
library    Print the built-in pose catalog (24 poses).
pose       Render one named pose to a PNG.
sequence   Render a sequence of named poses as a spritesheet, with
           optional linear joint interpolation between keyframes.
custom     Render from explicit joint coords in a JSON file.

Coordinate space: 0-100 horizontal, 0-150 vertical (relative). Renderer
scales to the requested --width / --height.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("ERROR: skeleton-rig requires Pillow (pip install pillow)", file=sys.stderr)
    sys.exit(2)


# ---------------------------------------------------------------------------
# Pose library — joint coords in 0-100 / 0-150 reference space.
#
# Joint keys (consistent across poses): head, neck, shoulder_l, shoulder_r,
# elbow_l, elbow_r, hand_l, hand_r, hip, hip_l, hip_r, knee_l, knee_r,
# foot_l, foot_r. Omitted joints skip their bone segments.
# ---------------------------------------------------------------------------

POSES: dict[str, dict[str, tuple[float, float]]] = {
    "idle": {
        "head": (50, 12), "neck": (50, 25),
        "shoulder_l": (42, 30), "shoulder_r": (58, 30),
        "elbow_l": (40, 50),    "elbow_r": (60, 50),
        "hand_l": (40, 70),     "hand_r": (60, 70),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
    "walk_a": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (42, 31), "shoulder_r": (58, 31),
        "elbow_l": (35, 50),    "elbow_r": (65, 50),
        "hand_l": (30, 70),     "hand_r": (70, 70),
        "hip": (50, 80),
        "hip_l": (45, 82),      "hip_r": (55, 82),
        "knee_l": (38, 100),    "knee_r": (62, 100),
        "foot_l": (32, 138),    "foot_r": (68, 138),
    },
    "walk_b": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (42, 31), "shoulder_r": (58, 31),
        "elbow_l": (65, 50),    "elbow_r": (35, 50),
        "hand_l": (70, 70),     "hand_r": (30, 70),
        "hip": (50, 80),
        "hip_l": (45, 82),      "hip_r": (55, 82),
        "knee_l": (62, 100),    "knee_r": (38, 100),
        "foot_l": (68, 138),    "foot_r": (32, 138),
    },
    "run_a": {
        "head": (50, 14), "neck": (50, 28),
        "shoulder_l": (42, 33), "shoulder_r": (58, 33),
        "elbow_l": (32, 48),    "elbow_r": (70, 48),
        "hand_l": (26, 60),     "hand_r": (76, 65),
        "hip": (50, 82),
        "hip_l": (45, 84),      "hip_r": (55, 84),
        "knee_l": (35, 95),     "knee_r": (62, 100),
        "foot_l": (28, 132),    "foot_r": (72, 138),
    },
    "run_b": {
        "head": (50, 14), "neck": (50, 28),
        "shoulder_l": (42, 33), "shoulder_r": (58, 33),
        "elbow_l": (70, 48),    "elbow_r": (32, 48),
        "hand_l": (76, 65),     "hand_r": (26, 60),
        "hip": (50, 82),
        "hip_l": (45, 84),      "hip_r": (55, 84),
        "knee_l": (62, 100),    "knee_r": (35, 95),
        "foot_l": (72, 138),    "foot_r": (28, 132),
    },
    "attack_swing": {
        "head": (45, 12), "neck": (47, 26),
        "shoulder_l": (40, 30), "shoulder_r": (54, 30),
        "elbow_l": (30, 25),    "elbow_r": (78, 22),
        "hand_l": (15, 35),     "hand_r": (90, 12),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (44, 105),    "knee_r": (56, 100),
        "foot_l": (40, 140),    "foot_r": (62, 138),
    },
    "attack_thrust": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (44, 31), "shoulder_r": (56, 31),
        "elbow_l": (32, 45),    "elbow_r": (72, 50),
        "hand_l": (18, 50),     "hand_r": (92, 50),
        "hip": (52, 80),
        "hip_l": (48, 82),      "hip_r": (56, 82),
        "knee_l": (42, 105),    "knee_r": (60, 102),
        "foot_l": (36, 140),    "foot_r": (66, 140),
    },
    "attack_overhead": {
        "head": (50, 14), "neck": (50, 28),
        "shoulder_l": (42, 32), "shoulder_r": (58, 32),
        "elbow_l": (40, 12),    "elbow_r": (60, 12),
        "hand_l": (45, -2),     "hand_r": (55, -2),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
    "hurt": {
        "head": (55, 16), "neck": (52, 28),
        "shoulder_l": (45, 32), "shoulder_r": (60, 32),
        "elbow_l": (38, 50),    "elbow_r": (70, 45),
        "hand_l": (30, 70),     "hand_r": (80, 40),
        "hip": (50, 82),
        "hip_l": (45, 84),      "hip_r": (55, 84),
        "knee_l": (40, 108),    "knee_r": (58, 110),
        "foot_l": (35, 145),    "foot_r": (62, 145),
    },
    "death_fallen": {
        "head": (75, 130), "neck": (65, 130),
        "shoulder_l": (60, 125), "shoulder_r": (60, 135),
        "elbow_l": (45, 120),    "elbow_r": (45, 140),
        "hand_l": (30, 118),     "hand_r": (30, 142),
        "hip": (40, 130),
        "hip_l": (40, 126),      "hip_r": (40, 134),
        "knee_l": (25, 120),     "knee_r": (25, 140),
        "foot_l": (15, 122),     "foot_r": (15, 138),
    },
    "jump_takeoff": {
        "head": (50, 18), "neck": (50, 32),
        "shoulder_l": (42, 36), "shoulder_r": (58, 36),
        "elbow_l": (38, 55),    "elbow_r": (62, 55),
        "hand_l": (35, 78),     "hand_r": (65, 78),
        "hip": (50, 85),
        "hip_l": (46, 87),      "hip_r": (54, 87),
        "knee_l": (43, 95),     "knee_r": (57, 95),
        "foot_l": (40, 130),    "foot_r": (60, 130),
    },
    "jump_peak": {
        "head": (50, 12), "neck": (50, 24),
        "shoulder_l": (42, 28), "shoulder_r": (58, 28),
        "elbow_l": (32, 18),    "elbow_r": (68, 18),
        "hand_l": (28, 5),      "hand_r": (72, 5),
        "hip": (50, 70),
        "hip_l": (46, 72),      "hip_r": (54, 72),
        "knee_l": (44, 85),     "knee_r": (56, 85),
        "foot_l": (42, 105),    "foot_r": (58, 105),
    },
    "jump_landing": {
        "head": (50, 22), "neck": (50, 36),
        "shoulder_l": (42, 40), "shoulder_r": (58, 40),
        "elbow_l": (36, 55),    "elbow_r": (64, 55),
        "hand_l": (32, 75),     "hand_r": (68, 75),
        "hip": (50, 90),
        "hip_l": (44, 92),      "hip_r": (56, 92),
        "knee_l": (38, 115),    "knee_r": (62, 115),
        "foot_l": (35, 140),    "foot_r": (65, 140),
    },
    "crouch": {
        "head": (50, 35), "neck": (50, 48),
        "shoulder_l": (42, 52), "shoulder_r": (58, 52),
        "elbow_l": (38, 70),    "elbow_r": (62, 70),
        "hand_l": (40, 90),     "hand_r": (60, 90),
        "hip": (50, 100),
        "hip_l": (44, 102),     "hip_r": (56, 102),
        "knee_l": (36, 122),    "knee_r": (64, 122),
        "foot_l": (35, 140),    "foot_r": (65, 140),
    },
    "cast": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (42, 30), "shoulder_r": (58, 30),
        "elbow_l": (32, 22),    "elbow_r": (68, 22),
        "hand_l": (30, 5),      "hand_r": (70, 5),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
    "block": {
        "head": (50, 14), "neck": (50, 28),
        "shoulder_l": (42, 32), "shoulder_r": (58, 32),
        "elbow_l": (50, 40),    "elbow_r": (50, 50),
        "hand_l": (60, 28),     "hand_r": (60, 38),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (44, 105),    "knee_r": (56, 105),
        "foot_l": (44, 140),    "foot_r": (56, 140),
    },
    "aim": {
        "head": (45, 12), "neck": (48, 26),
        "shoulder_l": (42, 30), "shoulder_r": (54, 30),
        "elbow_l": (50, 40),    "elbow_r": (62, 32),
        "hand_l": (60, 38),     "hand_r": (80, 28),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
    "climb": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (45, 30), "shoulder_r": (55, 30),
        "elbow_l": (42, 12),    "elbow_r": (58, 12),
        "hand_l": (40, -3),     "hand_r": (60, -3),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (42, 95),     "knee_r": (58, 105),
        "foot_l": (40, 120),    "foot_r": (60, 140),
    },
    "swim": {
        "head": (15, 60), "neck": (28, 65),
        "shoulder_l": (32, 60), "shoulder_r": (32, 70),
        "elbow_l": (18, 50),    "elbow_r": (48, 80),
        "hand_l": (5, 45),      "hand_r": (62, 85),
        "hip": (60, 68),
        "hip_l": (62, 64),      "hip_r": (62, 72),
        "knee_l": (78, 62),     "knee_r": (78, 74),
        "foot_l": (95, 60),     "foot_r": (95, 76),
    },
    "sit": {
        "head": (50, 30), "neck": (50, 44),
        "shoulder_l": (42, 48), "shoulder_r": (58, 48),
        "elbow_l": (38, 70),    "elbow_r": (62, 70),
        "hand_l": (40, 88),     "hand_r": (60, 88),
        "hip": (50, 90),
        "hip_l": (44, 92),      "hip_r": (56, 92),
        "knee_l": (30, 95),     "knee_r": (70, 95),
        "foot_l": (20, 130),    "foot_r": (80, 130),
    },
    "lay": {
        "head": (15, 80), "neck": (28, 80),
        "shoulder_l": (32, 75), "shoulder_r": (32, 85),
        "elbow_l": (45, 70),    "elbow_r": (45, 90),
        "hand_l": (55, 65),     "hand_r": (55, 95),
        "hip": (60, 80),
        "hip_l": (62, 77),      "hip_r": (62, 83),
        "knee_l": (78, 75),     "knee_r": (78, 85),
        "foot_l": (92, 73),     "foot_r": (92, 87),
    },
    "cheer": {
        "head": (50, 10), "neck": (50, 24),
        "shoulder_l": (42, 28), "shoulder_r": (58, 28),
        "elbow_l": (35, 10),    "elbow_r": (65, 10),
        "hand_l": (28, -6),     "hand_r": (72, -6),
        "hip": (50, 78),
        "hip_l": (46, 80),      "hip_r": (54, 80),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
    "wave": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (42, 30), "shoulder_r": (58, 30),
        "elbow_l": (40, 50),    "elbow_r": (62, 18),
        "hand_l": (40, 70),     "hand_r": (72, 5),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
    "point": {
        "head": (50, 12), "neck": (50, 26),
        "shoulder_l": (42, 30), "shoulder_r": (58, 30),
        "elbow_l": (40, 50),    "elbow_r": (70, 35),
        "hand_l": (40, 70),     "hand_r": (90, 32),
        "hip": (50, 80),
        "hip_l": (46, 82),      "hip_r": (54, 82),
        "knee_l": (46, 105),    "knee_r": (54, 105),
        "foot_l": (46, 140),    "foot_r": (54, 140),
    },
}

# Bone segments (pairs of joint names).
BONES = [
    ("head", "neck"),
    ("neck", "shoulder_l"), ("neck", "shoulder_r"),
    ("shoulder_l", "elbow_l"), ("shoulder_r", "elbow_r"),
    ("elbow_l", "hand_l"),    ("elbow_r", "hand_r"),
    ("neck", "hip"),
    ("hip", "hip_l"), ("hip", "hip_r"),
    ("hip_l", "knee_l"), ("hip_r", "knee_r"),
    ("knee_l", "foot_l"), ("knee_r", "foot_r"),
]

# OpenPose-flavored joint colors
JOINT_COLORS = {
    "head":       (255, 30,  30,  255),
    "neck":       (255, 100, 30,  255),
    "shoulder_l": (255, 200, 30,  255), "shoulder_r": (200, 255, 30, 255),
    "elbow_l":    (30,  255, 30,  255), "elbow_r":    (30, 255, 200, 255),
    "hand_l":     (30,  100, 255, 255), "hand_r":     (30, 30,  255, 255),
    "hip":        (200, 30,  255, 255),
    "hip_l":      (255, 30,  200, 255), "hip_r":      (255, 30, 100, 255),
    "knee_l":     (200, 100, 100, 255), "knee_r":     (100, 200, 100, 255),
    "foot_l":     (100, 100, 200, 255), "foot_r":     (200, 200, 100, 255),
}


# ---------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------

REF_W, REF_H = 100.0, 150.0


def render(joints: dict[str, tuple[float, float]], width: int, height: int,
           mono: bool = False, line_w: int = 6, joint_r: int = 8) -> Image.Image:
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def to_xy(p):
        x, y = p
        return (x / REF_W * width, y / REF_H * height)

    line_color = (255, 255, 255, 255) if mono else (220, 220, 220, 255)

    # Bones
    for a, b in BONES:
        if a not in joints or b not in joints:
            continue
        pa = to_xy(joints[a])
        pb = to_xy(joints[b])
        draw.line([pa, pb], fill=line_color, width=line_w)

    # Joints
    for name, p in joints.items():
        cx, cy = to_xy(p)
        color = (255, 255, 255, 255) if mono else JOINT_COLORS.get(name, line_color)
        draw.ellipse([cx - joint_r, cy - joint_r, cx + joint_r, cy + joint_r],
                     fill=color)
    return img


def interpolate(a: dict, b: dict, t: float) -> dict:
    """Linear joint interpolation between poses a and b (skip missing keys)."""
    out: dict[str, tuple[float, float]] = {}
    for k in set(a) | set(b):
        if k in a and k in b:
            ax, ay = a[k]
            bx, by = b[k]
            out[k] = (ax + (bx - ax) * t, ay + (by - ay) * t)
        elif k in a:
            out[k] = a[k]
        else:
            out[k] = b[k]
    return out


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_library(_args) -> None:
    rows = []
    for name, joints in POSES.items():
        rows.append({"name": name, "joints": len(joints),
                     "sample_joint": list(joints.items())[0] if joints else None})
    print(json.dumps({"count": len(POSES), "poses": rows}, indent=2))


def cmd_pose(args) -> None:
    if args.name not in POSES:
        raise SystemExit(f"unknown pose '{args.name}'. Available: {list(POSES)}")
    out = Path(args.output)
    img = render(POSES[args.name], args.width, args.height,
                 mono=args.mono, line_w=args.line_w, joint_r=args.joint_r)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(json.dumps({"ok": True, "wrote": str(out), "pose": args.name,
                      "size": [args.width, args.height], "mono": args.mono},
                     indent=2))


def cmd_sequence(args) -> None:
    names = [n.strip() for n in args.names.split(",") if n.strip()]
    if not names:
        raise SystemExit("--names empty")
    for n in names:
        if n not in POSES:
            raise SystemExit(f"unknown pose '{n}'")
    # Build the full frame list (keyframes + interpolated frames)
    inter = max(0, args.interpolate_frames)
    frames: list[dict] = [POSES[names[0]]]
    for i in range(1, len(names)):
        if inter > 0:
            for k in range(1, inter + 1):
                t = k / (inter + 1)
                frames.append(interpolate(POSES[names[i - 1]], POSES[names[i]], t))
        frames.append(POSES[names[i]])

    # Render and concatenate horizontally
    cell_imgs = [render(f, args.width, args.height,
                         mono=args.mono, line_w=args.line_w, joint_r=args.joint_r)
                 for f in frames]
    out = Image.new("RGBA", (args.width * len(cell_imgs), args.height), (0, 0, 0, 0))
    for i, im in enumerate(cell_imgs):
        out.paste(im, (args.width * i, 0), im)
    op = Path(args.output)
    op.parent.mkdir(parents=True, exist_ok=True)
    out.save(op)
    print(json.dumps({"ok": True, "wrote": str(op),
                      "names": names, "frame_count": len(cell_imgs),
                      "interpolated_between": inter,
                      "cell_size": [args.width, args.height]}, indent=2))


def cmd_custom(args) -> None:
    raw = json.loads(Path(args.joints_json).read_text(encoding="utf-8"))
    joints = {k: tuple(v) for k, v in raw.items()}
    img = render(joints, args.width, args.height,
                 mono=args.mono, line_w=args.line_w, joint_r=args.joint_r)
    op = Path(args.output)
    op.parent.mkdir(parents=True, exist_ok=True)
    img.save(op)
    print(json.dumps({"ok": True, "wrote": str(op),
                      "joints_count": len(joints)}, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="skeleton-rig: stick-figure pose images for OpenPose-style conditioning")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("library", help="List built-in poses")
    p.set_defaults(func=cmd_library)

    def _add_render_args(p):
        p.add_argument("--width", type=int, default=256)
        p.add_argument("--height", type=int, default=384)
        p.add_argument("--mono", action="store_true",
                       help="White-on-transparent only (default: OpenPose colors)")
        p.add_argument("--line-w", type=int, default=6, help="Bone line width")
        p.add_argument("--joint-r", type=int, default=8, help="Joint circle radius")
        p.add_argument("-o", "--output", required=True)

    p = sub.add_parser("pose", help="Render one named pose")
    p.add_argument("--name", required=True)
    _add_render_args(p)
    p.set_defaults(func=cmd_pose)

    p = sub.add_parser("sequence", help="Render a pose sequence as a horizontal spritesheet")
    p.add_argument("--names", required=True, help="Comma-separated pose names")
    p.add_argument("--interpolate-frames", type=int, default=0,
                   help="N interpolated frames between every consecutive pair")
    _add_render_args(p)
    p.set_defaults(func=cmd_sequence)

    p = sub.add_parser("custom", help="Render from explicit joints JSON")
    p.add_argument("--joints-json", required=True)
    _add_render_args(p)
    p.set_defaults(func=cmd_custom)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
