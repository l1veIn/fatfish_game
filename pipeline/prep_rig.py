"""Build the 大肥鱼 rig textures from art_src/rig/ (repo root):  python pipeline/prep_rig.py [--preview] [--seat] [--props]

- master_0.png (2048 px) -> game/assets/fatfish/rig/body.png, scaled to BODY_PX. The game draws
  it as one subdivided mesh and bends regions of it in a shader (head tilt, breathing, hair /
  tail / fin / ahoge sway: see game/scripts/ui/fish_rig.gd), so nothing is ever cut apart and
  there are no seams.
- ex_*_0.png are whole-head variants drawn from ref_head.png (the master's head crop). Each is
  aligned to the master head (scale + offset, found by matching the hair and headdress, which
  are the same in every variant), then only the face patch (eyes, cheeks, mouth) is kept, with
  feathered edges -> game/assets/fatfish/rig/face_<name>.png, all the same size, drawn at
  FACE_RECT over the body.
- writes game/data/fish_rig.json: sizes and the face rect in body-texture pixels.
- a second rig, "seat" (the shift: waist up, holding her iron basin), works the same way from
  seat_0.png + sx_*_0.png -> game/assets/fatfish/rig_seat/, and adds POSES: sp_*_0.png are the
  whole seated figure redrawn with other arms / basin / expression. Each is aligned to seat_0
  (on the top of the head), and only the pixels that really differ are taken from it (a
  cleaned, feathered difference mask), the rest stays the master -> pose_<name>.png, a full
  replacement of body.png that the game swaps in. -> game/data/fish_rig_seat.json
--preview writes art_src/rig/_faces.png (and _seat_faces.png, _seat_poses.png).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage, optimize

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "art_src", "rig")
OUT = os.path.join(ROOT, "game", "assets", "fatfish", "rig")
DATA = os.path.join(ROOT, "game", "data", "fish_rig.json")

BODY_PX = 1024                 # body texture size (the master is 2048; 1024 is plenty for 700 px on screen)
HEAD_CROP = (460, 0, 1620, 1160)   # ref_head.png = master.crop(HEAD_CROP)
FACE = (780, 520, 1270, 840)       # face patch in master pixels: eyes, cheeks, mouth
FEATHER = 22                       # px (master scale) of soft edge around the patch
# the master's hands came out with too few fingers: ref_handL/R.png are these crops of the
# master, handL2/R2_0.png their redraws (gen_rig.sh hands); HAND_PATCH is the area pasted back,
# in crop pixels
HAND_CROPS = {"L": (360, 1120, 800, 1560), "R": (1260, 1120, 1700, 1560)}
HAND_PICK = {"L": "handL2_0.png", "R": "handR2_0.png"}
HAND_PATCH = {"L": (80, 130, 310, 300), "R": (160, 130, 380, 300)}
EXPR = ["blink", "happy", "chew", "open", "puppy", "pout", "surprised", "sleepy", "think"]


def load(name: str) -> Image.Image:
    return Image.open(os.path.join(SRC, name)).convert("RGBA")


def align(variant: Image.Image, ref: Image.Image, exclude=None, keep=None) -> tuple:
    """Scale and offset that put `variant` (any size) onto `ref`'s canvas. Matches on the
    region outside the face (hair, headdress, fins), which should be identical; `keep` (ref
    pixels) limits the match to that box."""
    ref_small = np.asarray(ref.resize((290, 290), Image.LANCZOS)).astype(np.float32) / 255.0
    ex = exclude or (FACE[0] - HEAD_CROP[0], FACE[1] - HEAD_CROP[1], FACE[2] - HEAD_CROP[0], FACE[3] - HEAD_CROP[1])
    fx0, fy0, fx1, fy1 = ex[0] / ref.width, ex[1] / ref.height, ex[2] / ref.width, ex[3] / ref.height
    weight = (ref_small[..., 3] > 0.5).astype(np.float32)
    weight[int(fy0 * 290):int(fy1 * 290), int(fx0 * 290):int(fx1 * 290)] = 0.0   # ignore the face
    if keep is not None:
        box = np.zeros_like(weight)
        box[int(keep[1] / ref.height * 290):int(keep[3] / ref.height * 290), int(keep[0] / ref.width * 290):int(keep[2] / ref.width * 290)] = 1.0
        weight *= box

    variant = variant.resize((580, 580), Image.BILINEAR)   # align at low resolution: fast

    def warp(p) -> np.ndarray:
        s, dx, dy = p
        # variant pixel -> ref canvas: ref = s * var + (dx, dy), in ref-canvas fractions
        w = variant.width
        m = (1.0 / s, 0.0, -dx * w / s, 0.0, 1.0 / s, -dy * w / s)
        im = variant.transform(variant.size, Image.AFFINE, m, Image.BILINEAR)
        return np.asarray(im.resize((290, 290), Image.BILINEAR)).astype(np.float32) / 255.0

    def cost(p) -> float:
        v = warp(p)
        d = np.abs(v[..., :3] - ref_small[..., :3]).mean(axis=2) + np.abs(v[..., 3] - ref_small[..., 3])
        return float((d * weight).sum() / weight.sum())

    # coarse search on the offset, then refine all three
    best = (1e9, (1.0, 0.0, 0.0))
    for s in (0.94, 0.97, 1.0, 1.03, 1.06):
        for dx in np.linspace(-0.05, 0.05, 6):
            for dy in np.linspace(-0.05, 0.05, 6):
                c = cost((s, dx, dy))
                if c < best[0]:
                    best = (c, (s, dx, dy))
    res = optimize.minimize(cost, best[1], method="Nelder-Mead",
                            options={"xatol": 1e-4, "fatol": 1e-5, "maxiter": 200, "initial_simplex": None})
    return tuple(res.x), res.fun, best[0]


def face_patch(variant: Image.Image, ref: Image.Image, p: tuple, face=None, head=None) -> Image.Image:
    face = face or FACE
    head = head or HEAD_CROP
    s, dx, dy = p
    w = variant.width
    m = (1.0 / s, 0.0, -dx * w / s, 0.0, 1.0 / s, -dy * w / s)
    on_ref = variant.transform(variant.size, Image.AFFINE, m, Image.BICUBIC).resize(ref.size, Image.LANCZOS)
    box = (face[0] - head[0], face[1] - head[1], face[2] - head[0], face[3] - head[1])
    patch = on_ref.crop(box)
    # soft rectangular edge (the face skin is flat, so a feathered edge blends invisibly)
    mask = Image.new("L", patch.size, 0)
    mask.paste(255, (FEATHER, FEATHER, patch.width - FEATHER, patch.height - FEATHER))
    mask = mask.filter(ImageFilter.GaussianBlur(FEATHER / 2))
    a = np.minimum(np.asarray(patch.getchannel("A")), np.asarray(mask))
    patch.putalpha(Image.fromarray(a.astype(np.uint8)))
    return patch


def fix_hands(master: Image.Image) -> Image.Image:
    """Paste the redrawn hands into the master: align each redraw to its crop, colour-match it
    to the master around the patch (the redraws come out a little lighter), feathered paste."""
    out = master.copy()
    for side, box in HAND_CROPS.items():
        ref = master.crop(box)
        var = load(HAND_PICK[side])
        hp = HAND_PATCH[side]
        p, err, _ = align(var, ref, hp)
        s, dx, dy = p
        w = var.width
        m = (1.0 / s, 0.0, -dx * w / s, 0.0, 1.0 / s, -dy * w / s)
        on = var.transform(var.size, Image.AFFINE, m, Image.BICUBIC).resize(ref.size, Image.LANCZOS)
        a = np.asarray(on).astype(np.float32)
        r = np.asarray(ref).astype(np.float32)
        # colour match on a ring around the patch where both are opaque
        ring = np.zeros(ref.size[::-1], bool)
        x0, y0, x1, y1 = hp
        ring[max(0, y0 - 40):y1 + 40, max(0, x0 - 40):x1 + 40] = True
        ring[y0:y1, x0:x1] = False
        ring &= (a[..., 3] > 200) & (r[..., 3] > 200)
        for c in range(3):
            A = np.vstack([a[..., c][ring], np.ones(ring.sum())]).T
            k, b = np.linalg.lstsq(A, r[..., c][ring], rcond=None)[0]
            a[..., c] = np.clip(a[..., c] * k + b, 0, 255)
        mask = Image.new("L", ref.size, 0)
        mask.paste(255, (x0 + 14, y0 + 14, x1 - 14, y1 - 14))
        mask = np.asarray(mask.filter(ImageFilter.GaussianBlur(9))).astype(np.float32)[..., None] / 255.0
        merged = r * (1.0 - mask) + a * mask
        out.paste(Image.fromarray(merged.astype(np.uint8), "RGBA"), box[:2])
        print(f"hand {side}: align err {err:.4f}")
    return out


SEAT_HEAD = (480, 0, 1580, 1100)     # ref_seat_head.png = seat_0.crop(SEAT_HEAD)
SEAT_FACE = (700, 740, 1340, 1120)   # seated face patch, in seat_0 pixels
SEAT_EXPR = ["blink", "happy", "chew", "open", "puppy", "pout", "surprised", "sleepy", "think", "star",
             "blank", "jitome", "stuffed", "o", "tear",   # (deadpan set, v2)
             "grimace", "grok"]   # 顿悟: forcing greens down, then getting it (round 3)
NO_ALIGN = ["sulk"]   # the basin covers the top of the head we align on; the redraw keeps the framing
SEAT_POSES = ["eat_lift", "eat_scoop", "bang_up", "bang_down", "sulk", "full", "think"]   # (cheer: cut off at the top, unused)
SEAT_OUT = os.path.join(ROOT, "game", "assets", "fatfish", "rig_seat")
SEAT_DATA = os.path.join(ROOT, "game", "data", "fish_rig_seat.json")


def pose_layer(variant: Image.Image, master: Image.Image, no_align=False) -> tuple:
    """The parts of a redrawn pose that differ from the master, aligned on the top of the head."""
    p, err = ((1.0, 0.0, 0.0), 0.0) if no_align else align(variant, master, (0, 820, master.width, master.height))[:2]
    s_, dx, dy = p
    w = variant.width
    m = (1.0 / s_, 0.0, -dx * w / s_, 0.0, 1.0 / s_, -dy * w / s_)
    on = variant.transform(variant.size, Image.AFFINE, m, Image.BICUBIC).resize(master.size, Image.LANCZOS)
    a = np.asarray(on).astype(np.float32) / 255.0
    b = np.asarray(master).astype(np.float32) / 255.0
    # premultiplied colour difference, blurred so line-art wobble does not count
    da = a[..., :3] * a[..., 3:4] - b[..., :3] * b[..., 3:4]
    diff = np.abs(da).mean(axis=2) + np.abs(a[..., 3] - b[..., 3]) * 0.5
    diff = ndimage.gaussian_filter(diff, 4)
    mask = diff > 0.07
    mask = ndimage.binary_closing(mask, iterations=8)
    mask = ndimage.binary_fill_holes(mask)
    lab, n = ndimage.label(mask)
    if n:
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        keep = [i + 1 for i, sz in enumerate(sizes) if sz > 4000]
        mask = np.isin(lab, keep)
    mask = ndimage.binary_dilation(mask, iterations=14)
    soft = ndimage.gaussian_filter(mask.astype(np.float32), 7)
    # the layer is drawn over the master, so it can only add: a pose must keep its arms where
    # the master has none (the generated poses keep the hair behind them, which covers that)
    # a full replacement of the master: the pose inside the mask (transparency included, so
    # an arm that moved away really disappears), the master outside it (so the hair never pops)
    m3 = soft[..., None]
    out = b * (1.0 - m3) + a * m3
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA"), err, float(mask.mean())


def build_seat(preview: bool) -> None:
    if not os.path.exists(os.path.join(SRC, "seat_0.png")):
        return
    os.makedirs(SEAT_OUT, exist_ok=True)
    master = load("seat_0.png")
    k = BODY_PX / master.width
    master.resize((BODY_PX, BODY_PX), Image.LANCZOS).save(os.path.join(SEAT_OUT, "body.png"))
    ref = load("ref_seat_head.png")
    face_px = (round((SEAT_FACE[2] - SEAT_FACE[0]) * k), round((SEAT_FACE[3] - SEAT_FACE[1]) * k))
    faces, poses, sheet, psheet = {}, {}, [], []
    for name in SEAT_EXPR:
        f = f"sx_{name}_0.png"
        if not os.path.exists(os.path.join(SRC, f)):
            print("missing", f)
            continue
        var = load(f)
        sface = (SEAT_FACE[0] - SEAT_HEAD[0], SEAT_FACE[1] - SEAT_HEAD[1], SEAT_FACE[2] - SEAT_HEAD[0], SEAT_FACE[3] - SEAT_HEAD[1])
        p, err, _ = align(var, ref, sface)
        patch = face_patch(var, ref, p, SEAT_FACE, SEAT_HEAD)
        patch.resize(face_px, Image.LANCZOS).save(os.path.join(SEAT_OUT, f"face_{name}.png"))
        faces[name] = {"err": round(err, 4)}
        print(f"seat face {name:10s} err {err:.4f} scale {p[0]:.3f}")
        if preview:
            m = master.copy()
            m.alpha_composite(patch, (SEAT_FACE[0], SEAT_FACE[1]))
            bg = Image.new("RGBA", (800, 560), (70, 60, 55, 255))
            bg.alpha_composite(m.crop((620, 660, 1420, 1220)))
            sheet.append(bg)
    for name in SEAT_POSES:
        f = f"sp_{name}_0.png"
        if not os.path.exists(os.path.join(SRC, f)):
            print("missing", f)
            continue
        layer, err, cover = pose_layer(load(f), master, name in NO_ALIGN)
        layer.resize((BODY_PX, BODY_PX), Image.LANCZOS).save(os.path.join(SEAT_OUT, f"pose_{name}.png"))
        poses[name] = {"err": round(err, 4), "cover": round(cover, 3)}
        print(f"seat pose {name:10s} err {err:.4f} covers {cover:.0%}")
        if preview:
            bg = Image.new("RGBA", layer.size, (70, 60, 55, 255))
            bg.alpha_composite(layer)
            psheet.append(bg.resize((512, 512)))
    json.dump({"body_px": BODY_PX, "face_rect": [round(SEAT_FACE[0] * k), round(SEAT_FACE[1] * k), face_px[0], face_px[1]],
               "faces": faces, "poses": poses}, open(SEAT_DATA, "w", encoding="utf-8", newline="\n"), indent=1)
    for items, name, cols, tile in ((sheet, "_seat_faces.png", 4, (810, 570)), (psheet, "_seat_poses.png", 4, (520, 520))):
        if items:
            rows = (len(items) + cols - 1) // cols
            out = Image.new("RGB", (cols * tile[0], rows * tile[1]), (30, 30, 30))
            for i, t in enumerate(items):
                out.paste(t.convert("RGB"), ((i % cols) * tile[0], (i // cols) * tile[1]))
            out.save(os.path.join(SRC, name))


CREW = ["wen", "pu", "g", "ke", "zi", "ge"]
CREW_OUT = os.path.join(ROOT, "game", "assets", "crew")


def build_crew() -> None:
    """外包 helpers: crew_<id>_0.png (gen_rig.sh crew) cropped and scaled to 320 px tall."""
    os.makedirs(CREW_OUT, exist_ok=True)
    for cid in CREW:
        f = os.path.join(SRC, f"crew_{cid}_0.png")
        if not os.path.exists(f):
            print("missing crew", cid)
            continue
        im = Image.open(f).convert("RGBA")
        im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
        k = 320 / im.height
        im.resize((max(1, round(im.width * k)), 320), Image.LANCZOS).save(os.path.join(CREW_OUT, f"{cid}.png"))
        # asleep / running / cheering (gen_rig.sh crew_sleep, round3): same scale as awake, so
        # she stays the same size in every pose
        for pose in ("sleep", "run", "cheer"):
            fs = os.path.join(SRC, f"crew_{cid}_{pose}_0.png")
            if os.path.exists(fs):
                sl = Image.open(fs).convert("RGBA")
                sl = sl.crop(sl.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
                sl.resize((max(1, round(sl.width * k)), max(1, round(sl.height * k))), Image.LANCZOS).save(os.path.join(CREW_OUT, f"{cid}_{pose}.png"))
    print("crew ->", CREW_OUT)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    master = fix_hands(load("master_0.png"))
    master.save(os.path.join(SRC, "master_fixed.png"))
    k = BODY_PX / master.width
    master.resize((BODY_PX, BODY_PX), Image.LANCZOS).save(os.path.join(OUT, "body.png"))
    ref = load("ref_head.png")
    face_px = (round((FACE[2] - FACE[0]) * k), round((FACE[3] - FACE[1]) * k))
    faces = {}
    sheet = []
    for name in EXPR:
        path = os.path.join(SRC, f"ex_{name}_0.png")
        if not os.path.exists(path):
            print("missing", name)
            continue
        var = load(f"ex_{name}_0.png")
        p, err, coarse = align(var, ref)
        patch = face_patch(var, ref, p)
        patch.resize(face_px, Image.LANCZOS).save(os.path.join(OUT, f"face_{name}.png"))
        faces[name] = {"err": round(err, 4), "scale": round(p[0], 4), "dx": round(p[1], 4), "dy": round(p[2], 4)}
        print(f"{name:10s} align err {err:.4f} (coarse {coarse:.4f}) scale {p[0]:.3f} offset {p[1]:+.3f} {p[2]:+.3f}")
        if "--preview" in sys.argv:
            m = master.copy()
            m.alpha_composite(patch, (FACE[0], FACE[1]))
            bg = Image.new("RGBA", (700, 560), (70, 60, 55, 255))
            bg.alpha_composite(m.crop((660, 360, 1360, 920)))
            sheet.append(bg)
    json.dump({"body_px": BODY_PX, "face_rect": [round(FACE[0] * k), round(FACE[1] * k), face_px[0], face_px[1]],
               "faces": faces}, open(DATA, "w", encoding="utf-8", newline="\n"), indent=1)
    if sheet:
        cols = 3
        rows = (len(sheet) + cols - 1) // cols
        out = Image.new("RGB", (cols * 710, rows * 570), (30, 30, 30))
        for i, t in enumerate(sheet):
            out.paste(t.convert("RGB"), ((i % cols) * 710, (i // cols) * 570))
        out.save(os.path.join(SRC, "_faces.png"))
        print("preview -> art_src/rig/_faces.png")


## The third rig, "basin" (title screen before V4: standing, deadpan, holding her iron basin):
## gen_rig.sh stand_basin redraws of the standing master. Each is moved onto the master's canvas
## (the body on its head, the basin helmet on face, fins and shoulders) so the standing rig's
## shader regions and face patches fit -> game/assets/fatfish/rig_basin/ + fish_rig_basin.json.
BASIN_OUT = os.path.join(ROOT, "game", "assets", "fatfish", "rig_basin")
BASIN_DATA = os.path.join(ROOT, "game", "data", "fish_rig_basin.json")
BASIN_BODY = "stand_basin_a_0.png"
BASIN_POSES = {"sulk": ("stand_helmet_a_0.png", (460, 600, 1620, 1160))}   # pose: (drawing, match box: eyes and fins)
BASIN_FACES = ["blank", "jitome"]            # new ex_*; pout and blink come from the standing rig


def on_canvas(var: Image.Image, ref: Image.Image, p: tuple) -> Image.Image:
    s, dx, dy = p
    w = var.width
    m = (1.0 / s, 0.0, -dx * w / s, 0.0, 1.0 / s, -dy * w / s)
    return var.transform(var.size, Image.AFFINE, m, Image.BICUBIC).resize(ref.size, Image.LANCZOS)


def build_basin() -> None:
    if not os.path.exists(os.path.join(SRC, BASIN_BODY)):
        return
    os.makedirs(BASIN_OUT, exist_ok=True)
    master = load("master_fixed.png")
    k = BODY_PX / master.width
    var = load(BASIN_BODY)
    p, err, _ = align(var, master, keep=(0, 0, master.width, HEAD_CROP[3]))
    print(f"basin body err {err:.4f} scale {p[0]:.3f} offset {p[1]:+.3f} {p[2]:+.3f}")
    on_canvas(var, master, p).resize((BODY_PX, BODY_PX), Image.LANCZOS).save(os.path.join(BASIN_OUT, "body.png"))
    poses = {}
    for name, (f, box) in BASIN_POSES.items():
        var = load(f)
        p, err, _ = align(var, master, exclude=(0, 0, 1, 1), keep=box)   # the eyes are what must not jump
        print(f"basin pose {name} err {err:.4f} scale {p[0]:.3f} offset {p[1]:+.3f} {p[2]:+.3f}")
        on_canvas(var, master, p).resize((BODY_PX, BODY_PX), Image.LANCZOS).save(os.path.join(BASIN_OUT, f"pose_{name}.png"))
        poses[name] = {"err": round(err, 4)}
    ref = load("ref_head.png")
    face_px = (round((FACE[2] - FACE[0]) * k), round((FACE[3] - FACE[1]) * k))
    faces = {}
    for name in BASIN_FACES:
        var = load(f"ex_{name}_0.png")
        p, err, _ = align(var, ref)
        face_patch(var, ref, p).resize(face_px, Image.LANCZOS).save(os.path.join(BASIN_OUT, f"face_{name}.png"))
        faces[name] = {"err": round(err, 4)}
        print(f"basin face {name} err {err:.4f}")
    for name in ("pout", "blink"):
        Image.open(os.path.join(OUT, f"face_{name}.png")).save(os.path.join(BASIN_OUT, f"face_{name}.png"))
        faces[name] = {}
    json.dump({"body_px": BODY_PX, "face_rect": [round(FACE[0] * k), round(FACE[1] * k), face_px[0], face_px[1]],
               "faces": faces, "poses": poses}, open(BASIN_DATA, "w", encoding="utf-8", newline="\n"), indent=1)


## Single sprites around the rig (gen_rig.sh lie): trimmed to their pixels, scaled to fit `px`.
##   fatfish/lie_full.png  吃饱躺平, on the table at closing time and on the result card
##   ui/cursor_*.png       title-screen cursors (patting hand, spoon for the basin helmet)
PROPS = {"lie_a_0.png": ("fatfish/lie_full.png", 900), "cursor_hand_0.png": ("ui/cursor_hand.png", 64),
         "cursor_spoon_0.png": ("ui/cursor_spoon.png", 64)}


def blink_flat(rig: str, data: str, split: float) -> None:
    """Face "blink_flat": the closed eyes of face_blink over the flat mouth of face_blank (rows
    below `split` of the patch), so the deadpan face can blink without flashing a smile."""
    d = os.path.join(ROOT, "game", "assets", "fatfish", rig)
    bl = np.asarray(Image.open(os.path.join(d, "face_blink.png")).convert("RGBA")).astype(np.float32)
    bk = np.asarray(Image.open(os.path.join(d, "face_blank.png")).convert("RGBA")).astype(np.float32)
    w = np.clip((np.arange(bl.shape[0]) - split) / 10.0, 0.0, 1.0)[:, None, None]
    Image.fromarray((bl * (1 - w) + bk * w).round().astype(np.uint8)).save(os.path.join(d, "face_blink_flat.png"))
    path = os.path.join(ROOT, "game", "data", data)
    info = json.load(open(path, encoding="utf-8"))
    if "blink_flat" not in info["faces"]:
        info["faces"]["blink_flat"] = {}
        json.dump(info, open(path, "w", encoding="utf-8", newline="\n"), indent=1)
    print(rig, "face_blink_flat.png")


def build_props() -> None:
    blink_flat("rig_seat", "fish_rig_seat.json", 122.0)   # eyes above row ~122 of the patch, mouth below
    blink_flat("rig_basin", "fish_rig_basin.json", 102.0)
    for src, (dst, px) in PROPS.items():
        path = os.path.join(SRC, src)
        if not os.path.exists(path):
            print("missing", src)
            continue
        im = Image.open(path).convert("RGBA")
        im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
        im.thumbnail((px, px), Image.LANCZOS)
        im.save(os.path.join(ROOT, "game", "assets", dst))
        print(f"{src} -> {dst} {im.size}")


if __name__ == "__main__":
    if "--props" in sys.argv:
        build_basin()
        build_props()
        sys.exit()
    if "--seat" not in sys.argv:
        main()
    build_seat("--preview" in sys.argv)
    build_crew()
    build_basin()
    build_props()
