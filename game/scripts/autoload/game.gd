extends Node
## Persistent game state: tokens (the currency 大肥鱼 spits out), skill tree levels and the
## derived shift stats, the 大肥鱼 version ladder (V3 -> R1 -> ... -> AGI), plus the versioned
## save file and number formatting. The skill tree is data (res://data/skill_tree.json); stats
## are BASE with every owned node's effects applied, recomputed only when something is bought
## or loaded. Nodes carry a "ring" (the version that reveals them); a ticket node opens the
## trial for the next version, and passing the trial bumps `version`.

signal changed

## Autotests play on their own save so they never touch the player's progress.
var save_path := "user://save.json"
## 2 = the canteen core (tokens). Version-1 saves came from the old task-bubble prototype and
## are reset rather than migrated.
const SAVE_VERSION := 2
const TREE_PATH := "res://data/skill_tree.json"

## Shift stats before any upgrade. Every key here can be named in a node's "effects".
const BASE := {
	"box_n": 2.0,          # columns of the lunch box: 2 rows x 2 -> 3 -> 4 columns (显存扩容)
	"basins": 3.0,         # boxes you own (显存扩容 adds one per level too)
	"material": 0.0,       # 0 铁 1 铜 2 银 3 金: the whole meal x1 / 1.5 / 2 / 3
	"eat_rate": 2.0,       # bites she eats per second (猛炫)
	"tentacles": 0.0,      # 并发请求: tentacles on top of one per open window
	"shake": 1.0,          # 手抖: spread of where a scoop lands
	"scoop": 0.0,          # extra items per scoop
	"batch": 0.0,          # Batch Size: chance per scoop of one more dish
	"peaks": 0.0,          # 推理高峰: 1 = peak / off-peak hours
	"peak_time": 5.0,      # seconds of each peak
	"peak_good": 3.0,      # good-stuff multiplier during peaks
	"helper": 0.0,         # 招募小助手: 问问, then 谱谱 / 小G / 克劳 / 双子 / 格格 (CanteenRun.CREW)
	"crew_pu": 0.0,
	"crew_g": 0.0,
	"crew_ke": 0.0,
	"crew_zi": 0.0,
	"crew_ge": 0.0,
	"helper_speed": 1.0,   # how fast they run (多 Agent 编排)
	"crit_chance": 0.0,    # 中午吃什么: chance a bite is a crit
	"crit_mult": 2.0,
	"magnet": 0.0,         # px: the basin pulls nearby food in (the gold basin adds its own)
	"think_time": 2.5,     # 深度思考 (R1): seconds of slow motion the gauge holds
	"think_slow": 0.35,    # world speed while thinking
	"think_regen": 0.4,    # gauge refilled per second when not thinking
	"throw_rate": 1.0,     # API 价格打骨折: how often 梁阿姨 throws
	"stall_main": 1.0,     # 梁阿姨's stalls: menu level (0 = closed), data/menu.json
	"stall_wok": 0.0,
	"stall_dim": 0.0,
	"stall_fry": 0.0,
	"stall_sweet": 0.0,
	"balance_max": 2.0,    # 均衡倍率 at a perfect 主 : 荤 : 素 balance (RLHF raises it)
	"sig_slots": 0.0,      # 招牌菜 picked before a shift (MoE 激活专家: one per level)
	"auto_push": 0.0,      # Skill 自动推送 / 自动回收
	"auto_return": 0.0,
	# the scoring model, docs/tree_model.md (口 -> 盒 -> 顿); CanteenRun._read_stats reads them
	"stream": 0.0,         # 流式输出: 越吃越香 slope
	"ttft": 0.0,           # 降低首 Token 延迟: 越吃越香 starts 10 bites earlier per level
	"mtp": 0.0,            # MTP: + tokens per bite
	"menu_cut": 0.0,       # 今日菜单: dishes struck off before a shift
	"sft": 0.0,            # SFT: chance a dish is 优质
	"lora": 0.0,           # LoRA: + that chance per struck dish
	"dpo": 0.0,            # DPO: chance an 优质 dish is 金牌
	"fp32": 0.0,           # FP32: 金牌 x5
	"veg_std": 0.0,        # 食堂标配: chance per scoop of a spoon of greens
	"temp": 0.0,           # Temperature: chance a dish turns into a better one in the box
	"hot": 0.0,            # 高温采样: + to what a randomly touched dish is worth (x1.5)
	"halluc": 0.0,         # 幻觉: chance of a ghost bite
	"regen": 0.0,          # 重新生成: chance a served box is rerolled
	"emerge": 0.0,         # 涌现能力
	"overfit": 0.0,        # 过拟合
	"box_bonus": 0.0,      # 光学压缩: + to every box
	"fill_bonus": 0.0,     # 上下文填满: + to a full box
	"tier1": 0.0,          # 套餐等级: Prompt 模板 / Few-shot / Agent 工作流 / AGI 菜谱
	"tier2": 0.0,
	"tier3": 0.0,
	"tier4": 0.0,
	"inject": 0.0,         # 提示词注入
	"compress": 0.0,       # 上下文压缩: 套餐 take a cell less
	"fuse3": 0.0,          # 模型融合
	"hodge": 0.0,          # MoE 大杂烩
	"cot": 0.0,            # 思维链: + per chain merge in a box (max 3)
	"rag": 0.0,            # RAG: + per 优质 / 金牌 ingredient
	"spec": 0.0,           # 投机解码: chance per merge
	"crave": 0.0,          # 服务器繁忙: 馋 1 + crave (1 - e^(-t / crave_tau))
	"crave_tau": 6.0,      # 排队中 makes her 馋 faster
	"combo": 0.0,          # 多轮对话: + per box in a row
	"memory": 0.0,         # 上下文记忆
	"warm": 0.0,           # KV Cache 保温箱
	"final": 0.0,          # Final Answer: the 保温箱 box x(2 + final)
	"bon": 0.0,            # Best-of-N
	"eos": 0.0,            # <EOS>: the best bite of the 保温箱 box, eaten last, x3 / x5 / x8 (levels)
	"constit": 0.0,        # 宪法 AI: a softer balance curve
	"grok": 0.0,           # 顿悟
	"grok_need": 30.0,     # greens to force down before she gets it (学习率预热)
	"aftertaste": 0.0,     # 回甘: + per grokked green (6 base)
	"drift": 0.0,          # 向量漂移
	"fc": 0.0,             # Function Calling 点单
	"nutri": 0.0,          # 营养师 Agent
	"clip": 0.0,           # 梯度裁剪
	"async": 0.0,          # 异步调用
	"sleep": 0.0,          # 我去睡了
	"diverge": 0.0,        # 发散思维: px of pull while thinking
	"converge": 0.0,       # 收敛思维
	"critic": 0.0,         # 美食评鉴 (+ Benchmark): + per kind of 套餐 from the 5th
}

