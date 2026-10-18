"""Collect every translatable text into game/data/i18n/<locale>.json (repo root):
    python pipeline/i18n_extract.py [en]
Chinese is the source language and the key: every Chinese string literal in game/scripts
(comments skipped, triple-quoted strings included) plus the skill tree's names and
descriptions. Existing translations are kept, new keys are added with "" (the game then shows
the Chinese), keys that no longer exist are dropped. Prints what is still untranslated.
Lines ending in "# notr" are skipped (debug keys, autotest log). In code, texts reach the screen through tr(); strings built with % use the format string as
the key: tr("花费 %s token") % x.
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CJK = re.compile(r"[一-鿿]")
TRIPLE = re.compile(r'"""(.*?)"""', re.S)
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def unescape(s: str) -> str:
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\t", "\t").replace("\\\\", "\\")


def from_gd(text: str) -> list:
    keys = []
    for m in TRIPLE.finditer(text):
        if CJK.search(m.group(1)):
            keys.append(m.group(1).replace("\r", ""))
    text = TRIPLE.sub('""', text)
    for line in text.splitlines():
        if "# notr" in line:   # debug / log text that players never see
            continue
        code = line.split("##")[0]
        # drop a trailing "# comment" that is not inside a string
        out, in_str = "", False
        for i, ch in enumerate(code):
            if ch == '"' and (i == 0 or code[i - 1] != "\\"):
                in_str = not in_str
            if ch == "#" and not in_str:
                break
            out += ch
        for m in LITERAL.finditer(out):
            s = unescape(m.group(1))
            if CJK.search(s):
                keys.append(s)
    return keys


def main() -> None:
    loc = sys.argv[1] if len(sys.argv) > 1 else "en"
    keys = []
    for root, _, files in os.walk(os.path.join(ROOT, "game", "scripts")):
        for f in sorted(files):
            if f.endswith(".gd"):
                keys += from_gd(open(os.path.join(root, f), encoding="utf-8").read())
    tree = json.load(open(os.path.join(ROOT, "game", "data", "skill_tree.json"), encoding="utf-8"))
    for n in tree["nodes"]:
        keys += [n["name"], n["desc"]]
    menu = json.load(open(os.path.join(ROOT, "game", "data", "menu.json"), encoding="utf-8"))
    for f in menu["foods"]:
        keys += [f["name"]] + ([f["glyph"]] if f.get("glyph") else [])
    for st in menu["stalls"].values():
        keys.append(st["name"])
    for r in menu["recipes"]:
        keys += [r["name"]] + ([r["hint"]] if r.get("hint") else [])
    seen, ordered = set(), []
    for k in keys:
        if k not in seen:
            seen.add(k)
            ordered.append(k)
    path = os.path.join(ROOT, "game", "data", "i18n", f"{loc}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    old = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    out = {"_doc": old.get("_doc", "Translations (key = the Chinese text). Made by pipeline/i18n_extract.py; fill the empty values.")}
    for k in ordered:
        out[k] = old.get(k, "")
    json.dump(out, open(path, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
    missing = [k for k in ordered if not out[k]]
    print(f"{loc}: {len(ordered)} keys, {len(missing)} untranslated -> {os.path.relpath(path, ROOT)}")
    for k in missing[:400]:
        print("  ", json.dumps(k, ensure_ascii=False))


if __name__ == "__main__":
    main()
