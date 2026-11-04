# 吃白饭的大肥鱼 · Fatfish's Free Lunch

免费、开源、非商用的食堂增量游戏，与 DeepSeek 官方无关。Godot 4.7.2，目标平台为 PC / Steam 单机。当前为 v0.4.2 候选版本；完成上架和精品品质仍需真实玩家、目标硬件与平台验收。

用饭盒接住梁阿姨抛出的食材，凑出套餐，送到饭桌让大肥鱼吃掉；用赚到的 token 升级技能，逐步通过 V3 → R1 → V3.1 → V3.2 → V4 → AGI 的发布评测。

## 开始游戏

- 双击 `play.bat` 启动，`edit.bat` 打开编辑器。
- 鼠标直接控制饭盒；在右侧饭桌左键拿盒或送饭。食物吃下后产生收益。
- WASD / 方向键 / 手柄左摇杆移动，E / Enter / A 拿盒或送饭。
- 解锁深度思考后，按住空格 / Shift / 右键 / B / RB / RT。结束后冷却 1 秒，松开并恢复至少 0.5 秒能量后才能再次启动。
- Esc / P / Start 暂停。失去焦点默认暂停，回来后手动继续；设置和图鉴关闭后仍保持暂停。
- 技能树：鼠标选择购买，空白处拖动；方向键 / 摇杆选节点，A / Enter 购买，Y / G 开饭。Back / Select 切换工具区，B 返回技能地图；键盘 Tab 也可访问工具按钮。只有满级技能盖章。
- 技能树预告下一层空白便签。右键 / Backspace / 手柄 X 退款；有已购下游的前置至少保留 1 级，多余等级仍全额退还。
- 设置 → 游戏 →「键盘与手柄改键」可分别修改 8 项玩法操作，支持保存、冲突检查和恢复默认。移动和思考可用摇杆/扳机；离散操作用按钮。菜单导航、确认、返回、暂停保留固定键；教学与 HUD 随配置更新。
- 游戏内的「菜谱图鉴 → 食堂说明」可以回看接菜、档口进度、品质、合成、均衡和技能联动规则。

## 当前内容与规则

五档口、74 个升级节点加起点、20 种可收集套餐、五次发布评测、首局引导、AGI 结局和 25 项本地成就。支持简体中文和英文。设置包含四路音量、窗口尺寸、全屏、失焦暂停、减少动态、接菜顿帧。

- 档口的每个圆环代表一把独立备菜的勺子，预告首道菜；多个圆环是并行出菜。按 Esc →「档口指南」查看菜谱，选中招牌左右换位或恢复默认。立即生效、永久保存，备菜进度与产量不变；关闭指南仍保持暂停。完成 3 顿且开了至少 2 档后会提示一次。
- 深度思考保留减速、能量、冷却与技能联动，取消蓝色落点线。
- 普通进食语音共用 4 秒起播间隔，结束后再留 0.65 秒空白；吐菜、顿悟等关键反馈保留。
- AGI 末页可保存不带操作按钮的纪念饭票 PNG，并继续开饭。
- 金饭盒提高整顿收入，没有隐式全屏吸附。发散思维的吸附仅在思考时作用于饭盒附近。
- 银、金食材入盒仍有轮廓光。合成时原料的品质价值计入套餐。
- 收益没有上下文溢出扣款。版本的上下文成长仍影响明确的流式、连击与招牌菜成长上限。
- 「今日菜单」和「招牌菜」共用一个图文面板。划菜后每档口至少保留一道，满额替换规则在面板内说明。
- Prompt 模板：至少两份同菜装满盒可成为单品拼盘，触发连击；不计入图鉴配方。
- AGI 菜谱：首次学习后，图鉴公开全部 20 道套餐的完整配方，包括 3 道隐藏配方；收藏进度和成就仍以实际制作的套餐为准，每级神级套餐收益仍 +0.6 倍。
- 上下文压缩：含套餐、空至少两格的亲手送餐可存缓存，让下一亲手满盒 +15%。学会换菜后可用“单品 A → 首次存缓存的套餐盒 → 单品 B”同时续连击与换菜；重复半盒不能刷接力。
- 上下文记忆：连续单品拼盘换菜有额外加成，原有断连保护保留。
- 助手分工：招募买出场名额，六位自由轮换。各自选择补漏、指定配餐、补营养；格格每盒首份普通菜升为优质。编排让不同职责的有效配送为下一玩家盒存接力。
- 助手脚下用托盘、订单、三分餐盘区分职责，配餐显示目标菜品；圆点/箭头/沙漏分别表示接菜/送餐/等盒。分工界面使用同一套图例。
- 自动操作：推空盒、满盒回收、融合、Temperature、重新生成和过拟合可单独暂停，技能等级保留，下顿生效。
- 默认送餐先进先出；异步调用需招募与服务器繁忙，让玩家盒优先并保留馋值。助手配送有总量上限，闲置角色公平领盒。

