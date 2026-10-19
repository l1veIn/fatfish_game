# AGI 纪念饭票与结算章修复

## 流程与视觉

保留现有三页暖纸叙事、手绘角色、小木边按钮。末页改为可分享的纪念饭票，主句为“实现 AGI 了吗？……又饿了。”，副句为“通用人工智能，专用干饭系统。”，右侧留“下一顿，才刚开始。”的继续伏笔。

最后一页展示当前存档的真实顿数、累计 token、最佳单顿 token、已发现套餐数，以及当前技能总等级、实际生效的招牌菜和划掉菜单、最多三个已购关键技能。关键技能优先展示 grok、mtp、prompt、memory、compress、lora、eos、rag、think；不足三个再按数据顺序补已购非门票技能。它是有明确“当前进度”标识的构筑摘要，不伪称首次 AGI 通关的历史快照。

`继续开饭` 沿原 finished → mark_ending_seen → 技能树流程，继续购技能和开下一顿。标题的重看结局仍可到达分享页。旧存档与首次未看完结局继续沿用 ending_seen，无需 schema 升级。仅查看或导出不改进度。

## 本地 PNG

`保存纪念饭票` 会输出当前窗口分辨率的 PNG 到 `user://keepsakes/fatfish-agi-<时间>-<毫秒>.png`。成功后显示绝对路径，恢复按钮与焦点；失败明确显示重试提示，不假报成功。导出的那一帧隐藏翻页、返回、保存按钮、页码、提示与通知层，PNG 不包含本地路径。保留游戏名、手绘角色及原角色署名/许可说明。

main 只新增通知层成员引用及 `share_capture_changed` 信号连接。无需改 Game 状态。玩家真实存档和 `build/qa/player-build-analysis/save-snapshot.json` 都未写入；测试一律使用独立 profile。

## 英文结果章

原饭票、红章材质与弹印动画保留。结果章以字体真实宽度、字的升部/高度、章底纸和 -0.16 弧度旋转后的外接矩形计算布局。章位于饭票右侧 32 像素以外；弹印的最大放大比例受屏幕剩余宽度约束，防止 Absolutely stuffed 左侧压进金额列或右侧越屏。

`_drawn_result_bounds` 在每次实际绘制时记录字与纸的联合边界。shell 测试验证实际绘制边界、0–0.16 秒弹印阶段的边界、PNG 存在与尺寸、菜单/技能数据真实性、导出后焦点和标记不变。ending_flow 测试覆盖旧档继续、最终评测→结算→结局→技能树、标题重看，以及通知层在导出时的隐藏恢复。headless 明确返回 ERR_UNAVAILABLE，不把它当作 PNG 导出验证。

本轮代码文件：`game/scripts/ui/ending_screen.gd`、`game/scripts/main.gd`、`game/scripts/run/checkout_receipt.gd`；测试文件：`game/tests/ending_flow_test.gd`、`game/tests/presentation_shell_test.gd`；英译对照：`docs/ending-followup-translations.json`。
