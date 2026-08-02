#!/usr/bin/env python3
"""Renders the StepStep launcher icon and writes every Android density.

The icon is generated rather than hand-drawn so it can be re-rendered after a
tweak instead of living on as an unreproducible PNG. It matches the family
look established by coffeeNetwork: a matte, low-poly object in near-white with
black accents, lit from the upper left, floating on a plain light background.

The renderer is a tiny flat-shaded 3D pipeline — a 2D sneaker silhouette
extruded along Z, projected isometrically, painter-sorted and lambert-shaded.
Flat shading (one colour per face) is what gives the faceted, clay-render feel
of the reference rather than a smooth gradient.

Usage:
    python3 tool/generate_icon.py
"""

from __future__ import annotations

import math
import os
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFilter

# --------------------------------------------------------------------- config

MASTER = 1024
SUPERSAMPLE = 3  # rendered large, then downscaled — cheap, effective AA

BACKGROUND = (244, 244, 246)
UPPER_COLOR = (238, 238, 240)
SOLE_COLOR = (34, 34, 38)
ACCENT_COLOR = (168, 255, 62)  # the brand lime — the filled part of the ring
TRACK_COLOR = (58, 60, 68)     # unfilled ring, same role as AppColors.stroke

# Matte plastic: mostly ambient so faces stay bright and close in value, with
# just enough diffuse to separate them. A low ambient would read as glossy.
AMBIENT = 0.74
DIFFUSE = 0.34
LIGHT = (-0.45, 0.78, 0.44)

YAW = math.radians(-19)
PITCH = math.radians(13)

# ------------------------------------------------------------------ geometry
#
# The object is a fitness tracker puck showing StepStep's own progress ring.
#
# A sneaker was the first instinct and was tried first, but a shoe is a doubly
# curved form: approximating it with an extruded side profile reads as a loaf
# at any icon size. A puck is a genuinely extruded shape, so this renderer
# draws it honestly — and putting the app's ring on its face ties the icon to
# what you actually see when you open StepStep.


def rounded_rect(size: float, radius: float, segments: int = 4):
    """Corner points of a rounded square spanning 0..size on both axes."""
    points = []
    corners = [
        (size - radius, size - radius, 0),
        (radius, size - radius, 90),
        (radius, radius, 180),
        (size - radius, radius, 270),
    ]
    for cx, cy, start in corners:
        for i in range(segments + 1):
            angle = math.radians(start + 90 * i / segments)
            points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


def arc_band(cx, cy, outer, inner, start_deg, sweep_deg, segments: int = 28):
    """Closed ring segment, outer edge forward then inner edge back."""
    outer_pts, inner_pts = [], []
    for i in range(segments + 1):
        angle = math.radians(start_deg + sweep_deg * i / segments)
        outer_pts.append((cx + outer * math.cos(angle), cy + outer * math.sin(angle)))
        inner_pts.append((cx + inner * math.cos(angle), cy + inner * math.sin(angle)))
    return outer_pts + list(reversed(inner_pts))


BODY = rounded_rect(100, 50, segments=8)  # a disc: survives any launcher mask
SCREEN = rounded_rect(100, 26)
SCREEN = [(20 + (x - 0) * 0.60, 20 + (y - 0) * 0.60) for x, y in SCREEN]

# Ring starts at 12 o'clock and runs clockwise, exactly like the app's.
RING_TRACK = arc_band(50, 50, 24, 17, -90, 360)
RING_FILL = arc_band(50, 50, 24, 17, -90, 252)

DEPTH = 26.0

# A puck has one thickness end to end, unlike the tapering the sneaker needed.
WIDTH_PROFILE = [(0, 1.0), (100, 1.0)]


@dataclass(frozen=True)
class Face:
    points: tuple[tuple[float, float, float], ...]
    color: tuple[int, int, int]


