# 玩法机制核对与构筑交接 · 2026-10-19

本轮按 `Game.BASE`、生成后的 `skill_tree.json`、`menu.json` 和 `CanteenRun` 的实际执行路径逐项核对。这里记录实现事实，不把源码里未启用的旧试炼视作现有玩法，也不把独立逻辑测试当作完整通关平衡结论。助手更新的决策与验收见 [助手分工设计](helper-strategy-design.md)。

## 技能树与兼容性

- 实际数据一直是 **75 个节点：根节点 1 个，非根节点 74 个**。旧文档的“74 节点”省略了根。本轮没有增删节点，节点 ID、价格、价格成长、上限、版本圈、坐标保持原值。助手更新调整 hire/clip/sleep 的前置，async 要求 hire 与 busy 同时拥有；其余前置保留。
- 在 Prompt、上下文压缩、上下文记忆三个已有节点上增加正向机制，保留它们原来的套餐倍率、占格压缩和断连保护。老存档通过 `_recompute()` 自动获得对应已购等级的新增效果；不另存构筑状态。
- `mono_bonus`、`cache_bonus`、`rotation_bonus` 是新派生数值，默认 0。每顿的缓存与换菜序列只在 `CanteenRun` 中存在，不进入永久存档。
- 删除 `BASE` 中从未被技能授予、也未被消费者读取的 `crew_pu`、`crew_g`、`crew_ke`、`crew_zi`、`crew_ge`。`helper` 等级现在决定出场名额，六位角色自由选派；旧存档默认前 N 位。没有删除角色与特长，旧 `crew_*` 名称不作为解锁规则。

## 三个可以组合的机制

| 玩家操作 | 技能与收益 | 取舍和联动 |
|---|---|---|
| 亲手送出装满同一道散菜、至少两份的饭盒 | Prompt 每级整盒 +10%，可作为多轮对话的达标盒 | 集中接一种菜更容易连击；不增加菜谱图鉴。不同品级和火苗仍算同一道菜。 |
| 亲手送出含真实套餐、至少空两格的饭盒 | 上下文压缩存一份余量缓存，下一只亲手送出的满盒 +15% | 当下留空换后续收益；只存一份，普通半盒不会消耗。与压缩省格直接联动。 |
| 连续两只亲手送出的单品拼盘换一道菜 | 上下文记忆每级再给后一盒 +10% | 换菜比一直重复一种更难，但可以同时吃到 Prompt、缓存、多轮对话；普通盒会中断换菜接力；已学记忆时，首次存入空缓存的余量套餐盒能中继上一单品，重复半盒不能无限续连。 |

新收益与光学压缩、满盒、思维链加在同一个盒倍率池，不彼此相乘。例如 Prompt 1 + 缓存 + 记忆 2 的换菜满盒是额外 `0.10 + 0.15 + 0.20 = 0.45`，再参加既有馋、连击、整顿倍率。

可用的构筑方向是：先用 Prompt + 满盒练固定一种菜，菜单和招牌帮助集中接菜；之后配多轮对话维持稳定收益。第二条是压缩套餐、留下余量，再把缓存花在下一只大满盒，可与馋和保温箱叠加；装满和留空之间有节奏选择。第三条用记忆在两种单品拼盘间轮换，兼顾换菜收益和不同营养，但需要保留至少两种方便收集的菜。模型融合和 Temperature 都可能改变拼盘的份数或菜名，不能把全树点满当成这些构筑的唯一答案。

小助手、外卖不产生、不消耗、不打断上述玩家序列。幻觉不占格、不增加真实菜数量、不能伪造套餐或拼盘；单份大菜也不是拼盘。保温箱仍属于亲手送盒，首次送出时只提交一次规则，换出后再入队不重复结算序列。

