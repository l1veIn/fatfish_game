"""Promo v2: mix the new BGM, 梁阿姨's lines and the growl under the recorded game audio; encode MP4.
Run after prepare2.py and the Movie Writer capture (see README.md)."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/promo2-20261021'
AUD = ROOT / 'art_src/promo/audio'
FINAL = OUT / 'FatFish-Promo-AGI-1080p.mp4'
LENGTH = 59.0
TITLE = '超可爱的大肥鱼增量小游戏，要实现AGI得先吃饱！'

def run(args):
    subprocess.run([str(a) for a in args], check=True)

# (file, start in the video, gain). Speech onsets measured with speech-to-text: slogan_v2 0.28 s,
# serve 0.16 s, enough 0.94 s, so each line lands on its beat.
CLIPS = [
    (AUD / 'auntie_slogan_v2.mp3', 7.5 + 2 * 0.46875 - 0.28, 1.0),   # with the title stamp
    (AUD / 'growl_v1.mp3', 13.35, 0.9),                               # in the music's silence
    (AUD / 'auntie_serve_v1.mp3', 15.0 - 0.16, 1.0),                  # on the drop
    (AUD / 'auntie_enough_v1.mp3', 55.6 - 0.94, 0.8),                 # under the end card
]
inputs = ['-i', OUT / 'capture.avi', '-i', AUD / 'bgm_promo_a.mp3']
parts = []
for i, (f, at, gain) in enumerate(CLIPS):
    # loudnorm inside the delay chain broke the timing (short clips), so each line is levelled to a wav first
    wav = OUT / f'vo_{i}.wav'
    run(['ffmpeg', '-y', '-v', 'error', '-i', f, '-af', 'loudnorm=I=-16:TP=-2', '-ar', '48000', '-ac', '2', wav])
    inputs += ['-i', wav]
    ms = int(at * 1000)
    parts.append(f'[{i + 2}:a]volume={gain},adelay={ms}|{ms},apad=whole_dur={LENGTH}[v{i}]')
voices = ''.join(f'[v{i}]' for i in range(len(CLIPS)))
FULL = (48.75, 52.45)   # p5 吃饱了: the band goes muffled and quiet until the final chord
filters = ';'.join(parts + [
    f'{voices}amix=inputs={len(CLIPS)}:duration=longest:normalize=0,asplit[vo][vokey]',
    f"[1:a]aresample=48000,atrim=0:{LENGTH},"
    f"lowpass=f=650:enable='between(t,{FULL[0]},{FULL[1]})',volume=0.45:enable='between(t,{FULL[0]},{FULL[1]})',"
    f"volume=0.62[music]",
    '[music][vokey]sidechaincompress=threshold=0.05:ratio=4:attack=15:release=300[bed]',
    f'[0:a]aresample=48000,volume=0.85,atrim=0:{LENGTH}[game]',
    f'[bed][game][vo]amix=inputs=3:duration=first:normalize=0,'
    f'afade=t=out:st={LENGTH - 1.2}:d=1.2,loudnorm=I=-15:TP=-2.5:LRA=11,aresample=48000[audio]',
])
(OUT / 'audio-filter.txt').write_text(filters, encoding='utf-8')
run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'warning', *inputs,
     '-filter_complex', filters, '-map', '0:v', '-map', '[audio]', '-t', LENGTH,
     '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
     '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-ac', '2', '-movflags', '+faststart',
     '-metadata', f'title={TITLE}', '-metadata', 'artist=夸夸家族族长', FINAL])
# cover (the title card) and a storyboard
run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-ss', '10.2', '-i', FINAL, '-frames:v', '1', '-update', '1', OUT / 'cover.png'])
times = [5.9, 10.2, 14.3, 16.5, 19.6, 25, 31, 36.9, 39, 45, 50.5, 57]
for i, sec in enumerate(times):
    run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-ss', str(sec), '-i', FINAL,
         '-frames:v', '1', '-update', '1', OUT / f'frame-{i + 1:02d}.jpg'])
run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-framerate', '1', '-i', OUT / 'frame-%02d.jpg',
     '-vf', 'scale=640:360,tile=3x4:padding=12:margin=12:color=0x152735', '-frames:v', '1', '-update', '1', OUT / 'storyboard.jpg'])
probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(FINAL)]))
manifest = json.loads((OUT / 'source-manifest.json').read_text(encoding='utf-8'))
preserved = all(Path(p).exists() and hashlib.sha256(Path(p).read_bytes()).hexdigest() == sha
                for p, sha in manifest['player_files_before'].items())
(OUT / 'video-validation.json').write_text(json.dumps({'output': str(FINAL), 'player_files_unchanged': preserved,
                                                       'ffprobe': probe}, ensure_ascii=False, indent=2), encoding='utf-8')
assert preserved, 'Player files changed during capture; investigate before delivery.'
print(FINAL)
