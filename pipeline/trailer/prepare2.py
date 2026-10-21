"""Stage the promo v2 recording project (build/promo2-20261021/stage) without touching the game or saves.
Same isolation as prepare.py; adds the promo illustrations and full (unsubset) fonts for the captions."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build' / 'promo2-20261021'
STAGE = OUT / 'stage'
GODOT = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
OUT.mkdir(parents=True, exist_ok=True)
shutil.copytree(ROOT / 'game', STAGE, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.godot', 'addons', 'tests'))
project = (STAGE / 'project.godot').read_text(encoding='utf-8')
project = '\n'.join(line for line in project.splitlines()
                    if not line.startswith('_mcp_game_helper=') and not line.startswith('enabled=PackedStringArray'))
project = project.replace('config/custom_user_dir_name="FatFishFreeLunch"', 'config/custom_user_dir_name="FatFishPromoPC"')
project = project.replace('run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://promo/promo2.tscn"')
project = project.replace('window_width_override=1280', 'window_width_override=1920').replace('window_height_override=720', 'window_height_override=1080')
if '[rendering]' not in project:
    project += '\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\n'
project += '\n[editor]\nmovie_writer/mjpeg_quality=0.95\nmovie_writer/mix_rate=48000\n'
(STAGE / 'project.godot').write_text(project, encoding='utf-8', newline='\n')
# Movie Writer must keep 1080p even when the desktop's usable area is smaller (recording copy only).
settings = STAGE / 'scripts/autoload/settings.gd'
settings.write_text(settings.read_text(encoding='utf-8').replace(
    'if not OS.has_feature("web") and not DisplayServer.get_name() == "headless":',
    'if not OS.has_feature("web") and not DisplayServer.get_name() == "headless" and not OS.get_cmdline_args().has("--write-movie"):'),
    encoding='utf-8', newline='\n')
promo = STAGE / 'promo'
(promo / 'art').mkdir(parents=True, exist_ok=True)
shutil.copy2(Path(__file__).with_name('promo2.gd'), promo / 'promo2.gd')
(promo / 'promo2.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://promo/promo2.gd" id="1"]\n[node name="Promo2" type="Node2D"]\nscript = ExtResource("1")\n', encoding='utf-8')
# p4/p6: the *_fix takes (whale icons removed from the scenery)
ART = {'p1_hungry': 'p1_hungry_0', 'p2_auntie': 'p2_auntie_0', 'p3_catch': 'p3_catch_0',
       'p4_crew': 'p4_crew_fix_0', 'p5_full': 'p5_full_0', 'p6_agi': 'p6_agi_fix_0'}
for name, src in ART.items():
    Image.open(ROOT / f'art_src/promo/{src}.png').convert('RGB').save(promo / 'art' / f'{name}.png')
shutil.copy2(ROOT / 'art_src/fonts/ZCOOLKuaiLe-Regular.ttf', promo / 'ZCOOLKuaiLe-full.ttf')
shutil.copy2(ROOT / 'art_src/fonts/NotoSansSC-VF.ttf', promo / 'NotoSansSC-full.ttf')
import qrcode
qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=3)
qr.add_data('https://www.bilibili.com/toy/fatfish-free-lunch/index.html')
qr.make(fit=True)
qr.make_image(fill_color='#172837', back_color='#fff6df').save(promo / 'toy_qr.png')
subprocess.run([str(GODOT), '--headless', '--path', str(STAGE), '--import'], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
real_save = Path.home() / 'AppData/Roaming/FatFishFreeLunch'
manifest = {'player_files_before': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in real_save.glob('*') if p.is_file()},
            'art': ART, 'user_dir': 'FatFishPromoPC'}
(OUT / 'source-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(STAGE)
