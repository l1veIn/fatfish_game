"""Build a source-bound, isolated Godot Web ZIP for Bilibili Toy.

    py -3 pipeline/build_toy.py --baseline
    py -3 pipeline/build_toy.py --compare build/toy-.../build-manifest.json

Never changes game/. Texture compression is applied to staging .import settings,
not to source artwork. The ZIP uses a fixed member order and timestamp. The build
manifest records exact source/config/engine/output hashes, sizes and texture QA.
Requires the repository's Godot export templates, Python 3, Pillow, NumPy and fontTools.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tools/godot/Godot_v4.7.2-stable_win64_console.exe"
PROFILE = ROOT / "pipeline/toy_asset_profile.json"
EXCLUDED = {".godot", ".git", "addons", "tests", "__pycache__"}
TOY_SUFFIXES = {
    ".html", ".htm", ".css", ".js", ".json", ".wasm", ".data", ".md", ".csv", ".tsv",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico", ".woff2", ".woff", ".ttf",
    ".eot", ".mp3", ".wav", ".ogg", ".m4a", ".mp4", ".webm", ".atlas", ".ani", ".part",
    ".nani", ".unityweb",
}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def json_write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def files(root: Path) -> list[Path]:
    return sorted((p for p in root.rglob("*") if p.is_file()
                   and not set(p.relative_to(root).parts).intersection(EXCLUDED)),
                  key=lambda path: path.relative_to(root).as_posix())


def hashes(root: Path) -> dict[str, str]:
    return {p.relative_to(root).as_posix(): sha(p) for p in files(root)}


def tree_digest(values: dict[str, str]) -> str:
    data = "".join(f"{key}\0{value}\n" for key, value in sorted(values.items()))
    return hashlib.sha256(data.encode()).hexdigest()


def verify_font_glyphs(game: Path) -> dict:
    """Web has no system CJK fallback: require every authored Han character."""
    from fontTools.ttLib import TTFont
    required = set()
    for folder, suffixes in (("scripts", {".gd"}), ("scenes", {".tscn"}), ("data", {".json"})):
        for path in files(game / folder):
            if path.suffix in suffixes:
                required.update(re.findall(r"[\u4e00-\u9fff]", path.read_text(encoding="utf-8")))
    with TTFont(game / "assets/ui/NotoSansSC-VF.ttf") as font:
        cmap = font.getBestCmap()
    missing = sorted(char for char in required if ord(char) not in cmap)
    if missing:
        raise RuntimeError("Web UI font lacks characters: " + "".join(missing)
                           + ". Run py -3 pipeline/subset_font.py before building.")
    return {"required_han_characters": len(required), "missing": [],
            "font": "assets/ui/NotoSansSC-VF.ttf"}


def run(command: list[str], log: Path, timeout: int = 900) -> None:
    print(f"Running {log.name}", flush=True)
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                encoding="utf-8", timeout=timeout, cwd=ROOT)
    text = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode or re.search(r"(?:SCRIPT ERROR:|ERROR:|Export failed)", text):
        raise RuntimeError(f"Build step failed; inspect {log}")


def setting(text: str, key: str, value: str, section: str = "params") -> str:
    """Replace a Godot setting, or insert it into a named section."""
    pattern = rf"^{re.escape(key)}=.*$"
    if re.search(pattern, text, re.M):
        return re.sub(pattern, f"{key}={value}", text, flags=re.M)
    marker = f"[{section}]"
    if marker not in text:
        return text.rstrip() + f"\n\n{marker}\n\n{key}={value}\n"
    return text.replace(marker, f"{marker}\n{key}={value}", 1)


def selection(relative: str, size: int, profile: dict, baseline: bool) -> dict:
    chosen = dict(profile["default"])
    for rule in profile["rules"]:
        if any(fnmatch.fnmatchcase(relative, pattern) for pattern in rule["patterns"]):
            chosen.update({k: v for k, v in rule.items() if k != "patterns"})
            break
    if size < chosen.get("minimum_source_bytes", 0):
        chosen["compression"] = "lossless"
        chosen["reason"] = "Small source texture."
    if baseline:
        chosen["compression"] = "lossless"
        chosen["reason"] = "Lossless comparison baseline."
    return chosen


def texture_settings(stage: Path, profile: dict, baseline: bool) -> list[dict]:
    records = []
    for path in sorted((stage / "assets").rglob("*.png")):
        relative = path.relative_to(stage).as_posix()
        sidecar = path.with_suffix(path.suffix + ".import")
        if not sidecar.exists():
            # Godot owns numerals.png through its BMFont importer.
            continue
        text = sidecar.read_text(encoding="utf-8")
        if 'importer="texture"' not in text:
            continue
        chosen = selection(relative, path.stat().st_size, profile, baseline)
        existing_limit = re.search(r"^process/size_limit=([0-9]+)", text, re.M)
        if existing_limit and int(existing_limit.group(1)):
            # Preserve the established import dimensions; QA compares these
            # against a freshly decoded lossless import using the same limit.
            chosen["existing_size_limit"] = int(existing_limit.group(1))
        mode = 0 if chosen["compression"] == "lossless" else 1
        text = setting(text, "compress/mode", str(mode))
        if mode == 1:
            text = setting(text, "compress/lossy_quality", str(chosen["quality"]))
        # No resizing, format conversion or mipmap changes are permitted.
        sidecar.write_text(text, encoding="utf-8", newline="\n")
        records.append({"path": relative, "source_bytes": path.stat().st_size,
                        "source_sha256": sha(path), "settings": chosen})
    return records


def export_preset(shell: str) -> str:
    return f'''[preset.0]
name="Toy"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="toy"
export_filter="all_resources"
include_filter="*.json, assets/ui/OFL*.txt"
exclude_filter="addons/*,tests/*,web/*"
export_path=""
patches=PackedStringArray()
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell="{shell}"
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
'''


def imported_inventory(stage: Path) -> dict:
    """Count exported import targets once, including every texture mipmap."""
    by_extension, by_category = Counter(), Counter()
    entries, seen = [], set()
    for sidecar in files(stage):
        if sidecar.suffix != ".import":
            continue
        source = sidecar.relative_to(stage).as_posix().removesuffix(".import")
        text = sidecar.read_text(encoding="utf-8")
        for relative in re.findall(r'^path(?:\.[^=]+)?="res://([^"]+)"', text, re.M):
            if relative in seen:
                continue
            path = stage / relative
            if not path.exists():
                continue
            seen.add(relative)
            size = path.stat().st_size
            by_extension[path.suffix] += size
            category = "/".join(Path(source).parts[:2])
            by_category[category] += size
            entries.append({"source": source, "imported_path": relative, "bytes": size})
    return {"total_bytes": sum(by_extension.values()),
            "by_extension_bytes": dict(by_extension),
            "by_category_bytes": dict(by_category),
            "largest": sorted(entries, key=lambda p: p["bytes"], reverse=True)[:40],
            "files": entries}


def verify_textures(stage: Path, output: Path, records: list[dict], profile: dict) -> dict:
    """Decode actual Godot compressed imports and compare alpha and visible RGB."""
    from PIL import Image, ImageDraw
    import numpy as np

    qa = output / "qa"
    qa.mkdir()
    targets = [record["path"] for record in records
               if record["settings"]["compression"] == "lossy"]
    if not targets:
        return {"checked_textures": 0, "reason": "Lossless baseline."}
    json_write(qa / "texture-paths.json", targets)
    script = qa / "decode_textures.gd"
    script.write_text('''extends SceneTree
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var paths: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
    var destination: String = args[1]
    for i in paths.size():
        var texture: Texture2D = load("res://" + str(paths[i]))
        if texture == null:
            push_error("Texture load failed: " + str(paths[i]))
            quit(1)
            return
        var image := texture.get_image()
        if image == null:
            push_error("Texture image unavailable: " + str(paths[i]))
            quit(1)
            return
        image.clear_mipmaps()
        if image.save_png(destination.path_join(str(i) + ".png")) != OK:
            push_error("Texture decode write failed")
            quit(1)
            return
    quit()
''', encoding="utf-8")
    decoded = qa / "decoded"
    decoded.mkdir()
    run([str(ENGINE), "--headless", "--path", str(stage), "--script", str(script),
         "--", str(qa / "texture-paths.json"), str(decoded), "--test-profile=toy_build"], output / "texture-qa.log")
    settings_by_path = {record["path"]: record["settings"] for record in records}
    sized_targets = [path for path in targets if settings_by_path[path].get("existing_size_limit")]
    reference_paths = {}
    if sized_targets:
        reference_stage = qa / "lossless-reference"
        reference_stage.mkdir()
        (reference_stage / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Lossless size-limit reference"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        for relative in sized_targets:
            destination = reference_stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(stage / relative, destination)
            sidecar = stage / (relative + ".import")
            (reference_stage / (relative + ".import")).write_text(
                setting(sidecar.read_text(encoding="utf-8"), "compress/mode", "0"),
                encoding="utf-8", newline="\n")
        reference_decoded = qa / "lossless-reference-decoded"
        reference_decoded.mkdir()
        json_write(qa / "size-limited-paths.json", sized_targets)
        run([str(ENGINE), "--headless", "--path", str(reference_stage), "--editor", "--import", "--quit"],
            output / "texture-reference-import.log")
        run([str(ENGINE), "--headless", "--path", str(reference_stage), "--script", str(script),
             "--", str(qa / "size-limited-paths.json"), str(reference_decoded), "--test-profile=toy_build"],
            output / "texture-reference-decode.log")
        reference_paths = {relative: reference_decoded / f"{index}.png"
                           for index, relative in enumerate(sized_targets)}
    metrics, bad = [], []
    representatives = set(profile["quality_checks"]["representatives"])
    panels = []
    for index, relative in enumerate(targets):
        with Image.open(stage / relative) as image:
            original_dimensions = list(image.size)
        with Image.open(reference_paths.get(relative, stage / relative)) as image:
            source = image.convert("RGBA")
        with Image.open(decoded / f"{index}.png") as image:
            actual = image.convert("RGBA")
        a, b = np.asarray(source), np.asarray(actual)
        same_size = source.size == actual.size
        alpha_exact = same_size and np.array_equal(a[:, :, 3], b[:, :, 3])
        psnr = None
        if same_size:
            # Transparent RGB is immaterial. Weight partial alpha by visibility.
            weight = a[:, :, 3:4].astype(np.float64) / 255.0
            difference = (a[:, :, :3].astype(np.float64) - b[:, :, :3]) * weight
            mse = float(np.sum(difference * difference) / max(1.0, 3 * np.sum(weight * weight)))
            psnr = 99.0 if mse == 0 else 10 * math.log10(255 * 255 / mse)
        passed = (same_size and alpha_exact and psnr is not None
                  and psnr >= profile["quality_checks"]["minimum_visible_rgb_psnr_db"])
        entry = {"path": relative, "size": list(source.size),
                 "original_source_size": original_dimensions,
                 "existing_size_limit": settings_by_path[relative].get("existing_size_limit", 0),
                 "same_dimensions": same_size,
                 "exact_alpha": alpha_exact, "visible_rgb_psnr_db": round(psnr or 0, 3),
                 "passed": passed}
        metrics.append(entry)
        if not passed:
            bad.append(entry)
        if relative in representatives:
            # Each row includes a whole-image scale preview on dark and light
            # backgrounds, then full-resolution center crops for detail review.
            row = Image.new("RGB", (1440, 380), "#eeeeee")
            draw = ImageDraw.Draw(row)
            draw.text((12, 8), f"{relative} | visible PSNR {psnr:.2f} dB | exact alpha {alpha_exact}", fill="#111111")
            for column, (original, title, background, crop) in enumerate([
                (source, "Source / light", "#f7f2e5", False),
                (actual, "Toy / light", "#f7f2e5", False),
                (actual, "Toy / dark", "#222b3c", False),
                (source, "Source 1:1 crop", "#f7f2e5", True),
                (actual, "Toy 1:1 crop", "#f7f2e5", True),
            ]):
                panel = Image.new("RGBA", (280, 330), background)
                tile = original.copy()
                if crop:
                    cx, cy = tile.width // 2, tile.height // 2
                    tile = tile.crop((max(0, cx - 140), max(0, cy - 165),
                                      min(tile.width, cx + 140), min(tile.height, cy + 165)))
                else:
                    tile.thumbnail((270, 320), Image.Resampling.LANCZOS)
                panel.alpha_composite(tile, ((280 - tile.width) // 2, (330 - tile.height) // 2))
                x = column * 288
                row.paste(panel.convert("RGB"), (x, 45))
                draw.text((x + 6, 28), title, fill="#111111")
            panels.append(row)
    if panels:
        sheet = Image.new("RGB", (1440, 380 * len(panels)), "#eeeeee")
        for index, panel in enumerate(panels):
            sheet.paste(panel, (0, index * 380))
        sheet.save(qa / "texture-comparison.jpg", quality=95)
    summary = {"checked_textures": len(metrics),
               "all_dimensions_preserved": all(p["same_dimensions"] for p in metrics),
               "all_alpha_exact": all(p["exact_alpha"] for p in metrics),
               "minimum_visible_rgb_psnr_db": min(p["visible_rgb_psnr_db"] for p in metrics),
               "failed": bad, "textures": metrics,
               "visual_review": "Representative contact sheet requires human/agent inspection; numerical checks alone do not prove perceptual quality."}
    json_write(qa / "texture-quality.json", summary)
    if bad:
        raise RuntimeError(f"{len(bad)} texture QA failure(s); inspect {qa / 'texture-quality.json'}")
    return summary


def copy_licenses(web: Path) -> None:
    shutil.copy2(ROOT / "CREDITS.md", web / "CREDITS.md")
    shutil.copy2(ROOT / "LICENSE", web / "LICENSE.md")
    licenses = web / "licenses"
    licenses.mkdir()
    for path in sorted((ROOT / "game/assets/ui").glob("OFL*.txt")):
        shutil.copy2(path, licenses / f"{path.stem}.md")
    shutil.copy2(ROOT / "docs/THIRD_PARTY_NOTICES.txt", licenses / "THIRD_PARTY_NOTICES.md")


def platform_package(web: Path) -> dict:
    """Toy does not publish .pck files; Godot supports any mainPack filename."""
    original, renamed = web / "index.pck", web / "index.data"
    if not original.is_file() or renamed.exists():
        raise RuntimeError("Expected exactly one original index.pck before Toy packaging.")
    html = web / "index.html"
    text = html.read_text(encoding="utf-8")
    assignment = re.search(r"(?:const|let|var)\s+GODOT_CONFIG\s*=\s*", text)
    if assignment is None:
        raise RuntimeError("HTML shell must declare GODOT_CONFIG using Godot's JSON placeholder.")
    config, length = json.JSONDecoder().raw_decode(text[assignment.end():])
    if config.get("useThreads", False):
        raise RuntimeError("Toy export unexpectedly enables threads.")
    config["mainPack"] = "index.data"
    sizes = config.setdefault("fileSizes", {})
    sizes.pop("index.pck", None)
    sizes["index.data"] = original.stat().st_size
    text = (text[:assignment.end()] + json.dumps(config, separators=(",", ":"))
            + text[assignment.end() + length:])
    html.write_text(text, encoding="utf-8", newline="\n")
    original.rename(renamed)
    loader = (web / "index.js").read_text(encoding="utf-8")
    if "this.config.mainPack" not in loader or "this.preloadFile(pack, pack)" not in loader:
        raise RuntimeError("Engine loader mainPack support changed; inspect before release.")
    return {"renamed": {"from": "index.pck", "to": "index.data"},
            "main_pack": config["mainPack"], "file_sizes": sizes,
            "loader_main_pack_support_checked": True}


def make_zip(folder: Path, target: Path) -> None:
    unexpected = [p.relative_to(folder).as_posix() for p in files(folder)
                  if p.suffix.lower() not in TOY_SUFFIXES]
    if unexpected:
        raise RuntimeError(f"Files outside Toy publish suffix whitelist: {unexpected}")
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files(folder):
            info = zipfile.ZipInfo(path.relative_to(folder).as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", action="store_true", help="use lossless texture imports for comparison")
    parser.add_argument("--compare", type=Path, help="existing build-manifest.json to compare sizes and source hashes")
    parser.add_argument("--output", type=Path, help="new, empty build/toy-* directory; existing folders are refused")
    parser.add_argument("--profile", type=Path, default=PROFILE)
    parser.add_argument("--shell", help="res:// custom shell; auto-detects res://web/toy_shell.html")
    parser.add_argument("--max-zip-mb", type=float, help="optional verified account ZIP limit, decimal MB")
    args = parser.parse_args()
    if not ENGINE.is_file():
        raise SystemExit(f"Missing Godot executable: {ENGINE}")
    font_coverage = verify_font_glyphs(ROOT / "game")
    profile_bytes = args.profile.read_bytes()
    pipeline_bytes = Path(__file__).read_bytes()
    profile = json.loads(profile_bytes)
    config = (ROOT / "game/project.godot").read_text(encoding="utf-8")
    version = re.search(r'config/version="([^"]+)"', config).group(1)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    label = "lossless" if args.baseline else "compressed"
    output = (args.output or ROOT / "build" / f"toy-{version}-{label}-{stamp}").resolve()
    if output.parent != (ROOT / "build").resolve() or not output.name.startswith("toy-"):
        raise SystemExit("--output must be a new immediate build/toy-* directory")
    output.mkdir(parents=True, exist_ok=False)
    print(f"Output: {output}", flush=True)
    inputs = output / "build-inputs"
    inputs.mkdir()
    (inputs / "build_toy.py").write_bytes(pipeline_bytes)
    (inputs / "toy_asset_profile.json").write_bytes(profile_bytes)
    stage = output / "source"
    initial_hashes = hashes(ROOT / "game")
    shutil.copytree(ROOT / "game", stage, ignore=lambda _path, names: set(names).intersection(EXCLUDED))
    if hashes(stage) != initial_hashes:
        raise RuntimeError("Source changed while copying; rerun after edits finish.")
    config = re.sub(r'^.*="?\*?res://addons/.*\n?', "", config, flags=re.M)
    config = re.sub(r'\[editor_plugins\]\s*\n.*?(?=\n\[|\Z)', "", config, flags=re.S)
    config = setting(config, "renderer/rendering_method", '"gl_compatibility"', "rendering")
    config = setting(config, "renderer/rendering_method.mobile", '"gl_compatibility"', "rendering")
    config = setting(config, "textures/vram_compression/import_s3tc_bptc", "true", "rendering")
    config = setting(config, "textures/vram_compression/import_etc2_astc", "true", "rendering")
    if "godot_ai" in config or (stage / "addons").exists() or (stage / "tests").exists():
        raise RuntimeError("Editor/test tooling leaked into release stage.")
    shell = args.shell
    if shell is None:
        shell = "res://web/toy_shell.html" if (stage / "web/toy_shell.html").exists() else ""
    if shell and (not shell.startswith("res://") or not (stage / shell.removeprefix("res://")).is_file()):
        raise SystemExit(f"Missing custom HTML shell: {shell}")
    (stage / "export_presets.cfg").write_text(export_preset(shell), encoding="utf-8", newline="\n")
    (stage / "project.godot").write_text(config, encoding="utf-8", newline="\n")
    records = texture_settings(stage, profile, args.baseline)
    staged_hashes = hashes(stage)
    project = stage / "project.godot"
    # Cold imports cannot resolve the project theme until its font is imported.
    project.write_text(re.sub(r'^theme/custom_font=.*\n?', "", config, flags=re.M), encoding="utf-8", newline="\n")
    try:
        run([str(ENGINE), "--headless", "--path", str(stage), "--editor", "--import", "--quit"],
            output / "import-bootstrap.log")
    finally:
        project.write_text(config, encoding="utf-8", newline="\n")
    run([str(ENGINE), "--headless", "--path", str(stage), "--editor", "--import", "--quit"],
        output / "import.log")
    inventory = imported_inventory(stage)
    web = output / "web"
    web.mkdir()
    run([str(ENGINE), "--headless", "--path", str(stage), "--export-release", "Toy", str(web / "index.html")],
        output / "export-web.log")
    for path in sorted((stage / "web").glob("*.js")):
        if (web / path.name).exists():
            raise RuntimeError(f"JavaScript filename collides with Godot output: {path.name}")
        shutil.copy2(path, web / path.name)
    package_adjustments = platform_package(web)
    copy_licenses(web)
    (web / "README.md").write_text(
        f"Fatfish's Free Lunch / 吃白饭的大肥鱼 v{version}\n"
        "Toy Web candidate. Serve this folder over HTTP(S); entry: index.html.\n"
        "Single-threaded Godot Web (WebGL 2). No cross-origin isolation required.\n"
        "Free, non-commercial fan game. Not affiliated with DeepSeek.\n"
        "免费、非商用粉丝作品，与 DeepSeek 官方无关。\n"
        "See CREDITS.md, LICENSE.md and licenses/ for attribution and licensing.\n",
        encoding="utf-8")
    quality = verify_textures(stage, output, records, profile)
    export_hashes = hashes(stage)
    changes = {name: {"before": staged_hashes.get(name), "after": export_hashes.get(name)}
               for name in sorted(staged_hashes.keys() | export_hashes.keys())
               if staged_hashes.get(name) != export_hashes.get(name)}
    unexpected = [name for name in changes if not name.endswith(".import")]
    if unexpected:
        raise RuntimeError(f"Godot unexpectedly changed source files: {unexpected}")
    archive = output / f"FatFish-{version}-toy-{label}.zip"
    make_zip(web, archive)
    output_files = {p.relative_to(web).as_posix(): {"bytes": p.stat().st_size, "sha256": sha(p)}
                    for p in files(web)}
    git_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, capture_output=True).stdout.strip()
    git_changes = subprocess.run(["git", "status", "--short"], cwd=ROOT, text=True, capture_output=True).stdout.splitlines()
    comparison = None
    if args.compare:
        other = json.loads(args.compare.read_text(encoding="utf-8"))
        before = other["archive"]["bytes"]
        comparison = {"manifest": str(args.compare.resolve()), "baseline_zip_bytes": before,
                      "candidate_zip_bytes": archive.stat().st_size,
                      "saved_bytes": before - archive.stat().st_size,
                      "saved_percent": round(100 * (before - archive.stat().st_size) / before, 2),
                      "same_original_source": other["original_source_tree_sha256"] == tree_digest(initial_hashes),
                      "same_original_asset_bytes": all(
                          other["original_source_sha256"].get(name) == digest
                          for name, digest in initial_hashes.items()
                          if name.startswith("assets/") and not name.endswith((".import", ".uid"))),
                      "note": "Different original source hashes mean this comparison is indicative, not an isolated A/B test."}
    max_bytes = int(args.max_zip_mb * 1_000_000) if args.max_zip_mb else None
    manifest = {
        "schema_version": 1, "version": version, "created_utc": stamp, "mode": label,
        "git_head": git_head, "git_status_at_manifest": git_changes,
        "original_source_tree_sha256": tree_digest(initial_hashes), "original_source_sha256": initial_hashes,
        "staged_source_tree_sha256": tree_digest(staged_hashes), "staged_source_sha256": staged_hashes,
        "export_source_tree_sha256": tree_digest(export_hashes), "export_source_sha256": export_hashes,
        "import_changes": changes, "profile": profile,
        "profile_sha256": hashlib.sha256(profile_bytes).hexdigest(),
        "pipeline_sha256": hashlib.sha256(pipeline_bytes).hexdigest(), "engine_launcher_sha256": sha(ENGINE),
        "engine_sha256": sha(ENGINE.with_name(ENGINE.name.replace("_console", ""))),
        "web_export_template_sha256": sha(Path(os.environ["APPDATA"]) / "Godot/export_templates/4.7.2.stable/web_nothreads_release.zip"),
        "engine_version": subprocess.run([str(ENGINE), "--version"], text=True, capture_output=True).stdout.strip(),
        "configuration": {"thread_support": False, "renderer": "gl_compatibility", "shell": shell,
                          "desktop_texture_support": True, "mobile_texture_support": True,
                          "tooling_excluded": sorted(EXCLUDED), "mcp_autoload_removed": True},
        "platform_package": package_adjustments,
        "allowed_publish_suffixes": sorted(TOY_SUFFIXES),
        "texture_settings": records, "texture_quality": quality, "imported_resources": inventory,
        "font_coverage": font_coverage,
        "output_files": output_files, "output_total_bytes": sum(p["bytes"] for p in output_files.values()),
        "archive": {"path": archive.name, "bytes": archive.stat().st_size, "sha256": sha(archive)},
        "comparison": comparison, "account_zip_limit_bytes": max_bytes,
        "within_account_zip_limit": archive.stat().st_size <= max_bytes if max_bytes else None,
        "validation_limits": ["Browser and Toy platform runtime validation is separate.",
                              "Compression preserves dimensions and alpha, not decoded texture memory usage.",
                              "No physical mobile-device performance claim is made."]}
    json_write(output / "build-manifest.json", manifest)
    print(f"ZIP: {archive} ({archive.stat().st_size / 1_000_000:.2f} MB)", flush=True)
    print(f"Manifest: {output / 'build-manifest.json'}", flush=True)
    if max_bytes and archive.stat().st_size > max_bytes:
        raise SystemExit("Build created, but ZIP exceeds the supplied account limit.")


if __name__ == "__main__":
    main()
