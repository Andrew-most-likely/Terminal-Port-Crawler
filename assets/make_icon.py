"""
Generates assets/tpc.ico for the TPC (Terminal Port Crawler) build.

Design: a dark rounded-square "terminal" tile with a radar/scan glyph
(concentric rings + sweep + target dot) in terminal-green, since TPC is
a port scanner. Rendered at high resolution then downsampled into the
standard Windows icon sizes so it stays legible down to 16x16.

Run with: python assets/make_icon.py
"""
from PIL import Image, ImageDraw
import math

SIZE = 1024
bg_dark = (13, 17, 23, 255)       # near-black terminal background
bg_edge = (22, 27, 34, 255)       # subtle edge shade
accent = (57, 255, 140, 255)      # terminal green
accent_dim = (57, 255, 140, 110)  # dimmer green for outer ring
white = (235, 245, 240, 255)

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Rounded-square background tile
pad = 24
radius = 190
draw.rounded_rectangle(
    [pad, pad, SIZE - pad, SIZE - pad],
    radius=radius,
    fill=bg_dark,
    outline=bg_edge,
    width=6,
)

cx, cy = SIZE // 2, SIZE // 2 + 10

# Radar rings (scan sweep motif)
for r, w, col in [
    (330, 14, accent_dim),
    (230, 16, accent),
    (130, 16, accent_dim),
]:
    bbox = [cx - r, cy - r, cx + r, cy + r]
    draw.ellipse(bbox, outline=col, width=w)

# Sweep wedge from center
sweep_r = 330
start_deg = -95
end_deg = -25
draw.pieslice(
    [cx - sweep_r, cy - sweep_r, cx + sweep_r, cy + sweep_r],
    start=start_deg,
    end=end_deg,
    fill=(57, 255, 140, 60),
)

# Center target dot
dot_r = 34
draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=accent)

# A distant "blip" caught by the sweep
blip_r = 22
bx, by = cx + 205, cy - 205
draw.ellipse([bx - blip_r, by - blip_r, bx + blip_r, by + blip_r], fill=white)

# Crosshair ticks (top/bottom/left/right) for a technical "scanner" feel
tick_len = 40
tick_w = 12
for angle_deg in (0, 90, 180, 270):
    a = math.radians(angle_deg)
    r1, r2 = 355, 355 + tick_len
    x1, y1 = cx + r1 * math.cos(a), cy + r1 * math.sin(a)
    x2, y2 = cx + r2 * math.cos(a), cy + r2 * math.sin(a)
    draw.line([x1, y1, x2, y2], fill=accent, width=tick_w)

sizes = [16, 24, 32, 48, 64, 128, 256]
img.save("assets/tpc.ico", sizes=[(s, s) for s in sizes])
img.resize((256, 256), Image.LANCZOS).save("assets/tpc.png")
print("Wrote assets/tpc.ico and assets/tpc.png")
