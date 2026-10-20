"""Freeze game source hashes and run isolated release regression scenarios.

py -3 pipeline/validate_release.py --runs 40 --visual
Every invocation writes a new evidence folder. Failures and source changes are
retained in report.json; this script never upgrades an old report to a pass.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tools/godot/Godot_v4.7.2-stable_win64_console.exe"


def fingerprint() -> dict[str, str]:
    return {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / "game").rglob("*"))
            if p.is_file() and not any(part in {".godot", "addons"} for part in p.relative_to(ROOT / "game").parts)}


def player_fingerprint() -> dict[str, str]:
    folder = Path(os.environ.get("APPDATA", "")) / "FatFishFreeLunch"
    return {name: hashlib.sha256((folder / name).read_bytes()).hexdigest()
            for name in ["save.json", "save.json.bak", "settings.cfg"] if (folder / name).exists()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=0)
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--uncapped-ui", action="store_true", help="request VSync-off startup and a 120 FPS cap for UI fixtures; scene settings may override it; not a performance test")
    parser.add_argument("--ui-timeout", type=int, default=120)
    parser.add_argument("--only", action="append", default=[], help="run only an exact scenario name; repeat to select more")
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = ROOT / "build" / f"verification-{stamp}"
    out.mkdir(parents=True, exist_ok=False)
    before = fingerprint()
    player_before = player_fingerprint()
    results = []
    scenarios = [
        ("state", "release_state_test", "release_state", "RELEASE_STATE_TEST:"),
        ("audio-cooldown", "audio_cooldown_test", "audio_cooldown", '"failures":[]'),
        ("onboarding", "onboarding_test", "onboarding", '"ok":true'),
        ("settings", "settings_release_test", "settings-release", "SETTINGS_RELEASE_TEST failures=0"),
        ("ending", "ending_flow_test", "ending_release", "ENDING_FLOW_TEST PASS failures=0"),
        ("focus", "focus_recovery_test", "focus_recovery", "FOCUS_RECOVERY_TEST failures=0"),
        ("controls", "canteen_controls_test", "canteen_controls", '"ok":true'),
        ("mechanics", "mechanic_synergy_test", "mechanic_synergy", "MECHANIC_SYNERGY_TEST:"),
        ("helper-strategy", "helper_strategy_test", "helper_strategy", "HELPER_STRATEGY_TEST:"),
        ("helper-shift", "helper_shift_test", "helper_shift", "HELPER_SHIFT_TEST PASS failures=0"),
        ("random-shift", "random_shift_test", "random_shift", "RANDOM_SHIFT_TEST PASS failures=0"),
        ("crew-planner", "crew_planner_test", "crew_planner", "CREW_PLANNER_TEST PASS failures=0"),
        ("fish-meal", "fish_meal_visual_test", "fish_meal", "FISH_MEAL_VISUAL_TEST PASS"),
        ("planner", "meal_planner_test", "meal_planner_release", "MEAL_PLANNER_TEST PASS failures=0"),
        ("service-ui", "canteen_presentation_test", "canteen_presentation_release", '"failures":[]'),
        ("collections", "collection_presentation_test", "collection_presentation", "COLLECTION_PRESENTATION_TEST: 0 failures"),
        ("shell", "presentation_shell_test", "presentation_shell_release", "PRESENTATION_SHELL_TEST PASS"),
        ("tree-layout", "tree_presentation_test", "tree_presentation_release", '"failures":[]'),
        ("progression-layout", "progression_layout_test", "progression_layout", "PROGRESSION_LAYOUT_TEST: 99 checks, 0 failures"),
        ("tree-dependency", "tree_dependency_test", "tree_dependency_release", "TREE_DEPENDENCY_TEST PASS failures=0"),
        ("stall-layout", "stall_layout_ui_test", "stall_layout_ui", "STALL_LAYOUT_UI_TEST PASS"),
        ("input-remap", "input_remap_test", "input_remap_release", "INPUT_REMAP_TEST PASS failures=0"),
        ("input-access", "input_access_test", "input_access", "INPUT_ACCESS_TEST PASS"),
    ]

    def execute(name: str, command: list[str], marker: str, timeout=120):
        if args.only and name not in args.only:
            return
        if "--headless" not in command:
            timeout = max(timeout, args.ui_timeout)
            if args.uncapped_ui:
                command[1:1] = ["--disable-vsync", "--max-fps", "120"]
        log = out / f"{name}.log"
        started = datetime.now(timezone.utc).isoformat()
        with log.open("w", encoding="utf-8") as stream:
            try:
                run = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
                code = run.returncode
            except subprocess.TimeoutExpired:
                code = -1
        text = log.read_text(encoding="utf-8", errors="replace")
        errors = re.findall(r"^.*(?:SCRIPT ERROR:|ERROR:|FAIL ).*$", text, re.M)
        passed = code == 0 and marker in text and not errors
        results.append({"name": name, "passed": passed, "exit_code": code, "marker": marker, "command": command,
                        "log": str(log.relative_to(ROOT)), "started_utc": started, "errors": errors})
        print(f"{name}: {'PASS' if passed else 'FAIL'}", flush=True)

    for name, scene, profile, marker in scenarios:
        execute(name, [str(ENGINE), "--headless", "--path", str(ROOT / "game"),
                       f"res://tests/{scene}.tscn", "--", f"--test-profile={profile}", "--lang=zh_CN"], marker)
    if args.visual:
        execute("fish-meal-visual", [str(ENGINE), "--path", str(ROOT / "game"),
                "res://tests/fish_meal_visual_test.tscn", "--", "--test-profile=fish_meal",
                f"--out={out / 'fish-meal-visual'}"], "FISH_MEAL_VISUAL_TEST PASS", 180)
        execute("random-shift-visual", [str(ENGINE), "--path", str(ROOT / "game"),
                "res://tests/random_shift_test.tscn", "--", "--test-profile=random_shift",
                f"--out={out / 'random-shift-visual'}"], "RANDOM_SHIFT_TEST PASS failures=0", 180)
        for small in [False, True]:
            size = "960x540" if small else "1280x720"
            execute(f"collections-{size}", [str(ENGINE), "--path", str(ROOT / "game"),
                    "res://tests/collection_presentation_test.tscn", "--", "--test-profile=collection_presentation",
                    f"--render-size={size}", f"--out={out / ('collections-' + size)}"], "COLLECTION_PRESENTATION_TEST: 0 failures")
            for locale in ["zh_CN", "en"]:
                for name, scene, profile, marker in [
                        ("service", "canteen_presentation_test", "canteen_presentation_release", '"failures":[]'),
                        ("tree", "tree_presentation_test", "tree_presentation_release", '"failures":[]'),
                        ("tree-dependency", "tree_dependency_test", "tree_dependency_release", "TREE_DEPENDENCY_TEST PASS failures=0"),
                        ("stall-layout", "stall_layout_ui_test", "stall_layout_ui", "STALL_LAYOUT_UI_TEST PASS"),
                        ("input-remap", "input_remap_test", "input_remap_release", "INPUT_REMAP_TEST PASS failures=0"),
                        ("shell", "presentation_shell_test", "presentation_shell_release", "PRESENTATION_SHELL_TEST PASS")]:
                    key = f"{name}-{locale}-{size}"
                    command = [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", size,
                               f"res://tests/{scene}.tscn", "--", f"--test-profile={profile}",
                               f"--lang={locale}", f"--out={out / key}", f"--render-size={size}"]
                    if small and name in {"service", "tree", "tree-dependency", "stall-layout", "input-remap"}:
                        command.append("--small")
                    execute(key, command, marker)
                crew_size = "960x540" if small else "1920x1080"
                key = f"crew-planner-{locale}-{crew_size}"
                command = [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", crew_size,
                           "res://tests/crew_planner_test.tscn", "--", "--test-profile=crew_planner",
                           f"--lang={locale}", f"--out={out / key}"]
                if small:
                    command.append("--small")
                execute(key, command, "CREW_PLANNER_TEST PASS failures=0")
        for locale in ["zh_CN", "en"]:
            shots = out / f"visual-{locale}"
            execute(f"ending-{locale}", [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", "1280x720",
                    "res://tests/ending_flow_test.tscn", "--", f"--test-profile=ending_{locale}",
                    f"--lang={locale}", f"--out={shots}"], "ENDING_FLOW_TEST PASS failures=0")
            execute(f"planner-{locale}", [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", "1280x720",
                    "res://tests/meal_planner_test.tscn", "--", f"--test-profile=meal_planner_{locale}",
                    f"--lang={locale}", f"--out={out / ('planner-' + locale)}"], "MEAL_PLANNER_TEST PASS failures=0")
            execute(f"focus-{locale}", [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", "1280x720",
                    "res://tests/focus_recovery_test.tscn", "--", f"--test-profile=focus_{locale}",
                    f"--lang={locale}", f"--out={out / ('focus-' + locale)}"], "FOCUS_RECOVERY_TEST failures=0")
            execute(f"canteen-{locale}", [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", "1280x720",
                    "res://tests/canteen_visual_test.tscn", "--", f"--test-profile=canteen_visual_{locale}",
                    f"--lang={locale}", f"--out={out / ('canteen-' + locale)}"], '"ok":true', 180)
        execute("settings-visual", [str(ENGINE), "--path", str(ROOT / "game"), "--resolution", "1280x720",
                "res://tests/settings_release_test.tscn", "--", "--test-profile=settings-release",
                f"--settings-shots={out / 'settings-visual'}"], "SETTINGS_RELEASE_TEST failures=0")
        for locale, small in [("zh_CN", False), ("en", True)]:
            key = f"helper-shift-{locale}"
            command = [str(ENGINE), "--verbose", "--print-fps", "--path", str(ROOT / "game"),
                       "res://tests/helper_shift_test.tscn", "--", "--test-profile=helper_shift",
                       f"--lang={locale}", f"--out={out / key}"]
            if small:
                command.append("--small")
            execute(key, command, "HELPER_SHIFT_TEST PASS failures=0", 180)
    if args.runs > 0:
        execute("pacing", [str(ENGINE), "--headless", "--path", str(ROOT / "game"), "--", "--autotest",
                f"--test-profile=release_pacing_{stamp}", f"--runs={args.runs}"], "AUTOTEST OK:", 1800)
    after = fingerprint()
    stable = before == after
    player_unchanged = player_before == player_fingerprint()
    selected = not args.only or set(args.only) == {x["name"] for x in results}
    report = {"passed": bool(results) and selected and all(x["passed"] for x in results) and stable and player_unchanged,
              "uncapped_ui": args.uncapped_ui, "requested_scenarios": args.only,
              "engine": "Godot 4.7.2 stable", "source_unchanged": stable, "player_files_unchanged": player_unchanged,
              "checks": results, "source_sha256": before,
              "limitations": ["Automated fixtures and input injection do not establish human enjoyment or hardware gamepad compatibility.",
                              "No Steam backend, low-end hardware, or real-player pacing certification."]}
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(out, flush=True)
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
