"""Promo v3 (short cut, 2026-10-22): the BGM starts at its 15 s drop (full band in the first frame),
runs 16 bars to the end of its phrase at 45 s, then jumps to the final chord at 52.5 s.
Run after recording promo2.gd with `-- --cut=short` into build/promo3-20261022 (see README.md)."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/promo3-20261022'
AUD = ROOT / 'art_src/promo/audio'
FINAL = OUT / 'FatFish-Promo-Short-1080p.mp4'
LENGTH = 35.5
BAR, BEAT = 1.875, 0.46875
TITLE = '如果大肥鱼是一款增量游戏'

def run(args):
    subprocess.run([str(a) for a in args], check=True)

# (file, start in the video, gain); speech onsets: serve 0.16 s, slogan_v2 0.28 s
CLIPS = [
    (AUD / 'growl_v1.mp3', BAR + 2.3, 1.1),                  # chalkboard: 咕噜噜
    (AUD / 'auntie_serve_v1.mp3', 3 * BAR - 0.16, 1.0),      # 开饭咯
    (AUD / 'auntie_slogan_v2.mp3', 16 * BAR + 2 * BEAT - 0.28, 1.0),   # with the end stamp
]
inputs = ['-i', OUT / 'capture.avi', '-i', AUD / 'bgm_promo_a.mp3']
parts = []
for i, (f, at, gain) in enumerate(CLIPS):
    wav = OUT / f'vo_{i}.wav'
    run(['ffmpeg', '-y', '-v', 'error', '-i', f, '-af', 'loudnorm=I=-16:TP=-2', '-ar', '48000', '-ac', '2', wav])
    inputs += ['-i', wav]
    ms = int(at * 1000)
    parts.append(f'[{i + 2}:a]volume={gain},adelay={ms}|{ms},apad=whole_dur={LENGTH}[v{i}]')
voices = ''.join(f'[v{i}]' for i in range(len(CLIPS)))
FULL = (15 * BAR, 16 * BAR - 0.05)   # 吃饱了: muffled, quiet, then the chord
filters = ';'.join(parts + [
    f'{voices}amix=inputs={len(CLIPS)}:duration=longest:normalize=0,asplit[vo][vokey]',
    '[1:a]aresample=48000,asplit[m1][m2]',
    '[m1]atrim=15:45,asetpts=PTS-STARTPTS[body]',
    '[m2]atrim=52.5:58.5,asetpts=PTS-STARTPTS[chord]',
    '[body][chord]acrossfade=d=0.04:c1=tri:c2=tri,'
    f"lowpass=f=650:enable='between(t,{FULL[0]},{FULL[1]})',volume=0.45:enable='between(t,{FULL[0]},{FULL[1]})',"
    'volume=0.62[music]',
    '[music][vokey]sidechaincompress=threshold=0.05:ratio=4:attack=15:release=300[bed]',
    f'[0:a]aresample=48000,volume=0.85,atrim=0:{LENGTH}[game]',
    f'[bed][game][vo]amix=inputs=3:duration=first:normalize=0,atrim=0:{LENGTH},'
    f'afade=t=out:st={LENGTH - 1.0}:d=1.0,loudnorm=I=-14:TP=-2.5:LRA=11,aresample=48000[audio]',
])
(OUT / 'audio-filter.txt').write_text(filters, encoding='utf-8')
run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'warning', *inputs,
     '-filter_complex', filters, '-map', '0:v', '-map', '[audio]', '-t', LENGTH,
     '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
     '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-ac', '2', '-movflags', '+faststart',
     '-metadata', f'title={TITLE}', '-metadata', 'artist=夸夸家族族长', FINAL])
times = [0.4, 1.4, 5.0, 6.2, 9, 12, 14.5, 17.9, 20, 25, 28.8, 34]
for i, sec in enumerate(times):
    run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-ss', str(sec), '-i', FINAL,
         '-frames:v', '1', '-update', '1', OUT / f'frame-{i + 1:02d}.jpg'])
run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-framerate', '1', '-i', OUT / 'frame-%02d.jpg',
     '-vf', 'scale=640:360,tile=3x4:padding=12:margin=12:color=0x152735', '-frames:v', '1', '-update', '1', OUT / 'storyboard.jpg'])
manifest = json.loads((ROOT / 'build/promo2-20261021/source-manifest.json').read_text(encoding='utf-8'))
preserved = all(Path(p).exists() and hashlib.sha256(Path(p).read_bytes()).hexdigest() == sha
                for p, sha in manifest['player_files_before'].items())
assert preserved, 'Player files changed during capture; investigate before delivery.'
print(FINAL)
