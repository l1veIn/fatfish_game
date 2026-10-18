#!/usr/bin/env python3
"""65535 API 命令行封装（仅依赖标准库）。

用法见 ../SKILL.md。API Key 来自环境变量或项目 .env 中的 S65535_API_KEY。
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://task-api-1-cn.65535.space"
KEY_NAME = "S65535_API_KEY"

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass


def load_key() -> str:
    """优先读环境变量，其次从当前目录向上查找 .env。"""
    if os.environ.get(KEY_NAME):
        return os.environ[KEY_NAME].strip()
    here = [Path.cwd(), *Path.cwd().parents, *Path(__file__).resolve().parents]
    for d in here:
        f = d / ".env"
        if f.is_file():
            for line in f.read_text(encoding="utf-8-sig").splitlines():
                line = line.strip()
                if line.startswith("export "):
                    line = line[7:]
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    if k.strip() == KEY_NAME:
                        return v.strip().strip('"').strip("'")
    sys.exit(f"未找到 {KEY_NAME}：请写入项目根目录 .env 或设置环境变量。")


def http(method, path, body=None, query=None):
    url = BASE + path
    if query:
        url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {load_key()}")
    req.add_header("User-Agent", "dys-game-skill/1.0")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:800]}")


def show(obj):
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def to_data_uri(src: str) -> str:
    if src.startswith(("http://", "https://", "data:")):
        return src
    p = Path(src)
    mime = mimetypes.guess_type(p.name)[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}"


def download(url, dest: Path):
    req = urllib.request.Request(url, headers={"User-Agent": "dys-game-skill/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        dest.write_bytes(r.read())


def unwrap(d):
    """兼容 {data:{...}} 包装。"""
    if isinstance(d, dict) and "id" not in d and isinstance(d.get("data"), dict):
        return d["data"]
    return d


def cmd_image(a):
    inp = {"prompt": a.prompt, "n": a.n}
    if a.size:
        inp["size"] = a.size
    if a.resolution:
        inp["resolution"] = a.resolution
    if a.image:
        imgs = [to_data_uri(i) for i in a.image]
        inp["image"] = imgs[0] if len(imgs) == 1 else imgs
    if a.background:
        inp["background"] = a.background          # "transparent" (gpt-image-2.5): PNG with alpha
        inp.setdefault("output_format", "png")
    if a.quality:
        inp["quality"] = a.quality
    body = {"kind": "image", "model": a.model, "input": inp}
    task = unwrap(http("POST", "/v1/tasks", body))
    tid = task.get("id")
    if not tid:
        sys.exit(f"提交失败：{json.dumps(task, ensure_ascii=False)[:500]}")
    print(f"任务已提交：{tid}", file=sys.stderr)

    deadline = time.time() + a.timeout
    while time.time() < deadline:
        time.sleep(2)
        task = unwrap(http("GET", f"/v1/tasks/{tid}"))
        status = task.get("status")
        if status == "done":
            break
        if status == "failed":
            sys.exit(f"任务 {tid} 失败：{task.get('error_code')} {task.get('error_message')}")
    else:
        sys.exit(f"任务 {tid} 等待超时，可稍后用 `task {tid}` 查询（不要重复提交）。")

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    saved = []
    for i, url in enumerate(task.get("result_urls") or []):
        ext = Path(urllib.parse.urlparse(url).path).suffix or ".png"
        dest = out / f"{a.name or tid}_{i}{ext}"
        download(url, dest)
        saved.append(dest)
    res = task.get("result") or {}
    for i, item in enumerate(res.get("data", []) if isinstance(res, dict) else []):
        if item.get("b64_json"):
            dest = out / f"{a.name or tid}_b64_{i}.png"
            dest.write_bytes(base64.b64decode(item["b64_json"]))
            saved.append(dest)
    if not saved:
        sys.exit(f"任务 {tid} 已完成但没有找到图片结果。")
    print(f"任务 ID: {tid}")
    for p in saved:
        print(p.resolve())


def main():
    ap = argparse.ArgumentParser(description="65535 API")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("usage", help="余额与用量")
    s.add_argument("--start")
    s.add_argument("--end")
    sub.add_parser("models", help="当前 Key 可用模型")
    sub.add_parser("pricing", help="价格与在线状态")
    s = sub.add_parser("tasks", help="任务列表")
    s.add_argument("--kind", default="image")
    s.add_argument("--page", type=int, default=1)
    s.add_argument("--page-size", type=int, default=20)
    s = sub.add_parser("task", help="查询单个任务")
    s.add_argument("id")

    s = sub.add_parser("image", help="生成/修改图片并下载")
    s.add_argument("--prompt", required=True)
    s.add_argument("--model", default="gpt-image-2")
    s.add_argument("--size", help="如 1:1 / 16:9 / 9:16")
    s.add_argument("--resolution", help="如 1k / 2k")
    s.add_argument("--n", type=int, default=1)
    s.add_argument("--image", action="append", help="参考图 URL 或本地路径，可重复")
    s.add_argument("--background", choices=["transparent", "opaque", "auto"], help="背景：transparent 直接出透明 PNG（gpt-image-2.5）")
    s.add_argument("--quality", choices=["low", "medium", "high", "auto"], help="画质（官方参数）")
    s.add_argument("--out", default="generated-images")
    s.add_argument("--name", help="输出文件名前缀，默认任务 ID")
    s.add_argument("--timeout", type=int, default=600)

    a = ap.parse_args()
    if a.cmd == "usage":
        show(http("GET", "/v1/usage", query={"start_date": a.start, "end_date": a.end}))
    elif a.cmd == "models":
        show(http("GET", "/v1/models"))
    elif a.cmd == "pricing":
        show(http("GET", "/v1/pricing"))
    elif a.cmd == "tasks":
        show(http("GET", "/v1/tasks", query={"kind": a.kind, "page": a.page, "page_size": a.page_size}))
    elif a.cmd == "task":
        show(http("GET", f"/v1/tasks/{a.id}"))
    elif a.cmd == "image":
        cmd_image(a)


if __name__ == "__main__":
    main()