## The version ladder. Releasing a version = its 评测 (trial): one ordinary shift with your own
## build that must earn `target` tokens (after the end-of-shift multipliers); every try costs a
## ticket of TRIAL_FEE x target. `reward` is what the release gives for free (not a node).
## (`easier` is left from the old special trials, unused.)
## The rewards themselves are coded in CanteenRun by version: 1 深度思考, 2 混合思考, 3 DSA.
const VERSIONS := [
	{"plate": "大肥鱼 V3"},
	{"plate": "大肥鱼 R1", "trial": "spring", "trial_name": "春节前夜·服务器繁忙", "target": 2000.0,
		"reward": "深度思考（按住空格或右键，时间变慢）、上下文 64K、饭点延长"},
	{"plate": "大肥鱼 V3.1", "trial": "hybrid", "trial_name": "嗯，用户想要……", "target": 20000.0,
		"reward": "混合思考（好菜的落点自动标出来）、上下文 128K、饭点延长"},
	{"plate": "大肥鱼 V3.2", "trial": "ji", "trial_name": "V3.1-Terminus 终于不再冒「极」字了", "target": 60000.0,
		"reward": "DSA 稀疏注意力（磁铁只吸好东西，青菜会弹开）、上下文 256K、饭点延长"},
	{"plate": "大肥鱼 V4", "trial": "v4", "trial_name": "下周一定", "target": 400000.0,
		"reward": "上下文 1M、饭点延长"},
	{"plate": "大肥鱼 AGI", "trial": "agi", "trial_name": "实现 AGI，但是也要先吃饱", "target": 2000000.0,
		"reward": "通关！大肥鱼实现了 AGI，然后又饿了"},
]