def normalize(v: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(sum(c * c for c in v)) or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def face_normal(points) -> tuple[float, float, float]:
    """Newell's method — stable for the near-planar quads extrusion makes."""
    nx = ny = nz = 0.0
    count = len(points)
    for i in range(count):
        cur, nxt = points[i], points[(i + 1) % count]
        nx += (cur[1] - nxt[1]) * (cur[2] + nxt[2])
        ny += (cur[2] - nxt[2]) * (cur[0] + nxt[0])
        nz += (cur[0] - nxt[0]) * (cur[1] + nxt[1])
    return normalize((nx, ny, nz))


def shade(color, normal) -> tuple[int, int, int]:
    light = normalize(LIGHT)
    lambert = max(0.0, sum(a * b for a, b in zip(normal, light)))
    factor = AMBIENT + DIFFUSE * lambert
    return tuple(min(255, int(c * factor)) for c in color)


# Half-width along the shoe's length, as (x, factor). A constant-depth
# extrusion reads as a slab; a real shoe is narrow at the heel, widest across
# the forefoot and tapers again at the toe, and that taper is most of what
# makes the silhouette recognisable from a three-quarter view.
WIDTH_PROFILE = [(0, 0.56), (18, 0.63), (38, 0.78), (60, 0.96), (78, 1.0), (95, 0.70)]


def width_at(x: float) -> float:
    for i in range(len(WIDTH_PROFILE) - 1):
        x0, w0 = WIDTH_PROFILE[i]
        x1, w1 = WIDTH_PROFILE[i + 1]
        if x0 <= x <= x1:
            t = (x - x0) / (x1 - x0) if x1 != x0 else 0.0
            return w0 + (w1 - w0) * t
    return WIDTH_PROFILE[-1][1] if x > WIDTH_PROFILE[-1][0] else WIDTH_PROFILE[0][1]


def extrude(profile, color, depth=DEPTH) -> tuple[list[Face], list[Face]]:
    """Turns a 2D outline into a front cap plus one quad per edge.

    Returns (sortable, front) — the front cap is handed back separately
    because it must always paint last. Depth sorting cannot decide that for
    us: the taper lifts the side quads near the widest point to a higher
    average z than parts of the cap, so they paint over it and tear a hole in
    the silhouette.
    """
    half = [depth / 2 * width_at(x) for x, _ in profile]
    front = tuple((x, y, half[i]) for i, (x, y) in enumerate(profile))
    back = tuple((x, y, -half[i]) for i, (x, y) in enumerate(profile))

    sides = []
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        sides.append(Face((front[i], front[j], back[j], back[i]), color))
    return [Face(tuple(reversed(back)), color)] + sides, [Face(front, color)]


def project(point) -> tuple[float, float, float]:
    """Yaw, then pitch, then orthographic. Returns screen x, y and depth."""
    x, y, z = point
    x, z = x * math.cos(YAW) - z * math.sin(YAW), x * math.sin(YAW) + z * math.cos(YAW)
    y, z = y * math.cos(PITCH) - z * math.sin(PITCH), y * math.sin(PITCH) + z * math.cos(PITCH)
    return x, -y, z


def decal(profile, color, depth=DEPTH, lift=0.4) -> list[Face]:
    """A flat marking lying on the visible face, with no thickness of its own.

    Extruding a marking instead would give it a top face — and on a long, thin
    shape seen from above that top face is larger than the marking itself,
    which reads as a slab bolted on rather than a detail printed on.

    The winding is corrected rather than assumed: these outlines come from
    several generators (hand-written point lists, rounded rects, arc bands)
    that do not agree on direction, and a backwards one is silently culled.
    """
    points = tuple(
        (x, y, depth / 2 * width_at(x) + lift) for x, y in profile
    )
    if face_normal(points)[2] < 0:
        points = tuple(reversed(points))
    return [Face(points, color)]


def render_object(size: int) -> Image.Image:
    # Drawn back-to-front as whole objects rather than as one globally sorted
    # face list: the sole and the upper occupy the same depth range, so a
    # single sort interleaves their faces and punches holes through the shoe.
    # The stacking is known and fixed, so encode it directly.
    body_sides, body_front = extrude(BODY, UPPER_COLOR)

    def by_depth(faces):
        return sorted(
            ((tuple(project(p) for p in f.points), f) for f in faces),
            key=lambda item: sum(p[2] for p in item[0]) / len(item[0]),
        )

    projected_layers = [
        by_depth(body_sides),
        by_depth(body_front),
        by_depth(decal(SCREEN, SOLE_COLOR)),
        by_depth(decal(RING_TRACK, TRACK_COLOR, lift=0.7)),
        by_depth(decal(RING_FILL, ACCENT_COLOR, lift=0.9)),
    ]

    every = [item for layer in projected_layers for item in layer]
    xs = [p[0] for pts, _ in every for p in pts]
    ys = [p[1] for pts, _ in every for p in pts]
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)

    margin = 0.15
    span = max(max_x - min_x, max_y - min_y)
    scale = size * (1 - 2 * margin) / span
    off_x = (size - (max_x - min_x) * scale) / 2 - min_x * scale
    off_y = (size - (max_y - min_y) * scale) / 2 - min_y * scale

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    for layer in projected_layers:
        for points, face in layer:
            normal = face_normal(face.points)
            # Back faces of a closed extrusion are never visible; skipping them
            # keeps the silhouette clean where quads meet at grazing angles.
            if normal[2] < -0.02:
                continue
            flat = [(p[0] * scale + off_x, p[1] * scale + off_y) for p in points]
            color = shade(face.color, normal)
            draw.polygon(flat, fill=color + (255,), outline=color + (255,))

    return canvas


