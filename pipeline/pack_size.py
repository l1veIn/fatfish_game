"""How big the exported game data will be, by imported resource type (repo root):
    python pipeline/pack_size.py [--top 15]
Counts the imported files of every resource the export includes (tests/ and the old
assets/sprites/ are excluded, as in game/export_presets.cfg) plus the raw *.json files.
"""
import collections
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GAME = os.path.join(ROOT, "game")
SKIP = ("tests", os.path.join("assets", "sprites"), ".godot")


def main() -> None:
    top = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 15
    by_type = collections.Counter()
    files = []
    for root, _, names in os.walk(GAME):
        rel = os.path.relpath(root, GAME)
        if rel.startswith(SKIP):
            continue
        for n in names:
            src = os.path.join(root, n)
            if n.endswith(".json"):
                by_type["json"] += os.path.getsize(src)
                continue
            if not n.endswith(".import"):
                continue
            for line in open(src, encoding="utf-8"):
                if line.startswith("path") and '"' in line:
                    p = os.path.join(GAME, line.split('"')[1].replace("res://", ""))
                    if os.path.exists(p):
                        size = os.path.getsize(p)
                        by_type[p.rsplit(".", 1)[-1]] += size
                        files.append((size, os.path.relpath(src[:-7], GAME)))
    total = sum(by_type.values())
    print("by type (MB):", {k: round(v / 1e6, 1) for k, v in by_type.most_common()})
    print(f"total ≈ {total / 1e6:.1f} MB")
    for size, name in sorted(files, reverse=True)[:top]:
        print(f"  {size / 1e6:5.2f} MB  {name}")


if __name__ == "__main__":
    main()