var tokens := 0.0
var total_tokens := 0.0
var runs := 0
var best_run := 0.0      # most tokens earned in one shift
var levels := {}          # node id -> level
var version := 0          # 大肥鱼's version: index into VERSIONS
var trial_fails := {}
var recipes := {}         # 菜谱图鉴: recipe id -> times made
var signatures: Array = []  # 招牌菜 picked by the player (food ids); see active_signatures()
var struck: Array = []      # 今日菜单: dishes struck off (food ids), up to stat menu_cut
var seen_buttons := {}      # tree-screen buttons the player has pressed at least once (new ones glow)
const TRIAL_FEE := 0.1     # trial id -> times failed (each one makes the next try easier, max 3)

var nodes: Array = []     # from skill_tree.json
var _by_id := {}
var _stats := {}


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TREE_PATH))
	nodes = data["nodes"]
	if "--autotest" in OS.get_cmdline_user_args():
		save_path = "user://autotest_save.json"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for n in nodes:
		_by_id[n["id"]] = n
	_migrate_user_dir()
	load_game()
	if level("start") == 0:
		levels["start"] = 1
	_recompute()


func node(id: String) -> Dictionary:
	return _by_id.get(id, {})


func level(id: String) -> int:
	return int(levels.get(id, 0))


func total_levels() -> int:
	var t := 0
	for id in levels:
		t += int(levels[id])
	return t


func cost(id: String) -> float:
	var n := node(id)
	return floor(float(n["cost"]) * pow(float(n["growth"]), level(id)))


func is_maxed(id: String) -> bool:
	return level(id) >= int(node(id)["max"])


## A node shows up once its version ring is released and any parent is owned (the root is
## always shown).
func is_visible(id: String) -> bool:
	if int(node(id).get("ring", 0)) > version:
		return false
	var parents: Array = node(id)["parents"]
	if parents.is_empty():
		return true
	for p in parents:
		if level(p) > 0:
			return true
	return false


func can_buy(id: String) -> bool:
	var n := node(id)
	if n.get("locked", false) or ring_levels(int(n.get("ring", 0))) < int(n.get("need_levels", 0)):
		return false
	return is_visible(id) and not is_maxed(id) and tokens >= cost(id)


## Levels bought in one version ring (tickets and the root don't count).
func ring_levels(ring: int) -> int:
	var t := 0
	for id in levels:
		var n := node(id)
		if int(n.get("ring", 0)) == ring and n.get("kind", "") != "ticket" and id != "start":
			t += int(levels[id])
	return t


func plate() -> String:
	return VERSIONS[version]["plate"]


## How much feeling 大肥鱼 shows outside the shift (FishRig.emote), growing with her version:
## 0 木讷 up to V3.1 (deadpan, holding her basin), 1 at V3.2 (a small smile now and then),
## 2 from V4 (the full range, and the title shows her standing, smiling art).
func emotion() -> int:
	return 0 if version <= 2 else (1 if version == 3 else 2)


## The trial that is open right now ("" if none): the next version's ticket is bought.
func open_trial() -> String:
	if version + 1 >= VERSIONS.size():
		return ""
	var next: Dictionary = VERSIONS[version + 1]
	for n in nodes:
		if n.get("kind", "") == "ticket" and n.get("opens", "") == next.get("trial", "") and level(n["id"]) > 0:
			return next["trial"]
	return ""


func trial_name(trial: String) -> String:
	return trial_info(trial).get("trial_name", trial)


## The VERSIONS entry released by this trial ({} if none).
func trial_info(trial: String) -> Dictionary:
	for v in VERSIONS:
		if v.get("trial", "") == trial:
			return v
	return {}


## Passing a trial releases the next version: its ring shows up on the tree.
func pass_trial() -> void:
	version = mini(version + 1, VERSIONS.size() - 1)
	save_game()
	changed.emit()


## The target the next release asks for (a shift's fuse is 3 x this); the last one at the end.
func next_target() -> float:
	return float(VERSIONS[mini(version + 1, VERSIONS.size() - 1)].get("target", 0.0))


