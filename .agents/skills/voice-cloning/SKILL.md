---
name: voice-cloning
description: 使用 ElevenLabs 即时声音克隆 (Instant Voice Cloning - IVC) API，从一段或多段录音样本中克隆出特定角色的自定义音色，获取 voice_id 供配音或语音生成使用。当用户要求克隆声音、添加自定义角色声音、定制配音音色时使用。
---

# ElevenLabs 声音克隆 (Voice Cloning)

通过 ElevenLabs 的 Instant Voice Cloning (IVC) API，为游戏中的主要角色、NPC、旁白定制专属音色。克隆成功后返回唯一的 `voice_id`，可直接配合 `text-to-speech` 或 `voice-changer` 技能使用。

## 配置与前置

- 依赖环境变量 `ELEVENLABS_API_KEY`（已在 `.env` 中配置）。
- 依赖官方 Python SDK：`pip install elevenlabs`（已安装）。
- 权限说明：声音克隆（IVC）需要 ElevenLabs 付费订阅（Starter / Creator / Pro 等级别，当前账户为 Creator 套餐，完全支持）。

## 录音样本要求（提升克隆品质的最佳实践）

1. **样本时长**：单个样本建议在 1 到 5 分钟之间（或提供 3~5 段清晰片段，每段 30~60 秒）。
2. **音频质量**：必须无背景音乐、无重叠人声、无明显回音混响。若有底噪，脚本默认开启 `remove_background_noise`，也可以先通过 `voice-isolator` 技能先处理一遍音频再克隆。
3. **表现力**：样本语调尽量贴近该游戏角色在游戏里的常态语速、情绪。

## 常用命令

工具路径：`.agents/skills/voice-cloning/scripts/clone.py`

```bash
# 1. 提交样本创建克隆声音
python .agents/skills/voice-cloning/scripts/clone.py create \
  --name "npc_goblin_elder" \
  --files "path/to/sample1.wav" "path/to/sample2.mp3" \
  --description "沙哑阴险的地精长老声音" \
  --labels '{"gender": "male", "age": "elder", "character": "monster"}'

# 返回示例：
# {
#   "voice_id": "21m00Tcm4TlvDq8ikWAM",
#   "name": "npc_goblin_elder",
#   "status": "success"
# }

# 2. 列出所有克隆的声音
python .agents/skills/voice-cloning/scripts/clone.py list

# 3. 使用克隆后的 voice_id 进行配音生成
# （结合 text-to-speech 技能）
python -c "from elevenlabs import ElevenLabs; client = ElevenLabs(); audio = client.text_to_speech.convert(voice_id='<VOICE_ID>', text='快离开这里，人类！'); open('voice_output.mp3', 'wb').write(b''.join(audio))"

# 4. 删除不再需要的克隆声音
python .agents/skills/voice-cloning/scripts/clone.py delete --voice-id "<VOICE_ID>"
```

## 注意事项

- 克隆是创建新的音色（输出 `voice_id`）；
- 若只想把现有录音的音色实时换成另外一个人的声音，请使用 `voice-changer`；
- 若录音中有杂音或想提取人声，请使用 `voice-isolator`。
