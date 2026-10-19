"""Encode an approved transparent mascot as the boot, window and Windows executable icons.

python pipeline/pack_brand_icon.py art_src/brand/basin_deadpan_master.png
Only resamples/encodes the generated artwork; no background removal or visual edits.
"""
from pathlib import Path
import argparse
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    image = Image.open(args.source).convert("RGBA")
    assert image.width == image.height, "The approved icon must be square"
    assert image.getchannel("A").getextrema() == (0, 255), "Keep the generated transparency"
    target = ROOT / "game/assets/ui"
    icon = image.resize((512, 512), Image.Resampling.LANCZOS)
    icon.save(target / "icon.png")
    sizes = [(n, n) for n in (16, 24, 32, 48, 64, 128, 256)]
    icon.save(target / "icon.ico", format="ICO", sizes=sizes)
    ico = Image.open(target / "icon.ico")
    assert ico.ico.sizes() == set(sizes)
    output = ROOT / "build/qa/brand-icon"
    output.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (1000, 540), (24, 18, 14, 255))
    sheet.alpha_composite(icon, (14, 14))
    x = 548
    for n in (128, 64, 48, 32, 24, 16):
        preview = ico.ico.getimage((n, n))
        preview.save(output / f"icon-{n}.png")
        sheet.alpha_composite(preview, (x, 40))
        x += n + 14
    sheet.convert("RGB").save(output / "native-sizes.png")
    print("Encoded transparent 512px boot icon and seven Windows icon sizes.")


if __name__ == "__main__":
    main()
