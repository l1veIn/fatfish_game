"""Steam store graphics from the existing art (repo root):
    python pipeline/make_store_art.py [--shots <autotest shots dir> ...]
Builds every capsule, the library hero and the library logo in Chinese and English into
art_src/store/, plus art_src/store/_contact_sheet.jpg to check them all at a glance.
Sources: the canteen wall, counter, Auntie Liang and the food from art_src/assets/ (the
2048 px originals, not the downscaled game copies), the Fatfish from art_src/fatfish/base_0.png
and the game font (Noto Sans SC, Black weight) for the logo.
Red lines (docs/steam_release.md 2.2): no DeepSeek name or logo, the only whale is the emblem
on her apron (the one on her rice bowl is painted out here), nothing that looks official, and
no "free" / price text on the capsules (Valve allows only artwork and the game name on them).
--shots copies the screenshots picked in SHOTS from autotest screenshot folders, e.g.
    tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --resolution 1920x1080 -- --autotest --runs=10 --shots=<dir>
(add --lang=en for English) into art_src/store/screenshots/ as 1920x1080 PNGs.
"""
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSETS = os.path.join(ROOT, "art_src", "assets")
OUT = os.path.join(ROOT, "art_src", "store")
FONT = os.path.join(ROOT, "art_src", "fonts", "NotoSansSC-VF.ttf")

LANGS = ("zh", "en")
TITLE = {   # logo lines: (text, size relative to the main line)
    "zh": [("吃白饭的", 0.64), ("大肥鱼", 1.0)],
    "en": [("Fatfish's", 0.78), ("Free Lunch", 1.0)],
}
CREAM = (255, 250, 228)
GOLD = (255, 186, 82)
BROWN = (74, 38, 20)
BROWN_DEEP = (52, 26, 14)
RIM = (255, 244, 222)

# Screenshots picked from the autotest shots (lang, file in that run's folder, output name).
# Keep these real gameplay: shifts, the tree, the trial. Re-pick after re-running the autotest.
SHOTS = [
    ("zh", "run_9_b.png", "zh_01_peak.png"),
    ("zh", "run_7_b.png", "zh_02_feeding.png"),
    ("zh", "run_6_b.png", "zh_03_crit.png"),
    ("zh", "tree_10.png", "zh_04_skill_tree.png"),
    ("zh", "card_9.png", "zh_05_result.png"),
    ("zh", "title.png", "zh_06_title.png"),
    ("en", "run_3_b.png", "en_01_shift.png"),
    ("en", "run_1_b.png", "en_02_feeding.png"),
    ("en", "tree_4.png", "en_03_skill_tree.png"),
    ("en", "card_4.png", "en_04_result.png"),
    ("en", "title.png", "en_05_title.png"),
]


# ---------------------------------------------------------------- helpers
_cache: dict = {}


def trim(im: Image.Image) -> Image.Image:
    return im.crop(im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())


def sprite(name: str) -> Image.Image:
    """A trimmed 2048 px source sprite from art_src/assets (or the fixed Fatfish)."""
    if name not in _cache:
        if name == "fish":
            _cache[name] = trim(fish_without_bowl_whale())
        else:
            _cache[name] = trim(Image.open(os.path.join(ASSETS, name + "_0.png")).convert("RGBA"))
    return _cache[name]


def by_height(im: Image.Image, h: float) -> Image.Image:
    h = max(1, int(round(h)))
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)


def by_width(im: Image.Image, w: float) -> Image.Image:
    w = max(1, int(round(w)))
    return im.resize((w, max(1, round(im.height * w / im.width))), Image.LANCZOS)


def place(canvas: Image.Image, im: Image.Image, x: float, y: float, anchor: str = "mb") -> None:
    """Paste with an anchor: first letter l/m/r (x), second t/m/b (y)."""
    dx = {"l": 0, "m": im.width / 2, "r": im.width}[anchor[0]]
    dy = {"t": 0, "m": im.height / 2, "b": im.height}[anchor[1]]
    layer = Image.new("RGBA", canvas.size)
    layer.paste(im, (int(round(x - dx)), int(round(y - dy))), im)
    canvas.alpha_composite(layer)


