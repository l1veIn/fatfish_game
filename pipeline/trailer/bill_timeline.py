"""The cost + open-source video (2026-11-07): voice lines, timeline, stage, final mix.

    py -3 pipeline/trailer/bill_timeline.py voice     # 梁阿姨 reads the bill (ElevenLabs, key from .env, skips existing)
    py -3 pipeline/trailer/bill_timeline.py stage     # timeline.json + isolated Godot project in build/bill-20261107/stage
    (record with Godot --write-movie, see README.md)
    py -3 pipeline/trailer/bill_timeline.py export    # music + voice + game sound -> FatFish-Bill-1080p.mp4

Every number here is either from the author's own cost post (tieba.baidu.com/p/11124963312) or from
the local usage logs, passed in via stats.json (usage_stats). Nothing is estimated silently.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/bill-20261107"
AUD = ROOT / "art_src/promo/audio/bill"
PROMO_AUD = ROOT / "art_src/promo/audio"
GODOT = ROOT / "tools/godot/Godot_v4.7.2-stable_win64_console.exe"
GAME_SRC = ROOT / "game"
TITLE = "做这个游戏只花了31.7刀，还不够Steam上架费：账单和源码全公开"
BAR = 1.875


def stats() -> dict:
    return json.loads((ROOT / "pipeline/trailer/bill_stats.json").read_text(encoding="utf-8"))


def lines() -> dict:
    s = stats()
    return {
        "hook": "[loud, cheerful] 这游戏总成本——三十一块七！[laughs] 美元！",
        "intro": "[hearty] 来，小票给你念念。",
        "claude": "[reading aloud, brisk] 写代码，Claude 订阅，二十刀。",
        "eleven": "[reading aloud, brisk] 音效、配音、配乐，ElevenLabs，十刀。",
        "image": "[reading aloud, surprised] 将近三百张图，十一块三——人民币！",
        "total": "[loud] 合计，三十一块七。",
        "steam": "[laughing hard] Steam 上架费？一百刀！",
        "tokens": f"[curious, then shouting] 那 AI 到底吃了多少？{s['total_spoken']} token！",
        "sliver": f"[conspiratorial] 真正写出来的，只有{s['output_spoken']}。",
        "reread": "[amused] 剩下的，全在翻来覆去读上下文。",
        "joke": "[laughing] 跟大肥鱼一个样——吃得多，吐得少！",
        "api": f"[impressed] 按 API 原价算，光 Claude 就要{s['api_spoken']}。",
        "human": "[bossy] 那人干嘛？人负责说：不对，重来！",
        "r1": "[scolding] 留样柜的饭不能吃！",
        "r2": "[scolding] 手指画错了！",
        "r3": "[scolding] 音效太长了！",
        "update": "[excited] 这次更新，V4.1 三章！",
        "update2": "[excited] 会识图，能跑腿，十三个新技能。",
        "open": "[warm and proud] 账单摊开了，源码也摊开了！",
        "open2": "[warm, inviting] 全在 GitHub，拿去做你自己的！",
    }


def voice() -> None:
    import requests
    key = None
    for line in open(ROOT / ".env", encoding="utf-8-sig"):
        if line.startswith("ELEVENLABS_API_KEY="):
            key = line.split("=", 1)[1].strip()
    if not key:
        sys.exit("ELEVENLABS_API_KEY not found")
    vid = json.load(open(ROOT / "art_src/voice/voices.json", encoding="utf-8"))["auntie"]
    AUD.mkdir(parents=True, exist_ok=True)
    for name, text in lines().items():
        dest = AUD / f"{name}.mp3"
        if dest.exists():
            print("skip", name)
            continue
        r = requests.post(f"https://api.elevenlabs.io/v1/text-to-speech/{vid}", headers={"xi-api-key": key}, timeout=120,
                          params={"output_format": "mp3_44100_192"}, json={"text": text, "model_id": "eleven_v3"})
        if r.status_code != 200:
            print(f"  !! {name}: HTTP {r.status_code} {r.text[:200]}")
            continue
        dest.write_bytes(r.content)
        print("ok", name)


def trimmed(name: str) -> Path:
    """The line with its leading and trailing silence cut, loudness matched."""
    wav = OUT / "vo_tight" / f"{name}.wav"
    if not wav.exists():
        wav.parent.mkdir(parents=True, exist_ok=True)
        src = PROMO_AUD / "auntie_slogan_v2.mp3" if name == "slogan" else AUD / f"{name}.mp3"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-af",
                        "silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.02,areverse,"
                        "silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.08,areverse,"
                        "silenceremove=stop_periods=-1:stop_duration=0.2:stop_threshold=-40dB:stop_silence=0.1,atempo=1.14,loudnorm=I=-16:TP=-2", "-ar", "48000", "-ac", "2", str(wav)], check=True)
    return wav


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def timeline() -> dict:
    """Lay the lines one after another; each shot starts on its first line."""
    s = stats()
    order = [  # (line, gap after it in seconds)
        ("hook", 0.1), ("claude", 0.08), ("eleven", 0.08), ("image", 0.08), ("total", 0.06), ("steam", 0.2),
        ("tokens", 0.15), ("sliver", 0.06), ("reread", 0.06), ("api", 0.12), ("joke", 0.15),
        ("human", 0.06), ("r1", 0.05), ("r2", 0.05), ("r3", 0.2),
        ("update", 0.05), ("update2", 0.2), ("open", 0.06), ("open2", 0.12), ("slogan", 0.1),
    ]
    at = {}
    clips = []
    t = 0.12
    for name, gap in order:
        d = duration(trimmed(name))
        at[name] = t
        clips.append({"name": name, "t": round(t, 3), "d": round(d, 3)})
        t += d + gap
    length = round(t + 2.6, 2)
    shots = [
        [0.0, "game", "hook"],
        [at["claude"], "bill", "b1_receipt"],
        [at["tokens"], "tokens", "tokens"],
        [at["api"], "ill", "b2_context"],
        [at["human"], "redo", "b3_redo"],
        [at["update"], "game", "vision"],
        [at["update2"] + 1.1, "tree", "tree"],
        [at["open"], "github", "github"],
        [at["open2"], "ill", "b4_open"],
        [at["slogan"], "end", "p6_agi"],
    ]
    captions = [
        {"text": "总成本 31.7 美元", "style": "big", "x": 960, "y": 170, "size": 150, "from": 0.1, "to": at["claude"]},
        {"text": "首发账单 · 源码全公开", "style": "stamp", "x": 960, "y": 350, "size": 64, "from": 0.9, "to": at["claude"]},
        {"text": "Steam 上架费：100 美元", "style": "stamp", "x": 960, "y": 930, "size": 84, "from": at["steam"], "to": at["tokens"]},
        {"text": s["api_label"], "style": "stamp", "x": 900, "y": 150, "size": 60, "from": at["api"] + 0.05, "to": at["joke"]},
        {"text": "吃得多，吐得少", "style": "big", "x": 960, "y": 150, "size": 130, "from": at["joke"] + 0.1, "to": at["human"]},
        {"text": "AI 负责干活，人负责说“不对，重来”", "style": "paper", "x": 960, "y": 110, "size": 66, "from": at["human"] + 0.1, "to": at["update"]},
        {"text": "V4.1 三章上线", "style": "big", "x": 960, "y": 130, "size": 120, "from": at["update"], "to": at["update2"] + 1.05},
        {"text": "识图：缺的菜，窗口替你点亮", "style": "paper", "x": 660, "y": 960, "size": 56, "from": at["update"] + 0.3, "to": at["update2"] + 1.05},
        {"text": "13 个新技能 · 3 次新评测", "style": "paper", "x": 620, "y": 960, "size": 56, "from": at["update2"] + 1.15, "to": at["open"]},
        {"text": "开源了", "style": "stamp", "x": 1500, "y": 180, "size": 110, "from": at["open"] + 0.25, "to": at["open2"]},
        {"text": "代码 MIT · 素材 CC BY-NC-SA", "style": "paper", "x": 960, "y": 970, "size": 52, "from": at["open"] + 0.5, "to": at["open2"]},
        {"text": "拿去做你自己的", "style": "big", "x": 700, "y": 150, "size": 110, "from": at["open2"] + 0.1, "to": at["slogan"]},
        {"text": "要实现 AGI，得先吃饱！", "style": "stamp", "x": 400, "y": 450, "size": 58, "from": at["slogan"] + 0.15, "to": length},
    ]
    # burned-in subtitles: every voice line, because a lot of people watch with the sound low
    plain = {name: re.sub(r"\[[^\]]*\]\s*", "", text) for name, text in lines().items()}
    for c in clips:
        if c["name"] in plain:
            captions.append({"text": plain[c["name"]], "style": "sub", "x": 960, "y": 1034, "size": 44,
                             "from": c["t"], "to": c["t"] + c["d"] + 0.05})
    bill = {"lines": [
        {"t": at["claude"], "name": "Claude Pro 订阅", "note": "写代码 · 用掉一周额度的八成", "amount": "$20"},
        {"t": at["eleven"], "name": "ElevenLabs 首月半价", "note": "54 音效 · 42 配音 · 8 首 BGM", "amount": "$10"},
        {"t": at["image"], "name": "生图 gpt-image-2.5", "note": "将近 300 张，11.32 元", "amount": "$1.7"},
        {"t": at["total"], "name": "合计", "note": "", "amount": "$31.7", "total": True},
    ]}
    tokens = {
        "t_roll": at["tokens"] + 0.5, "t_bar": at["sliver"], "t_output": at["sliver"] + 0.5, "t_api": 1e9,
        "total_yi": s["total_yi"], "scope": s["scope"], "read_share": s["read_share"], "write_share": s["write_share"],
        "output_share": s["output_share"], "read_label": s["read_label"], "output_label": s["output_label"],
        "api_label": s["api_label"],
    }
    redo = [{"t": at["r1"], "text": "留样柜的饭不能吃"}, {"t": at["r2"], "text": "手指画错了"}, {"t": at["r3"], "text": "音效太长了"}]
    beats = [{"t": b["t"], "sfx": "ticket", "db": -3.0} for b in bill["lines"]]
    beats += [{"t": at["steam"], "sfx": "crit", "db": -2.0}, {"t": at["hook"] + 0.1, "sfx": "version_up", "db": -3.0}, {"t": at["api"] + 0.1, "sfx": "token", "db": -2.0}]
    beats += [{"t": r["t"] + 0.16, "sfx": "ticket", "db": -2.0} for r in redo]
    beats += [{"t": at["open"] + 0.25, "sfx": "ticket", "db": 0.0}, {"t": at["slogan"] + 0.15, "sfx": "ticket", "db": 0.0}]
    kb = {"b1_receipt": [1.05, 0.5, 0.5, 1.18, 0.5, 0.42], "b2_context": [1.0, 0.5, 0.5, 1.14, 0.42, 0.6],
          "b3_redo": [1.16, 0.5, 0.45, 1.02, 0.5, 0.5], "b4_open": [1.2, 0.6, 0.5, 1.0, 0.5, 0.5],
          "p6_agi": [1.2, 0.62, 0.42, 1.0, 0.5, 0.5]}
    return {"length": length, "shots": shots, "captions": captions, "bill": bill, "tokens": tokens, "redo": redo, "beats": beats,
            "clips": clips, "kb": kb, "end_cta": 0.6, "art": list(kb)}


ART = {"b1_receipt": "b1_receipt_0", "b2_context": "b2_context_fix_0", "b3_redo": "b3_redo_0", "b4_open": "b4_open_0", "p6_agi": "p6_agi_fix_0"}


def stage() -> None:
    from PIL import Image
    import qrcode
    data = timeline()
    st = OUT / "stage"
    shutil.copytree(GAME_SRC, st, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".godot", "addons", "tests", "build"))
    project = (st / "project.godot").read_text(encoding="utf-8")
    project = "\n".join(l for l in project.splitlines() if not l.startswith("_mcp_game_helper=") and not l.startswith("enabled=PackedStringArray"))
    project = project.replace('config/custom_user_dir_name="FatFishFreeLunch"', 'config/custom_user_dir_name="FatFishPromoBill"')
    project = project.replace('run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://promo/promo_bill.tscn"')
    project = project.replace("window_width_override=1280", "window_width_override=1920").replace("window_height_override=720", "window_height_override=1080")
    if "[rendering]" not in project:
        project += '\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\n'
    project += "\n[editor]\nmovie_writer/mjpeg_quality=0.95\nmovie_writer/mix_rate=48000\n"
    (st / "project.godot").write_text(project, encoding="utf-8", newline="\n")
    settings = st / "scripts/autoload/settings.gd"
    settings.write_text(settings.read_text(encoding="utf-8").replace(
        'if not OS.has_feature("web") and not DisplayServer.get_name() == "headless":',
        'if not OS.has_feature("web") and not DisplayServer.get_name() == "headless" and not OS.get_cmdline_args().has("--write-movie"):'),
        encoding="utf-8", newline="\n")
    promo = st / "promo"
    (promo / "art").mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(__file__).with_name("promo_bill.gd"), promo / "promo_bill.gd")
    (promo / "promo_bill.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://promo/promo_bill.gd" id="1"]\n[node name="PromoBill" type="Node2D"]\nscript = ExtResource("1")\n', encoding="utf-8")
    (promo / "timeline.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
    for name, src in ART.items():
        Image.open(ROOT / f"art_src/promo/{src}.png").convert("RGB").save(promo / "art" / f"{name}.png")
    shutil.copy2(ROOT / "art_src/fonts/ZCOOLKuaiLe-Regular.ttf", promo / "ZCOOLKuaiLe-full.ttf")
    shutil.copy2(ROOT / "art_src/fonts/NotoSansSC-VF.ttf", promo / "NotoSansSC-full.ttf")
    shutil.copy2(OUT / "github.png", promo / "github.png")
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=3)
    qr.add_data("https://www.bilibili.com/toy/fatfish-free-lunch/index.html")
    qr.make(fit=True)
    qr.make_image(fill_color="#172837", back_color="#fff6df").save(promo / "toy_qr.png")
    subprocess.run([str(GODOT), "--headless", "--path", str(st), "--import"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("length", data["length"], "stage", st)


def export() -> None:
    data = json.loads((OUT / "stage/promo/timeline.json").read_text(encoding="utf-8"))
    length = float(data["length"])
    final = OUT / "FatFish-Bill-1080p.mp4"
    inputs = ["-i", str(OUT / "capture.avi"), "-i", str(PROMO_AUD / "bgm_promo_a.mp3")]
    parts = []
    for i, c in enumerate(data["clips"]):
        inputs += ["-i", str(trimmed(c["name"]))]
        ms = int(float(c["t"]) * 1000)
        parts.append(f"[{i + 2}:a]adelay={ms}|{ms},apad=whole_dur={length}[v{i}]")
    n = len(data["clips"])
    voices = "".join(f"[v{i}]" for i in range(n))
    # the BGM's body: from the 15 s drop for 16 bars, repeated, ending on the 52.5 s final chord.
    # Rendered on its own first: chained crossfades of split streams silently ended the track early.
    body = 16 * BAR
    loops = int((length - 5.0) // body) + 1
    cut = length - 4.5
    bgm = str(PROMO_AUD / "bgm_promo_a.mp3")
    music_inputs = []
    for _ in range(loops):
        music_inputs += ["-ss", "15", "-t", str(body), "-i", bgm]
    music_inputs += ["-ss", "52.5", "-t", "6", "-i", bgm]
    joined = "".join(f"[{i}:a]" for i in range(loops))
    bed_wav = OUT / "music-bed.wav"
    subprocess.run(["ffmpeg", "-y", "-v", "error", *music_inputs, "-filter_complex",
                    f"{joined}concat=n={loops}:v=0:a=1,aresample=48000,atrim=0:{cut},asetpts=PTS-STARTPTS[a];"
                    f"[{loops}:a]aresample=48000[c];[a][c]acrossfade=d=0.05:c1=tri:c2=tri[m]",
                    "-map", "[m]", "-ac", "2", "-ar", "48000", str(bed_wav)], check=True)
    assert duration(bed_wav) > length - 0.5, f"music bed too short: {duration(bed_wav)}"
    inputs[3] = str(bed_wav)
    music = ["[1:a]volume=0.42[music]"]
    filters = ";".join(parts + music + [
        f"{voices}amix=inputs={n}:duration=longest:normalize=0,asplit[vo][vokey]",
        "[music][vokey]sidechaincompress=threshold=0.04:ratio=5:attack=12:release=280[bed]",
        f"[0:a]aresample=48000,volume=0.8,atrim=0:{length}[game]",
        f"[bed][game][vo]amix=inputs=3:duration=first:normalize=0,atrim=0:{length},"
        f"afade=t=out:st={length - 0.9}:d=0.9,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[audio]",
    ])
    (OUT / "audio-filter.txt").write_text(filters, encoding="utf-8")
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "warning", *inputs, "-filter_complex_script", str(OUT / "audio-filter.txt"),
                    "-map", "0:v", "-map", "[audio]", "-t", str(length), "-c:v", "libx264", "-preset", "slow", "-crf", "18",
                    "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart",
                    "-metadata", f"title={TITLE}", str(final)], check=True)
    # Silent stretches never show up on a contact sheet: audio and video must end together.
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,duration", "-of", "csv=p=0", str(final)],
                         capture_output=True, text=True, check=True).stdout
    durations = dict(line.split(",")[:2] for line in out.strip().splitlines())
    assert abs(float(durations["audio"]) - float(durations["video"])) < 0.2, durations
    print(final, os.path.getsize(final), durations)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    {"voice": voice, "stage": stage, "export": export}[sys.argv[1]]()
