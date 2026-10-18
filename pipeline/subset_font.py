"""Shrink the UI font to the characters the game actually uses (repo root):
    python pipeline/subset_font.py
Reads the full Noto Sans SC variable font from art_src/fonts/ and writes a subset to
game/assets/ui/NotoSansSC-VF.ttf with every character found in game scripts, scenes and data
files, plus ASCII and common CJK punctuation. The weight axis is kept. Run it again after
adding new text; characters that are still missing fall back to the system CJK font.
"""
import os
import re

from fontTools import subset

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "art_src", "fonts", "NotoSansSC-VF.ttf")
DST = os.path.join(ROOT, "game", "assets", "ui", "NotoSansSC-VF.ttf")

chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set("，。、；：？！…—～·「」『』《》（）【】“”‘’％＋－×÷０１２３４５６７８９ ")
for folder, exts in (("game/scripts", (".gd",)), ("game/scenes", (".tscn",)), ("game/data", (".json",))):
    for root, _, files in os.walk(os.path.join(ROOT, folder)):
        for f in files:
            if f.endswith(exts):
                text = open(os.path.join(root, f), encoding="utf-8").read()
                chars |= set(re.findall(r"[^\x00-\x7f]", text))

opts = subset.Options()
opts.layout_features = ["*"]
opts.name_IDs = ["*"]
opts.notdef_outline = True
font = subset.load_font(SRC, opts)
sub = subset.Subsetter(opts)
sub.populate(text="".join(sorted(chars)))
sub.subset(font)
subset.save_font(font, DST, opts)
print(f"{len(chars)} characters -> {os.path.getsize(DST) / 1e6:.2f} MB ({os.path.getsize(SRC) / 1e6:.1f} MB full)")

# the display font for numbers and titles (docs/hud_design.md): 站酷快乐体, SIL OFL
SRC2 = os.path.join(ROOT, "art_src", "fonts", "ZCOOLKuaiLe-Regular.ttf")
DST2 = os.path.join(ROOT, "game", "assets", "ui", "ZCOOLKuaiLe.ttf")
if os.path.exists(SRC2):
    font = subset.load_font(SRC2, opts)
    sub = subset.Subsetter(opts)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(font)
    subset.save_font(font, DST2, opts)
    print(f"display font -> {os.path.getsize(DST2) / 1e6:.2f} MB")
