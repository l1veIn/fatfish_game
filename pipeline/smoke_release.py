"""Run one isolated packaged meal and bind its source to a successful frozen verification.

python pipeline/smoke_release.py build/candidate-... --verification build/verification-.../report.json
This is a package/rendering smoke test, not a human playthrough or performance benchmark.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def player() -> dict:
    folder = Path(os.environ['APPDATA']) / 'FatFishFreeLunch'
    return {name: sha(folder / name) for name in ['save.json', 'save.json.bak', 'settings.cfg'] if (folder / name).exists()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--verification', type=Path, required=True)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    manifest = json.loads((candidate / 'build-manifest.json').read_text(encoding='utf-8'))
    verification = json.loads(args.verification.read_text(encoding='utf-8'))
    assert verification['passed'] and verification['source_unchanged'] and verification['player_files_unchanged']

    def source_mismatches():
        config = (ROOT / 'game/project.godot').read_text(encoding='utf-8')
        config = re.sub(r'^_mcp_game_helper=.*\n?', '', config, flags=re.M)
        config = re.sub(r'\[editor_plugins\]\s*\n.*?(?=\n\[|\Z)', '', config, flags=re.S)
        mismatches = []
        for relative, expected in manifest['source_sha256'].items():
            source = ROOT / 'game' / relative
            normalized = hashlib.sha256(config.encode('utf-8')).hexdigest() if relative == 'project.godot' else sha(source)
            verified = verification['source_sha256'].get('game/' + relative)
            if normalized != expected or sha(source) != verified or sha(candidate / 'source' / relative) != manifest['export_source_sha256'][relative]:
                mismatches.append(relative)
        return mismatches

    before = player()
    mismatches = source_mismatches()
    assert not mismatches, mismatches
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    shots = candidate / ('smoke-shots-' + stamp)
    command = [str(candidate / 'windows/FatFish.exe'), '--disable-vsync', '--max-fps', '120', '--resolution', '1280x720', '--',
               '--autotest', '--runs=1', '--test-profile=package_smoke_' + stamp, '--lang=zh_CN', '--shots=' + str(shots)]
    log_path = candidate / ('smoke-' + stamp + '.log')
    with log_path.open('w', encoding='utf-8') as stream:
        run = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=300)
    log = log_path.read_text(encoding='utf-8', errors='replace')
    errors = re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|FAIL ).*$', log, re.M)
    after = player()
    mismatches = source_mismatches()
    report = {'passed': run.returncode == 0 and 'AUTOTEST OK:' in log and not errors and before == after and not mismatches,
              'exit_code': run.returncode, 'errors': errors, 'player_files_unchanged': before == after,
              'player_before_sha256': before, 'player_after_sha256': after, 'source_mismatches': mismatches,
              'packaged_source_matches_verification': not mismatches, 'source_file_count': len(manifest['source_sha256']),
              'exe_sha256': sha(candidate / 'windows/FatFish.exe'), 'command': command,
              'shots': [str(p.relative_to(candidate)) for p in sorted(shots.glob('*.png'))],
              'verification_report': str(args.verification.resolve()), 'verification_sha256': sha(args.verification),
              'import_changes': manifest['import_changes'], 'utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'Packaged real window, one automatic meal, isolated profile. VSync-off is requested at startup but scene settings may override it; not a human gameplay or hardware performance certification.'}
    (candidate / ('smoke-report-' + stamp + '.json')).write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
