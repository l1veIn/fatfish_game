"""Game icon from a character portrait (repo root):
    python pipeline/make_icon.py <portrait.png> <cx> <cy> <r> [<tight_r>]
A medallion: deep-sea navy disc, silver-white double ring, the face cropped from the portrait
around (cx, cy) with radius r. Small sizes (<= 48 px) use the tighter radius (default 0.7 r)
so the face still reads in a taskbar. Flat light-grey/white backdrops are swapped for a glow.
Outputs game/assets/ui/icon.png (512 px, window / web icon) and game/assets/ui/icon.ico
(16-256 px, the Windows exe icon).
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
import sys

CONCEPT = sys.argv[1] if len(sys.argv) > 4 else ""
UI = os.path.join(ROOT, "game", "assets", "ui")
GOLD = (226, 238, 250)       # ring colours: maid white-silver over the deep sea
GOLD_DARK = (96, 128, 170)
NAVY = (14, 34, 72)


def medallion(size: int, center: tuple, radius: int) -> Image.Image:
    """Render at 4x and scale down for smooth edges."""
    s = size * 4
    src = Image.open(CONCEPT).convert("RGBA")
    cx, cy = center
    face = src.crop((cx - radius, cy - radius, cx + radius, cy + radius)).resize((s, s), Image.LANCZOS)
    # swap the concept sheet's flat grey backdrop for a navy radial glow
    probe = face.convert("RGB")
    sentinel = (255, 0, 255)
    # seeds along the left/right edges (the grey also sits under the sword blade), only on
    # light low-saturation pixels so the robe and hair are never filled
    for y in range(0, s, max(1, s // 24)):
        for x in (0, s - 1):
            px = probe.getpixel((x, y))
            if px != sentinel and min(px) > 165 and max(px) - min(px) < 25:
                ImageDraw.floodfill(probe, (x, y), sentinel, thresh=34)
    bg = Image.frombytes("L", (s, s), bytes(255 if px == sentinel else 0 for px in probe.get_flattened_data()))
    # grow the backdrop a little over the anti-aliased fringe so no pale halo is left
    bg = bg.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(s * 0.004))
    glow = Image.new("RGBA", (s, s), NAVY + (255,))
    gd = ImageDraw.Draw(glow)
    for i in range(40, 0, -1):          # lighter blue toward the centre-top
        r = s * 0.62 * i / 40
        c = tuple(int(NAVY[k] + (v - NAVY[k]) * (1 - i / 40)) for k, v in enumerate((70, 96, 150)))
        gd.ellipse((s / 2 - r, s * 0.42 - r, s / 2 + r, s * 0.42 + r), fill=c + (255,))
    face = Image.composite(glow, face, bg)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    ring = int(s * 0.055)
    d.ellipse((0, 0, s - 1, s - 1), fill=GOLD_DARK)                 # outer rim (shadow side)
    d.ellipse((ring // 3, ring // 3, s - 1 - ring // 2, s - 1 - ring // 2), fill=GOLD)
    inner = (ring, ring, s - 1 - ring, s - 1 - ring)
    d.ellipse(inner, fill=NAVY)
    mask = Image.new("L", (s, s), 0)
    pad = ring + int(s * 0.02)
    ImageDraw.Draw(mask).ellipse((pad, pad, s - 1 - pad, s - 1 - pad), fill=255)
    out.paste(face, (0, 0), mask)
    # thin inner gold line and a soft highlight on the upper-left of the rim
    d = ImageDraw.Draw(out)
    d.ellipse((pad - ring // 4, pad - ring // 4, s - 1 - pad + ring // 4, s - 1 - pad + ring // 4), outline=GOLD, width=max(2, ring // 4))
    hl = Image.new("L", (s, s), 0)
    ImageDraw.Draw(hl).arc((ring // 3, ring // 3, s - 1 - ring // 3, s - 1 - ring // 3), 200, 280, fill=200, width=ring // 2)
    out.paste((255, 244, 210, 255), (0, 0), hl.filter(ImageFilter.GaussianBlur(s * 0.004)))
    return out.resize((size, size), Image.LANCZOS)


def main() -> None:
    if not CONCEPT:
        sys.exit(__doc__)
    cx, cy, r = (int(v) for v in sys.argv[2:5])
    big = (cx, cy, r)
    tight = (cx, cy, int(sys.argv[5]) if len(sys.argv) > 5 else int(r * 0.7))
    medallion(512, big[:2], big[2]).save(os.path.join(UI, "icon.png"))
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [medallion(n, (tight if n <= 48 else big)[:2], (tight if n <= 48 else big)[2]) for n in sizes]
    frames[-1].save(os.path.join(UI, "icon.ico"), sizes=[(n, n) for n in sizes], append_images=frames[:-1])
    sheet = Image.new("RGBA", (sum(sizes) + 10 * len(sizes) + 522, 512), (60, 60, 60, 255))
    x = 0
    for im in [Image.open(os.path.join(UI, "icon.png"))] + frames[::-1]:
        sheet.alpha_composite(im, (x, 0))
        x += im.width + 10
    sheet.save(os.path.join(ROOT, "art_src", "icon_preview.png"))
    print("icon.png + icon.ico written")


if __name__ == "__main__":
    main()
