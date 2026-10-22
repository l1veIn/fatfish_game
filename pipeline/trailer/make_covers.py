"""Bilibili covers for the short promo (2026-10-22): 1920x1200 (16:10), key content kept inside the
centred 4:3 area that some feeds crop to. Output build/promo3-20261022/cover_*.png"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/promo3-20261022'
FONT = str(ROOT / 'art_src/fonts/ZCOOLKuaiLe-Regular.ttf')
W, H = 1920, 1200
INK, CREAM, GOLD, RED, CHALK = (59, 36, 22), (255, 241, 207), (255, 206, 115), (210, 58, 46), (245, 245, 230)

def art(name, zoom, cx, cy):
    im = Image.open(ROOT / f'art_src/promo/{name}.png').convert('RGB')
    w, h = im.size
    cw = w / zoom; ch = cw * H / W
    x0 = min(max(cx * w - cw / 2, 0), w - cw); y0 = min(max(cy * h - ch / 2, 0), h - ch)
    return im.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS)

def text(d, xy, s, size, fill, stroke=INK, sw=None, anchor='la'):
    f = ImageFont.truetype(FONT, size)
    sw = sw if sw is not None else max(6, size // 9)
    d.text((xy[0] + 6, xy[1] + 10), s, font=f, fill=(0, 0, 0), stroke_width=sw, stroke_fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=f, fill=fill, stroke_width=sw, stroke_fill=stroke, anchor=anchor)

# A: the chalkboard joke (the bit the author liked): today's plan, 1. reach AGI, 2. eat first.
im = art('p1_hungry_0', 1.25, 0.66, 0.5)
board = Image.open(ROOT / 'game/assets/canteen/ui_chalkboard.png').convert('RGBA').resize((980, 590), Image.LANCZOS)
im.paste(board, (150, 150), board)
d = ImageDraw.Draw(im)
f = lambda s: ImageFont.truetype(FONT, s)
d.text((250, 250), '今日计划', font=f(100), fill=CHALK)
d.line((250, 372, 660, 376), fill=CHALK, width=6)
d.text((250, 410), '1. 实现 AGI', font=f(92), fill=CHALK)
# struck out in chalk: her real priority is item 2
d.line((240, 470, 760, 452), fill=(255, 140, 120), width=9)
d.text((250, 545), '2. 先吃饭！', font=f(118), fill=GOLD)
im.save(OUT / 'cover_a_chalkboard.png')

# B: the action shot with the title promise
im = art('p3_catch_0', 1.1, 0.55, 0.5)
d = ImageDraw.Draw(im)
text(d, (960, 120), '大肥鱼吃白饭模拟器', 150, CREAM, anchor='ma')
f2 = ImageFont.truetype(FONT, 96)
box = d.textbbox((0, 0), '免费玩 · 喂饱她 = AGI？', font=f2)
bw, bh = box[2] - box[0] + 80, box[3] - box[1] + 50
stamp = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
sd = ImageDraw.Draw(stamp)
sd.rounded_rectangle((0, 0, bw - 1, bh - 1), 18, fill=(255, 248, 230, 240), outline=RED, width=9)
sd.text((40, 18 - box[1]), '免费玩 · 喂饱她 = AGI？', font=f2, fill=RED)
stamp = stamp.rotate(4, expand=True, resample=Image.BICUBIC)
im.paste(stamp, (W // 2 - stamp.width // 2 - 330, 880), stamp)
im.save(OUT / 'cover_b_action.png')
# preview at feed size, both side by side
prev = Image.new('RGB', (2 * 480 + 30, 300 + 20), (30, 30, 30))
for i, n in enumerate(['cover_a_chalkboard', 'cover_b_action']):
    prev.paste(Image.open(OUT / f'{n}.png').resize((480, 300), Image.LANCZOS), (10 + i * 500, 10))
prev.save(OUT / 'cover_preview_feed.jpg', quality=90)
print('ok')