def render_icon(size: int = MASTER) -> Image.Image:
    work = size * SUPERSAMPLE
    image = Image.new("RGB", (work, work), BACKGROUND)

    obj = render_object(work)

    # Contact shadow: the object's own silhouette, squashed, offset and blurred.
    alpha = obj.split()[3]
    shadow_src = Image.new("RGBA", obj.size, (0, 0, 0, 0))
    shadow_src.putalpha(alpha.point(lambda a: int(a * 0.30)))
    shadow = shadow_src.resize((work, int(work * 0.20)), Image.LANCZOS)
    shadow = shadow.filter(ImageFilter.GaussianBlur(work * 0.022))

    shadow_layer = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    shadow_layer.paste(shadow, (int(work * 0.01), int(work * 0.735)), shadow)

    image.paste(shadow_layer, (0, 0), shadow_layer)
    image.paste(obj, (0, 0), obj)

    return image.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------- output

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Adaptive icons crop to a circle and reserve the outer ~18% for parallax, so
# the foreground layer is rendered smaller inside a transparent square.
ADAPTIVE_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def write_all(root: str) -> None:
    res = os.path.join(root, "android", "app", "src", "main", "res")
    master = render_icon(MASTER)

    assets = os.path.join(root, ".github", "assets")
    os.makedirs(assets, exist_ok=True)
    master.save(os.path.join(assets, "icon.png"))
    master.resize((256, 256), Image.LANCZOS).save(
        os.path.join(assets, "icon-256.png")
    )

    for density, px in DENSITIES.items():
        target = os.path.join(res, f"mipmap-{density}")
        os.makedirs(target, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(target, "ic_launcher.png")
        )

    # Adaptive foreground: transparent, object scaled to the 66% safe zone.
    fg_master = render_object(MASTER)
    for density, px in ADAPTIVE_DENSITIES.items():
        target = os.path.join(res, f"mipmap-{density}")
        os.makedirs(target, exist_ok=True)
        layer = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        inner = int(px * 0.62)
        layer.paste(
            fg_master.resize((inner, inner), Image.LANCZOS),
            ((px - inner) // 2, (px - inner) // 2),
        )
        layer.save(os.path.join(target, "ic_launcher_foreground.png"))

    print(f"wrote icons under {res}")


if __name__ == "__main__":
    write_all(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