`meal_rules.gd` 是无场景状态的纯函数：`profile(items, capacity)` 只返回盒内容特征；`plan(profile, previous_mono_kind, cache_ready, mono_bonus, cache_bonus, rotation_bonus)` 返回预览、各项加成与下一状态。HUD 可反复预览而不花掉缓存。只有 `_note_served()` 在真实提交时写回状态，并把结果冻结进盒子的 `meal_rule`。默认按先进先出进食；异步调用优先玩家盒。连击由 `_commit_delivery_chain()` 按送盒顺序冻结，保温和优先级调整不会改变已经预告的收益。

反馈接口已接到手中饭盒的预览、缓存已备好提示、右侧缓存徽章、实际吃饭/保温箱收入及结账的“其中搭配 / 接力加成”。助手接力也进入普通盒和保温盒共用的加法池。这条小票说明已包含在收入里，不再次给钱。未吃完而进入“我去睡了”的食物只走半价补结算，不兑现未吃掉的盒倍率。

## 已修正的隐藏、过时与无效语义

| 项目 | 核对结果与处理 |
|---|---|
| 上下文溢出扣收入 | 旧结账保险丝是未说明的收入扣减，不是可购买的技能。本轮按用户要求由 canteen 删除。版本上下文仍是正向成长上限，填满/压缩/记忆都保留并提供明确正向效果。 |
| 金饭盒吸菜 | 材质以前暗送吸附，违反玩家对“金盆更值钱”的理解；canteen 已取消。玩家主动吸菜只来自思考时的发散思维。谱谱自己的近距离吸菜是独立助手特长。 |
| 思考不断开关 | 结束思考后有 1 秒冷却，必须松开后再开始；技能文字写明。原充能、慢速和自然回复保留。 |
| 菜单把整个档口划空 | 旧 `_stall_kind()` 会兜底重新出全部菜，但 LoRA 仍按原划线数奖励。`Game.active_struck()` 现在统一返回真实有效的选择，每个已开档口至少留一道；运行场景和界面使用同一结果。 |
| 旧菜单存档 | `load_game()` 在重算技能后将无效/未开放/超容量/整档口全划掉的旧列表归一化。按原选择顺序保留合法项，遇到会划掉最后一道的项跳过；下一次正常保存写入归一化结果。 |
| 菜单容量已满 | 切换前先恢复最早一项，再检查新项是否合法。容量为 1 时可以在同档口两菜之间切换，不会误拒绝。失败返回原因，不改变或重写存档。 |
| Temperature | 同窗口、同类别升级菜名；没有更高菜时提升一个品级，已顿悟青菜也走品级升级。保护当前最接近套餐所缺的原料。旧“都变优质”说明不准确，已修正文案。 |
| 模型融合 | 三份菜名、品级、火苗相同的真实散菜变一份高品级菜，金牌不再融合。结果仍占该菜原来的格数，不能承诺“永远一格”。减少份数可能牺牲一部分纯价值换空间，适合继续接菜。 |
| MoE 大杂烩 | 满盒、且没有只差一样的套餐时，三个不同窗口的真实散菜变二级乱炖。不是任何时候都自动吞三菜；文字已补条件。 |
| 向量漂移 | 顿悟青菜的营养一半素一半荤，仍要主食才能均衡。旧“全吃菜也均衡”过度承诺已删除。 |
| 我去睡了 | 包括桌上、正在吃、配送在途、玩家手中、小助手手中的剩菜；同一盒跨容器引用去重，已结算保温盒排除。半价基于食物结算并再算整顿加成，不是每盒完整分数的一半。 |
| Batch Size ×2 | 实际是每勺按概率多一份，不是整勺翻倍。名称改为“Batch Size：多来一份”，数值未改。 |
| V3.2 更聪明吸附 | DSA 是未学顿悟时拒收青菜；本身不送吸附距离，且不要求正在思考。奖励与门票文字已说明真实行为。学了顿悟后这个拒收限制关闭。 |
| 失败评测降低难度 | `trial_fails` 记录最多 3 次，但当前评测只读取固定目标，失败次数不改变出菜、时长、目标或技能。Game 的旧减难注释已移除，canteen 的旧试炼说明由其负责人同步清理；不暗改平衡。 |

