"""Create a local, visibly labelled SDK/viewport fixture; never ship it in Toy.

Uses the production shell and bridge, a fake engine, and a delayed App SDK.
It verifies DOM geometry and SDK ordering, not physical Bilibili App behavior.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/qa/toy-container4"
OUT.mkdir(parents=True, exist_ok=True)
shell = (ROOT / "game/web/toy_shell.html").read_text(encoding="utf-8")
shell = shell.replace("https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js", "late_sdk.js")
for key, value in {"$GODOT_PROJECT_NAME": "Toy container QA fixture", "$GODOT_HEAD_INCLUDE": "",
                   "$GODOT_THREADS_ENABLED": "false", "$GODOT_CONFIG": "{}", "$GODOT_URL": "fake_engine.js"}.items():
    shell = shell.replace(key, value)
(OUT / "frame.html").write_text(shell, encoding="utf-8")
(OUT / "toy_bridge.js").write_bytes((ROOT / "game/web/toy_bridge.js").read_bytes())
(OUT / "fake_engine.js").write_text("""
class Engine {
  static getMissingFeatures() { return []; }
  startGame() { return Promise.resolve(); }
}
""", encoding="utf-8")
(OUT / "late_sdk.js").write_text("""
setTimeout(() => {
  let listener;
  window.toy = {
    isSupport: async name => ['onContainerChange','getContainerState','setContainerMode'].includes(name),
    onContainerChange(fn) {
      listener = fn;
      parent.postMessage({qa:'listen'}, '*');
      return () => {};
    },
    getContainerState: () => new Promise(resolve => setTimeout(() => resolve({
      deviceType:'phone', orientation:'portrait', immersive:false,
      viewport:{width:390,height:844}, safeArea:{top:44,bottom:34}
    }), 800)),
    setContainerMode(mode) {
      parent.postMessage({qa:'mode', mode}, '*');
      setTimeout(() => {
        listener({deviceType:'phone', orientation:'landscape', immersive:true,
          viewport:{width:390,height:844}, safeArea:{left:44,right:44,top:0,bottom:21}});
      }, 250);
      return Promise.resolve();
    }
  };
  // Equivalent to the production async script's load notification arriving late.
  if (window.FatFishToy) void window.FatFishToy.prepare();
}, 2700);
""", encoding="utf-8")
(OUT / "index.html").write_text("""<!doctype html><meta charset="utf-8">
<title>Toy container integration fixture</title>
<style>body{font:16px system-ui;background:#ece7dc;color:#241b14}iframe{border:2px solid #a67c43;width:390px;height:844px;box-sizing:content-box}pre{white-space:pre-wrap}</style>
<h1>Toy container integration fixture — simulated App, fake engine</h1>
<p>Real production shell/bridge. SDK arrives after entry. Portrait → landscape; stale SDK viewport/read. This is not a physical phone test.</p>
<pre id="result">Waiting for delayed SDK…</pre><iframe id="frame" src="frame.html"></iframe>
<script>
const frame=document.getElementById('frame'), events=[];
frame.onload=()=>setTimeout(()=>frame.contentDocument.getElementById('start-button').click(),100);
window.addEventListener('message', e=>{
  if(e.source!==frame.contentWindow || !e.data.qa) return;
  events.push(e.data.qa);
  if(e.data.qa==='mode') {
    frame.style.width='844px'; frame.style.height='390px';
    setTimeout(()=>{
      const doc=frame.contentDocument, rect=doc.getElementById('game').getBoundingClientRect();
      const result={scope:'simulated SDK and fake engine; actual iframe CSS geometry',events,
        viewport:[frame.contentWindow.innerWidth,frame.contentWindow.innerHeight],
        game:[rect.x,rect.y,rect.width,rect.height],mode:doc.documentElement.dataset.toyLandscape};
      result.passed=events[0]==='listen' && result.mode==='confirmed' &&
        Math.abs(rect.width-756)<1 && Math.abs(rect.height-369)<1 && Math.abs(rect.x-44)<1 && Math.abs(rect.y)<1;
      document.getElementById('result').textContent=JSON.stringify(result,null,2);
    },1300);
  }
});
</script>""", encoding="utf-8")
sources = ["game/web/toy_shell.html", "game/web/toy_bridge.js", "pipeline/prepare_toy_container_probe.py"]
(OUT / "source.json").write_text(json.dumps({name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                             for name in sources}, indent=2), encoding="utf-8")
print(OUT)