## 今日菜单: strike a dish off / put it back (the oldest strike drops out when all are used).
func toggle_struck(id: String) -> void:
	if struck.has(id):
		struck.erase(id)
	else:
		struck.append(id)
		while struck.size() > int(stat("menu_cut")):
			struck.pop_front()
	save_game()
	changed.emit()


## Right click on the tree: refund every level of one node (tickets and the root stay).
func refund(id: String) -> float:
	var n := node(id)
	if id == "start" or n.get("kind", "") == "ticket" or level(id) == 0:
		return 0.0
	var back := 0.0
	for i in level(id):
		back += float(n["cost"]) * pow(float(n.get("growth", 1.0)), i)
	levels.erase(id)
	tokens += back
	_recompute()
	save_game()
	changed.emit()
	return back


## A trial's target and its ticket price.
func trial_target(trial: String) -> float:
	return float(trial_info(trial).get("target", 0.0))


func trial_fee(trial: String) -> float:
	return ceilf(trial_target(trial) * TRIAL_FEE)


## Pays the ticket for one try; false if you cannot afford it.
func pay_trial(trial: String) -> bool:
	var fee := trial_fee(trial)
	if trial == "" or tokens < fee:
		return false
	tokens -= fee
	save_game()
	changed.emit()
	return true


## The 招牌菜 in effect: the picked ones the open stalls serve, then the first others they
## serve, up to sig_slots.
func active_signatures() -> Array:
	CanteenRun.load_menu()
	var slots := int(stat("sig_slots"))
	var out: Array = []
	for id in signatures:
		if out.size() < slots and signature_available(id):
			out.append(id)
	for id in CanteenRun.KIND:
		if out.size() >= slots:
			break
		if signature_available(id) and not out.has(id):
			out.append(id)
	return out


func signature_available(id: String) -> bool:
	if not CanteenRun.KIND.has(id):
		return false
	var k: int = CanteenRun.KIND[id]
	return CanteenRun.SIG[k] != null and CanteenRun.STALL[k] != "" and stat("stall_" + CanteenRun.STALL[k]) >= CanteenRun.LEVEL[k]


## Toggles a 招牌菜 (the oldest pick drops out when all slots are full).
func toggle_signature(id: String) -> void:
	var on := active_signatures()
	if on.has(id):
		on.erase(id)
	else:
		on.append(id)
		while on.size() > int(stat("sig_slots")):
			on.pop_front()
	signatures = on
	save_game()
	changed.emit()


## 回滚到 checkpoint: every skill level is refunded in full (tickets and versions stay).
func respec() -> float:
	var back := 0.0
	var keep := {"start": 1}
	for id in levels:
		var n := node(id)
		if id == "start" or n.get("kind", "") == "ticket":
			keep[id] = levels[id]
			continue
		for i in int(levels[id]):
			back += float(n["cost"]) * pow(float(n.get("growth", 1.0)), i)
	levels = keep
	tokens += back
	_recompute()
	save_game()
	changed.emit()
	return back


func fail_trial(trial: String) -> int:
	trial_fails[trial] = mini(int(trial_fails.get(trial, 0)) + 1, 3)
	save_game()
	return int(trial_fails[trial])


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	tokens -= cost(id)
	levels[id] = level(id) + 1
	_recompute()
	save_game()
	changed.emit()
	return true


func stat(key: String) -> float:
	return float(_stats[key])


func _recompute() -> void:
	_stats = {}
	for key in BASE:
		var v := float(BASE[key])
		var mul := 1.0
		for id in levels:
			var effects: Dictionary = node(id).get("effects", {})
			if not effects.has(key):
				continue
			var e: Dictionary = effects[key]
			var lv := int(levels[id])
			v += float(e.get("add", 0.0)) * lv
			mul *= pow(float(e.get("mul", 1.0)), lv)
		_stats[key] = v * mul


## Records a 套餐 made; true the first time (a new entry in the 菜谱图鉴).
func find_recipe(id: String) -> bool:
	var first := not recipes.has(id)
	recipes[id] = int(recipes.get(id, 0)) + 1
	return first


func add_tokens(amount: float) -> void:
	tokens += amount
	total_tokens += amount
	changed.emit()


