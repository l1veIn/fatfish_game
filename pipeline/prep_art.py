"""Turn generated white-background art (65535 gpt-image-2) into transparent game sprites
(repo root):
    python pipeline/prep_art.py <in.png|in_dir> <out.png|out_dir> [--height 256] [--thresh 38]
- the white backdrop is flood-filled from the borders, so white details inside the subject
  (maid apron, rice, eye highlights) survive; the edge is eroded 1 px and softened
- images that already come with transparency are only cropped
- cropped to content, optionally scaled to a fixed height
A directory processes every *.png in it ("name_0.png" from the image skill becomes "name.png").
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def key_white(path: str, thresh: int = 38) -> Image.Image:
    src = Image.open(path)
    if src.mode == "RGBA" and src.getchannel("A").getextrema()[0] < 16:
        # already transparent (gpt-image-2 sometimes returns a cut-out): just crop
        return src.crop(src.getbbox())
    im = src.convert("RGB")
    probe = im.copy()
    w, h = im.size
    sentinel = (255, 0, 255)
    step = max(w, h) // 40
    seeds = [(x, 0) for x in range(0, w, step)] + [(x, h - 1) for x in range(0, w, step)] + \
            [(0, y) for y in range(0, h, step)] + [(w - 1, y) for y in range(0, h, step)]
    for s in seeds:
        if probe.getpixel(s) != sentinel and min(probe.getpixel(s)) > 225:
            ImageDraw.floodfill(probe, s, sentinel, thresh=thresh)
    bg = np.all(np.asarray(probe) == sentinel, axis=2)
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out.crop(out.getbbox())


def fit_height(im: Image.Image, h: int) -> Image.Image:
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)


def main() -> None:
    args = [a for a in sys.argv[1:]]
    opt = lambda k, d: int(args[args.index(k) + 1]) if k in args else d
    height, thresh = opt("--height", 0), opt("--thresh", 38)
    src, dst = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or not args[i - 1].startswith("--"))][:2]
    if os.path.isdir(src):
        os.makedirs(dst, exist_ok=True)
        jobs = [(os.path.join(src, f), os.path.join(dst, f[:-6] + ".png" if f.endswith("_0.png") else f))
                for f in sorted(os.listdir(src)) if f.endswith(".png")]
    else:
        jobs = [(src, dst)]
    for a, b in jobs:
        im = key_white(a, thresh)
        if height:
            im = fit_height(im, height)
        im.save(b)
        print(f"{os.path.basename(a)} -> {b} {im.size}")


if __name__ == "__main__":
    main()