[六种构筑方向与青菜流分析](docs/build-archetypes-analysis.md)保留 0.4.0 的具体档口、菜单与操作分析；[助手分工与新版搭配](docs/helper-strategy-design.md)说明 0.4.1 的改动，区分规则验证与实玩平衡。

当前机制以实际源码、[机制审计](docs/mechanics-audit.md)和游戏内说明为准。较早的 `core_design_v2/v3`、`steam_release.md` 及特殊试炼原型文档属于历史设计，不代表现版承诺。

## 存档与测试隔离

Windows 存档在 `%APPDATA%\FatFishFreeLunch\save.json`，备份为 `save.json.bak`，设置独立保存在 `settings.cfg`。v3 存档兼容旧 v2 进度，支持损坏主档后的备份/临时文件恢复，并保护未来版本存档免于覆盖。

手动 QA 使用 `-- --test-profile=<name>`；该参数不启用机器人，设置读写隔离到 `qa_<name>_settings.cfg`，不会修改玩家设置。自动测试和所有 `res://tests/*.tscn` 使用独立档案。不要把 QA 档案或设置同步进 Steam Cloud。

## 构建与验证

```powershell
py -3 pipeline/build_release.py
py -3 pipeline/build_release.py --web
py -3 pipeline/validate_release.py --visual --runs 12 --uncapped-ui --ui-timeout 300
```

构建输出在新建的 `build/candidate-<version>-<timestamp>/`，包含独立 Windows 包、ZIP、许可和源文件/产物 SHA-256。构建从隔离源码副本导出，排除 `tests/`、Godot MCP 插件与编辑器配置。`--web` 额外生成浏览器包。

验证报告在 `build/verification-*/report.json`，检查测试前后源码与玩家文件是否变化。报告保留失败，不覆盖旧证据。`--uncapped-ui` 用启动参数请求关闭垂直同步并限制120帧；场景随后应用的设置可能覆盖它。该选项仅为加快截图，不能用来推断正式游戏性能。导出运行可用 `pipeline/smoke_release.py <候选目录> --verification <成功的report.json>`，它先校验源码匹配，再用独立档案运行一顿并保存截图。

自动输入、夹具或机器人回测不替代真实玩家手感、实物手柄和硬件兼容性评审。本轮见 [v0.4.2 档口与输入更新验收](docs/stall-input-release-validation.md)，助手机制见 [v0.4.1 验收](docs/helper-release-validation.md)，此前原风格精修见 [视觉验证记录](docs/presentation-polish-validation.md)，早期功能基线见 [v0.3 验证记录](docs/release-validation.md)，平台准备情况见 [Steam 发布状态](docs/steam_release_current.md)。

## 维护入口

| 路径 | 用途 |
| --- | --- |
| `game/scripts/run/canteen_run.gd` | 接菜、轨迹、思考、合成、送餐、吃饭与结算 |
| `game/scripts/run/meal_rules.gd` | 单品拼盘、缓存和换菜联动的纯规则 |
| `game/scripts/autoload/game.gd` | 存档、升级、有效菜单与成就 |
| `pipeline/build_tree.py` | 技能树唯一生成源，输出 `game/data/skill_tree.json` |
| `game/data/menu.json` | 食材、档口与配方 |
| `game/scripts/ui/meal_planner.gd` | 今日菜单 / 招牌菜的统一面板 |
| `game/scripts/ui/crew_planner_panel.gd` | 助手出场、职责、配餐和自动操作 |
| `game/scripts/ui/recipe_book.gd` | 菜谱、食材图鉴与食堂说明 |
| `game/assets/portraits/release/` | 新大肥鱼功能插画和成就立绘 |
| `docs/release-art-prompts.json` | 生图参考、提示词与输出记录 |
| `pipeline/i18n_extract.py` | 收集中英翻译键；新增内容后补齐 `en.json` |
| `pipeline/subset_font.py` | 新增中文后重新生成游戏字体子集 |

素材生产沿用项目已有角色参考与艺术方向。新增素材必须记录来源、许可和使用位置；密钥只保存在本地环境，不写入日志或仓库。新插画使用内置 image_gen；不把素材数量当成质量结论。

## 许可

角色原型「溟月」© 上善无形，女仆版「蓝色大肥鱼」© ZipZipPipe，依 CC BY-NC-SA 4.0 二创。原创代码使用 MIT；美术与其他依赖各自遵循其许可，详见 [CREDITS](CREDITS.md)、[LICENSE](LICENSE) 与 `docs/THIRD_PARTY_NOTICES.txt`。
