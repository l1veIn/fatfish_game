# 收藏界面局部改进与暖色回收 · 2026-10-19

本轮只改图鉴、成就收藏、成就提示及专属验证场景。世界状态、存档、技能和收益不改；`closed` 信号及原有打开入口继续保留。

用户纠正以 `30e97c7` 的暖色手绘食堂、纸张、木边和原有入口为基准。此前的大面积深绿界面已撤回；这次只保留解决明确问题的分页、清晰小奖章、大图详情和通知延迟。不能把局部可读性优化扩大为替换整套美术语言。

## 图鉴：实际双页书

`RecipeBook` 不创建 `ScrollContainer`。背景复用原 `assets/canteen/bg_wall.png` 暖色食堂，覆盖轻棕遮罩；正文棕墨，按钮使用原 `UiKit.CREAM/WOOD` 风格。书页按 `recipe_spread.png` 的原比例 1680×945 绘在逻辑坐标 `(120,126)`，不九宫格拉伸、不裁掉金属角；蓝色只保留书图自带的窄布边。正文安全区为左页 x235–855、右页 x1065–1685，页码独立位于每页下沿。顶部书签切换目录、套餐、食材和食堂说明。

目录能直接点击进入三个章节。普通套餐每页最多两道；超过三种原料的大套餐独占一页，留出大图与完整原料表，不缩小文字解决英文过长。食材按档口排列，每页三道。十节说明每页一节，正文 28 逻辑像素。未发现菜谱仍显示线索和剪影；“制作次数”符合 `Game.recipes` 在合成时记数的实际语义。

上下页一次翻动一对书页。页码和跨页总数同时显示；章末禁用下一页，章首禁用上一页。鼠标、聚焦按钮确认、PgUp/PgDn、手柄 LB/RB 都走同一翻页函数。Esc/B 合上；没有用鼠标滚轮伪装翻书。

## 成就：奖章陈列和大详情

`AchievementsPanel` 恢复基线的暖棕木板和奶油纸卡，外侧露出原食堂背景，标题/返回入口仍在上方。左边六分类（含全部），中间每页 2×3 枚奖章；奖章本体显示 112×112，名称和点亮状态分别有自己的区域。选择或键盘聚焦奖章，右侧立即展示所属分类、418×316 的原角色插画、成就名和完整条件。不把复杂人物插画缩进小卡片，不把达成条件只藏在 hover。

正式小图来自 `assets/ui/premium/badge_meal/growth/recipe/balance/kitchen/gold.png`。`gold_box` 使用 gold，其余按分类分配。未获得奖章降低亮度、用暖灰纸并显示“待点亮”；选中态用淡金纸和金边，键盘焦点再用外扩明亮边框，不能仅依赖颜色区分。旧角色大插画只出现在详情区。

成就提示 `AchievementToast` 恢复原奶油纸、木边和棕墨文字，同步用对应的小奖章（104×104），保留排队、显示时长、减少动态行为和存档失败提示。它不暂停、不取得焦点、不接鼠标。进行中的 `CanteenRun` 会保留整个成就队列，等 `_ended` 进入结算或离开跑局后再依次显示；若在提示显示中开始下一局，会把这枚奖章收回队首，下一次结算重新完整展示。场景查找仅在准备出队且缓存失效时进行，等待期间用弱引用检查状态，新跑局通过 `node_added` 事件接入；不每帧递归搜索。存档失败警告仍会立即提示。

## 输入与接口交接

- 两个收藏面板都是 `PROCESS_MODE_ALWAYS`，自己不改变暂停状态。关闭发出一次 `closed`，并恢复打开前仍有效的焦点；原父页面的关闭回调继续有效。
- 图鉴保留 `_page` 与 `_fill()` 供既有调试使用；新增 `_spread`、`_page_count`、`_leaves`、`_entry_controls`、`_previous`、`_next`。`_page` 默认 `index`，不再默认套餐。
- 成就新增 `_medals`（当前页最多六枚）、`_category_buttons`、`_filtered`、`_selected_id`、`_spread`、`_page_count`。`_medals` 上仍有 `achievement_id` 元数据。
- **旧测试已迁移**：`ending_flow_test.gd` 不再要求 `_cards` 一次含全部成就或 `_scroll.scroll_vertical > 0`，已通过真实按键分页收集全部 `_medals` 的 ID，检查详情与返回焦点。`focus_recovery_test.gd` 不再要求十个说明卡同时出现或聚焦滚动，已通过真实按键切到 `rules`，遍历 5 跨页、每次 2 节，并验证暂停时钟停止与合书保留暂停。
- 不为兼容旧滚动断言保留一个隐藏 ScrollContainer，这会让测试掩盖产品模型变化。

## 验证入口

`game/tests/collection_presentation_test.tscn` 只接受 `--test-profile=collection_presentation`。夹具设置解锁和未解锁记录，仅修改内存；记录玩家 save.json 与 settings.cfg 前后字节。通过实际 GUI Enter、Esc、方向键、PageDown、手柄 A/B/LB/RB 和鼠标点击打开标题收藏、选择目录、翻页、选择成就、暂停内查看说明再返回。遍历中英全部页和全部成就详情，检查每个文本文字区的保留尺寸，不只检查第一页。

运行示例：

```powershell
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/collection_presentation_test.tscn -- --test-profile=collection_presentation
```

真实图形运行加 `--rendering-method gl_compatibility --resolution 1280x720` 并去掉 `--headless`，用户参数加 `--render-size=1280x720` 覆盖设置自动应用的窗口大小；`--out=<绝对目录>` 可输出中英文目录、普通/长套餐、食材、说明、成就分类与通知截图以及源码哈希报告。GPU 必须与其他视觉验收串行。小窗用 `--resolution 960x540 -- --test-profile=collection_presentation --render-size=960x540` 另跑同一场景。

新文案集中在 `docs/collection-presentation-translations.json`，已由根代理统一合入 `en.json` 和字体。暖色回收没有新增文案。专属测试使用正式翻译，不向玩家设置或翻译文件写内容。

暖色回收后，专属收藏无头 GUI 和真实 GPU 的 1280×720、960×540 两轮各覆盖中英两种语言，均为 0 failures；包括通知局内队列、结算补发、下一局收回、离局补发与顺序不丢失。最新图像与源码/背景/UiKit/奖章/翻译哈希报告分别在 `build/collection-qa/warm1280x720` 和 `build/collection-qa/warm960x540`，每轮 24 张图。旧的非 warm 目录保留为此前方案证据，**不代表当前美术**。

视觉对照采用 `30e97c7` 源码及历史截图 `build/qa/focus/en/handbook_top.png`、`build/qa/portraits-fixed/achievements_top.png`。历史截图用于对照基础语言，不声称是该提交逐字节复现。原来的暖纸、棕墨、木边和金标题已恢复；只保留分页和图像尺度的局部改进。已目检新目录、普通与最长套餐、说明、分类奖章及大详情：书图维持原比例，正文不越页，红书签不被翻页说明压住，英文名称有正常换行空间；540p 图书说明仍可辨读。未观察到大面积深绿色背景。旧 ending_flow 与 focus_recovery 的输入接口迁移此前已通过，本轮没有改变其布局接口或交互逻辑。

所有验证使用独立 QA 档案，玩家 settings.cfg 与 save.json 前后字节一致。回归夹具和模拟手柄按钮不能证明实物手柄体验、完整合法游玩路线或玩家主观美感。
