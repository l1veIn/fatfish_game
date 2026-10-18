"""Turn the generated canteen art (art_src/assets/*_0.png, see gen_assets.sh) into game assets
(repo root):  python pipeline/prep_canteen.py [--preview]
- transparent sprites are cropped to their content and scaled to their in-game size
- the canteen wall is cover-scaled to 1920x1080, darkened and desaturated so the food pops
- writes game/assets/canteen/*.png and game/data/canteen_art.json (box grid areas)
--preview also writes art_src/assets/_box_grid_check.png with the measured grid drawn on
each lunch box, to check that food will sit in the compartments.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "art_src", "assets")
OUT = os.path.join(ROOT, "game", "assets", "canteen")
DATA = os.path.join(ROOT, "game", "data", "canteen_art.json")

# name -> ("height"|"width"|"long", px)
SPRITES = {
    "auntie_normal": ("height", 300), "auntie_shaky": ("height", 300), "auntie_busy": ("height", 300),
    "auntie_panic": ("height", 300), "auntie_happy": ("height", 300),
    "food_ball": ("long", 128), "food_bowl": ("long", 128), "food_leg": ("long", 128),
    "food_gold": ("long", 128), "food_veg": ("long", 128), "food_dump": ("long", 128),
    "ladle": ("long", 110), "tentacle": ("height", 40),
    "counter": ("width", 1420), "table": ("width", 480),
    "box_2": ("width", 360), "box_3": ("width", 420), "box_4": ("width", 480),
}

ROUND3 = {"sign_plate": ("width", 240), "warm_box": ("width", 190), "ticket": ("width", 200),
          "ticket_gold": ("width", 200), "stamp": ("width", 110), "pin": ("width", 40)}
# polish pass (gen_assets.sh polish): effect sprites, the two table trays, an arrow
POLISH = {"fx_silver": ("long", 256), "fx_gold": ("long", 256), "fx_burst": ("long", 320),
          "fx_steam": ("long", 128), "fx_star": ("long", 96), "tray_empty": ("width", 300),
          "tray_full": ("width", 300), "ui_arrow": ("width", 96)}
# the HUD kit's blank pieces (docs/hud_design.md)
HUD_UI = {"ui_badge": ("width", 240), "ui_bubble": ("width", 380), "ui_chalkboard": ("width", 440),
          "ui_paper": ("width", 320), "ui_banner": ("width", 820), "ui_tray": ("width", 340)}
# opaque full-screen pictures (the skill tree board, the recipe book), cover-scaled to 1920x1080
FULLSCREEN = ["cork_bg", "recipe_page"]

# The compartment grid inside each lunch box image, as fractions of the cropped image:
# (left, top, right, bottom) of the area covered by the n x n compartments, measured from the
# generated art (run with --preview and adjust if a box is regenerated).
BOX_GRID = {
    "box_2": [0.07, 0.04, 0.93, 0.80],
    "box_3": [0.07, 0.04, 0.93, 0.80],
    "box_4": None,   # computed in make_box_4()
}
# gpt-image-2.5 kept drawing the "4x4" box with 4 columns x 3 rows, so the 4x4 box is that image
# with its middle row of compartments copied in once more. Measured on the 2048 px original,
# as fractions: compartment rows 0.165-0.328-0.516-0.715, columns 0.10 ... 0.91.
B4_ROW2 = (0.328, 0.516)
B4_GRID = (0.10, 0.165, 0.91, 0.715)


def make_box_4() -> tuple:
    im = Image.open(os.path.join(SRC, "box_4_0.png")).convert("RGBA")
    w, h = im.size
    y0, y1 = int(h * B4_ROW2[0]), int(h * B4_ROW2[1])
    strip = im.crop((0, y0, w, y1))
    out = Image.new("RGBA", (w, h + strip.height))
    out.paste(im.crop((0, 0, w, y1)), (0, 0))
    out.paste(strip, (0, y1))
    out.paste(im.crop((0, y1, w, h)), (0, y1 + strip.height))
    l, t, r, b = B4_GRID[0] * w, B4_GRID[1] * h, B4_GRID[2] * w, B4_GRID[3] * h + strip.height
    bbox = out.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    out = out.crop(bbox)
    grid = [(l - bbox[0]) / out.width, (t - bbox[1]) / out.height, (r - bbox[0]) / out.width, (b - bbox[1]) / out.height]
    return out, [round(v, 4) for v in grid]


# grid of the generated 2x3 / 2x4 boxes, as fractions of the cropped art (checked with --preview)
BOX_2XN_GRID = {3: [0.06, 0.05, 0.94, 0.82], 4: [0.05, 0.05, 0.95, 0.82]}


def make_box_cols(cols: int) -> tuple:
    """2 x cols box (2026-10-16: the box grows 2x2 -> 2x3 -> 2x4, wider not deeper): the 2x2 art
    with its left column (inner left edge to the middle divider) repeated before the middle."""
    im = crop(Image.open(os.path.join(SRC, "box_2_0.png")).convert("RGBA"))
    l, t, r, b = BOX_GRID["box_2"]
    w, h = im.size
    mid = round(w * (l + r) / 2.0)          # centre of the middle divider
    cell = round(w * (r - l) / 2.0)
    strip = im.crop((mid - cell, 0, mid, h))
    out = Image.new("RGBA", (w + cell * (cols - 2), h))
    out.paste(im.crop((0, 0, mid, h)), (0, 0))
    for i in range(cols - 2):
        out.paste(strip, (mid + i * cell, 0))
    out.paste(im.crop((mid, 0, w, h)), (mid + (cols - 2) * cell, 0))
    W = out.width
    grid = [l * w / W, t, (r * w + cell * (cols - 2)) / W, b]
    return out, [round(v, 4) for v in grid]


def crop(im: Image.Image) -> Image.Image:
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    return im.crop(a.getbbox())


def fit(im: Image.Image, mode: str, px: int) -> Image.Image:
    w, h = im.size
    if mode == "height":
        s = px / h
    elif mode == "width":
        s = px / w
    else:
        s = px / max(w, h)
    return im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    # every other food / 套餐 sprite (gen_assets.sh menu): long side 128 (套餐 160)
    for f in sorted(os.listdir(SRC)):
        if f.startswith("food_") and f.endswith("_0.png") and f[:-6] not in SPRITES:
            SPRITES[f[:-6]] = ("long", 160 if f.startswith("food_set_") else 128)
    # round 3: stalls (per level and closed), the sign plate, the 保温箱, the skill tree board pieces
    for f in sorted(os.listdir(SRC)):
        n = f[:-6]
        if f.endswith("_0.png") and n not in SPRITES:
            if f.startswith("stall_"):
                SPRITES[n] = ("width", 320)
            elif n in ROUND3:
                SPRITES[n] = ROUND3[n]
            elif n in POLISH:
                SPRITES[n] = POLISH[n]
            elif n.startswith("icon_"):
                SPRITES[n] = ("long", 96)   # HUD icons (gen_assets.sh hud)
            elif n in HUD_UI:
                SPRITES[n] = HUD_UI[n]
    for name, (mode, px) in SPRITES.items():
        if name == "box_4":
            im, BOX_GRID["box_4"] = make_box_4()
            fit(im, mode, px).save(os.path.join(OUT, name + ".png"))
            continue
        im = crop(Image.open(os.path.join(SRC, name + "_0.png")).convert("RGBA"))
        if name == "tentacle":
            # keep the straight middle of the strip, so it tiles without the rounded ends
            w = im.width
            im = im.crop((int(w * 0.08), 0, int(w * 0.92), im.height))
        im = fit(im, mode, px)
        if name == "counter":
            # the mockup has a low counter: keep the steel top and the name plates, drop the plain
            # wood below them (the vertical planks hide the seam), keep the bottom trim
            cut0, cut1 = round(im.height * 0.62), round(im.height * 0.895)
            low = Image.new("RGBA", (im.width, im.height - (cut1 - cut0)))
            low.paste(im.crop((0, 0, im.width, cut0)), (0, 0))
            low.paste(im.crop((0, cut1, im.width, im.height)), (0, cut0))
            im = low
        im.save(os.path.join(OUT, name + ".png"))
    # the wall: cover 1920x1080, then darker and less saturated than the foreground
    bg = Image.open(os.path.join(SRC, "bg_wall_0.png")).convert("RGB")
    s = max(1920 / bg.width, 1080 / bg.height)
    bg = bg.resize((round(bg.width * s), round(bg.height * s)), Image.LANCZOS)
    x0, y0 = (bg.width - 1920) // 2, (bg.height - 1080) // 2
    bg = bg.crop((x0, y0, x0 + 1920, y0 + 1080))
    bg = ImageEnhance.Color(bg).enhance(0.7)
    bg = ImageEnhance.Brightness(bg).enhance(0.62)
    bg.save(os.path.join(OUT, "bg_wall.png"))
    # round 3b: the continuous counter without its hanging lamps (they would hide 梁阿姨), squeezed
    # a little to 1420 x 330; the shutter without the speckled margin the generator left
    src = os.path.join(SRC, "counter_long_0.png")
    if os.path.exists(src):
        im = Image.open(src).convert("RGBA")
        im = im.crop((0, round(im.height * 0.225), im.width, im.height))
        cut0, cut1 = round(im.height * 0.66), round(im.height * 0.77)   # a lower tiled front panel
        low = Image.new("RGBA", (im.width, im.height - (cut1 - cut0)))
        low.paste(im.crop((0, 0, im.width, cut0)), (0, 0))
        low.paste(im.crop((0, cut1, im.width, im.height)), (0, cut0))
        fit(low, "width", 1420).save(os.path.join(OUT, "counter_long.png"))
    src = os.path.join(SRC, "counter_shutter_0.png")
    if os.path.exists(src):
        im = Image.open(src).convert("RGBA")
        im = im.crop((round(im.width * 0.0275), round(im.height * 0.145), round(im.width * 0.9725), round(im.height * 0.857)))
        fit(im, "width", 400).save(os.path.join(OUT, "counter_shutter.png"))
    for name in FULLSCREEN:
        src = os.path.join(SRC, name + "_0.png")
        if os.path.exists(src):
            im = Image.open(src).convert("RGB")
            k = max(1920 / im.width, 1080 / im.height)
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            x0, y0 = (im.width - 1920) // 2, (im.height - 1080) // 2
            im.crop((x0, y0, x0 + 1920, y0 + 1080)).save(os.path.join(OUT, name + ".png"))
    # 2x3 / 2x4: generated from the 2x2 as reference (gen_assets.sh box_2xN); the pasted version
    # (make_box_cols) showed seams, it stays as a fallback
    for cols in (3, 4):
        src = os.path.join(SRC, f"box_2x{cols}_v2_0.png")
        if os.path.exists(src):
            im = crop(Image.open(src).convert("RGBA"))
            BOX_GRID[f"box_2x{cols}"] = BOX_2XN_GRID[cols]
        else:
            im, BOX_GRID[f"box_2x{cols}"] = make_box_cols(cols)
        fit(im, "width", int(360 * cols / 2)).save(os.path.join(OUT, f"box_2x{cols}.png"))
    json.dump({"box_grid": BOX_GRID}, open(DATA, "w", encoding="utf-8"), indent=1)
    print("canteen art ->", OUT)
    if "--preview" in sys.argv:
        tiles = []
        for name, (l, t, r, b) in BOX_GRID.items():
            im = Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")
            n = int(name[-1])
            rows = 2 if "x" in name or name == "box_2" else n
            d = ImageDraw.Draw(im)
            x0, y0, x1, y1 = l * im.width, t * im.height, r * im.width, b * im.height
            for i in range(n + 1):
                d.line([(x0 + (x1 - x0) * i / n, y0), (x0 + (x1 - x0) * i / n, y1)], fill=(255, 0, 80, 255), width=2)
            for i in range(rows + 1):
                d.line([(x0, y0 + (y1 - y0) * i / rows), (x1, y0 + (y1 - y0) * i / rows)], fill=(255, 0, 80, 255), width=2)
            bgc = Image.new("RGBA", im.size, (55, 47, 42, 255))
            bgc.alpha_composite(im)
            tiles.append(bgc)
        sheet = Image.new("RGB", (sum(t.width for t in tiles) + 20 * len(tiles), max(t.height for t in tiles)), (30, 30, 30))
        x = 0
        for t in tiles:
            sheet.paste(t.convert("RGB"), (x, 0))
            x += t.width + 20
        sheet.save(os.path.join(SRC, "_box_grid_check.png"))
        print("grid check -> art_src/assets/_box_grid_check.png")


def stamp_ring() -> None:
    """stamp_ring.png: the red stamp's outer rings only (the rice bowl in the middle cut away),
    a blank stamp the checkout writes multipliers into."""
    import numpy as np
    a = np.asarray(Image.open(os.path.join(SRC, "stamp_0.png")).convert("RGBA")).astype(np.float32).copy()
    ys, xs = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    pts = np.argwhere(a[..., 3] > 40)
    cy, cx = pts.mean(0)
    r = np.hypot(ys - cy, xs - cx) / (max(np.ptp(pts[:, 0]), np.ptp(pts[:, 1])) / 2)
    a[..., 3] *= np.clip((r - 0.74) / 0.04, 0, 1)
    im = Image.fromarray(a.astype(np.uint8))
    im = crop(im)
    im.thumbnail((256, 256), Image.LANCZOS)
    im.save(os.path.join(OUT, "stamp_ring.png"))


RIM_PAD = 14   # px of room around a food sprite for its glow


def food_rims() -> None:
    """rim/food_<x>.png: a soft white glow hugging each food's own outline (its alpha grown
    out and blurred, the food itself cut away), padded by RIM_PAD on every side. The game tints
    it warm gold and lets it breathe under 金牌 food (docs: no circles, the light follows the
    dish's shape)."""
    from PIL import ImageFilter
    import numpy as np
    os.makedirs(os.path.join(OUT, "rim"), exist_ok=True)
    for f in sorted(os.listdir(OUT)):
        if not (f.startswith("food_") and f.endswith(".png")):
            continue
        im = Image.open(os.path.join(OUT, f)).convert("RGBA")
        a = Image.new("L", (im.width + RIM_PAD * 2, im.height + RIM_PAD * 2), 0)
        a.paste(im.getchannel("A"), (RIM_PAD, RIM_PAD))
        grown = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(5))
        g = np.asarray(grown).astype(np.float32) / 255.0
        own = np.asarray(a).astype(np.float32) / 255.0
        rim = np.clip(g * 1.6 - own * 0.85, 0.0, 1.0)
        out = np.dstack([np.full_like(rim, 255), np.full_like(rim, 255), np.full_like(rim, 255), rim * 255]).astype(np.uint8)
        Image.fromarray(out, "RGBA").save(os.path.join(OUT, "rim", f))
        # the sheen: SHEEN_FRAMES frames side by side of a soft diagonal band of light crossing
        # the dish, cut to the dish's own alpha (so it only shows on the food)
        al = np.asarray(im.getchannel("A")).astype(np.float32) / 255.0
        h, w = al.shape
        ys, xs = np.mgrid[0:h, 0:w]
        diag = (xs / w + ys / h) * 0.5          # 0 top-left .. 1 bottom-right
        frames = []
        for i in range(SHEEN_FRAMES):
            c = -0.2 + 1.4 * i / (SHEEN_FRAMES - 1)
            band = np.exp(-((diag - c) / 0.055) ** 2) + 0.35 * np.exp(-((diag - c + 0.13) / 0.03) ** 2)
            a2 = np.clip(band, 0, 1) * al * 0.9
            frames.append(np.dstack([np.full_like(a2, 255), np.full_like(a2, 255), np.full_like(a2, 255), a2 * 255]))
        os.makedirs(os.path.join(OUT, "sheen"), exist_ok=True)
        Image.fromarray(np.concatenate(frames, axis=1).astype(np.uint8), "RGBA").save(os.path.join(OUT, "sheen", f))


SHEEN_FRAMES = 10


if __name__ == "__main__":
    main()
    stamp_ring()
    food_rims()