`struck_toggle_reason(id)` 返回空字符串表示可切换，否则返回“先学会今日菜单”“菜未开放”或“每个档口至少保留一道菜”。`toggle_struck(id) -> bool` 返回实际是否成功。`active_struck()` 是所有界面与局内读取菜单的接口；不得直接 `struck.slice()` 冒充有效列表。

## 全部派生数值与执行位置

下表逐项覆盖当前 `Game.BASE`。通常先经 `_read_stats()` 读入运行场景，再由列出的函数消费；“固定”表示当前没有售卖技能修改它，并非虚构一个有用技能。节点 ID 可在 `skill_tree.json` 查到对应显示名。代码消费者均位于 `canteen_run.gd`，另标文件者除外。

| 数值（默认） | 授予节点 | 实际消费者 | 生效语义 |
|---|---|---|---|
| `box_n` (2.0) | `vram` | `_cap / _width / _pack` | 扩为 2×3、2×4，容量与接菜宽度同步增加。 |
| `basins` (3.0) | `vram` | `_empty / _update_flying / _new_basin` | 玩家可循环使用的盒数；助手自带盒。 |
| `material` (0.0) | `mat` | `_read_stats 的 _g / _bite` | 铁、铜、银、金收入 ×1/1.5/2/3；不授予吸附。 |
| `eat_rate` (2.0) | `eat` | `_update_fish` | 吃菜频率；提高消化桌上队列的速度。 |
| `tentacles` (0.0) | `conc` | `_setup_arms / _update_arms` | 在每个已开窗口一勺的基础上增加勺子，受 SLOTS 上限约束。 |
| `shake` (1.0) | 固定 | `_throw / _fling` | 固定散布与手抖演出参数，当前无售卖节点。 |
| `scoop` (0.0) | 固定 | `_fling` | 固定 0 的额外份数预留项，当前无节点改变，不能作为现有升级宣传。 |
| `batch` (0.0) | `batch` | `_fling` | 每勺按概率额外多抛一份，并非整勺 ×2。 |
| `peaks` (0.0) | `peak` | `_update_peaks / _update_arms` | 启用周期高峰，出菜加快。 |
| `peak_time` (5.0) | `peak` | `_update_peaks` | 高峰持续秒数，基础 5 秒、每级 +3 秒。 |
| `peak_good` (3.0) | 固定 | `_stall_kind` | 固定高峰稀有菜权重倍率，无单独售卖节点。 |
| `helper` (0.0) | `hire` | `Game.active_helpers / _read_stats / _update_crew` | 六位角色的同时出场名额，允许休息与换人。 |
| `crew_relay` (0.0) | `orch` | `_award_helper_relay / _consume_helper_relay` | 每类有效助手配送存一份接力，下一玩家非空盒每份 +15%/30%，最多三类。 |
| `helper_speed` (1.0) | `orch` | `_update_crew / _plan_crew` | 助手移动速度和可赶到的接菜目标范围。 |
| `crit_chance` (0.0) | `lunch` | `_bite` | 每口暴击几率。 |
| `crit_mult` (2.0) | `lunch` | `_bite` | 暴击倍数；中午吃什么同时提高概率和倍数。 |
| `magnet` (0.0) | 固定 | `_magnet / _steer_food` | 固定 0 的基础吸附预留项；材质不再更改。 |
| `think_time` (2.5) | `think` | `_update_thinking` | 思考能量上限，R1 才能使用。 |
| `think_slow` (0.35) | 固定 | `_process` | 固定思考世界速度 0.35，非全局 time_scale。 |
| `think_regen` (0.4) | 固定 | `_update_thinking` | 未思考时能量回复速度，固定 0.4。 |
| `throw_rate` (1.0) | `api` | `_update_arms` | 各勺出菜间隔；技能按乘法叠加。 |
| `stall_main` (1.0) | `stall_main` | `_read_stats / _stall_kind / _can_make` | 主食菜目等级；基础主食窗口已开。 |
| `stall_wok` (0.0) | `stall_wok` | `_read_stats / _stall_kind / _can_make` | 炒菜窗口开启与菜目等级。 |
| `stall_dim` (0.0) | `stall_dim` | `_read_stats / _stall_kind / _can_make` | 面点窗口开启与菜目等级。 |
| `stall_fry` (0.0) | `stall_fry` | `_read_stats / _stall_kind / _can_make` | 炸物窗口开启与菜目等级。 |
| `stall_sweet` (0.0) | `stall_sweet` | `_read_stats / _stall_kind / _can_make` | 甜品窗口开启与菜目等级。 |
| `balance_max` (2.0) | `rlhf` | `balance_mult` | 4:3:3 主荤素均衡的最高整顿倍率。 |
| `sig_slots` (0.0) | `moe` | `Game.active_signatures / _sig_value / _update_arms` | 开饭前可选招牌数；按具体菜的 SIG 奖励生效。 |
| `auto_push` (0.0) | `skills` | `_update_skills` | 手上空时自动取得空盒。 |
| `auto_return` (0.0) | `skills` | `_update_skills` | 手上满盒自动送桌。 |
| `stream` (0.0) | `stream` | `_stream_mult` | 吃得越多的对数倍率，受版本流式上限约束。 |
| `ttft` (0.0) | `ttft` | `_read_stats 的 stream_from / _stream_mult` | 每级让流式起算提前 10 口。 |
| `mtp` (0.0) | `mtp` | `_bite` | 可赚钱的每口固定额外 token。 |
| `menu_cut` (0.0) | `menu` | `Game.active_struck / _validated_struck / _read_stats` | 划菜容量；每档口至少留一道，只认有效划线。 |
| `sft` (0.0) | `sft` | `_throw` | 普通食物变优质的概率，优质 ×2。 |
| `lora` (0.0) | `lora` | `_read_stats 的 g_good / _throw` | 每道实际有效划线额外提高优质率。 |
| `dpo` (0.0) | `dpo` | `_throw` | 已掷为优质的菜再变金牌的概率，不是所有菜独立金牌概率。 |
| `fp32` (0.0) | `fp32` | `_grade_x` | 金牌倍率从 ×4 到 ×5。 |
| `veg_std` (0.0) | `canteen_std` | `_fling` | 出菜时概率额外抛青菜；须炒菜窗口已开且青菜未划掉。 |
| `temp` (0.0) | `temp` | `_catch / _upgrade` | 保护套餐所需原料的同档口同类升级，附带火苗。 |
| `hot` (0.0) | `hot` | `_part_value / _item_value / _bite` | 带火苗及暴击的额外价值；基础高温 ×1.5。 |
| `halluc` (0.0) | `halluc` | `_catch` | 概率增加同窗口的火苗幻觉一口，不占真实格。 |
| `regen` (0.0) | `regen` | `_serve / _upgrade` | 玩家送盒概率升级散菜；不重新判定已冻结的送盒序列。 |
| `emerge` (0.0) | `emerge` | `_catch` | 三份真实带火苗散菜有 25% 几率变神级涌现乱炖。 |
| `overfit` (0.0) | `overfit` | `_catch` | 顿悟后散菜有 15% 概率变火苗青菜。 |
| `box_bonus` (0.0) | `ocr` | `_start_box / _end 保温箱` | 所有盒的加法倍率池。 |
| `fill_bonus` (0.0) | `fill` | `_start_box / _end 保温箱` | 真实满盒的加法奖励。 |
| `mono_bonus` (0.0) | `prompt` | `MealRules.plan / _note_served / _start_box / _end` | 新增单品拼盘加法奖励与连击资格。 |
| `cache_bonus` (0.0) | `compress` | `MealRules.plan / _note_served / _start_box / _end` | 新增一份余量缓存，只为下一只玩家满盒结算一次。 |
| `rotation_bonus` (0.0) | `memory` | `MealRules.plan / _note_served / _start_box / _end` | 新增连续单品拼盘换菜奖励，普通玩家盒断序。 |
| `tier1` (0.0) | `prompt` | `_tier_x` | 一级套餐每级加 0.2 倍。 |
| `tier2` (0.0) | `fewshot` | `_tier_x` | 二级套餐每级加 0.3 倍。 |
| `tier3` (0.0) | `agentwf` | `_tier_x` | 三级套餐每级加 0.4 倍。 |
| `tier4` (0.0) | `agirec` | `_tier_x` | 四级套餐每级加 0.6 倍。 |
| `inject` (0.0) | `inject` | `_merge / _bite` | 合成时把一份真实青菜塞入套餐，随套餐一起吃。 |
| `compress` (0.0) | `compress` | `_cells` | 套餐少占一格、最少一格；与新增 cache_bonus 分工。 |
| `fuse3` (0.0) | `fuse3` | `_catch` | 三同菜、同品级、同火苗合一，保留单菜占格。 |
| `hodge` (0.0) | `hodge` | `_catch` | 满盒且不差一份就成套餐时，三个不同窗口散菜合乱炖。 |
| `cot` (0.0) | `cot` | `_merge / _start_box / _end` | 套餐再入套餐的合成链每盒最多计三次。 |
| `rag` (0.0) | `rag` | `_part_value` | 优质或金牌原料进入套餐时额外加原料价值。 |
| `spec` (0.0) | `spec` | `_merge` | 合成后概率补最接近套餐缺的最后一菜，或给一口幻觉饭团。 |
| `crave` (0.0) | `busy` | `_crave_x / _start_box / _end` | 等待使下一盒倍率趋近上限；首级另补 0.5。 |
| `crave_tau` (6.0) | `queue` | `_crave_x` | 指数增长时间常数，越小越快接近馋上限。 |
| `combo` (0.0) | `multiturn` | `_commit_delivery_chain / _start_box / _end` | 按玩家送盒顺序冻结连击倍率；首级另补 0.05。 |
| `memory` (0.0) | `memory` | `_commit_delivery_chain` | 断连掉一半；2 级每顿首断免损。另有 rotation_bonus。 |
| `warm` (0.0) | `warm` | `_press / _put_warm / _end` | 启用保温箱；关门吃且按最高馋值结算。 |
| `final` (0.0) | `final` | `_read_stats 的 warm_x / _end` | 保温箱 ×2 变 ×3、×4、×5。 |
| `bon` (0.0) | `bon` | `_serve / _box_worth` | 自动保留裸食物价值最高的盒；比较不含盒倍率或等待潜力。 |
| `eos` (0.0) | `eos` | `_end` | 保温箱最佳一口额外结算到总 ×3、×5、×8。 |
| `constit` (0.0) | `constit` | `balance_mult` | 放宽均衡曲线；不免除营养分类需求。 |
| `grok` (0.0) | `grok` | `_update_fish / _bite / _item_value` | 硬吃青菜到阈值后青菜赚钱；也关闭 DSA 拒青菜。 |
| `grok_need` (30.0) | `warmup` | `_update_fish` | 顿悟需要咽下的青菜口数，预热每级减 6。 |
| `aftertaste` (0.0) | `aftertaste` | `_item_value` | 顿悟青菜每级多值 2 token，基础 6。 |
| `drift` (0.0) | `drift` | `_bite` | 顿悟青菜营养一半素、一半荤；不提供主食。 |
| `fc` (0.0) | `fc` | `Game.helper_config / _helper_recipe_missing / _plan_crew` | 逐助手指定可制作菜谱，按自己这盒缺料收集，完成即送。 |
| `nutri` (0.0) | `nutri` | `_projected_nutrition / _plan_crew` | 逐助手选补营养职责，计算已吃和在途菜后的 4:3:3 缺口。 |
| `clip` (0.0) | `clip` | `_end` | 至少五个已记录盒时，最差 floor(盒数×20%) 盒补到平均值。 |
| `async` (0.0) | `async` | `_pop_next_box / _start_box` | 玩家盒优先，各组先进先出；助手不消耗等待馋值，也不享用或凭空增长该等待倍率。 |
| `sleep` (0.0) | `sleep` | `_end` | 剩菜按半价食物结算，再参与整顿倍率；不补剩余盒倍率。 |
| `diverge` (0.0) | `diverge` | `_magnet / _steer_food` | 仅思考时扩大玩家近距离拉菜范围。 |
| `converge` (0.0) | `converge` | `_steer_food / _wanted / _update_items` | 仅思考时跳过用不上的菜，影响吸菜与实际接住。 |
| `critic` (0.0) | `critic`、`bench` | `review_mult / _bite` | 吃过的不同套餐从第五种起增加整顿倍率；Benchmark 加同一数值。 |

