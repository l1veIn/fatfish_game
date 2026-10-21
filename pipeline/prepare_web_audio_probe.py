"""Create a separate instrumented copy of a Web export for browser audio QA."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve()
if output.exists():
    raise SystemExit("Use a new output directory; existing QA evidence is preserved.")
shutil.copytree(source, output)
probe = Path(__file__).with_name("web_audio_probe.js")
shutil.copy2(probe, output / probe.name)
html = output / "index.html"
content = html.read_text(encoding="utf-8")
assert "<head>" in content
html.write_text(content.replace("<head>", '<head>\n<script src="web_audio_probe.js"></script>', 1), encoding="utf-8")
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
(output.parent / (output.name + "-source.json")).write_text(json.dumps({
    "source": str(source), "source_files_sha256": {
        p.relative_to(source).as_posix(): digest(p) for p in sorted(source.rglob("*")) if p.is_file()
    }, "probe_sha256": digest(probe), "output": str(output),
    "limitation": "Measures browser PCM reaching destination, not physical speaker output.",
}, indent=2), encoding="utf-8")
print(output)
