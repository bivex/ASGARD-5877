#!/usr/bin/env python3
"""Generate the GitHub social preview banner for ASGARD-5877 (1280x640).

GitHub picks up .github/assets/social-preview.jpg for the repository page and
for social cards.  Run: python3 scripts/make_social_preview.py
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1280, 640
BG_TOP = (10, 14, 28)
BG_BOTTOM = (18, 26, 48)
ACCENT = (94, 234, 212)
ACCENT_DIM = (56, 130, 246)
TEXT = (236, 241, 250)
MUTED = (150, 165, 190)

img = Image.new("RGB", (W, H), BG_TOP)
draw = ImageDraw.Draw(img)

# Vertical gradient background.
for y in range(H):
    t = y / (H - 1)
    draw.line(
        [(0, y), (W, y)],
        fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)),
    )

# Faint grid, like a memory map.
grid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gdraw = ImageDraw.Draw(grid)
for x in range(0, W, 40):
    gdraw.line([(x, 0), (x, H)], fill=(120, 160, 220, 16))
for y in range(0, H, 40):
    gdraw.line([(0, y), (W, y)], fill=(120, 160, 220, 16))
img = Image.alpha_composite(img.convert("RGBA"), grid).convert("RGB")
draw = ImageDraw.Draw(img)

# Accent bar on the left.
draw.rectangle([(0, 0), (10, H)], fill=ACCENT)

# Glow behind the title.
glow = Image.new("RGB", (W, H), (0, 0, 0))
g = ImageDraw.Draw(glow)
g.ellipse([-200, 90, 900, 430], fill=(20, 90, 110))
glow = glow.filter(ImageFilter.GaussianBlur(120))
img = Image.blend(img, Image.blend(img, glow, 0.0), 0.0)
img = Image.composite(Image.blend(img, glow, 0.35), img, Image.new("L", (W, H), 60))
draw = ImageDraw.Draw(img)


def font(path, size):
    return ImageFont.truetype(path, size)


mono = "/System/Library/Fonts/Menlo.ttc"
sans = "/System/Library/Fonts/SFNS.ttf"
bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

draw.text((84, 150), "ASGARD-5877", font=font(bold, 104), fill=TEXT)
draw.text((88, 282), "virtualization-based code protector", font=font(sans, 40), fill=ACCENT)
draw.text(
    (88, 336),
    "OCaml toolchain  ->  hardened C++20 VM runtime",
    font=font(mono, 26),
    fill=MUTED,
)

# ISA chips.
chips = ["x86-64", "ARM64", "RISC-V", "CFF", "MBA", "F*"]
x = 88
for chip in chips:
    f = font(mono, 22)
    w = draw.textlength(chip, font=f) + 32
    draw.rounded_rectangle([x, 412, x + w, 456], radius=10, outline=(70, 95, 140), width=2)
    draw.text((x + 16, 423), chip, font=f, fill=(198, 214, 238))
    x += w + 14

draw.text(
    (88, 520),
    "Business Source License 1.1  -  free for open source, Apache-2.0 after three years",
    font=font(sans, 24),
    fill=MUTED,
)

import os

out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".github", "assets", "social-preview.jpg")
os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out, "JPEG", quality=92, optimize=True)
print("written", out, img.size)