def blur_np(z: np.ndarray, rad: int) -> np.ndarray:
    """Gaussian-ish blur (three box passes) of a float array, without scipy."""
    z = z.astype(np.float64)
    for _ in range(3):
        for ax in (0, 1):
            pad = [(rad, rad) if i == ax else (0, 0) for i in range(z.ndim)]
            c = np.cumsum(np.pad(z, pad, mode="edge"), axis=ax)
            c = np.insert(c, 0, 0, axis=ax)
            n = z.shape[ax]
            z = (np.take(c, range(2 * rad + 1, 2 * rad + 1 + n), axis=ax) - np.take(c, range(n), axis=ax)) / (2 * rad + 1)
    return z


def fish_without_bowl_whale() -> Image.Image:
    """base_0.png with the little whale on her rice bowl painted out (the apron emblem stays):
    the blue pixels are filled from the surrounding bowl colour (normalised blur)."""
    im = Image.open(os.path.join(ROOT, "art_src", "fatfish", "base_0.png")).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    x0, y0, x1, y1 = 700, 985, 820, 1080          # the whale on the bowl, in the 2048 px original
    reg = a[y0:y1, x0:x1, :3]
    r, b = reg[..., 0], reg[..., 2]
    blue = Image.fromarray(((b - r > 45) * 255).astype(np.uint8))
    m = blue.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.MinFilter(9)).filter(ImageFilter.MaxFilter(5))
    m = (np.asarray(m) > 0) & (b >= r - 8)        # never grow into her pink fingers
    bowl = (~m) & (b >= r - 8) & (reg.mean(-1) > 170)
    w = bowl.astype(np.float64)
    out = reg.copy()
    done = np.zeros_like(m)
    for rad in (4, 8, 16):
        den = blur_np(w, rad)
        fill = np.stack([blur_np(reg[..., k] * w, rad) for k in range(3)], -1) / np.maximum(den, 1e-4)[..., None]
        sel = m & ~done & (den > 0.05)
        out[sel] = fill[sel]
        done |= sel
    a[y0:y1, x0:x1, :3] = out
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def filled_box(name: str, n: int, foods: list) -> Image.Image:
    """A lunch box with food in its compartments (grid from game/data/canteen_art.json)."""
    box = sprite(name).copy()
    gl, gt, gr, gb = {"box_2": (0.07, 0.04, 0.93, 0.80), "box_3": (0.07, 0.04, 0.93, 0.80)}[name]
    cw, ch = (gr - gl) * box.width / n, (gb - gt) * box.height / n
    for i, f in enumerate(foods):
        if f is None:
            continue
        cx = gl * box.width + (i % n + 0.5) * cw
        cy = gt * box.height + (i // n + 0.5) * ch
        food = by_height(sprite(f), min(cw, ch) * 0.86)
        place(box, food, cx, cy, "mm")
    return box


# ---------------------------------------------------------------- background
def background(w: int, h: int, focus=(0.5, 0.5), zoom=1.0, blur=0.0, dark=0.0) -> Image.Image:
    """The canteen wall, cover-scaled, with an evening warm grade and a soft vignette."""
    src = Image.open(os.path.join(ASSETS, "bg_wall_0.png")).convert("RGB")
    s = max(w / src.width, h / src.height) * zoom
    sw, sh = math.ceil(src.width * s), math.ceil(src.height * s)
    big = src.resize((sw, sh), Image.LANCZOS)
    x = min(max(0, int(focus[0] * sw - w / 2)), sw - w)
    y = min(max(0, int(focus[1] * sh - h / 2)), sh - h)
    bg = big.crop((x, y, x + w, y + h))
    if blur:
        bg = bg.filter(ImageFilter.GaussianBlur(blur * h))
    bg = ImageEnhance.Color(bg).enhance(1.08)
    warm = Image.new("RGB", bg.size, (255, 170, 90))
    bg = Image.blend(bg, ImageChops.multiply(bg, warm), 0.18)
    bg = ImageEnhance.Brightness(bg).enhance(1.0 - dark)
    # vignette: darker toward the corners
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / math.sqrt(2)
    v = np.clip(1.0 - 0.45 * np.clip(d - 0.35, 0, 1) ** 1.4 * 1.8, 0, 1)
    arr = np.asarray(bg).astype(np.float32) * v[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8)).convert("RGBA")


