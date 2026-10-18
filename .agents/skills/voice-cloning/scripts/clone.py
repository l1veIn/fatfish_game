#!/usr/bin/env python3
"""ElevenLabs 声音克隆 (Instant Voice Cloning - IVC) 命令行工具。

使用官方 SDK (elevenlabs)。API Key 读取环境变量 ELEVENLABS_API_KEY 或项目根目录 .env。
"""
import argparse
import json
import os
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass


def ensure_env():
    if not os.environ.get("ELEVENLABS_API_KEY"):
        for d in [Path.cwd(), *Path.cwd().parents]:
            env_file = d / ".env"
            if env_file.is_file():
                for line in env_file.read_text(encoding="utf-8-sig").splitlines():
                    line = line.strip()
                    if line.startswith("export "):
                        line = line[7:]
                    if "=" in line and not line.startswith("#"):
                        k, v = line.split("=", 1)
                        if k.strip() in ("ELEVENLABS_API_KEY", "ElevenLabs_KEY"):
                            os.environ["ELEVENLABS_API_KEY"] = v.strip().strip('"').strip("'")
                            return


def main():
    ensure_env()
    from elevenlabs import ElevenLabs

    client = ElevenLabs()

    parser = argparse.ArgumentParser(description="ElevenLabs 声音克隆 (IVC)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    # 1. 创建克隆
    c = sub.add_parser("create", help="通过音频样本克隆新声音")
    c.add_argument("--name", required=True, help="声音名称（如：hero_voice_01）")
    c.add_argument("--files", nargs="+", required=True, help="1个或多个音频样本文件路径 (mp3/wav)")
    c.add_argument("--description", default="", help="声音描述（如：深沉威严的老年国王）")
    c.add_argument("--labels", help="标签 JSON 格式，如 '{\"gender\": \"male\", \"age\": \"old\"}'")
    c.add_argument("--remove-noise", action="store_true", default=True, help="自动移除背景噪音")

    # 2. 列出自定义克隆声音
    l = sub.add_parser("list", help="列出已克隆的声音")
    l.add_argument("--all", action="store_true", help="包含预设库声音")

    # 3. 删除克隆声音
    d = sub.add_parser("delete", help="删除指定的克隆声音")
    d.add_argument("--voice-id", required=True, help="待删除的 voice_id")

    args = parser.parse_args()

    if args.cmd == "create":
        opened_files = []
        for fpath in args.files:
            p = Path(fpath)
            if not p.is_file():
                sys.exit(f"文件不存在: {fpath}")
            opened_files.append(open(p, "rb"))

        labels_dict = None
        if args.labels:
            try:
                labels_dict = json.loads(args.labels)
            except Exception as e:
                sys.exit(f"labels 必须是合法的 JSON 字符串: {e}")

        try:
            res = client.voices.ivc.create(
                name=args.name,
                files=opened_files,
                description=args.description,
                labels=labels_dict,
                remove_background_noise=args.remove_noise,
            )
            print(json.dumps({
                "voice_id": res.voice_id,
                "name": args.name,
                "status": "success"
            }, ensure_ascii=False, indent=2))
        finally:
            for f in opened_files:
                f.close()

    elif args.cmd == "list":
        resp = client.voices.get_all()
        voices = resp.voices
        if not args.all:
            voices = [v for v in voices if v.category == "cloned"]
        results = [
            {
                "voice_id": v.voice_id,
                "name": v.name,
                "category": v.category,
                "labels": v.labels,
                "description": v.description,
            }
            for v in voices
        ]
        print(json.dumps(results, ensure_ascii=False, indent=2))

    elif args.cmd == "delete":
        client.voices.delete(voice_id=args.voice_id)
        print(json.dumps({"voice_id": args.voice_id, "status": "deleted"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
