# 技能依赖与档口换位 · 2026-10-19

基线 d60c9b4 / v0.4.1。沿用现有暖色手绘画面、小黑板、柜台、便签和所有角色。保护工作区已有 project.godot/MCP 改动；测试只写独立 profile。

## 本轮行为

- 单点右键退款：如果存在已购买的直接下游技能，这个节点最低保留1级，只退多余等级对应的实际购入价格。叶节点仍可全退；重复退款不增钱。完整回滚仍按原规则退全树并保留版本门票。多前置的已购买分支同样保护已点亮的父节点。
- 只预告一层后续空白便签：当前尚未正常显示、但至少有一个正常显示的直接前置的节点可预览。不从预览继续展开。保留节点坐标、旧票纸、图钉与细线；不泄漏名称/价格/描述，不可购买。鼠标和键盘可以得到简洁的解锁解释。
- 删除思考及混合思考的蓝色落点标记与相关文案；减速、冷却、吸附、收敛等技能逻辑保留。预测数学若仍为助手使用则保留内部用途。
- 五个物理柜台位置保留原图。档口身份可以交换这些位置；通过 Esc → 档口指南编辑，左右移动或恢复默认。招牌、菜单菜盘、关门状态、勺子和未来出菜源同步移动。位置配置永久保存，旧存档缺字段使用原排序。
- 暂停中立即应用；不刷新勺子的备菜计时、已预告菜品或抬勺状态，不重新分配额外触手，不移动已经在飞的食材、玩家和助手。移动只改变位置，不改变菜谱、等级和产量。关闭指南保持暂停，再继续游戏。
- 默认名次/参考排序 `dim,wok,main,fry,sweet`。闭门档口也可换位，仍以关闭状态显示。指导出现条件：正常局、非新手教学/自动测试、已完成至少3顿且至少2档开门；只提示一次，指南入口始终可用，不强制打断游玩。

## 公共接口与所有者

整合者拥有 Game 和 canteen_run、翻译/字体、导入/GPU/打包/提交。Game 新接口：

- `refund_floor(id) -> int`、`refund_dependents(id) -> Array`（已购直接下游ID）；`refund()`保留float返款接口。
- `is_preview(id) -> bool`：正常不可见且至少一个正常可见父项；不递归预览。
- `DEFAULT_STALL_ORDER`、`stall_order: Array`；`active_stall_order() -> Array` 返回验证后的副本；`set_stall_order(order: Array) -> bool` 仅接受五个合法ID的完整排列，保存并发changed；`stall_layout_intro_due() -> bool` 只判断进度和seen标记。
- schema3增加可选 `stall_order` 字段；缺失、非法、重复、缺项恢复默认。reset清为默认；全技能回滚保留位置偏好。

CanteenRun 新接口：`stall_order: Array`（本局），`stall_pans(id) -> Array`（身份映射到固定物理槽），`stall_slot(id) -> int`，`apply_stall_order(order: Array) -> bool`（只允许暂停且未结束，先保存验证配置，再重定位既有勺子/重绘）。`STALL_ORDER/PANS`保留为默认物理槽基准，不作为当前身份排序。`_win_x(slot)`表示物理槽中心，`_win_span(id)`按当前映射。额外触手始终按默认身份顺序分配，重排不增减任何档口勺子数。

- 树界面所有者：tree_screen.gd、新 tree_dependency_test.gd/.tscn；空便签与退款反馈，所有新增英文另存build/tree-dependency-en.json。
- 档口界面所有者：canteen_overlay.gd、pause_menu.gd、新 stall_layout_ui_test.gd/.tscn；现有指南内位置编辑，双语与键鼠/手柄焦点、暂停恢复，英文另存build/stall-layout-ui-en.json。不改Game和运行逻辑。
- 独立规则验收所有者：新 progression_layout_test.gd/.tscn；退款/一层预览/序列验证/存取/重排保持状态的语义测试，不改生产源码。

最终在冻结源码上验证依赖退款、旧存档默认/坏配置、交换与恢复、指南真实输入和语言/小窗口；查看实际柜台截图与移位后的正常出菜。每块提交，结束推送。自动运行证据不等于真人策略平衡。
