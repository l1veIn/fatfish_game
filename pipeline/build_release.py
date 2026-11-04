"""Build an isolated Windows release candidate without shipping editor tooling.

    py -3 pipeline/build_release.py
    py -3 pipeline/build_release.py --web

Copies only the game into a fresh staging directory, removes the editor-only MCP
autoload there, imports/exports with checked exit codes, and writes SHA-256 receipts.
The working editor project and all previous build directories stay intact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tools/godot/Godot_v4.7.2-stable_win64_console.exe"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], log: Path, timeout: int = 600) -> None:
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                encoding="utf-8", timeout=timeout, cwd=ROOT)
    text = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode or re.search(r"(?:SCRIPT ERROR:|ERROR: Failed|Export failed)", text):
        raise RuntimeError(f"Build step failed; inspect {log}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", action="store_true", help="also export a Web companion build")
    args = parser.parse_args()
    if not ENGINE.exists():
        raise SystemExit(f"Missing engine: {ENGINE}")
    translations = json.loads((ROOT / "game/data/i18n/en.json").read_text(encoding="utf-8"))
    missing = [k for k, v in translations.items() if not k.startswith("_") and not v]
    if missing:
        raise SystemExit(f"English localization incomplete: {len(missing)} empty entries")
    config = (ROOT / "game/project.godot").read_text(encoding="utf-8")
    version = re.search(r'config/version="([^"]+)"', config).group(1)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = ROOT / "build" / f"candidate-{version}-{stamp}"
    output.mkdir(parents=True, exist_ok=False)
    stage = output / "source"
    shutil.copytree(ROOT / "game", stage,
                    ignore=shutil.ignore_patterns(".godot", ".git", "addons", "tests"))
    config = re.sub(r'^_mcp_game_helper=.*\n?', '', config, flags=re.M)
    config = re.sub(r'\[editor_plugins\]\s*\n.*?(?=\n\[|\Z)', '', config, flags=re.S)
    (stage / "project.godot").write_text(config, encoding="utf-8", newline="\n")
    # Keep the Windows file properties aligned with the actual game version.
    # Only normalize the staged preset; leave the editor's export settings alone.
    windows_version = ".".join((version.split(".") + ["0"] * 4)[:4])
    preset = stage / "export_presets.cfg"
    preset.write_text(re.sub(r'application/(file|product)_version="[^"]*"',
                            lambda match: f'application/{match.group(1)}_version="{windows_version}"',
                            preset.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    assert "godot_ai" not in config and not (stage / "addons").exists()
    source_hashes = {str(p.relative_to(stage)).replace("\\", "/"): sha(p)
                     for p in sorted(stage.rglob("*")) if p.is_file()}
    # Godot initializes the project-wide theme before its first asset import.
    # A cold staging cache cannot resolve that theme's imported font yet.
    # Bootstrap without that setting, then restore and strictly verify the
    # complete release configuration after the font has actually been imported.
    project = stage / "project.godot"
    project.write_text(re.sub(r'^theme/custom_font=.*\n?', '', config, flags=re.M),
                       encoding="utf-8", newline="\n")
    try:
        run([str(ENGINE), "--headless", "--path", str(stage), "--editor", "--import", "--quit"],
            output / "import-bootstrap.log")
    finally:
        project.write_text(config, encoding="utf-8", newline="\n")
    run([str(ENGINE), "--headless", "--path", str(stage), "--editor", "--import", "--quit"], output / "import.log")
    targets = [("Windows", "windows", "FatFish.exe")]
    if args.web:
        targets.append(("Web", "web", "index.html"))
    for preset, folder, filename in targets:
        target = output / folder
        target.mkdir()
        run([str(ENGINE), "--headless", "--path", str(stage), "--export-release", preset, str(target / filename)],
            output / f"export-{folder}.log")
        for name in ["CREDITS.md", "LICENSE"]:
            shutil.copy2(ROOT / name, target / name)
        licenses = target / "licenses"
        licenses.mkdir()
        for license_file in (ROOT / "game/assets/ui").glob("OFL*.txt"):
            shutil.copy2(license_file, licenses / license_file.name)
        shutil.copy2(ROOT / "docs/THIRD_PARTY_NOTICES.txt", licenses / "THIRD_PARTY_NOTICES.txt")
        (target / "README.txt").write_text(
            f"Fatfish's Free Lunch / 吃白饭的大肥鱼 v{version}\n\n"
            "Free, non-commercial fan game. Not affiliated with DeepSeek.\n"
            "免费、非商用粉丝作品，与 DeepSeek 官方无关。\n\n"
            "Run FatFish.exe. Mouse: move box, left click to pick up/serve.\n"
            "Keyboard: WASD/arrows to move, E/Enter to pick up/serve, Esc to pause.\n"
            "Gamepad: left stick to move, A to pick up/serve, Start to pause.\n"
            "移动鼠标接菜，饭盒靠近右侧饭桌后左键取盒或送饭；Esc 暂停。\n"
            "Settings: language, audio, window size, reduced motion and impact effects.\n"
            "设置可调整语言、音量、窗口尺寸、减少动态效果和反馈。\n\n"
            "Windows saves: %APPDATA%\\FatFishFreeLunch\\save.json\n"
            "Keep save.json and save.json.bak when moving progress.\n"
            "Local achievements are included. Steam integration is not yet configured.\n",
            encoding="utf-8")
        shutil.make_archive(str(output / f"FatFish-{version}-{folder}"), "zip", target)
    # Importers may normalize sidecar metadata (e.g. a BMFont owns its PNG atlas
    # and marks that image's separate importer as skip). Record both the copied
    # inputs and the actual exported source; do not claim those bytes are equal.
    export_source_hashes = {str(p.relative_to(stage)).replace("\\", "/"): sha(p)
                            for p in sorted(stage.rglob("*"))
                            if p.is_file() and ".godot" not in p.relative_to(stage).parts}
    import_changes = {name: {"before": source_hashes.get(name), "after": export_source_hashes.get(name)}
                      for name in sorted(source_hashes.keys() | export_source_hashes.keys())
                      if source_hashes.get(name) != export_source_hashes.get(name)}
    unexpected_changes = [name for name in import_changes if not name.endswith(".import")]
    if unexpected_changes:
        raise RuntimeError(f"Export changed non-import source files: {unexpected_changes}")
    manifest = {
        "version": version, "created_utc": stamp, "source_sha256": source_hashes,
        "export_source_sha256": export_source_hashes, "import_changes": import_changes,
        "tooling_excluded": ["addons/", "tests/", "_mcp_game_helper", "editor_plugins"],
        "artifacts": {str(p.relative_to(output)).replace("\\", "/"): {"sha256": sha(p), "bytes": p.stat().st_size}
                      for p in output.rglob("*") if p.is_file() and p.suffix in {".zip", ".exe"}},
    }
    (output / "build-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(output)
    print("Build complete. Run the packaged executable for release smoke testing.")


if __name__ == "__main__":
    main()