## 1234 -> "1234", 12345 -> "1.23万", 1.5e8 -> "1.50亿", 3e12 -> "3.00万亿", 3e16 -> "3.00京"
## In English: 12.3K, 1.50M, 2.00B, 3.00T.
func fmt(x: float) -> String:
	if x < 10000.0:
		return str(int(floor(x)))
	if Settings.is_english():
		for u in [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]:
			if x >= u[0] and x < u[0] * 1000.0:
				return "%.2f%s" % [x / u[0], u[1]] if x < u[0] * 100.0 else "%d%s" % [int(x / u[0]), u[1]]
	if x < 1e8:
		return "%.2f万" % (x / 1e4)   # notr
	if x < 1e12:
		return "%.2f亿" % (x / 1e8)   # notr
	if x < 1e16:
		return "%.2f万亿" % (x / 1e12)   # notr
	if x < 1e20:
		return "%.2f京" % (x / 1e16)   # notr
	var e := int(floor(log(x) / log(10.0)))
	return "%.2fe%d" % [x / pow(10.0, e), e]


## Saves atomically: write save.json.tmp, keep the previous save as save.json.bak, then rename,
## so a crash or power cut mid-write never leaves a broken save (load_game falls back to .bak).
func save_game() -> void:
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write the save")
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "tokens": tokens, "total_tokens": total_tokens,
		"runs": runs, "best_run": best_run, "levels": levels, "fish_version": version, "trial_fails": trial_fails, "recipes": recipes, "signatures": signatures, "struck": struck, "seen_buttons": seen_buttons, "saved_at": Time.get_unix_time_from_system()}, "\t"))
	f.close()
	if FileAccess.file_exists(save_path):
		DirAccess.rename_absolute(save_path, save_path + ".bak")
	DirAccess.rename_absolute(tmp, save_path)


## Builds before 0.2 kept the save in Godot's default folder (app_userdata/吃白饭的大肥鱼);
## the game now has its own ASCII folder (application/config/custom_user_dir_name), friendlier
## to Steam Cloud. Copy an old save over once.
func _migrate_user_dir() -> void:
	if FileAccess.file_exists(save_path) or OS.has_feature("web") or save_path.contains("autotest"):
		return
	var old := OS.get_data_dir().path_join("Godot/app_userdata/吃白饭的大肥鱼/save.json")   # notr
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(save_path))
		print("save moved from ", old)


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not d is Dictionary and FileAccess.file_exists(save_path + ".bak"):
		push_warning("save file unreadable, using the backup")
		d = JSON.parse_string(FileAccess.get_file_as_string(save_path + ".bak"))
	if not d is Dictionary:
		push_warning("save file unreadable, starting fresh")
		return
	if int(d.get("version", 1)) < 2:
		print("old prototype save (version %d) reset for the canteen version" % int(d.get("version", 1)))
		return
	d = _migrate(d)
	tokens = float(d.get("tokens", 0.0))
	total_tokens = float(d.get("total_tokens", 0.0))
	runs = int(d.get("runs", 0))
	best_run = float(d.get("best_run", 0.0))
	version = clampi(int(d.get("fish_version", 0)), 0, VERSIONS.size() - 1)
	trial_fails = d.get("trial_fails", {})
	recipes = d.get("recipes", {})
	signatures = d.get("signatures", [])
	struck = d.get("struck", [])
	seen_buttons = d.get("seen_buttons", {})
	levels = {}
	var saved: Dictionary = d.get("levels", {})
	for id in saved:
		if _by_id.has(id):   # nodes removed from the tree are dropped
			levels[id] = mini(int(saved[id]), int(_by_id[id]["max"]))


## Upgrade older saves step by step: add a branch per SAVE_VERSION bump.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", SAVE_VERSION))
	if v > SAVE_VERSION:
		push_warning("save is from a newer version (%d)" % v)
	return d


func reset_save() -> void:
	tokens = 0.0
	total_tokens = 0.0
	runs = 0
	best_run = 0.0
	version = 0
	trial_fails = {}
	recipes = {}
	struck = []
	seen_buttons = {}
	levels = {"start": 1}
	_recompute()
	save_game()
	changed.emit()
