"""Extract candidate animations from the cloned third-party fan projects into plain PNG frame
folders and render a side-by-side comparison (repo root):
    python pipeline/preview_third_party.py
Sources (cloned to art_src/third_party/, see CREDITS.md for licences):
  dsh      PC2005-cloud/dsh-pet               VP9-alpha WebM, 640x360 @ 24 fps -> sampled to 10 fps
  tnd      tndmgzo7/blue-fat-fish-desktop-pet  sprite atlas (256 px cells) + extra frame folders, 10 fps
  yun      YunYueSama/codex-deepseek-pet      grid sheets (512 px cells, story-* 384 px)
Frames go to art_src/third_party_frames/<source>/<anim>/NN.png (cropped to the shared bounding
box of the animation, so feet stay put). Previews: art_src/third_party_frames/compare.png (still
contact sheet) and compare_<source>.gif (all animations looping side by side).
"""
import json
import os
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TP = os.path.join(ROOT, "art_src", "third_party")
OUT = os.path.join(ROOT, "art_src", "third_party_frames")
FONT = os.path.join(ROOT, "art_src", "fonts", "NotoSansSC-VF.ttf")
BG = (12, 32, 66, 255)

DSH = ["待机呼吸休闲", "吃白饭", "吃Token", "是啊，吃什么", "深度思考碎碎念", "工作状态-忙碌点按",
       "余额-分文不剩", "打瞌睡被惊醒", "被吓一跳", "工作状态-雀跃庆祝"]
TND = ["idle", "ds_rice_slurp", "ds_token_nibble", "ds_beg_rice", "ds_bowl_sulk", "ds_not_fat",
       "ds_deep_think", "ds_outsource_nap", "ds_server_busy", "ds_shock_sit"]
TND_EXTRA = ["ds_full_belly_nobubble", "ds_swim_water"]
YUN = ["dense-idle", "dense-eat", "dense-sleep", "dense-dance", "story-meal", "story-token"]


def clean_alpha(im: Image.Image, floor: int = 24) -> Image.Image:
    """Drop the faint alpha noise some encoders leave over the whole frame."""
    a = im.getchannel("A").point(lambda v: 0 if v < floor else v)
    im.putalpha(a)
    return im


def crop_common(frames: list) -> list:
    box = None
    for f in frames:
        b = f.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return [f.crop(box) for f in frames] if box else frames


def save(src: str, anim: str, frames: list) -> None:
    d = os.path.join(OUT, src, anim)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    for i, f in enumerate(crop_common(frames)):
        f.save(os.path.join(d, f"{i:02d}.png"))
    print(f"{src}/{anim}: {len(frames)} frames")


def extract_dsh() -> None:
    tmp = os.path.join(OUT, "_tmp")
    for name in DSH:
        shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp)
        # libvpx-vp9 must be forced as the decoder, the native one drops the alpha plane
        subprocess.run(["ffmpeg", "-v", "error", "-c:v", "libvpx-vp9", "-i",
                        os.path.join(TP, "dsh-pet", "dsh-pet", "assets", "webm", name + ".webm"),
                        "-vf", "fps=10", os.path.join(tmp, "%03d.png")], check=True)
        frames = [clean_alpha(Image.open(os.path.join(tmp, f)).convert("RGBA")) for f in sorted(os.listdir(tmp))]
        save("dsh", name, frames)
    shutil.rmtree(tmp, ignore_errors=True)


def extract_tnd() -> None:
    base = os.path.join(TP, "blue-fat-fish-desktop-pet", "app", "assets")
    atlas = json.load(open(os.path.join(base, "atlas.json"), encoding="utf-8"))
    pages = [Image.open(os.path.join(base, p["image"])).convert("RGBA") for p in atlas["meta"]["pages"]]
    cell = atlas["meta"]["cell"]["w"]
    for name in TND:
        frames = []
        for fr in atlas["animations"][name]["frames"]:
            img = pages[fr.get("page", 0)].crop((fr["x"], fr["y"], fr["x"] + fr["w"], fr["y"] + fr["h"]))
            if fr.get("flip_x"):
                img = img.transpose(Image.FLIP_LEFT_RIGHT)
            c = Image.new("RGBA", (cell, cell))
            c.paste(img, (fr["offset_x"], fr["offset_y"]))
            frames.append(c)
        save("tnd", name, frames)
    for name in TND_EXTRA:
        d = os.path.join(base, "extra", name)
        frames = [Image.open(os.path.join(d, f)).convert("RGBA") for f in sorted(os.listdir(d)) if f.endswith(".png")]
        if not frames:   # some variants keep their frames one level down
            for sub in sorted(os.listdir(d)):
                p = os.path.join(d, sub)
                if os.path.isdir(p):
                    frames += [Image.open(os.path.join(p, f)).convert("RGBA") for f in sorted(os.listdir(p)) if f.endswith(".png")]
        save("tnd", name, frames)


