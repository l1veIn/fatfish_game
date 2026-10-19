"""Inspect local meal records; compare only explicitly labelled, compatible manual runs.

python pipeline/compare_meals.py <save_meals directory> --csv build/meals.csv
python pipeline/compare_meals.py <directory> --manifest build/playtest-labels.json
No game progress is loaded or written. Unlabelled runs never get an inferred build name.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import statistics
from collections import defaultdict
from pathlib import Path

ROUTES = ("greens", "rotation", "warm", "review", "helpers", "random")


def load_records(folder: Path) -> list[tuple[Path, dict]]:
    records = []
    for path in sorted(folder.glob("meal*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema") == 1 and "result" in data and "build" in data:
            records.append((path, data))
    return records


def summarize(path: Path, data: dict, label: dict) -> dict:
    result, build = data["result"], data["build"]
    return {
        "file": path.name, "mode": data["mode"], "route": label.get("route", "unlabelled"),
        "stage": build["stage"], "skill_spend": build["skill_spend"],
        "earned": result["earned"], "paid_bites": result["paid_bites"],
        "live_bites": data["paid_bites"]["live"], "warm_bites": data["paid_bites"]["warm"],
        "sleep_bites": data["paid_bites"]["sleep"], "grok_seconds": data["first_grok_seconds"],
        "recipe_kinds_eaten": len(result["recipes_eaten"]),
        "warm_share": result["warm_share"], "eos_share": result["eos_share"],
        "spilled": result["spilled"], "wait_seconds": result["fish_wait_seconds"],
        "active_seconds": result.get("active_seconds", ""),
        "pressure": label.get("pressure", ""), "recovery": label.get("recovery", ""),
        "notes": label.get("notes", ""), "dropped_events": data["dropped_events"],
    }


def cohort(data: dict, label: dict) -> tuple | None:
    """Same cap, not same exact spend. Reject uncertain/mixed/automated evidence."""
    if not label:
        return None
    if label.get("route") not in ROUTES:
        raise ValueError("route must be one of " + ", ".join(ROUTES))
    cap = float(label["budget_cap"])
    if cap <= 0 or not label.get("player") or not label.get("device"):
        raise ValueError("positive budget_cap, player and device are required")
    if type(label.get("pressure")) is not int or not 1 <= label["pressure"] <= 5:
        raise ValueError("pressure must be a human rating from 1 to 5")
    if not label.get("recovery"):
        raise ValueError("recovery must describe recovery or say no interruption occurred")
    build, result = data["build"], data["result"]
    if (data["mode"] != "manual" or build["trial"] or data["dropped_events"]
            or not data.get("hash_complete", True) or not all(data["source_sha256"].values())
            or result["reason"] != "食堂关门了" or float(build["skill_spend"]) > cap):
        return None
    hashes = json.dumps(data["source_sha256"], sort_keys=True).encode()
    return (hashlib.sha256(hashes).hexdigest(), build["game_version"], build["stage"],
            build["duration"], cap, label["player"], label["device"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--manifest", type=Path, help="JSON mapping meal filename to human route/budget/player/device/pressure/recovery/notes")
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args()
    labels = json.loads(args.manifest.read_text(encoding="utf-8")) if args.manifest else {}
    records = load_records(args.directory)
    if not records:
        parser.error("no completed schema-1 meal records found")
    unknown = set(labels) - {path.name for path, _ in records}
    if unknown:
        parser.error("manifest references missing records: " + ", ".join(sorted(unknown)))
    rows, groups = [], defaultdict(lambda: defaultdict(list))
    for path, data in records:
        label = labels.get(path.name, {})
        row = summarize(path, data, label)
        rows.append(row)
        try:
            key = cohort(data, label)
        except (ValueError, KeyError, TypeError) as error:
            parser.error(f"{path.name}: {error}")
        if key is not None:
            groups[key][row["route"]].append(row)
        print(f"{path.name} [{row['mode']}/{row['route']}] spend={row['skill_spend']:,.0f} "
              f"score={row['earned']:,.0f} bites={row['paid_bites']} "
              f"sets={row['recipe_kinds_eaten']} warm={row['warm_share']:.1%} EOS={row['eos_share']:.1%}")
    if args.csv:
        args.csv.parent.mkdir(parents=True, exist_ok=True)
        with args.csv.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print("\nCompatible manual cohorts (same source, stage, duration, budget cap, player, device):")
    if not groups:
        print("None. Automated, unlabelled, unfinished and over-budget meals are not balance evidence.")
    for key, routes in groups.items():
        print(f"cap={key[4]:,.0f}, stage={key[2]}, player={key[5]}, device={key[6]}, source={key[0][:12]}")
        for route in ROUTES:
            runs = routes.get(route, [])
            if not runs:
                print(f"  {route}: missing")
                continue
            scores = [r["earned"] for r in runs]
            spend = [r["skill_spend"] for r in runs]
            pressure = [r["pressure"] for r in runs]
            print(f"  {route}: n={len(runs)} score median={statistics.median(scores):,.0f} "
                  f"range={min(scores):,.0f}..{max(scores):,.0f} "
                  f"spend={min(spend):,.0f}..{max(spend):,.0f} pressure median={statistics.median(pressure):g}")
        print("  These observations support design review; they do not certify mature or balanced builds.")


if __name__ == "__main__":
    main()
