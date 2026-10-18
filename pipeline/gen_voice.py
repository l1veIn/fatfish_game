"""Voices for 大肥鱼 and 梁阿姨 (docs/polish_roadmap.md, group 1): one designed ElevenLabs voice
per character, so every line sounds like the same person. Interjections only (嗯、哦、诶、啊、哼、
噗……), never full sentences: nothing to translate, and nobody real is imitated.

Usage (repo root):
    python pipeline/gen_voice.py design fish|auntie   # candidate voices -> art_src/voice/candidates/
    python pipeline/gen_voice.py save <role> <generated_voice_id> <name>   # keep the picked one
    python pipeline/gen_voice.py lines fish|auntie    # record every cue -> game/assets/audio/voice/
Reads ELEVENLABS_API_KEY from the environment or ./.env (never printed).
"""
import base64
import json
import os
import sys

import requests

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art_src", "voice")
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

ROLES = {
    # 大肥鱼: no lines, only vocal attitude (user: 臭屁小女孩的语气), voiced like anime brats are: by an
    # adult voice actress (ElevenLabs will not design children's voices)
    "fish": {
        "description": ("A young adult female voice actress performing a cute bratty anime character for a game: "
                        "cheeky and smug, a bit lazy and full of herself, giggles mischievously, huffs and pouts, "
                        "munches greedily. Bright, high and cute but not shrill, slightly nasal, playful attitude. "
                        "Native Mandarin Chinese speaker. Clean close-mic studio recording, no background noise."),
        "text": ("哼哼~ 嘿嘿嘿。诶~？嗯哼！唔姆唔姆唔姆……嗯~~好吃！哇哦~ 哼！噗——呸呸！呃……呜……"
                 "诶？！嘿嘿~ 嗯哼哼。哈~ 嗝。嘻嘻。哼，才不要。唔……嗯嗯！哇~~ 嘿嘿，还要！"
                 "哼哼哼~ 唔姆……嗯~！诶嘿。哼！嘿嘿嘿~ 嗯~~ 哇！"),
    },
    # 梁阿姨: hearty canteen-auntie noises, a few two-word calls at most
    "auntie": {
        "description": ("A fictional middle-aged Chinese school canteen dinner lady: loud, warm, hearty and bossy in a "
                        "kind motherly way, a little hoarse from shouting over the lunch rush, big laugh. Native "
                        "Mandarin Chinese speaker. Clean studio recording, no background noise."),
        "text": ("哎——！来来来！哎哟~ 好嘞！啧啧啧。哈哈哈！快快快！哎呀呀……嗯！多吃点菜！"
                 "哎——！好嘞好嘞！哟~ 来咯！哈哈！啧！哎哟喂……嘿！来来来来！好——嘞！"
                 "哎呀！嗯嗯！哈哈哈哈！快点快点！哎~ 来！"
                 "哟——！好嘞好嘞好嘞！哎哟哎哟~ 来来来，排好队！哈哈哈！嗯——！"),
    },
}


def design(role: str) -> None:
    spec = ROLES[role]
    os.makedirs(os.path.join(OUT, "candidates"), exist_ok=True)
    # the v3 voice designer first (more expressive: giggles, huffs); the older endpoint if it is not there
    r = requests.post(f"{API}/text-to-voice/design", headers=HEADERS, timeout=300,
                      json={"voice_description": spec["description"], "text": spec["text"], "model_id": "eleven_ttv_v3"},
                      params={"output_format": "mp3_44100_128"})
    if r.status_code != 200:
        print(f"  (v3 designer: HTTP {r.status_code} {r.text[:160]}; trying the older one)")
        r = requests.post(f"{API}/text-to-voice/create-previews", headers=HEADERS, timeout=300,
                          json={"voice_description": spec["description"], "text": spec["text"]},
                          params={"output_format": "mp3_44100_128"})
    if r.status_code != 200:
        sys.exit(f"HTTP {r.status_code}: {r.text[:300]}")
    previews = r.json().get("previews", [])
    index = []
    for i, p in enumerate(previews):
        path = os.path.join(OUT, "candidates", f"{role}_{chr(65 + i)}.mp3")
        open(path, "wb").write(base64.b64decode(p["audio_base_64"]))
        index.append({"file": os.path.basename(path), "generated_voice_id": p["generated_voice_id"]})
        print(path)
    json.dump(index, open(os.path.join(OUT, "candidates", f"{role}.json"), "w", encoding="utf-8"), indent=1)


def save(role: str, gid: str, name: str) -> None:
    spec = ROLES[role]
    r = requests.post(f"{API}/text-to-voice/create-voice-from-preview", headers=HEADERS, timeout=120,
                      json={"voice_name": name, "voice_description": spec["description"], "generated_voice_id": gid})
    if r.status_code != 200:
        sys.exit(f"HTTP {r.status_code}: {r.text[:300]}")
    vid = r.json()["voice_id"]
    path = os.path.join(OUT, "voices.json")
    voices = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    voices[role] = vid
    json.dump(voices, open(path, "w", encoding="utf-8"), indent=1)
    print(role, "->", vid)