def extract_yun() -> None:
    base = os.path.join(TP, "codex-deepseek-pet", "assets", "whale")
    for name in YUN:
        sheet = Image.open(os.path.join(base, name + ".png")).convert("RGBA")
        cell = 384 if name.startswith("story-") else 512   # story sheets are 4 x 8 cells of 384 px
        frames = []
        for y in range(0, sheet.height, cell):
            for x in range(0, sheet.width, cell):
                c = sheet.crop((x, y, x + cell, y + cell))
                if c.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox():
                    frames.append(c)
        save("yun", name, frames)


def _frames(src: str, anim: str) -> list:
    d = os.path.join(OUT, src, anim)
    return [Image.open(os.path.join(d, f)) for f in sorted(os.listdir(d))]


def _fit(im: Image.Image, h: int) -> Image.Image:
    s = h / im.height
    if im.width * s > h * 1.8:
        s = h * 1.8 / im.width
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def render() -> None:
    font = ImageFont.truetype(FONT, 22)
    small = ImageFont.truetype(FONT, 17)
    groups = [("dsh", "PC2005-cloud/dsh-pet（WebM 640×360，禁止商用，需署名）", DSH),
              ("tnd", "tndmgzo7/blue-fat-fish-desktop-pet（256px 图集，CC BY-NC-SA 4.0）", TND + TND_EXTRA),
              ("yun", "YunYueSama/codex-deepseek-pet（512px 网格，署名许可 1.0）", YUN)]
    # still sheet: per animation, 5 evenly spaced frames
    H, N = 150, 5
    rows = []
    for src, title, anims in groups:
        rows.append(("title", title))
        for a in anims:
            rows.append((src, a))
    width = 260 + N * (H * 1.8 + 10)
    sheet = Image.new("RGBA", (int(width), sum(44 if r[0] == "title" else H + 14 for r in rows) + 20), BG)
    d = ImageDraw.Draw(sheet)
    y = 10
    for src, a in rows:
        if src == "title":
            d.text((12, y + 8), a, font=font, fill=(255, 230, 150))
            y += 44
            continue
        fr = _frames(src, a)
        d.text((12, y + H // 2 - 20), a, font=small, fill=(220, 232, 255))
        d.text((12, y + H // 2 + 4), f"{len(fr)} 帧", font=small, fill=(140, 160, 200))
        x = 260
        for i in range(N):
            im = _fit(fr[round(i * (len(fr) - 1) / max(N - 1, 1))], H)
            sheet.alpha_composite(im, (int(x), y + (H - im.height)))
            x += H * 1.8 + 10
        y += H + 14
    sheet.convert("RGB").save(os.path.join(OUT, "compare.png"))
    # one looping GIF per source: every animation in a grid cell, 10 fps
    for src, title, anims in groups:
        cols, CH = 4 if len(anims) > 6 else 3, 220
        cw = int(CH * 1.6)
        rws = (len(anims) + cols - 1) // cols
        clips = {a: [_fit(f, CH - 34) for f in _frames(src, a)] for a in anims}
        n = max(len(c) for c in clips.values())
        out = []
        for t in range(n):
            g = Image.new("RGBA", (cols * cw, rws * CH), BG)
            gd = ImageDraw.Draw(g)
            for k, a in enumerate(anims):
                cx, cy = (k % cols) * cw, (k // cols) * CH
                f = clips[a][t % len(clips[a])]
                g.alpha_composite(f, (cx + (cw - f.width) // 2, cy + CH - 8 - f.height))
                gd.text((cx + 8, cy + 4), a, font=small, fill=(220, 232, 255))
            out.append(g.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT))
        out[0].save(os.path.join(OUT, f"compare_{src}.gif"), save_all=True, append_images=out[1:], duration=100, loop=0)
        print(f"compare_{src}.gif: {n} frames")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    extract_dsh()
    extract_tnd()
    extract_yun()
    render()
