"""Pack the chosen 大肥鱼 animations into grid sprite sheets for Godot (repo root):
    python pipeline/pack_fish_anims.py          # needs art_src/third_party/ (clones) and
                                                # art_src/third_party_frames/ (preview_third_party.py)
Writes game/assets/fatfish/anims/<name>.png (frames left->right, top->bottom) and
game/data/fish_anims.json: {name: {sheet, w, h, cols, frames, fps, loop, loop_from, loop_to, pivot}}.
`loop_from`/`loop_to` (inclusive) is the section that repeats after the intro plays once
(the whole clip when absent and loop is true). `pivot` is the feet point inside a frame.
Sources and licences: see CREDITS.md. Every packed clip is listed there with its origin.
"""
import json
import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TND = os.path.join(ROOT, "art_src", "third_party", "blue-fat-fish-desktop-pet", "app", "assets")
FRAMES = os.path.join(ROOT, "art_src", "third_party_frames")
OUT = os.path.join(ROOT, "game", "assets", "fatfish", "anims")
MANIFEST = os.path.join(ROOT, "game", "data", "fish_anims.json")

# game name -> source. tnd clips keep their 256 px cells (shared feet line y=244), so they can
# be swapped on one sprite without jumping; dsh / yun clips are cropped and pivot bottom-centre.
CLIPS = {
    # during a shift (tndmgzo7/blue-fat-fish-desktop-pet, CC BY-NC-SA 4.0)
    "idle":         ("tnd", "idle"),
    "nibble":       ("tnd", "ds_token_nibble"),
    "slurp":        ("tnd", "ds_rice_slurp"),
    "think":        ("tnd", "ds_deep_think"),
    "outsource":    ("tnd", "ds_outsource_nap"),
    "beg":          ("tnd", "ds_beg_rice"),
    "happy":        ("tnd", "happy_jump"),
    "not_fat":      ("tnd", "ds_not_fat"),
    "full_belly":   ("tnd_extra", "ds_full_belly_nobubble"),
    "basin":        ("tnd", "ds_basin"),     # lifts the iron basin, wears it, it slips over her eyes
    # bonus clips (PC2005-cloud/dsh-pet, non-commercial, link back required)
    "eat_rice":     ("dsh", "吃白饭"),
    "broke":        ("dsh", "余额-分文不剩"),
    # big close-up (YunYueSama/codex-deepseek-pet, 大肥鱼项目署名许可 1.0)
    "title_idle":   ("yun", "dense-idle"),
}
DSH_FPS = 10      # preview_third_party.py samples the 24 fps videos at 10 fps
YUN_FPS = 10


def tnd_clip(name: str) -> tuple:
    atlas = json.load(open(os.path.join(TND, "atlas.json"), encoding="utf-8"))
    pages = [Image.open(os.path.join(TND, p["image"])).convert("RGBA") for p in atlas["meta"]["pages"]]
    a = atlas["animations"][name]
    frames = []
    for fr in a["frames"]:
        img = pages[fr.get("page", 0)].crop((fr["x"], fr["y"], fr["x"] + fr["w"], fr["y"] + fr["h"]))
        if fr.get("flip_x"):
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        c = Image.new("RGBA", (256, 256))
        c.paste(img, (fr["offset_x"], fr["offset_y"]))
        frames.append(c)
    meta = {"fps": a.get("fps", 10), "loop": bool(a.get("loop", False)), "pivot": [128, 244]}
    if "loop_section" in a:
        meta["loop_from"], meta["loop_to"] = a["loop_section"]
    return frames, meta


def tnd_extra(name: str) -> tuple:
    d = os.path.join(TND, "extra", name)
    timing = json.load(open(os.path.join(TND, "extra", "ds_full_belly", "timing.json"), encoding="utf-8"))
    frames = [Image.open(os.path.join(d, f)).convert("RGBA") for f in sorted(os.listdir(d)) if f.endswith(".png")]
    ls = timing["loop_section"]
    return frames, {"fps": timing["fps"], "loop": False, "pivot": [128, timing["baseline_y"]],
                    "loop_from": ls["start"], "loop_to": ls["end_exclusive"] - 1}


def cropped(src: str, name: str, fps: int, loop: bool) -> tuple:
    d = os.path.join(FRAMES, src, name)
    frames = [Image.open(os.path.join(d, f)).convert("RGBA") for f in sorted(os.listdir(d))]
    w, h = frames[0].size
    return frames, {"fps": fps, "loop": loop, "pivot": [w // 2, h]}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    for game_name, (src, name) in CLIPS.items():
        if src == "tnd":
            frames, meta = tnd_clip(name)
        elif src == "tnd_extra":
            frames, meta = tnd_extra(name)
        elif src == "dsh":
            frames, meta = cropped("dsh", name, DSH_FPS, True)
        else:
            frames, meta = cropped("yun", name, YUN_FPS, True)
        w, h = frames[0].size
        cols = min(len(frames), max(1, 8192 // w), 10)
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * w, rows * h))
        for i, f in enumerate(frames):
            sheet.paste(f, ((i % cols) * w, (i // cols) * h))
        sheet.save(os.path.join(OUT, game_name + ".png"), optimize=True)
        manifest[game_name] = {"sheet": f"res://assets/fatfish/anims/{game_name}.png", "w": w, "h": h,
                               "cols": cols, "frames": len(frames), "source": f"{src}:{name}", **meta}
        print(f"{game_name:12s} {src}:{name} {len(frames)} frames {w}x{h} -> {sheet.size}")
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