## Her noises and the auntie's calls, by cue: each list item is one variant (the game picks one
## at random and varies the pitch a little). eleven_v3 reads the [tags] as performance notes.
CUES = {
    "fish": {
        "dig_in": ["[excited] 嘿嘿~！", "嗯~！", "[giggles] 嘻嘻~"],            # a box arrives
        "bite": ["[quick] 啊呜！", "[quick] 嗷呜！", "[quick] 啊姆！", "[quick] 啊呜~"],   # every bite (-> sfx chomp, short)
        "munch": ["[quick] 唔姆！", "[quick] 姆！", "[quick] 嗯姆！"],        # (now and then while eating; user: short)
        "savor": ["[delighted] 嗯~~~！", "[delighted] 唔嗯！", "哇哦~~"],       # something good: a 套餐, a 金牌
        "bliss": ["[satisfied sigh] 哈~~", "[happy hum] 嗯嗯嗯~", "[dreamy] 呼~~"],  # a big one: 神级, 保温箱
        "wait": ["嗯？", "[curious] 嗯哼？"],                                 # nothing to eat
        "bang": ["[impatient] 哼哼！", "[whiny] 嗯——！"],                      # banging the basin
        "hmph": ["[pouting] 哼！", "[annoyed] 哼哼！"],                        # sulking, basin on her head
        "spit": ["[disgusted, quick] 噗！", "[disgusted, quick] 呸！"],       # greens (user: short)
        "grimace": ["[hesitant, then surprised] 唔……嗯？", "[reluctant, then curious] 呜……诶？"],   # forcing greens down: huh, not bad?
        "grok": ["[surprised] 诶？！", "[amazed] 诶——？！"],                   # 顿悟
        "crit": ["[excited] 哇！", "[gleeful] 嘿！"],                          # a crit bite
        "full": ["[content] 嗝……嘿嘿~", "[satisfied] 呼……嗝。"],              # closing time
        "happy": ["[giggles] 嘿嘿~", "[smug] 嗯哼~"],                         # a skill bought
        "not_fat": ["[pouting] 哼~", "[huffy] 才、才不……哼！"],               # every fifth skill
        "broke": ["[sad] 呜……", "[sulky] 嗯……"],                             # can't afford it
    },
    "auntie": {
        "start": ["[cheerful, loud] 来来来！", "[loud] 开饭咯！"],            # the shift starts
        "rush": ["[loud, hurried] 快快快！", "[shouting] 哎——！"],           # rush hour
        "care": ["[motherly] 多吃点菜！", "[bossy, warm] 青菜也要吃啊！"],     # 阿姨的关心
        "laugh": ["[hearty laugh] 哈哈哈！", "[cheerful] 好嘞！"],             # a 评测 passed
    },
}


## Short cues are cut to this many seconds (fading out), whatever breath the voice adds after
## the syllable (user: 短促).
MAXLEN = {"bite": 0.45, "munch": 0.5, "spit": 0.65, "savor_v2": 0.9, "grimace": 1.3}   # cue, or cue_vN


def lines(role: str) -> None:
    import subprocess
    vid = json.load(open(os.path.join(OUT, "voices.json"), encoding="utf-8"))[role]
    raw = os.path.join(OUT, "raw")
    game = os.path.join(ROOT, "game", "assets", "audio", "voice")
    os.makedirs(raw, exist_ok=True)
    os.makedirs(game, exist_ok=True)
    for cue, texts in CUES[role].items():
        for i, text in enumerate(texts):
            name = f"{role}_{cue}_v{i + 1}"
            mp3 = os.path.join(raw, name + ".mp3")
            if not os.path.exists(mp3):
                r = requests.post(f"{API}/text-to-speech/{vid}", headers=HEADERS, timeout=120,
                                  params={"output_format": "mp3_44100_128"},
                                  json={"text": text, "model_id": "eleven_v3"})
                if r.status_code != 200:
                    print(f"  !! {name}: HTTP {r.status_code} {r.text[:200]}")
                    continue
                open(mp3, "wb").write(r.content)
            # trim the silence at both ends, even out the loudness, mono ogg for Godot (the per-bite
            # noise is a pooled sound effect instead: game/assets/audio/sfx/chomp_vN.wav)
            ogg = os.path.join(game, name + ".ogg")
            if role == "fish" and cue == "bite":
                ogg = os.path.join(ROOT, "game", "assets", "audio", "sfx", f"chomp_v{i + 1}.wav")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, "-af",
                            "silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.06,areverse,"
                            "silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.06,areverse,"
                            "loudnorm=I=-18:TP=-2:LRA=7" + (",atrim=0:%.2f,afade=t=out:st=%.2f:d=0.08" % (cap, cap - 0.08) if (cap := MAXLEN.get(f"{cue}_v{i + 1}", MAXLEN.get(cue))) else ""), "-ac", "1", "-ar", "44100"] + (["-c:a", "pcm_s16le"] if ogg.endswith(".wav") else ["-c:a", "libvorbis", "-q:a", "6"]) + [ogg],
                           check=True)
            print(name)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "design":
        design(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == "lines":
        lines(sys.argv[2])
    elif len(sys.argv) >= 5 and sys.argv[1] == "save":
        save(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__)