def glow(canvas: Image.Image, x: float, y: float, r: float, color=(255, 214, 140), alpha=0.55) -> None:
    """A soft warm light (screen-blended radial gradient) to lift a character off the wall."""
    w, h = canvas.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - x) ** 2 + (yy - y) ** 2) / r
    a = np.clip(1 - d, 0, 1) ** 2 * alpha
    base = np.asarray(canvas).astype(np.float32)
    c = np.array(color, np.float32)
    rgb = base[..., :3]
    rgb = 255 - (255 - rgb) * (1 - a[..., None] * c / 255)
    base[..., :3] = rgb
    canvas.paste(Image.fromarray(base.clip(0, 255).astype(np.uint8), "RGBA"))


def shadow_of(im: Image.Image, blur: float, alpha: int = 150, color=(30, 14, 6)) -> Image.Image:
    a = im.getchannel("A").point(lambda v: v * alpha // 255)
    pad = int(blur * 3) + 2
    sh = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), color + (0,))
    m = Image.new("L", sh.size, 0)
    m.paste(a, (pad, pad))
    sh.putalpha(m.filter(ImageFilter.GaussianBlur(blur)))
    return sh


def place_with_shadow(canvas, im, x, y, anchor="mb", off=(0.0, 0.0), blur=0.0, alpha=130):
    if blur:
        sh = shadow_of(im, blur, alpha)
        pad = (sh.width - im.width) / 2
        dx = {"l": -pad, "m": 0, "r": pad}[anchor[0]]
        dy = {"t": -pad, "m": 0, "b": pad}[anchor[1]]
        place(canvas, sh, x + off[0] + dx, y + off[1] + dy, anchor)
    place(canvas, im, x, y, anchor)


def trail(canvas: Image.Image, pts: list, width: float, alpha: int = 150) -> None:
    """A motion streak behind a flying food: a tapering white curve through pts (tail -> head)."""
    layer = Image.new("RGBA", canvas.size)
    d = ImageDraw.Draw(layer)
    n = 24
    path = []
    for i in range(n + 1):        # quadratic bezier through the 3 points
        t = i / n
        (x0, y0), (x1, y1), (x2, y2) = pts
        path.append(((1 - t) ** 2 * x0 + 2 * (1 - t) * t * x1 + t * t * x2, (1 - t) ** 2 * y0 + 2 * (1 - t) * t * y1 + t * t * y2))
    for i in range(n):
        t = (i + 1) / n
        wd = max(1, int(width * t))
        d.line([path[i], path[i + 1]], fill=(255, 252, 238, int(alpha * t)), width=wd)
        d.ellipse((path[i + 1][0] - wd / 2, path[i + 1][1] - wd / 2, path[i + 1][0] + wd / 2, path[i + 1][1] + wd / 2), fill=(255, 252, 238, int(alpha * t)))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(width * 0.12)))


def sparkle(canvas: Image.Image, x: float, y: float, r: float, alpha: int = 230) -> None:
    layer = Image.new("RGBA", canvas.size)
    d = ImageDraw.Draw(layer)
    k = r * 0.22
    d.polygon([(x, y - r), (x + k, y - k), (x + r, y), (x + k, y + k), (x, y + r), (x - k, y + k), (x - r, y), (x - k, y - k)], fill=(255, 246, 200, alpha))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(max(0.6, r * 0.04))))


# ---------------------------------------------------------------- logo
def heavy(px: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT, px)
    f.set_variation_by_axes([900])
    return f


# per-glyph tilt (degrees) and bounce (fraction of the line size), cycled
TILT = [-4.0, 3.0, -2.0, 4.0, -3.0, 2.5, -1.5]
BOUNCE = [0.0, -0.035, 0.02, -0.03, 0.025, -0.02, 0.015]


