"""Shared geometry for the BARREL mark.

Shape: two circular caps (large on the left, small on the right) joined by
straight external-tangent edges top and bottom. Optionally rotated around
the shape's center by `tilt_deg` (positive = visual clockwise on a y-down
canvas, so the tip dips below horizontal).

Used by:
  - scripts/generate_barrel_icon.py   (primary app icon)
  - scripts/generate_alt_icon.py      (alt night icon)
  - scripts/compose_marketing.py      (wordmark mark)
  - BaseballStatTracker/Views/BarrelShape.swift (SwiftUI port)
"""
from __future__ import annotations

import math

# Defaults matched against the brand-guide reference:
# thick_height ≈ 16% of the bat's horizontal extent,
# thin_height  ≈ 4%   (so the tip cap is ~25% the diameter of the thick cap).
DEFAULT_THICK_H_FRAC = 0.16
DEFAULT_THIN_H_FRAC = 0.04
DEFAULT_TILT_DEG = 5.0


def build_barrel_polygon(
    center_x: float,
    center_y: float,
    shape_w: float,
    thick_h_frac: float = DEFAULT_THICK_H_FRAC,
    thin_h_frac: float = DEFAULT_THIN_H_FRAC,
    tilt_deg: float = DEFAULT_TILT_DEG,
    arc_steps: int = 36,
) -> list[tuple[float, float]]:
    """Return a closed polygon approximating the barrel shape.

    The polygon is suitable for PIL's `ImageDraw.polygon(..., width=STROKE)`
    to draw a stroked outline. Coordinates are in canvas space (y-down).
    """
    r_L = 0.5 * thick_h_frac * shape_w
    r_R = 0.5 * thin_h_frac * shape_w
    if r_R >= r_L:
        raise ValueError("thin cap must be smaller than thick cap")

    half_w = shape_w / 2.0
    # Left cap center and right cap center in local coords (bat centered at origin).
    cx_L = -half_w + r_L
    cx_R = +half_w - r_R
    d = cx_R - cx_L  # horizontal distance between cap centers
    if d <= 0:
        raise ValueError("shape too short for the given cap radii")

    # External-tangent tilt of the normal from each cap center to its tangent point.
    # With equal y-centers, the normals are parallel and tilted by arcsin((rL-rR)/d)
    # from vertical.
    phi = math.asin((r_L - r_R) / d)
    sin_p, cos_p = math.sin(phi), math.cos(phi)

    # Tangent points (local, y-down: upper side has negative y).
    tL_top = (cx_L + r_L * sin_p, -r_L * cos_p)
    tR_top = (cx_R + r_R * sin_p, -r_R * cos_p)
    tR_bot = (cx_R + r_R * sin_p, +r_R * cos_p)
    tL_bot = (cx_L + r_L * sin_p, +r_L * cos_p)

    pts: list[tuple[float, float]] = []

    # Start at top-left tangent point.
    pts.append(tL_top)
    # Straight top edge to top-right tangent point.
    pts.append(tR_top)

    # Arc around right cap from tR_top → tR_bot, sweeping through the right side
    # of the circle (the short way, through +x).
    a_top_R = math.atan2(tR_top[1], tR_top[0] - cx_R)  # negative (upper)
    a_bot_R = math.atan2(tR_bot[1], tR_bot[0] - cx_R)  # positive (lower)
    for i in range(1, arc_steps + 1):
        t = a_top_R + (a_bot_R - a_top_R) * (i / arc_steps)
        pts.append((cx_R + r_R * math.cos(t), r_R * math.sin(t)))

    # Straight bottom edge back to bottom-left tangent point.
    pts.append(tL_bot)

    # Arc around left cap from tL_bot → tL_top, sweeping through the left side
    # (the long way, through -x = angle π).
    a_bot_L = math.atan2(tL_bot[1], tL_bot[0] - cx_L)        # positive
    a_top_L = math.atan2(tL_top[1], tL_top[0] - cx_L)        # negative
    target = a_top_L + 2 * math.pi                           # unwrap so we sweep forward
    for i in range(1, arc_steps + 1):
        t = a_bot_L + (target - a_bot_L) * (i / arc_steps)
        pts.append((cx_L + r_L * math.cos(t), r_L * math.sin(t)))

    # Rotate each point by tilt_deg around local origin (shape center), then
    # translate to canvas coordinates. Positive tilt = visual CW on y-down screen.
    beta = math.radians(tilt_deg)
    cos_b, sin_b = math.cos(beta), math.sin(beta)
    final: list[tuple[float, float]] = []
    for (x, y) in pts:
        xr = x * cos_b - y * sin_b
        yr = x * sin_b + y * cos_b
        final.append((center_x + xr, center_y + yr))
    return final
