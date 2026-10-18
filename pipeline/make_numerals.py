"""「饭票数字」(docs/font_plan.md): the game's own number font, a bitmap font for money,
multipliers, counts and stamps. The skeleton is 站酷快乐体's digits; on top: a thick dark ink
outline, a white face with a soft top-to-bottom shade (the game tints it gold / red / blue when
drawing), a small highlight and a printed drop shadow, the edge a little worn like ticket print.
Characters it lacks fall back to 站酷快乐体 in game.

Usage (repo root):  python pipeline/make_numerals.py
Writes game/assets/ui/numerals.png + numerals.fnt (AngelCode BMFont text; Godot imports it).
"""
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FONT = os.path.join(ROOT, "game", "assets", "ui", "ZCOOLKuaiLe.ttf")
OUT = os.path.join(ROOT, "game", "assets", "ui")
CHARS = "0123456789×+-−%.,/:()?万亿KMB"
SIZE = 96          # glyph size the font is drawn at (Godot scales it to the size asked for)
STROKE = 12        # outline, px at SIZE
FACE = 4           # the white face is drawn this much bolder than the font's thin stroke
PAD = 16
INK = (52, 26, 10)


def glyph(ch: str, font: ImageFont.FreeTypeFont, rng: np.random.Generator) -> tuple:
    l, t, r, b = font.getbbox(ch, stroke_width=STROKE)
    w, h = r - l + PAD * 2, b - t + PAD * 2
    origin = (PAD - l, PAD - t)
    outline = Image.new("L", (w, h), 0)
    ImageDraw.Draw(outline).text(origin, ch, font=font, fill=255, stroke_width=STROKE, stroke_fill=255)
    face = Image.new("L", (w, h), 0)
    ImageDraw.Draw(face).text(origin, ch, font=font, fill=255, stroke_width=FACE, stroke_fill=255)
    face = face.filter(ImageFilter.GaussianBlur(0.6))
    # the face: white, shaded a little darker toward the bottom, a highlight up and left
    shade = np.linspace(1.0, 0.8, h)[:, None] * np.ones((1, w))
    hi = np.asarray(ImageChops.subtract(face, face.transform(face.size, Image.AFFINE, (1, 0, 3, 0, 1, 4)))).astype(np.float32) / 255.0
    lum = np.clip(shade + hi * 0.25, 0, 1)
    f = np.asarray(face).astype(np.float32) / 255.0
    o = np.asarray(outline).astype(np.float32) / 255.0
    # a worn print edge: low-frequency noise nibbles at the outline
    noise = Image.fromarray((rng.random((h // 6 + 1, w // 6 + 1)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    n = np.asarray(noise).astype(np.float32) / 255.0
    edge = (o > 0) & (o < 0.98)
    o = np.where(edge & (n < 0.18), o * 0.6, o)
    rgb = np.zeros((h, w, 3), np.float32)
    for c in range(3):
        rgb[..., c] = (INK[c] / 255.0) * (1 - f) + lum * f
    a = np.maximum(o, f)
    # a printed shadow below right
    sh = np.roll(np.roll(o, 4, axis=0), 3, axis=1) * 0.45
    out_a = a + sh * (1 - a)
    out_rgb = (rgb * a[..., None] + np.array(INK) / 255.0 * 0.6 * (sh * (1 - a))[..., None]) / np.maximum(out_a, 1e-4)[..., None]
    img = np.dstack([np.clip(out_rgb, 0, 1) * 255, np.clip(out_a, 0, 1) * 255]).astype(np.uint8)
    adv = font.getlength(ch) + STROKE * 0.9
    return Image.fromarray(img, "RGBA"), origin, adv


def main() -> None:
    font = ImageFont.truetype(FONT, SIZE)
    rng = np.random.default_rng(11)
    ascent, descent = font.getmetrics()
    glyphs = [(ch,) + glyph(ch, font, rng) for ch in CHARS]
    # pack in rows
    W = 1024
    x = y = row_h = 0
    places = []
    for ch, im, origin, adv in glyphs:
        if x + im.width > W:
            x, y = 0, y + row_h + 2
            row_h = 0
        places.append((x, y))
        x += im.width + 2
        row_h = max(row_h, im.height)
    H = 1 << int(np.ceil(np.log2(y + row_h + 2)))
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    lines = [f'info face="FanpiaoNumerals" size={SIZE} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=2,2',
             f"common lineHeight={ascent + descent + STROKE} base={ascent + STROKE // 2} scaleW={W} scaleH={H} pages=1 packed=0",
             'page id=0 file="numerals.png"', f"chars count={len(glyphs)}"]
    for (ch, im, origin, adv), (px, py) in zip(glyphs, places):
        atlas.alpha_composite(im, (px, py))
        # xoffset/yoffset: where the image's top-left sits relative to the pen position / line top
        xo = -origin[0] + 0
        yo = STROKE // 2 - origin[1] + 0
        lines.append(f"char id={ord(ch)} x={px} y={py} width={im.width} height={im.height} xoffset={xo} yoffset={yo} xadvance={int(round(adv))} page=0 chnl=15")
    atlas.save(os.path.join(OUT, "numerals.png"))
    open(os.path.join(OUT, "numerals.fnt"), "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print(f"{len(glyphs)} glyphs -> numerals.png ({W}x{H}) + numerals.fnt")


if __name__ == "__main__":
    main()