def logo(lang: str, em: int, align: str = "left", one_line: bool = False, deco: bool = False) -> Image.Image:
    """The game title as a chunky sticker: cream-to-gold fill, dark brown outline with a little
    extrusion, a cream rim and a soft shadow. Rendered at 2x and downscaled.
    em = pixel size of the main line in the result."""
    ss = 2
    E = em * ss
    lines = TITLE[lang]
    if one_line:
        lines = [(" ".join(t for t, _ in lines) if lang == "en" else "".join(t for t, _ in lines), 0.86)]
    stroke = int(E * 0.085)
    rim = int(E * 0.055)
    extr = int(E * 0.06)
    pad = stroke + rim + extr + int(E * 0.25)
    # glyph placements: (char, font, x, baseline, angle)
    glyphs = []
    widths = []
    y = 0.0
    gi = 0
    for li, (text, rel) in enumerate(lines):
        size = int(E * rel)
        f = heavy(size)
        asc = f.getmetrics()[0]
        y += size * (0.88 if lang == "zh" else 0.80) if li else asc * 0.95
        x = 0.0
        row = []
        for i, ch in enumerate(text):
            adv = f.getlength(text[: i + 1]) - f.getlength(text[:i])
            if ch != " ":
                row.append([ch, f, x, y + BOUNCE[gi % len(BOUNCE)] * size, TILT[gi % len(TILT)] * (0.7 if lang == "en" else 1.0), size])
                gi += 1
            x += adv * (1.0 if lang == "en" else 0.97)
        widths.append(x)
        glyphs.append(row)
        y += size * (0.12 if lang == "zh" else 0.20)
    width = max(widths)
    for row, wd in zip(glyphs, widths):
        off = {"left": 0, "center": (width - wd) / 2, "right": width - wd}[align]
        for g in row:
            g[2] += off
    W, H = int(width + 2 * pad), int(y + 2 * pad)

    def mask(grow: int, dy: int = 0) -> Image.Image:
        m = Image.new("L", (W, H), 0)
        for ch, f, gx, gy, ang, size in (g for row in glyphs for g in row):
            g = Image.new("L", (int(size * 1.6 + 2 * grow), int(size * 1.8 + 2 * grow)), 0)
            ox, oy = grow + size * 0.3, grow + size * 1.2
            ImageDraw.Draw(g).text((ox, oy), ch, font=f, fill=255, anchor="ls", stroke_width=grow, stroke_fill=255)
            cx, cy = ox + f.getlength(ch) / 2, oy - size * 0.38
            g = g.rotate(ang, resample=Image.BICUBIC, center=(cx, cy))
            px, py = int(pad + gx - ox), int(pad + gy - oy + dy)
            region = m.crop((px, py, px + g.width, py + g.height))
            m.paste(ImageChops.lighter(region, g), (px, py))
        return m

    fill_m = mask(0)
    line_m = mask(stroke)
    deep_m = Image.new("L", (W, H), 0)
    for k in range(1, extr + 1, max(1, extr // 8)):
        deep_m = ImageChops.lighter(deep_m, mask(stroke, k))
    rim_m = close(ImageChops.lighter(mask(stroke + rim), mask(stroke + rim, extr)), E * 0.06)
    out = Image.new("RGBA", (W, H))
    # soft shadow under the whole sticker
    sh = Image.new("RGBA", (W, H), (36, 16, 6, 0))
    sh.putalpha(rim_m.point(lambda v: v * 150 // 255).filter(ImageFilter.GaussianBlur(E * 0.05)))
    out.alpha_composite(sh, (0, int(E * 0.05)))
    out.alpha_composite(solid(RIM, rim_m))
    out.alpha_composite(solid(BROWN_DEEP, deep_m))
    out.alpha_composite(solid(BROWN, line_m))
    # fill: vertical cream -> gold gradient per line, plus a glossy top band
    grad = np.zeros((H, W, 4), np.uint8)
    for row in glyphs:
        if not row:
            continue
        size = row[0][5]
        top = pad + row[0][3] - size * 0.86
        bot = pad + row[0][3] + size * 0.06
        y0, y1 = max(0, int(top - size * 0.15)), min(H, int(bot + size * 0.2))
        t = np.clip((np.arange(y0, y1) - top) / (bot - top), 0, 1)[:, None]
        for k in range(3):
            grad[y0:y1, :, k] = (CREAM[k] + (GOLD[k] - CREAM[k]) * t ** 1.3).astype(np.uint8)
    g = Image.fromarray(grad, "RGBA")
    g.putalpha(fill_m)
    out.alpha_composite(g)
    if deco:   # an onigiri tucked onto the top-right of the main line
        last = glyphs[-1][-1]
        f = last[1]
        oni = by_height(sprite("food_ball"), last[5] * 0.5).rotate(-16, resample=Image.BICUBIC, expand=True)
        ox = pad + last[2] + f.getlength(last[0]) + stroke * 0.2
        oy = pad + last[3] - last[5] * 0.78
        ring = solid(RIM, oni.getchannel("A").filter(ImageFilter.MaxFilter(2 * (rim // 2) + 1)))
        dark = solid(BROWN, oni.getchannel("A").filter(ImageFilter.MaxFilter(2 * (stroke // 4) + 1)))
        grown = Image.new("RGBA", (W + oni.width, H))
        grown.alpha_composite(out)
        out = grown
        for layer in (ring, dark, oni):
            place(out, layer, ox, oy, "mm")
    bbox = out.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    out = out.crop(bbox)
    return out.resize((max(1, out.width // ss), max(1, out.height // ss)), Image.LANCZOS)


def close(m: Image.Image, r: float) -> Image.Image:
    """Morphological closing (fills the small gaps between glyphs) via blur + threshold."""
    d = m.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 24 else 0)
    e = d.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 231 else 0)
    return ImageChops.lighter(m, e.filter(ImageFilter.GaussianBlur(1.2)))


def solid(color, m: Image.Image) -> Image.Image:
    im = Image.new("RGBA", m.size, tuple(color) + (0,))
    im.putalpha(m)
    return im


def fit_logo(lang: str, max_w: float, max_h: float, **kw) -> Image.Image:
    """The logo scaled to fit a box (rendered near the right size so strokes stay crisp)."""
    probe = logo(lang, 100, **kw)
    s = min(max_w / probe.width, max_h / probe.height)
    im = logo(lang, int(100 * s * 1.02), **kw)
    s2 = min(max_w / im.width, max_h / im.height, 1.0)
    return im if s2 >= 1.0 else im.resize((int(im.width * s2), int(im.height * s2)), Image.LANCZOS)


# ---------------------------------------------------------------- scenes
def canteen(w: int, h: int, sp: dict) -> Image.Image:
    """The shared scene: Auntie Liang behind the counter flinging food over it, the Fatfish in
    front with her rice bowl (and optionally a full lunch box). Positions in sp are fractions
    of w / h."""
    c = background(w, h, sp.get("focus", (0.5, 0.45)), sp.get("zoom", 1.0), sp.get("blur", 0.002), sp.get("dark", 0.0))
    ax, ay, ah = sp["auntie"]
    glow(c, ax * w, (ay - ah * 0.4) * h, ah * h * 1.1, alpha=0.35)
    aunt = by_height(sprite(sp.get("auntie_face", "auntie_happy")), ah * h)
    if sp.get("auntie_flip"):
        aunt = aunt.transpose(Image.FLIP_LEFT_RIGHT)
    place_with_shadow(c, aunt, ax * w, ay * h, "mb", off=(0, ah * h * 0.02), blur=ah * h * 0.02, alpha=90)
    cx, cy, cwid = sp["counter"]
    counter = by_width(sprite("counter"), cwid * w)
    place_with_shadow(c, counter, cx * w, cy * h, "mt", off=(0, cwid * w * 0.006), blur=cwid * w * 0.008, alpha=140)
    for f in sp.get("foods", []):        # (name, x, y, size, angle, (trail tail x, y, ctrl x, y) or None)
        name, fx, fy, fs, ang, tr = f
        if tr:
            trail(c, [(tr[0] * w, tr[1] * h), (tr[2] * w, tr[3] * h), (fx * w, fy * h)], fs * h * 0.42)
        im = by_height(sprite(name), fs * h).rotate(ang, resample=Image.BICUBIC, expand=True)
        place_with_shadow(c, im, fx * w, fy * h, "mm", off=(fs * h * 0.05, fs * h * 0.08), blur=fs * h * 0.05, alpha=110)
    for s in sp.get("sparkles", []):
        sparkle(c, s[0] * w, s[1] * h, s[2] * h)
    fx, fy, fh = sp["fish"]
    glow(c, fx * w, (fy - fh * 0.55) * h, fh * h * 0.75, alpha=0.40)
    fish = by_height(sprite("fish"), fh * h)
    if sp.get("fish_flip"):
        fish = fish.transpose(Image.FLIP_LEFT_RIGHT)
    place_with_shadow(c, fish, fx * w, fy * h, "mb", off=(fh * h * 0.012, fh * h * 0.01), blur=fh * h * 0.018, alpha=150)
    if "box" in sp:
        bx, by_, bw = sp["box"]
        box = by_width(filled_box("box_3", 3, ["food_ball", "food_dump", "food_leg", "food_dump", "food_gold", "food_ball", "food_leg", "food_ball", "food_dump"]), bw * w)
        box = box.rotate(sp.get("box_angle", 0), resample=Image.BICUBIC, expand=True)
        place_with_shadow(c, box, bx * w, by_ * h, "mm", off=(bw * w * 0.03, bw * w * 0.05), blur=bw * w * 0.03, alpha=150)
    return c


# Flying-food sets shared by the landscape capsules (x, y, size as fractions; trail tail + control)
FOODS_WIDE = [
    ("food_ball", 0.535, 0.40, 0.14, -18, (0.62, 0.22, 0.55, 0.22)),
    ("food_leg", 0.78, 0.13, 0.13, 24, (0.68, 0.24, 0.72, 0.10)),
    ("food_dump", 0.62, 0.73, 0.12, 12, (0.62, 0.36, 0.60, 0.50)),
    ("food_gold", 0.965, 0.50, 0.11, -12, None),
]

SPECS = {
    # 920x430: logo on the left, the two characters on the right
    "header_capsule": dict(size=(920, 430), focus=(0.55, 0.42), auntie=(0.635, 0.50, 0.52),
                           counter=(0.68, 0.43, 0.62), fish=(0.865, 1.10, 1.0), foods=FOODS_WIDE,
                           sparkles=[(0.545, 0.22, 0.035), (0.96, 0.10, 0.03), (0.70, 0.86, 0.03)],
                           logo=dict(box=(0.035, 0.08, 0.50, 0.84), align="left")),
    # 1232x706 (main capsule on the front page)
    "main_capsule": dict(size=(1232, 706), focus=(0.55, 0.42), auntie=(0.615, 0.47, 0.46),
                         counter=(0.66, 0.41, 0.62), fish=(0.85, 1.06, 0.94), box=(0.56, 0.86, 0.22), box_angle=-8,
                         foods=[("food_ball", 0.47, 0.30, 0.12, -18, (0.58, 0.20, 0.52, 0.12)),
                                ("food_leg", 0.92, 0.17, 0.12, 24, (0.75, 0.20, 0.84, 0.06)),
                                ("food_dump", 0.55, 0.58, 0.10, 12, (0.62, 0.30, 0.55, 0.38))],
                         sparkles=[(0.51, 0.22, 0.03), (0.95, 0.10, 0.025), (0.62, 0.74, 0.03)],
                         logo=dict(box=(0.04, 0.10, 0.42, 0.62), align="left")),
    # 462x174: just the logo and her face, big
    "small_capsule": dict(size=(462, 174), focus=(0.5, 0.40), zoom=1.15, auntie=(0.86, 0.52, 0.0),
                          counter=None, fish=(0.86, 2.25, 2.40), foods=[], sparkles=[(0.67, 0.18, 0.06)],
                          logo=dict(box=(0.025, 0.05, 0.64, 0.90), align="left")),
    # 748x896: logo on top, Auntie behind the counter, the Fatfish in front
    "vertical_capsule": dict(size=(748, 896), focus=(0.5, 0.45), auntie=(0.44, 0.53, 0.30),
                             counter=(0.5, 0.48, 1.30), fish=(0.64, 1.04, 0.62), box=(0.24, 0.86, 0.36), box_angle=-8,
                             foods=[("food_ball", 0.17, 0.42, 0.075, -18, (0.36, 0.38, 0.25, 0.32)),
                                    ("food_leg", 0.86, 0.40, 0.08, 24, (0.66, 0.38, 0.78, 0.30)),
                                    ("food_dump", 0.20, 0.62, 0.065, 12, (0.38, 0.47, 0.25, 0.50))],
                             sparkles=[(0.10, 0.36, 0.02), (0.92, 0.33, 0.02)],
                             logo=dict(box=(0.06, 0.035, 0.88, 0.27), align="center")),
    # 600x900 library capsule: same layout, narrower
    "library_capsule": dict(size=(600, 900), focus=(0.5, 0.45), auntie=(0.44, 0.53, 0.28),
                            counter=(0.5, 0.48, 1.45), fish=(0.64, 1.04, 0.60), box=(0.22, 0.87, 0.40), box_angle=-8,
                            foods=[("food_ball", 0.16, 0.42, 0.07, -18, (0.36, 0.38, 0.25, 0.32)),
                                   ("food_leg", 0.86, 0.40, 0.075, 24, (0.66, 0.38, 0.78, 0.30)),
                                   ("food_dump", 0.18, 0.62, 0.06, 12, (0.38, 0.47, 0.25, 0.50))],
                            sparkles=[(0.10, 0.36, 0.02), (0.92, 0.33, 0.02)],
                            logo=dict(box=(0.06, 0.035, 0.88, 0.25), align="center")),
    # 3840x1240 library hero, no text: characters in the middle, the left kept calm for the logo
    "library_hero": dict(size=(3840, 1240), focus=(0.5, 0.40), blur=0.003, auntie=(0.46, 0.50, 0.46),
                         counter=(0.47, 0.44, 0.60), fish=(0.665, 1.05, 0.98), box=(0.355, 0.80, 0.11), box_angle=-6,
                         foods=[("food_ball", 0.375, 0.30, 0.11, -18, (0.43, 0.24, 0.40, 0.16)),
                                ("food_leg", 0.545, 0.11, 0.10, 24, (0.50, 0.24, 0.51, 0.08)),
                                ("food_dump", 0.80, 0.30, 0.09, 12, None),
                                ("food_gold", 0.27, 0.56, 0.08, -12, (0.36, 0.36, 0.29, 0.38))],
                         sparkles=[(0.41, 0.18, 0.025), (0.83, 0.16, 0.02), (0.25, 0.47, 0.02)], logo=None),
}


def build(name: str, lang: str) -> Image.Image:
    sp = dict(SPECS[name])
    w, h = sp["size"]
    if sp.get("counter") is None:          # small capsule: background, glow and her face only
        c = background(w, h, sp["focus"], sp.get("zoom", 1.0), 0.004, 0.08)
        fx, fy, fh = sp["fish"]
        glow(c, fx * w, h * 0.35, h * 0.9, alpha=0.4)
        fish = by_height(sprite("fish"), fh * h)
        place_with_shadow(c, fish, fx * w, fy * h, "mb", blur=h * 0.02)
    else:
        c = canteen(w, h, sp)
    for s in sp.get("sparkles", []) if sp.get("counter") is None else []:
        sparkle(c, s[0] * w, s[1] * h, s[2] * h)
    if sp.get("logo"):
        lx, ly, lw, lh = sp["logo"]["box"]
        kw = {k: v for k, v in sp["logo"].items() if k != "box"}
        lg = fit_logo(lang, lw * w, lh * h, **kw)
        ax = {"left": lx * w, "center": (lx + lw / 2) * w - lg.width / 2, "right": (lx + lw) * w - lg.width}[kw.get("align", "left")]
        place(c, lg, ax, (ly + lh / 2) * h, "lm")
    return c.convert("RGB")


def contact_sheet(files: list, path: str) -> None:
    """All outputs on one dark page, each labelled with its file name and size."""
    font = heavy(22)
    font.set_variation_by_axes([500])
    colw, gap = 940, 30
    tiles = []
    for f in files:
        im = Image.open(f).convert("RGBA")
        s = min(colw / im.width, 520 / im.height, 1.0)
        tiles.append((os.path.relpath(f, OUT).replace("\\", "/"), im.size, im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)))
    cols = 2
    rows = []
    for i in range(0, len(tiles), cols):
        rows.append(tiles[i:i + cols])
    H = sum(max(t[2].height for t in r) + 50 + gap for r in rows) + gap
    sheet = Image.new("RGBA", (cols * (colw + gap) + gap, H), (34, 30, 28, 255))
    d = ImageDraw.Draw(sheet)
    y = gap
    for r in rows:
        x = gap
        for name, size, im in r:
            if name.endswith("logo_zh.png") or name.endswith("logo_en.png"):   # transparent: show on a checker
                chk = Image.new("RGBA", im.size, (70, 66, 62, 255))
                cd = ImageDraw.Draw(chk)
                for yy in range(0, im.height, 20):
                    for xx in range(0, im.width, 20):
                        if (xx // 20 + yy // 20) % 2:
                            cd.rectangle((xx, yy, xx + 19, yy + 19), fill=(96, 90, 86, 255))
                chk.alpha_composite(im)
                im = chk
            sheet.alpha_composite(im, (x, y + 40))
            d.text((x, y + 6), f"{name}  {size[0]}×{size[1]}", fill=(255, 236, 200), font=font)
            x += colw + gap
        y += max(t[2].height for t in r) + 50 + gap
    sheet.convert("RGB").save(path, quality=88)


def copy_shots(dirs: list) -> list:
    """Pick the SHOTS out of autotest screenshot folders (the folder name or path must contain
    'en' for the English run, anything else counts as Chinese)."""
    out = os.path.join(OUT, "screenshots")
    os.makedirs(out, exist_ok=True)
    by_lang = {}
    for d in dirs:
        by_lang["en" if os.path.basename(os.path.normpath(d)).endswith("en") else "zh"] = d
    done = []
    for lang, src, dst in SHOTS:
        p = os.path.join(by_lang.get(lang, ""), src)
        if lang not in by_lang or not os.path.exists(p):
            print("  missing screenshot", lang, src)
            continue
        im = Image.open(p)
        if im.size != (1920, 1080):
            print("  wrong size", p, im.size)
            continue
        im.convert("RGB").save(os.path.join(out, dst))
        done.append(os.path.join(out, dst))
    return done


def main() -> None:
    args = sys.argv[1:]
    shot_dirs = []
    while "--shots" in args:
        i = args.index("--shots")
        shot_dirs.append(args[i + 1])
        del args[i:i + 2]
    only = args
    os.makedirs(OUT, exist_ok=True)
    files = []
    for name in SPECS:
        if only and name not in only:
            continue
        langs = ("",) if SPECS[name].get("logo") is None else LANGS
        for lang in langs:
            path = os.path.join(OUT, f"{name}{'_' + lang if lang else ''}.png")
            build(name, lang or "zh").save(path)
            files.append(path)
            print("wrote", os.path.relpath(path, ROOT))
    if not only or "library_logo" in only:
        for lang in LANGS:   # transparent, at most 1280x720
            lg = fit_logo(lang, 1240, 680, align="center", deco=True)
            path = os.path.join(OUT, f"library_logo_{lang}.png")
            lg.save(path)
            files.append(path)
            print("wrote", os.path.relpath(path, ROOT), lg.size)
    if shot_dirs:
        shutil.rmtree(os.path.join(OUT, "screenshots"), ignore_errors=True)
        files += copy_shots(shot_dirs)
    elif os.path.isdir(os.path.join(OUT, "screenshots")):
        files += [os.path.join(OUT, "screenshots", f) for f in sorted(os.listdir(os.path.join(OUT, "screenshots")))]
    if not only:
        contact_sheet(files, os.path.join(OUT, "_contact_sheet.jpg"))
        print("wrote art_src/store/_contact_sheet.jpg")


if __name__ == "__main__":
    main()
