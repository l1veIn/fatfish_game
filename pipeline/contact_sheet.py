"""Numbered thumbnail grid of one rendered animation, for picking split/hit frames.
Usage: python pipeline/contact_sheet.py <frames_dir>/<anim> <out.png> [cols] [thumb_px]"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 12
tp = int(sys.argv[4]) if len(sys.argv) > 4 else 150
files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * tp, rows * tp), (45, 60, 60, 255))
font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(os.path.join(src, f)).convert("RGBA")
    w, h = im.size
    im = im.crop((w * 0.12, h * 0.12, w * 0.88, h * 0.95)).resize((tp, tp))
    x, y = (i % cols) * tp, (i // cols) * tp
    sheet.alpha_composite(im, (x, y))
    d.text((x + 4, y + 2), str(i), fill=(255, 230, 120), font=font)
sheet.save(out)
print(len(files), "frames")
