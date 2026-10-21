"""Create a local browser DOM routing check, not a physical phone/Godot playtest."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
out = root / "build/qa/toy-hand-browser5"
out.mkdir(parents=True, exist_ok=True)
(out / "toy_bridge.js").write_bytes((root / "game/web/toy_bridge.js").read_bytes())
(out / "index.html").write_text('''<!doctype html><meta charset="utf-8">
<title>Toy touch input routing check</title>
<style>body{font:18px system-ui;background:#f7ecd9;color:#352a24}canvas{border:2px solid #aa8652;background:#ded2b9}pre{white-space:pre-wrap}</style>
<h1>Touch / compatibility mouse routing</h1>
<p>Production bridge, real DOM event propagation, synthetic events. No Godot engine or physical phone.</p>
<canvas id="canvas" width="840" height="120"></canvas><pre id="result">Running…</pre>
<script src="toy_bridge.js"></script><script>
const canvas=document.getElementById('canvas'), downstream=[], checks=[];
for(const type of ['touchstart','touchend','mousedown','mousemove','mouseup'])
  canvas.addEventListener(type,e=>downstream.push(type));
const dispatch=(type, ctor=Event, props={})=>canvas.dispatchEvent(new ctor(type,{bubbles:true,cancelable:true,...props}));
dispatch('touchstart',TouchEvent);
dispatch('mousemove',MouseEvent); dispatch('mousedown',MouseEvent);
dispatch('touchend',TouchEvent); dispatch('mouseup',MouseEvent);
checks.push({name:'native touch survives; untagged compatibility mouse does not reach engine listeners',pass:JSON.stringify(downstream)===JSON.stringify(['touchstart','touchend'])});
dispatch('pointermove',PointerEvent,{pointerType:'mouse'}); dispatch('mousemove',MouseEvent);
checks.push({name:'real mouse pointer immediately switches back to mouse control',pass:downstream.at(-1)==='mousemove'&&downstream.length===3});
document.getElementById('result').textContent=JSON.stringify({scope:'DOM event routing only; synthetic input, no physical phone',checks,downstream,passed:checks.every(c=>c.pass)},null,2);
</script>''', encoding="utf-8")
sources = ["game/web/toy_bridge.js", "pipeline/prepare_toy_input_probe.py"]
(out / "source.json").write_text(json.dumps({p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}, indent=2), encoding="utf-8")
print(out)