## 不经过 BASE 的规则与残留边界

- **版本成长**：V3/R1/V3.1/V3.2/V4/AGI 的饭点为 60/70/80/90/105/120 秒；流式上限 2/2.5/3.5/4.5/6.5/6.5；连击额外叠层上限 3/5/7/9/12/12；招牌单菜累积上限 30/50/70/85/100/100%。R1 解锁思考，V3.2 解锁 DSA；0.4.2 移除了思考和 V3.1 的蓝色落点标记。版本文字不再只报抽象的上下文容量。
- **评测门票**：五个门票节点不写 BASE，`Game.open_trial()` 与 `pay_trial()` 开评测；目标 2,000 / 20,000 / 60,000 / 400,000 / 2,000,000，票价为目标的 10%。失败不返门票、也不降低下次难度。当前都是普通一顿的收入目标，没有服务器生存或清理“极”字的隐藏目标。
- **小助手特长**：问问加宽接菜口；谱谱近距离拉菜；小G接得更高；克劳拾附近落地食物；双子移动更快；格格为每盒第一份普通散菜提为优质，兼顾拨开极字。它们按出场名额自由选择，不依赖旧 `crew_*` 数值。训练与顿悟青菜、优质/金牌及热菜按同一价值策略处理，格格不再拨青菜，并为第一份普通散菜做质检；分工在开饭前配置，下顿生效。
- **隐含首级数值**：服务器繁忙拥有后额外加 0.5，因此第一级馋的最高倍率为 ×2，后续每级 +0.5；多轮对话拥有后额外加 0.05，因此第一级每连盒 +10%，后续每级 +5%。数据 effects 并非完整的最终倍率。
- **普通套餐与图鉴**：20 道普通配方来自 `menu.json`。乱炖和涌现是特殊组合；单品拼盘仅是盒型，三者不凭新盒规则伪造普通配方解锁。
- **旧原型残留**：`legacy = ""`，`floor_back = 0`、`app_rate = 0`、`dream = 0`、`think_eat = false`、`ji_rate = 0`、`token_mult = 1` 当前固定；旧难题/“极”试炼相关分支不由当前节点解锁。它们仍在旧代码里，但不计入本轮可玩机制或商店承诺。
- **未新增虚假控制项**：没有“降低上下文惩罚”空技能，没有新全屏吸附，没有全局字体/色盲模式承诺。菜单选择仍允许阻断某些套餐配方；这是玩家排菜的取舍，不自动替玩家保持所有配方可做。

## 验证与剩余工作

专属测试场景 `game/tests/mechanic_synergy_test.tscn` 只接受 `--test-profile=mechanic_synergy`；同时检查 `Game.save_path` 为 `user://qa_*`。它验证 74 非根节点、全部 effect 都有 BASE、旧等级得到新效果而保留旧效果、拼盘/幻觉/套餐边界、缓存只存用一次、换菜与普通盒断序、纯预览不消费、菜单最后一道保护、旧档菜单归一化、局内 LoRA 真实计数和拒绝动作不写档。

运行：`tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/mechanic_synergy_test.tscn -- --test-profile=mechanic_synergy`。结果：42 项，0 失败。专属 QA 文件可写，玩家设置前后字节一致。节点购买元数据与 Git HEAD 比较保持一致。

这些检查证明规则与存档边界，不证明新构筑完整经济平衡。局内输入、提示排版、可见收入与完整路线回归由 canteen/界面负责人继续验证。少量新增正向收益可能缩短个别路线；暂不为了追平机器人旧通关局数反向削弱原有技能。
