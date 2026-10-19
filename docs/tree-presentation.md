# 技能树、配餐与教学：原风格局部修复

以 `30e97c7` 的三份源码为基线恢复暖色手绘呈现。已撤掉此前深绿全屏、裁切地图和固定右详情栏方案；本说明替代前一版重做记录。保留全屏软木板、红绳、饭票/图钉、左下角色、左上小黑板、原工具栏和点击购买方式，不改节点坐标、价格、状态或经济接口。

## 必要修复

- 技能票从 176×116 微调为 172×108，消除原数据中四对临界交叠。满级红章缩为 28px 并靠右下放，避开名称、等级与进度条；部分升级不盖满级章。图钉保留原长宽比。
- 保留原浮动小黑板和全文换行，仅修定位：在节点两侧和屏幕安全区域选择位置，避开原上方黑板、工具栏、开饭/评测按钮和新功能提示卡。说明可读期间不会因鼠标进入正文而闪退，点击正文也不会购买后面的技能；点击空白收起。全部技能的中英文、未购买/部分/满级实测最长 367/425 逻辑像素，无需引入分页、滚动框或固定侧栏。
- 保留手柄/键盘单次升级及地图焦点修复、菜单单实例、模式切换、输入阻挡、Tab 焦点闭环和关闭返回。图鉴入口防重复实例。放开鼠标即结束拖图，包括松开位置在工具栏上。
- 今日菜单/招牌菜恢复原三列图卡、暖纸木色和右侧人物位置。大窗使用薄木边和普通纸面，去掉放大的票券穿孔边框。菜图与两行状态独立占区，菜名和右侧长文避免相互挤压；TextureRect 在入树后设置实际尺寸。
- 教学恢复原 1080×174 暖纸票、原坐标和原文案。保留按实际饭盒素材边界避让及 80px 返回缓冲，完成/跳过后的提示也避让饭盒。

本轮没有新增玩家文案，`tree-presentation-translations.json` 为空对照。

## 验证

`meal_planner_test` 英文独立 profile 的 59 项真实 GUI 事件检查通过。`tree_presentation_test` 英文 1280×720、中文 960×540 headless 各 1,324 项通过、退出码 0：覆盖原结构存在、所有节点无矩形交叠、原鼠标点击购买、Enter 单次购买、浮动说明点击不穿透，以及全部技能三种等级状态在五个边缘/中心位置避让固定区域，菜单图文边界和教学避让。

最终报告位于 `build/qa/tree-presentation/warm-headless-en/` 和 `warm-headless-zh/`，报告保存源码 SHA256 与最长说明测量值。这是隔离存档的注入状态验证，不是完整通关。`TREE_PRESENTATION_RESULT` 为结束标记。

```powershell
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/meal_planner_test.tscn -- --test-profile=meal_planner_warm_restore --lang=en
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/tree_presentation_test.tscn -- --test-profile=tree_presentation_warm_en --lang=en --out=C:/Users/A/Desktop/fatfish_game/build/qa/tree-presentation/warm-headless-en
```

GPU 由根协调串行：相同场景去掉 `--headless`，用新的 `--out` 目录；`--small` 为 960×540，默认 1280×720，语言使用 `--lang=zh_CN` 或 `--lang=en`。测试输出 12 张截图，包含完整长说明、屏幕边缘说明、锁定/费用不足/部分/满级、菜单两页及教学常规/低位饭盒/完成提示。旧 `zh720/en720/zh540/en540` 深绿版本截图已经失效，不得作为当前原风格版本的视觉验收。

当前未运行本轮 GPU，不把 headless 边界检查当作实际美术和可读性验收；源码已冻结，等待根复核。
