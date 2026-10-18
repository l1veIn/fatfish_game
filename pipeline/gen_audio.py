"""Generate the game's sound effects, ambience loops and music with ElevenLabs, then
convert them for Godot: SFX -> trimmed WAV, loops/music -> OGG. Existing files are skipped,
so re-running only fills in what is missing (delete a file to regenerate it).

Usage (repo root):  python pipeline/gen_audio.py [sfx|loops|music|all|normalize] [name ...]
Reads ELEVENLABS_API_KEY from the environment or ./.env.
Raw downloads go to art_src/audio_raw/, game files to game/assets/audio/.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

import requests

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RAW = os.path.join(ROOT, "art_src", "audio_raw")
OUT = os.path.join(ROOT, "game", "assets", "audio")
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


def fetch(url: str, body: dict, dest: str) -> bool:
    r = requests.post(url, headers=HEADERS, json=body, params={"output_format": "mp3_44100_128"}, timeout=600)
    if r.status_code != 200:
        print(f"  !! {os.path.basename(dest)}: HTTP {r.status_code} {r.text[:300]}")
        return False
    open(dest, "wb").write(r.content)
    return True


def ffmpeg(*args: str) -> None:
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


LOOP_FADE = 2.5   # seconds of the music's end crossfaded into its start


def make_loop(raw: str, final: str) -> None:
    """Music -> seamless loop: the last LOOP_FADE seconds are faded out over the faded-in first
    LOOP_FADE seconds, so the end of the file flows straight into its start. Also loudness-
    normalised so all tracks sit at the same level."""
    tmp = final + ".tmp.wav"
    ffmpeg("-i", raw, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", tmp)
    with wave.open(tmp, "rb") as w:
        rate, ch = w.getframerate(), w.getnchannels()
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(np.float32)
    n = int(LOOP_FADE * rate)
    ramp = np.linspace(0.0, 1.0, n)[:, None]
    head = a[:n] * np.sqrt(ramp) + a[-n:] * np.sqrt(1.0 - ramp)   # equal-power crossfade
    out = np.concatenate([head, a[n:-n]])
    with wave.open(tmp, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(np.clip(out, -32768, 32767).astype(np.int16).tobytes())
    ffmpeg("-i", tmp, "-c:a", "libvorbis", "-q:a", "5", final)
    os.remove(tmp)


def peak_normalize(path: str, target_db: float = -1.0) -> None:
    """Sound effects come back at very different levels; bring every peak to target_db so the
    in-game volumes (Audio.sfx volume_db) are the only mixing knob."""
    r = subprocess.run(["ffmpeg", "-i", path, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    peak = [l for l in r.stderr.splitlines() if "max_volume" in l]
    if not peak:
        return
    gain = target_db - float(peak[0].split()[-2])
    if abs(gain) < 0.5:
        return
    tmp = path + ".tmp.wav"
    ffmpeg("-i", path, "-af", f"volume={gain:.2f}dB", tmp)
    os.replace(tmp, path)


## Sound families that must sound equally loud from variant to variant (a crunch must not jump
## 8 dB between two catches): loudness-normalised to this many LUFS instead of peak-normalised,
## with a limiter so raising a quiet one does not clip. Matched by name prefix.
LEVEL_LUFS = {"catch": -26.0, "combo": -20.0}


def loudness(path: str) -> float:
    r = subprocess.run(["ffmpeg", "-i", path, "-af", "apad=pad_dur=0.5,ebur128", "-f", "null", "-"],
                       capture_output=True, text=True)
    lines = [l for l in r.stderr.splitlines() if l.strip().startswith("I:")]
    return float(lines[-1].split()[1])


def level(path: str) -> None:
    name = os.path.basename(path).rsplit(".", 1)[0]
    target = next((v for k, v in LEVEL_LUFS.items() if name.startswith(k)), None)
    if target is None:
        peak_normalize(path)
        return
    gain = target - loudness(path)
    if abs(gain) < 0.5:
        return
    tmp = path + ".tmp.wav"
    ffmpeg("-i", path, "-af", f"volume={gain:.2f}dB,alimiter=limit=0.89:attack=1:release=30:level=disabled", tmp)
    os.replace(tmp, path)


def main() -> None:
    cues = json.load(open(os.path.join(ROOT, "pipeline", "audio_cues.json"), encoding="utf-8"))
    group = sys.argv[1] if len(sys.argv) > 1 else "all"
    if group == "normalize":   # re-level the existing sound effects (LEVEL_LUFS, else peaks)
        for f in sorted(os.listdir(os.path.join(OUT, "sfx"))):
            if f.endswith(".wav"):
                level(os.path.join(OUT, "sfx", f))
        return
    only = set(sys.argv[2:])
    for sub in ("sfx", "loops", "music"):
        os.makedirs(os.path.join(RAW, sub), exist_ok=True)
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)

    for kind in ("sfx", "loops", "music"):
        if group not in (kind, "all"):
            continue
        for name, spec in cues[kind].items():
            if only and name not in only:
                continue
            ext = "wav" if kind == "sfx" else "ogg"
            final = os.path.join(OUT, kind, f"{name}.{ext}")
            raw = os.path.join(RAW, kind, f"{name}.mp3")
            if os.path.exists(final) or (name.startswith("perc_") and os.path.exists(raw)):
                continue   # perc_*: drum one-shots for make_music_layers.py, kept raw, not in the game
            print(f"{kind}: {name}")
            if not os.path.exists(raw):
                if kind == "music":
                    ok = fetch(f"{API}/music", {"prompt": spec["prompt"], "music_length_ms": spec["length_ms"],
                                                "model_id": "music_v2_5", "force_instrumental": True}, raw)
                else:
                    ok = fetch(f"{API}/sound-generation", {"text": spec["text"], "duration_seconds": spec["duration"],
                                                           "prompt_influence": 0.5, "loop": kind == "loops"}, raw)
                if not ok:
                    continue
            if name.startswith("perc_"):
                continue
            if kind == "sfx":
                # trim leading silence so hits land on the frame they are triggered;
                # very quiet sounds can be trimmed away entirely, so fall back to untrimmed
                ffmpeg("-i", raw, "-af", "silenceremove=start_periods=1:start_threshold=-45dB", "-ac", "1", final)
                if os.path.getsize(final) < 4000:
                    ffmpeg("-i", raw, "-ac", "1", final)
                level(final)
            elif kind == "music":
                make_loop(raw, final)
            else:
                ffmpeg("-i", raw, "-c:a", "libvorbis", "-q:a", "5", final)
    print("done")


if __name__ == "__main__":
    main()
