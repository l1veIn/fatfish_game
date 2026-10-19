# 食堂操作与机制修复

本轮仅修改 `game/scripts/run/canteen_run.gd`，新增专属 `canteen_controls_test.gd/.tscn`；`meal_rules.gd`、Game 字段、暂停菜单和设置由各自所有者实现。未运行共享 Godot MCP、编辑器导入或 GPU 验收。

## 根因与处理

| 用户现象 | 根因 | 当前实现 |
| --- | --- | --- |
| 金饭盒改变全屏轨迹 | `_magnet()` 额外添加 220 像素，旧力场在 360 像素高度内不断累加横向速度 | 删除材质磁力；显式技能只影响下降、接近盒口的食物，180 像素高、最多 220 像素横向距离，边缘衰减，横向目标速度不超过 150 像素/秒。谱谱的局部吸力同样改为衰减、收束。 |
| 思考没 CD、耗尽后音效爆发 | 每帧以 `按住且能量>0` 决定状态，耗尽后的回气立即再次激活 | `THINK_COOLDOWN = 1.0` 秒；`THINK_MIN_CHARGE = 0.5` 秒；只接受新的按下沿。持有到耗尽，哪怕能量回满也必须松开再按。声音仅在实际状态变化时触发。 |
| 暂停恢复误触思考 | 按键残留、原状态未清理 | `pause(from_focus := false)` 接入公共失焦提示；暂停结束思考，恢复有 0.18 秒输入保护，仍需新的按下沿。 |
| 金色落点看似偏离、像等级特效 | 预测忽略磁力；旧重力半隐式积分与解析预测不一致；标记用金色和星星 | 普通食物改为精确重力位移；预测使用与真实食物相同的局部吸力。标记统一淡蓝短线，明确表示“饭盒当前接触高度的预计落点”，只在思考或混合思考生效时显示。助手或玩家后续移动会令预测更新。 |
| 入盘后金银品质难辨 | `boxed` 明确禁用轮廓，只剩间歇扫光；助手盒完全丢掉品质渲染 | 空中、玩家盒、助手盒保留贴合素材轮廓的银/金常亮光。减少动态时停用扫光和星星，保留静态轮廓。没有新增圆圈。 |
| 鼠标饭盒跟手差 | 鼠标与手柄共用重盒速度/加速度限制 | 鼠标直接追踪目标，食物晃动独立计算；键盘/手柄仍限速并有更快响应。 |
| 偶发漏接 | 只比较帧末横坐标；没有记录盒子运动；长帧中固定让助手先接 | 记录前帧盒位置，做食物相对盒口的连续扫掠判定。玩家与助手按接触时间决定先后。8 像素横向容差、12 像素盒口厚度防止像素边缘漏接。 |
| 上下文溢出暗扣 token | 结账阶段对超过下一目标 1.5 倍的收入开平方并从钱包扣除 | 已完全删除限制、扣款和 receipt.fuse 赋值。局内收入与结账倍率正常保留。 |
| 档口双条不明 | 每条对应一根独立出菜触手，但没有解释 | 每档口显示“出菜 ×N”，每条进度标勺序号；柜台说明“每条进度是一把勺子 · 满格后抛菜”。 |

## 构筑接线

`MEAL_RULES` 预加载 `game/scripts/run/meal_rules.gd`。`_box_profile()` 用真实 `_cells()`（含压缩后格数）标准化食物；`_plan_box()` 同时用于手边预览与真实送出。

`_note_served()` 仅在非空玩家饭盒第一次实际提交时冻结 `meal_rule` 和 `chain_multiplier`。助手、外卖、空盒不改变缓存、轮换或连击；普通玩家盒会按规则中断连续单品状态。预览不消耗缓存。

- `mono_bonus`：满盒至少两份同种真实散菜形成单品拼盘，可成为连击合格盒。不同品级仍为同一种；幽灵不占格、不破坏纯度，也不能凑数量。
- `cache_bonus`：真实套餐盒留至少两格空位，存一份缓存；下一只玩家满盒消耗，不叠层。
- `rotation_bonus`：连续单品拼盘更换食物种类，后一盒获得额外加成。

连击按**送盒顺序**冻结，而不是按吃盒顺序计算：桌面是栈，原来的后送先吃会反转玩家的操作顺序。`_start_box()` 和保温箱结算读取该盒已冻结的倍率。`_rule_income` 累计实际已获得的搭配额外收入，在结账中作为“其中”项展示，避免重复加钱。首局教学、`Game.record_run()` 和局数保存接口保留。

