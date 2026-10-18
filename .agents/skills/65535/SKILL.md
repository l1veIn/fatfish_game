---
name: "65535"
description: 使用 65535 API 查询余额、用量、模型、价格和异步任务，并通过 /v1/tasks 生成或修改图片。用户提到 65535、查询 API 余额或消费、查看可用模型或任务，或者要求用 65535 生图时使用。
---

# 65535

通过 65535 API 查询账户信息或异步生成图片。隐藏无关技术细节，直接向用户报告结果。

## 配置

- 请求地址固定为 `https://task-api-1-cn.65535.space`。
- API Key 变量名 `S65535_API_KEY`，已放在项目根目录 `.env`；脚本会先读环境变量，再向上查找 `.env`。
- 如果两处都没有，让用户在聊天中粘贴 Key，并写入 `.env`（`S65535_API_KEY=...`）。**不要**输出 Key。

## 用法（推荐用脚本，免去手写 curl 与转义）

脚本：`.agents/skills/65535/scripts/s65535.py`（Python 3，仅标准库，Windows/macOS/Linux 通用）。

```bash
python .agents/skills/65535/scripts/s65535.py usage [--start YYYY-MM-DD --end YYYY-MM-DD]
python .agents/skills/65535/scripts/s65535.py models
python .agents/skills/65535/scripts/s65535.py pricing
python .agents/skills/65535/scripts/s65535.py tasks --kind image --page 1 --page-size 20
python .agents/skills/65535/scripts/s65535.py task TASK_ID
python .agents/skills/65535/scripts/s65535.py image --prompt "..." [--model M] [--size 16:9] [--resolution 2k] [--n 1] [--image 参考图URL或本地路径] [--background transparent] [--quality high] [--out generated-images] [--name 文件名前缀]
```

`image` 会提交任务、每 2 秒轮询、下载结果到 `generated-images/`，并打印任务 ID 与本地绝对路径。

## 查询说明

- 余额与用量：`balance` 或 `remaining` 是美元余额；`usage.today`、`usage.total`、`model_stats`、`daily_stats` 分别是今日、累计、按模型、按日。只展示用户问到的项目。
- 模型与价格：`/v1/models` 返回当前 Key 可用模型；`/v1/pricing` 返回价格和在线状态。不要依赖 `pricing.endpoints` 判断生图能力，部署可能不在该字段标 image。
- 任务记录：用户没要求时，不展示完整提示词、原始响应或其他敏感字段。

## 模型选择

- 默认 `gpt-image-2`。用户指定模型时原样传入，不要擅自替换。
- 用户未指定时先 `models`：列表中有 `gpt-image-2` 就用它，否则从返回的模型名中选，不要猜测不存在的模型。
- 透明背景：`--background transparent`（配 gpt-image-2.5，直接出带透明通道的 PNG，不用再抠图）。
- 实测可用：`gpt-image-2`、`gpt-image-2-auto`、`gpt-image-2-n`、`gpt-image-2-eco`、`gemini-3-pro-image`、`gemini-3.1-flash-image`。实际范围以当前 Key 的响应为准。

## 生成流程

1. 仅在用户**明确要求**创建或修改图片时提交任务；讨论提示词或接口时不要生图。
2. 保留用户指定的主体、构图、风格、颜色、文字和排除项。信息足够就直接生成，不重复确认。
3. 只传用户需要的字段。数量默认 1；方图、横图、竖图默认 `1:1`、`16:9`、`9:16`。
4. 有参考图时用 `--image`（URL 或本地路径，本地图自动转 base64 data URI）。
5. 状态：`pending`、`running` 继续等待；`done` 成功；`failed` 停止并报告 `error_code` 与 `error_message`。**不要重复创建替代任务**。
6. 成功后向用户报告任务 ID 和本地绝对路径；界面支持时用 Markdown 直接展示图片。

## 底层请求格式（脚本异常时的参考）

```json
{
  "kind": "image",
  "model": "gpt-image-2",
  "input": {"prompt": "...", "size": "16:9", "resolution": "2k", "n": 1, "image": "URL 或 data URI"}
}
```

`POST /v1/tasks`，Header `Authorization: Bearer $S65535_API_KEY`；再轮询 `GET /v1/tasks/TASK_ID`。结果在 `result_urls`，或 `result.data[].b64_json`。不要向请求体添加 `path`，65535 会按 `kind` 自动选接口。

## 禁止

不要输出 API Key、原始 base64、内部状态名或无关接口细节。