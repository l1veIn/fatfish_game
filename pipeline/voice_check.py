"""Objective pronunciation check for voice lines (repo root):
    python pipeline/voice_check.py [--dir game/assets/audio/voice] [--model base]
Transcribes every line in game/data/voice_lines.json with faster-whisper and scores it two ways:
- PER: edit distance between the toneless pinyin of the script and of the transcript,
  divided by the script length. Ignores simplified/traditional and homophones, so what is
  left is wrong or missing syllables.
- tone-aware rate: the same with toned pinyin. The recogniser picks characters whose tones
  match what it heard, so this exposes wrong tones (a foreign accent) that PER forgives.
Rough guide with the small "base" model (tone-aware): < 0.25 good, 0.25-0.4 questionable,
> 0.4 bad. Very short or non-word lines (shouts) score badly by nature; listen to those.

score(path, text) is importable for picking the best take of a line.
"""
import json
import os
import re
import sys

from pypinyin import Style, lazy_pinyin

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_model = None


def _whisper(name="base"):
    global _model
    if _model is None:
        from faster_whisper import WhisperModel
        _model = WhisperModel(name, device="cpu", compute_type="int8")
    return _model


def syllables(text: str, tones=False) -> list:
    han = re.sub(r"[^一-鿿]", "", text)
    if tones:
        return lazy_pinyin(han, style=Style.TONE3, neutral_tone_with_five=True)
    return lazy_pinyin(han)


def edit_distance(a: list, b: list) -> int:
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def transcribe(path: str, model="base") -> str:
    segs, _ = _whisper(model).transcribe(path, beam_size=5, language="zh")
    return "".join(s.text for s in segs)


def score(path: str, text: str, model="base") -> tuple:
    """(PER, tone-aware error rate, transcript)"""
    heard = transcribe(path, model)
    ref = syllables(text)
    if not ref:
        return 0.0, 0.0, heard
    per = edit_distance(ref, syllables(heard)) / len(ref)
    ter = edit_distance(syllables(text, True), syllables(heard, True)) / len(ref)
    return per, ter, heard


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    vdir = sys.argv[sys.argv.index("--dir") + 1] if "--dir" in sys.argv else os.path.join(ROOT, "game", "assets", "audio", "voice")
    model = sys.argv[sys.argv.index("--model") + 1] if "--model" in sys.argv else "base"
    lines = json.load(open(os.path.join(ROOT, "game", "data", "voice_lines.json"), encoding="utf-8"))["lines"]
    by_voice = {}
    for l in lines:
        path = None
        for ext in (".ogg", ".wav", ".mp3"):
            if os.path.exists(os.path.join(vdir, l["file"] + ext)):
                path = os.path.join(vdir, l["file"] + ext)
                break
        if path is None:
            print(f"--- {l['file']}: missing")
            continue
        per, ter, heard = score(path, l["text"], model)
        by_voice.setdefault(l["voice"], []).append((per, ter))
        flag = "OK " if ter < 0.25 else ("?  " if ter < 0.4 else "BAD")
        print(f"{flag} {l['file']:9s} [{l['voice']:8s}] PER {per:.2f} tone {ter:.2f}  {l['text']}")
        print(f"{'':22s}heard: {heard}")
    for v, xs in by_voice.items():
        print(f"voice {v}: mean PER {sum(x[0] for x in xs) / len(xs):.2f}, "
              f"tone-aware {sum(x[1] for x in xs) / len(xs):.2f} over {len(xs)} lines")


if __name__ == "__main__":
    main()
