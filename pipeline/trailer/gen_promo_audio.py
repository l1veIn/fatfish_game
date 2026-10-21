"""Promo video audio (2026-10-21): a 60 s BGM written section by section to the edit, plus
梁阿姨 calling the slogan in her game voice. ElevenLabs; key read from ./.env (never printed).

Usage (repo root):  python pipeline/trailer/gen_promo_audio.py [music|voice|all]
Outputs art_src/promo/audio/ (raw mp3s; skips files that exist).
"""
import json
import os
import sys

import requests

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art_src", "promo", "audio")
API = "https://api.elevenlabs.io/v1"


def api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if key:
        return key
    for line in open(os.path.join(ROOT, ".env"), encoding="utf-8-sig"):
        if line.startswith("ELEVENLABS_API_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("ELEVENLABS_API_KEY not found")


HEADERS = {"xi-api-key": api_key()}

# Section lengths are the edit's shot boundaries (trailer2.gd SECTIONS uses the same numbers).
SECTIONS = [
    ("deadpan intro", 7000,
     ["very sparse and quiet", "solo music box and soft pizzicato strings", "hesitant, deadpan comedic timing",
      "little pauses", "ends with a short silence before the drop"],
     ["drums", "bass"]),
    ("title hit", 4000,
     ["sudden big cheerful drop", "brass stab and crash cymbal on the first beat", "full band kicks in",
      "bright main hook on glockenspiel and whistle"], []),
    ("lunch rush", 16000,
     ["bouncy groove", "marimba and plucky ukulele", "snappy snare and handclaps", "playful whistled lead melody",
      "busy canteen energy"], []),
    ("level up", 10000,
     ["building up step by step", "rising glockenspiel arpeggios", "chiptune synth plucks join",
      "sense of growing stronger", "drum fill at the end"], []),
    ("chaos peak", 10000,
     ["fullest and most energetic part", "festive and chaotic fun", "fast handclaps and tambourine",
      "the main hook played big by the whole band"], []),
    ("full belly", 4000,
     ["sudden comedic breakdown", "slow lazy tuba and soft Rhodes", "sleepy and satisfied", "half time"],
     ["fast drums"]),
    ("finale", 9000,
     ["triumphant anthem version of the main hook", "warm and joyful", "big final chord on the last beat",
      "short natural ring-out ending"], []),
]
GLOBAL = ["cute anime game trailer music", "cheerful lofi-pop with chiptune sparkle", "marimba, ukulele, glockenspiel, "
          "pizzicato strings, whistle", "128 bpm", "major key", "instrumental", "polished mix"]
NEGATIVE = ["vocals", "singing", "spoken words", "dark", "aggressive", "dubstep"]


def post(url: str, body: dict, dest: str) -> None:
    if os.path.exists(dest):
        print("skip", os.path.basename(dest))
        return
    r = requests.post(url, headers=HEADERS, json=body, params={"output_format": "mp3_44100_192"}, timeout=900)
    if r.status_code != 200:
        print(f"  !! {os.path.basename(dest)}: HTTP {r.status_code} {r.text[:400]}")
        return
    open(dest, "wb").write(r.content)
    print("ok", os.path.basename(dest))


def music() -> None:
    plan = {"positive_global_styles": GLOBAL, "negative_global_styles": NEGATIVE,
            "sections": [{"section_name": n, "positive_local_styles": p, "negative_local_styles": neg,
                          "duration_ms": d, "lines": []} for n, d, p, neg in SECTIONS]}
    json.dump(plan, open(os.path.join(OUT, "composition_plan.json"), "w", encoding="utf-8"), indent=1)
    for tag in ("a", "b"):   # two takes; pick by structure and listening
        post(f"{API}/music", {"composition_plan": plan, "model_id": "music_v2_5"},
             os.path.join(OUT, f"bgm_promo_{tag}.mp3"))


# 梁阿姨's designed voice (art_src/voice/voices.json); a few takes, the edit uses one.
LINES = {
    "auntie_slogan_v1": "[loud, cheerful] 要实现AGI，得先吃饱！",
    "auntie_slogan_v2": "[shouting, warm and bossy] 要实现AGI——得先吃饱！",
    "auntie_slogan_v3": "[hearty, laughing] 要实现AGI，得先吃饱！",
    "auntie_serve_v1": "[loud, cheerful] 开饭咯——！",
    "auntie_enough_v1": "[motherly, laughing] 慢点吃，管够！",
}


def voice() -> None:
    vid = json.load(open(os.path.join(ROOT, "art_src", "voice", "voices.json"), encoding="utf-8"))["auntie"]
    for name, text in LINES.items():
        dest = os.path.join(OUT, name + ".mp3")
        if os.path.exists(dest):
            print("skip", name)
            continue
        r = requests.post(f"{API}/text-to-speech/{vid}", headers=HEADERS, timeout=120,
                          params={"output_format": "mp3_44100_192"},
                          json={"text": text, "model_id": "eleven_v3"})
        if r.status_code != 200:
            print(f"  !! {name}: HTTP {r.status_code} {r.text[:200]}")
            continue
        open(dest, "wb").write(r.content)
        print("ok", name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("voice", "all"):
        voice()
    if what in ("music", "all"):
        music()