`_read_stats()` 已改用 `Game.active_struck()`，LoRA 只按真正有效的划菜数量计算。

## 验证

命令：

```powershell
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/canteen_controls_test.tscn -- --test-profile=canteen_controls --lang=zh_CN
```

结果：`CANTEEN_CONTROLS_RESULT`，`ok: true`，60 项，退出码 0。使用 `user://qa_canteen_controls.json`，无机器人、不写玩家设置。

覆盖持续按住 15 秒的状态转换次数（恰好开始/结束各一次）、冷却期间提前按下、暂停输入锁、金材质无吸力、局部力场边界与限速、鼠标即时跟随、手柄速度、快速斜穿、鼠标横扫、远处不误接、长帧玩家/助手先后、无力场预测坐标、有力场真实碰撞对照、静态品质轮廓参数，以及单品/缓存/换菜/连击的满盒、空盒、不同品级、幽灵、压缩、助手、外卖、重复提交和倒序吃盒边界。结账高收入直接验证钱包没有溢出扣款。

这是确定性状态、碰撞和接口验收；尚未证明最终小屏幕排版、实物手柄手感、GPU 呈现或声音听感。同步测试在同帧排入音频命令，退出前先让混音线程处理 0.12 秒，再停播、清空流并等待 0.12 秒；最终退出无脚本错误、无对象或资源泄漏告警。最终视听验证由根代理统一执行。

## 串行 GPU 可视夹具

新增 `game/tests/canteen_visual_test.gd/.tscn`，固定随机种子 `20261019`，使用单独的 `canteen_visual_*` 存档。场景注入的饭盒和技能状态明确标为测试夹具，不宣称来自合法升级或完整通关。真实窗口与 PNG 都要求 1280×720；不缩放截图。默认通过 `Input.parse_input_event()` 持续按住一次 Space **至少 15 秒真实时间**，记录每 0.25 秒的能量、冷却、按键状态和转换次数，应只有开始、耗尽结束各一次。

```powershell
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --resolution 1280x720 res://tests/canteen_visual_test.tscn -- --test-profile=canteen_visual_zh --lang=zh_CN --out=C:/absolute/output/zh
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --resolution 1280x720 res://tests/canteen_visual_test.tscn -- --test-profile=canteen_visual_en --lang=en --out=C:/absolute/output/en
```

两条命令必须串行执行；GPU 由根代理协调，本代理未执行。追加 `--short` 将持有时间缩短至 3 秒，报告明确标记 `full_15_second_hold: false`。中英文 `--headless --short` 已各通过 23 项，12 个场景状态构建成功，干净退出；headless 不生成 PNG，也不构成视觉验收。

输出 `canteen_visual_report.json` 绑定关键源码、数据和截图 SHA256，记录引擎、语言、夹具说明、每张图的目的与状态。结束标记为 `CANTEEN_VISUAL_RESULT`，截图标记为 `CANTEEN_VISUAL_SHOT`。

12 张全窗口截图分开检查：手持金饭盒的银/金食材、同状态减少动态、桌上品质、进食品质、五档口八勺进度、预存缓存提示、缓存就绪、拼盘叠缓存预览、换菜预览、真实思考中的蓝色落点、耗尽冷却、持续按住恢复满能量后仍需松开。没有把多张界面缩小挤到同一截图。

## 新中文的英文交接

本轮未修改 `en.json`。同内容已保存为 `docs/canteen-controls-translations.json`，供统一提取/合并：

```json
{
  "松手结束 · 冷却 1 秒": "Release to stop · 1s cooldown",
  "冷却 %.1f 秒": "Cooldown %.1fs",
  "松开后再按": "Release, then press again",
  "思考恢复中": "Recharging",
  "按住 空格 / 右键 / B": "Hold Space / RMB / B",
  "出菜 ×%d": "Ladles ×%d",
  "每条进度是一把勺子 · 满格后抛菜": "One bar per ladle · Full bar means a serving",
  "蓝线：饭盒高度的预计落点": "Blue mark: landing at box height",
  "缓存已备好": "Cache ready",
  "搭配 +%d%%": "Build bonus +%d%%",
  "其中搭配加成：单品 / 缓存 / 换菜": "Including platter / cache / variety bonuses",
  "缓存": "Cache",
  "送出可存缓存": "Serve to store a cache",
  "单品拼盘": "Single-dish platter",
  "换菜": "Variety"
}
```
