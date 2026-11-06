"""Bilibili cover for the cost video: one big character, one big number, little text (1920x1200, 16:10).
Key content stays inside the centred 4:3 area that some feeds crop to. Output build/bill-20261107/cover.png"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/bill-20261107"
FONT = str(ROOT / "art_src/fonts/ZCOOLKuaiLe-Regular.ttf")
W, H = 1920, 1200
INK, CREAM, GOLD, RED = (59, 36, 22), (255, 241, 207), (255, 206, 115), (210, 58, 46)


def font(size):
    return ImageFont.truetype(FONT, size)


def outlined(d, xy, s, size, fill, stroke=INK, width=None, anchor="mm"):
    f = font(size)
    width = width if width is not None else max(8, size // 8)
    d.text((xy[0] + 7, xy[1] + 11), s, font=f, fill=(0, 0, 0), stroke_width=width, stroke_fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=f, fill=fill, stroke_width=width, stroke_fill=stroke, anchor=anchor)


im = Image.open(ROOT / "art_src/promo/b1_receipt_0.png").convert("RGB")
w, h = im.size
cw = w / 1.02
ch = cw * H / W
if ch > h:
    ch = h
    cw = ch * W / H
x0 = max(0, min(w - cw, 0.56 * w - cw / 2))
y0 = max(0, min(h - ch, 0.5 * h - ch / 2))
im = im.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS).convert("RGBA")
# a soft dark corner behind the number; the octopus and the girl stay clear
shade = Image.new("L", (W, H), 0)
px = shade.load()
for y in range(H):
    for x in range(W):
        k = max(0.0, min(1.0, (y - 480) / 420)) * max(0.0, min(1.0, (1500 - x) / 500))
        px[x, y] = int(190 * k)
im.paste(Image.new("RGBA", (W, H), (25, 14, 8, 255)), (0, 0), shade)
d = ImageDraw.Draw(im, "RGBA")
outlined(d, (430, 640), "总成本", 150, CREAM)
outlined(d, (640, 850), "31.7 刀", 300, GOLD)
stamp = Image.new("RGBA", (1000, 150), (0, 0, 0, 0))
s = ImageDraw.Draw(stamp)
s.rounded_rectangle((0, 0, 999, 149), 18, fill=(255, 248, 230, 248), outline=RED, width=9)
s.text((500, 75), "账单和源码全公开", font=font(100), fill=RED, anchor="mm")
stamp = stamp.rotate(2.5, expand=True, resample=Image.BICUBIC)
im.paste(stamp, (150, 1020), stamp)
im = im.convert("RGB")
im.save(OUT / "cover.png")
im.convert("RGB").resize((480, 300), Image.LANCZOS).save(OUT / "qa" / "cover_feed.jpg", quality=90)
print("ok")
