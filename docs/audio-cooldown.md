# 大肥鱼普通语音间隔 · 2026-10-19

后期吃饭事件密集，原 `Audio.vo()` 仅按调用方概率决定播放，且同优先级可相互截断。结果是不同普通语音不断接续或打断，即使随机变体不重复，也容易疲劳。此次只调整 `audio.gd` 的语音调度，沿用全部已有资源，不改吃饭事件、收益或调用概率。

## 规则

- 普通进食/等待反应共用 **4.0 秒真实时间的起播间隔**：`fish_dig_in/bang/hmph/wait/grimace/bliss/savor/munch/crit`，且调用优先级小于 3。
- 大肥鱼上一句真正播放结束后，普通语音还需留 **0.65 秒空白**；被关键语音中断也会设置这段间隔。下一句普通语音满足冷却、空白和当前无人说话三个条件才播放。
- 普通语音不会截断正在播放的任何角色语音；被拒绝的请求直接丢弃，不排队，也不延长冷却。食物仍有原来的咀嚼音和动作反馈。
- **吐菜 `fish_spit`、顿悟 `fish_grok`、吃饱/失败 `fish_full/broke`** 不受普通冷却。保留原有优先级：吐菜 2 不能截断顿悟 3，同级关键事件仍可替换。
- **优先级 3+** 明确表示重要事件，包括结算里的 `fish_savor(3)`，不被普通规则误伤。
- `fish_happy/not_fat` 用于技能购买、标题互动和音量试听，不属于高频吃饭反应，保持即时；原购买发声概率不变。`version_up/trial_pass` 等升级音效走 SFX，完全不改。
- 采用 `Time.get_ticks_msec()`，不随慢动作、顿帧、4 倍测试速度或暂停冻结。Audio 保持 `PROCESS_MODE_ALWAYS`：正在说的话会自然结束，菜单期间不会积压被拒绝的语音。Master / Voice 静音只控制输出，恢复静音不补播旧请求。

4 秒把普通反应限制为最多每分钟约 15 次，事件仍按原概率触发；0.65 秒用于长句和关键句后的呼吸空间。这里没有改成定期自动发声，也没有增加新的语音。

## 验证

专属场景：`game/tests/audio_cooldown_test.tscn`，只接受 `--test-profile=audio_cooldown`，检查 `Settings._testing` 与 QA 存档路径。测试前后比较玩家 `save.json` 与 `settings.cfg` 字节，未调用保存设置或玩家存档写入。

```powershell
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/audio_cooldown_test.tscn -- --test-profile=audio_cooldown --out=C:/Users/A/Desktop/fatfish_game/build/qa/audio-cooldown
```

首次结果：**29 项检查，0 failures**。4 倍 time_scale 下混合普通语音高频请求 8.35 真实秒，实际起播三句，间隔 4.003 / 4.016 秒；关键语音结束后普通语音恢复留白实测 0.711 秒；暂停且 0.2 倍时钟等待 4.084 真实秒后正常恢复。覆盖普通/关键优先级、吐菜例外、顿悟保护、结算例外、购买/试听例外、chance=0、升级音效、静音和暂停无队列积压。

报告 `build/qa/audio-cooldown/report.json` 绑定 `audio.gd`、测试源码、所有大肥鱼 OGG 的 SHA-256 和时长，记录真实驱动名/混音采样率。此次驱动是 **Dummy**：验证的是已有音频流的真实时间播放状态、调度和静音总线设置，**没有录制扬声器输出，也没有完成主观听审**。玩家正在游玩，本轮没有启动额外 GPU 窗口或有声监听，不以这些检查声称整体声音疲劳感已被人类听审确认。

既有混音回归使用 `--test-profile=audio_cooldown_mix` 独立路径，结果 **0 failed**，见 `build/audio-cooldown-mix.log`；路由、音乐分层、duck、语音优先级及咀嚼互斥通过。它的真实输出电平项目在 headless 下按既有规则跳过。
