extends Node
## Persistent game state: tokens (the currency 大肥鱼 spits out), skill tree levels and the
## derived shift stats, the 大肥鱼 version ladder (V3 -> R1 -> ... -> AGI), plus the versioned
## save file and number formatting. The skill tree is data (res://data/skill_tree.json); stats
## are BASE with every owned node's effects applied, recomputed only when something is bought
## or loaded. Nodes carry a "ring" (the version that reveals them); a ticket node opens the
## trial for the next version, and passing the trial bumps `version`.

signal changed
signal achievement_unlocked(id: String)
signal save_failed(message: String)
signal save_committed(payload: String)

## Autotests play on their own save so they never touch the player's progress.
var save_path := "user://save.json"
## 2 = the canteen core (tokens). Version-1 saves came from the old task-bubble prototype and
## are reset rather than migrated.
const SAVE_VERSION := 3
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
	"helper": 0.0,         # number of simultaneously active helpers, freely chosen from six
	"helper_speed": 1.0,   # how fast they run (多 Agent 编排)
	"crew_relay": 0.0,     # distinct completed helper jobs support the next player delivery
	"crit_chance": 0.0,    # 中午吃什么: chance a bite is a crit
	"crit_mult": 2.0,
	"magnet": 0.0,         # fixed base radius; material never grants attraction
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
	"mono_bonus": 0.0,     # Prompt 模板: full box of one real dish qualifies as a platter
	"cache_bonus": 0.0,    # 上下文压缩: a roomy recipe box charges the next full player box
	"rotation_bonus": 0.0, # 上下文记忆: alternating the dish in consecutive single-dish platters
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
		"reward": "深度思考、上下文 64K（流式、连击和招牌菜的成长上限提高）、饭点延长"},
	{"plate": "大肥鱼 V3.1", "trial": "hybrid", "trial_name": "嗯，用户想要……", "target": 20000.0,
		"reward": "上下文 128K（成长上限提高）、饭点延长"},
	{"plate": "大肥鱼 V3.2", "trial": "ji", "trial_name": "V3.1-Terminus 终于不再冒「极」字了", "target": 60000.0,
		"reward": "DSA 稀疏注意力（未学顿悟时避开青菜）、上下文 256K（成长上限提高）、饭点延长"},
	{"plate": "大肥鱼 V4", "trial": "v4", "trial_name": "下周一定", "target": 400000.0,
		"reward": "上下文 1M（流式、连击和招牌菜的成长上限提高）、饭点延长"},
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
const HELPER_IDS := ["wen", "pu", "g", "ke", "zi", "ge"]
const AUTOMATION_KEYS := ["auto_push", "auto_return", "fuse3", "temp", "regen", "overfit", "bon"]
const DEFAULT_STALL_ORDER := ["dim", "wok", "main", "fry", "sweet"]
var stall_order: Array = DEFAULT_STALL_ORDER.duplicate()
var helper_plan: Dictionary = {}  # optional schema-3 selections; missing entries keep the old team
var automation: Dictionary = {}   # missing entries preserve the purchased skill's enabled behavior
var _helper_recipe_cache_key := ""
var _helper_recipe_cache: Array = []
var seen_buttons := {}      # tree-screen buttons the player has pressed at least once (new ones glow)
var achievements := {}      # stable ids -> first unlock time, independent of refundable skills
var lifetime := {"eaten": 0, "full_boxes": 0}
var ending_seen := false
var save_status := ""
var _save_read_only := false
var _test_profile := false
var _achievement_defs: Array = []
var _recipe_ids: Array = []
var _food_ids: Array = []
const TRIAL_FEE := 0.1     # each attempt costs 10% of its target; failure counts do not change difficulty

var nodes: Array = []     # from skill_tree.json
var _by_id := {}
var _stats := {}


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TREE_PATH))
	nodes = data["nodes"]
	var args := OS.get_cmdline_user_args()
	# Custom test scenes also stay isolated when launched from the editor/MCP without
	# command-line user arguments. Explicit test profiles below may override the name.
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/") and arg.ends_with(".tscn"):
			_test_profile = true
			save_path = "user://qa_scene_%s.json" % arg.get_file().get_basename().validate_filename()
	for arg in args:
		if arg.begins_with("--test-profile="):
			var profile := arg.trim_prefix("--test-profile=")
			var valid := not profile.is_empty() and profile.length() <= 48
			for ch in profile:
				if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(ch):
					valid = false
			_test_profile = true
			save_path = "user://qa_%s.json" % (profile if valid else "invalid_profile")
			if not valid:
				push_warning("Invalid test profile; using isolated invalid_profile save")
	if "--autotest" in args:
		if not _test_profile:
			save_path = "user://autotest_save.json"
		_test_profile = true
		for suffix in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(save_path + suffix)
	for n in nodes:
		_by_id[n["id"]] = n
	var defs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	_achievement_defs = defs.get("achievements", [])
	var menu: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu.json"))
	for recipe in menu.get("recipes", []):
		if recipe.get("kind", "") != "special":
			_recipe_ids.append(str(recipe.id))
	for food in menu.get("foods", []):
		_food_ids.append(str(food.id))
	_migrate_user_dir()
	load_game()
	if level("start") == 0:
		levels["start"] = 1
	_recompute()
	_check_achievements({}, false)


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
	if node(id).get("require_all", false):
		return parents.all(func(p): return level(p) > 0)
	for p in parents:
		if level(p) > 0:
			return true
	return false


func can_buy(id: String) -> bool:
	var n := node(id)
	if n.get("locked", false) or ring_levels(int(n.get("ring", 0))) < int(n.get("need_levels", 0)):
		return false
	return is_visible(id) and not is_maxed(id) and tokens >= cost(id)


## Reveal only the existence of one next branch, never recurse through other previews.
func is_preview(id: String) -> bool:
	var n := node(id)
	return not n.is_empty() and not is_visible(id) and n.get("parents", []).any(func(p): return is_visible(str(p)))


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
	_check_achievements()
	save_game()
	changed.emit()


## The next release's earning target; retain the final target after AGI.
func next_target() -> float:
	return float(VERSIONS[mini(version + 1, VERSIONS.size() - 1)].get("target", 0.0))


## The effective menu always keeps at least one currently available dish per open stall.
## Old saves are processed in selection order: skip only exclusions that would empty a stall.
func active_struck() -> Array:
	return _validated_struck(struck)


func _available_menu() -> Dictionary:
	CanteenRun.load_menu()
	var available := {}
	for id in CanteenRun.KIND:
		var k: int = CanteenRun.KIND[id]
		var stall: String = CanteenRun.STALL[k]
		if not CanteenRun.IS_SET[k] and not stall.is_empty() and float(_stats.get("stall_" + stall, 0.0)) >= CanteenRun.LEVEL[k]:
			available[id] = stall
	return available


func _validated_struck(selection: Array) -> Array:
	var available := _available_menu()
	var remaining := {}
	for id in available:
		var stall: String = available[id]
		remaining[stall] = int(remaining.get(stall, 0)) + 1
	var out: Array = []
	var capacity := maxi(0, int(_stats.get("menu_cut", 0.0)))
	for id in selection:
		if out.size() >= capacity:
			break
		if not available.has(id) or out.has(id):
			continue
		var stall: String = available[id]
		if int(remaining[stall]) <= 1:
			continue
		out.append(id)
		remaining[stall] = int(remaining[stall]) - 1
	return out


## An empty string means the change is valid. The UI translates the returned reason.
func struck_toggle_reason(id: String) -> String:
	var on := active_struck()
	if on.has(id):
		return ""
	var capacity := maxi(0, int(_stats.get("menu_cut", 0.0)))
	if capacity == 0:
		return "先学会「今日菜单」，再挑想划掉的菜。"
	if not _available_menu().has(id):
		return "这道菜还没有开放。"
	on.append(id)
	while on.size() > capacity:
		on.pop_front()
	if not _validated_struck(on).has(id):
		return "每个档口至少保留一道菜。"
	return ""


## The oldest strike drops out at capacity. Failed changes cannot alter or save selections.
func toggle_struck(id: String) -> bool:
	var on := active_struck()
	if on.has(id):
		on.erase(id)
	else:
		if not struck_toggle_reason(id).is_empty():
			return false
		on.append(id)
		while on.size() > int(stat("menu_cut")):
			on.pop_front()
	struck = _validated_struck(on)
	save_game()
	changed.emit()
	return true


## Bought outgoing branches keep an owned prerequisite alive, even with another parent.
func refund_dependents(id: String) -> Array:
	var out: Array = []
	for n in nodes:
		if level(str(n.id)) > 0 and n.get("parents", []).has(id):
			out.append(str(n.id))
	return out


func refund_floor(id: String) -> int:
	var n := node(id)
	if n.is_empty() or level(id) <= 0:
		return 0
	if id == "start" or n.get("kind", "") == "ticket":
		return level(id)
	return 1 if not refund_dependents(id).is_empty() else 0


## Refund unused levels; the last prerequisite point stays while a child is owned.
func refund(id: String) -> float:
	var n := node(id)
	if n.is_empty() or id == "start" or n.get("kind", "") == "ticket" or level(id) == 0:
		return 0.0
	var keep := refund_floor(id)
	if level(id) <= keep:
		return 0.0
	var back := 0.0
	for i in range(keep, level(id)):
		back += floor(float(n["cost"]) * pow(float(n.get("growth", 1.0)), i))
	if keep > 0:
		levels[id] = keep
	else:
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
	if trial == "" or trial != open_trial() or fee <= 0.0 or tokens < fee:
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


## Prepared between meals. All six characters are available; recruitment buys team slots.
func helper_capacity() -> int:
	return clampi(int(stat("helper")), 0, HELPER_IDS.size())


## Reveal each planning page only when its corresponding skill has been learned.
func automation_pages() -> Array[String]:
	var pages: Array[String] = []
	if helper_capacity() > 0:
		pages.append("crew")
	if stat("auto_push") > 0:
		pages.append("automation")
	return pages


func active_helpers() -> Array:
	var out: Array = []
	var cap := helper_capacity()
	for i in HELPER_IDS.size():
		var id: String = HELPER_IDS[i]
		var entry: Dictionary = helper_plan.get(id, {})
		if bool(entry.get("active", i < cap)) and out.size() < cap:
			out.append(id)
	return out


## Keep requested jobs even after a refund/menu edit, but explain the safe effective fallback.
func helper_config(id: String) -> Dictionary:
	var entry: Dictionary = helper_plan.get(id, {}) if HELPER_IDS.has(id) else {}
	var role: String = entry.get("role", "sweep")
	var recipe: String = entry.get("recipe", "")
	var result := {"active": active_helpers().has(id), "role": role, "recipe": recipe,
		"requested_role": role, "requested_recipe": recipe, "reason": ""}
	if role == "recipe":
		if stat("fc") <= 0.0:
			result.reason = "需要先学会 Function Calling：点单。"
		elif not helper_recipe_options().any(func(r): return r.id == recipe):
			result.reason = "当前菜单或饭盒无法完成这道菜，暂时改为补漏。"
	elif role == "nutrition" and stat("nutri") <= 0.0:
		result.reason = "需要先学会营养师 Agent。"
	elif role not in ["sweep", "recipe", "nutrition"]:
		result.reason = "这项分工已不可用，暂时改为补漏。"
	if not str(result.reason).is_empty():
		result.role = "sweep"
		result.recipe = ""
	return result


func set_helper_config(id: String, active: bool, role: String, recipe: String) -> bool:
	if not HELPER_IDS.has(id) or helper_capacity() <= 0 or role not in ["sweep", "recipe", "nutrition"]:
		return false
	if role == "recipe" and (stat("fc") <= 0.0 or not helper_recipe_options().any(func(r): return r.id == recipe)):
		return false
	if role == "nutrition" and stat("nutri") <= 0.0:
		return false
	var team := active_helpers()
	if active and not team.has(id) and team.size() >= helper_capacity():
		return false
	# Materialize the current team before editing so a default member cannot silently replace
	# a benched member, and selecting the sixth character cannot evict an earlier choice.
	for member in HELPER_IDS:
		if not helper_plan.has(member):
			helper_plan[member] = {"active": team.has(member), "role": "sweep", "recipe": ""}
	helper_plan[id] = {"active": active, "role": role, "recipe": recipe if role == "recipe" else ""}
	save_game()
	changed.emit()
	return true


func automation_enabled(key: String) -> bool:
	return AUTOMATION_KEYS.has(key) and stat(key) > 0.0 and bool(automation.get(key, true))


func set_automation(key: String, enabled: bool) -> bool:
	if not AUTOMATION_KEYS.has(key) or stat(key) <= 0.0:
		return false
	automation[key] = enabled
	save_game()
	changed.emit()
	return true


func _valid_stall_order(value: Variant) -> bool:
	if not value is Array or value.size() != DEFAULT_STALL_ORDER.size():
		return false
	var seen: Array = []
	for id in value:
		if not id is String or not DEFAULT_STALL_ORDER.has(id) or seen.has(id):
			return false
		seen.append(id)
	return true


func active_stall_order() -> Array:
	return stall_order.duplicate() if _valid_stall_order(stall_order) else DEFAULT_STALL_ORDER.duplicate()


func set_stall_order(order: Array) -> bool:
	if not _valid_stall_order(order):
		return false
	var before := stall_order.duplicate()
	var had_intro := seen_buttons.has("intro_stall_layout")
	var prior_intro: Variant = seen_buttons.get("intro_stall_layout", false)
	stall_order = order.duplicate()
	seen_buttons["intro_stall_layout"] = true
	if not save_game():
		stall_order = before
		if had_intro:
			seen_buttons["intro_stall_layout"] = prior_intro
		else:
			seen_buttons.erase("intro_stall_layout")
		return false
	changed.emit()
	return true


func stall_layout_intro_due() -> bool:
	if runs < 3 or bool(seen_buttons.get("intro_stall_layout", false)):
		return false
	var open := 0
	for id in DEFAULT_STALL_ORDER:
		if stat("stall_" + id) > 0:
			open += 1
	return open >= 2


## A recipe must have a feasible collection order, including intermediate auto-merges and
## the real two-row packing rule. These pure previews never discover recipes or spend food.
func helper_recipe_options() -> Array:
	CanteenRun.load_menu()
	var known := recipes.keys()
	known.sort()
	var key := JSON.stringify([_available_menu().keys(), active_struck(), stat("box_n"), stat("compress"), known])
	if key == _helper_recipe_cache_key:
		return _helper_recipe_cache.duplicate(true)
	var options: Array = []
	var available := _available_menu()
	for id in active_struck():
		available.erase(id)
	var sim := CanteenRun.new()
	sim.box_n = int(stat("box_n"))
	sim.compress = int(stat("compress"))
	for r in CanteenRun.RECIPES:
		if r.kind == "hidden" and not recipes.has(r.id):
			continue
		var parts: Array = sim._ingredients(int(r.result))
		var possible := not parts.is_empty()
		for part in parts:
			var food_id: String = CanteenRun.KIND.find_key(int(part))
			if not available.has(food_id):
				possible = false
		if not possible or sim._pack([int(r.result)]).is_empty():
			continue
		var memo := {}
		if _helper_recipe_route(sim, int(r.result), [], parts, memo):
			options.append({"id": str(r.id), "name": str(r.name), "kind": int(r.result)})
	sim.free()
	_helper_recipe_cache_key = key
	_helper_recipe_cache = options
	return options.duplicate(true)


func _helper_recipe_route(sim: CanteenRun, target: int, items: Array, remaining: Array, memo: Dictionary) -> bool:
	if items.any(func(it): return CanteenRun.K(int(it)) == target):
		return true
	if remaining.is_empty():
		return false
	var kinds: Array = items.map(func(it): return CanteenRun.K(int(it)))
	var rest := remaining.duplicate()
	rest.sort()
	var key := JSON.stringify([kinds, rest])
	if memo.has(key):
		return false
	memo[key] = true
	var tried: Array = []
	for i in remaining.size():
		var part: int = remaining[i]
		if tried.has(part):
			continue
		tried.append(part)
		var next := items.duplicate()
		next.append(part)
		sim._merge_items(next)
		if sim._pack(next).is_empty():
			continue
		var missing := remaining.duplicate()
		missing.remove_at(i)
		if _helper_recipe_route(sim, target, next, missing, memo):
			return true
	return false


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
			back += floor(float(n["cost"]) * pow(float(n.get("growth", 1.0)), i))
	levels = keep
	tokens += back
	_recompute()
	if back > 0.0:
		_unlock("checkpoint")
	save_game()
	changed.emit()
	return back


func fail_trial(trial: String) -> int:
	trial_fails[trial] = mini(int(trial_fails.get(trial, 0)) + 1, 3)
	save_game()
	return int(trial_fails[trial])


func buy(id: String) -> bool:
	if not _by_id.has(id) or not can_buy(id):
		return false
	tokens -= cost(id)
	levels[id] = level(id) + 1
	_recompute()
	_check_achievements()
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
func save_game() -> bool:
	if _save_read_only:
		return _save_error("This save belongs to a newer game version; it has not been overwritten.")
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _save_error("Cannot write save file (%s)." % error_string(FileAccess.get_open_error()))
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "tokens": tokens, "total_tokens": total_tokens,
		"runs": runs, "best_run": best_run, "levels": levels, "fish_version": version,
		"trial_fails": trial_fails, "recipes": recipes, "signatures": signatures, "struck": struck,
		"helper_plan": helper_plan, "automation": automation, "stall_order": active_stall_order(),
		"seen_buttons": seen_buttons, "achievements": achievements, "lifetime": lifetime,
		"ending_seen": ending_seen, "saved_at": Time.get_unix_time_from_system()}, "\t"))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK or _read_save(tmp).is_empty():
		return _save_error("Save write did not complete; previous progress is preserved.")
	# Never rotate a corrupt primary over the last good backup. Copy, then replace the
	# primary: a failed backup or final rename leaves the original in place.
	if not _read_save(save_path).is_empty():
		var backup_tmp := save_path + ".bak.tmp"
		var err := DirAccess.copy_absolute(save_path, backup_tmp)
		if err == OK:
			err = DirAccess.rename_absolute(backup_tmp, save_path + ".bak")
		if err != OK:
			return _save_error("Cannot update save backup (%s)." % error_string(err))
	var rename_error := DirAccess.rename_absolute(tmp, save_path)
	if rename_error != OK:
		return _save_error("Cannot replace save file (%s)." % error_string(rename_error))
	save_status = ""
	if platform_sync_allowed():
		save_committed.emit(FileAccess.get_file_as_string(save_path))
	return true


func platform_sync_allowed() -> bool:
	return not _test_profile and not _save_read_only


## Supply the same last-known-good save that load_game uses, including backup recovery.
func cloud_snapshot() -> String:
	for suffix in ["", ".tmp", ".bak"]:
		var data := _read_save(save_path + suffix)
		if not data.is_empty():
			return JSON.stringify(data)
	return ""


## Validate through the ordinary save reader before touching the active save. Keep an
## independent pre-cloud copy so choosing another device's progress is recoverable.
func restore_cloud_save(payload: String) -> bool:
	var candidate := save_path + ".cloud.tmp"
	var file := FileAccess.open(candidate, FileAccess.WRITE)
	if file == null:
		return _save_error("Cannot prepare the cloud save; local progress is preserved.")
	file.store_string(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	var data := _read_save(candidate)
	if write_error != OK or data.is_empty() or int(data.get("version", 0)) < 2 or int(data.version) > SAVE_VERSION:
		DirAccess.remove_absolute(candidate)
		return _save_error("Cloud save is damaged or uses an unsupported version; local progress is preserved.")
	var local := cloud_snapshot()
	if not local.is_empty():
		var backup := FileAccess.open(save_path + ".before-cloud", FileAccess.WRITE)
		if backup == null:
			return _save_error("Cannot back up local progress; cloud restore was cancelled.")
		backup.store_string(local)
		backup.flush()
		var backup_error := backup.get_error()
		backup.close()
		if backup_error != OK:
			return _save_error("Cannot back up local progress; cloud restore was cancelled.")
	var err := DirAccess.rename_absolute(candidate, save_path)
	if err != OK:
		return _save_error("Cannot install the cloud save; local progress is preserved.")
	load_game()
	changed.emit()
	return true


func _save_error(message: String) -> bool:
	save_status = message
	push_warning(message)
	save_failed.emit(message)
	return false


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## A syntactically valid JSON object can still be an unusable save. Refuse wrong field
## types before converting them, so a damaged primary also gets backup recovery.
func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	var d: Dictionary = parser.data
	if not _number(d.get("version", null)):
		return {}
	if int(d.version) > SAVE_VERSION:
		return d   # protect future formats without trying to interpret their schema
	if int(d.version) >= 2:
		for key in ["tokens", "total_tokens", "runs", "best_run", "fish_version", "levels"]:
			if not d.has(key):
				return {}
	for key in ["tokens", "total_tokens", "runs", "best_run", "fish_version"]:
		if d.has(key) and not _number(d[key]):
			return {}
	for key in ["levels", "trial_fails", "recipes", "seen_buttons", "achievements", "lifetime"]:
		if d.has(key) and not d[key] is Dictionary:
			return {}
	for key in ["signatures", "struck"]:
		if d.has(key) and not d[key] is Array:
			return {}
	return d


## Builds before 0.2 kept the save in Godot's default folder (app_userdata/吃白饭的大肥鱼);
## the game now has its own ASCII folder (application/config/custom_user_dir_name), friendlier
## to Steam Cloud. Copy an old save over once.
func _migrate_user_dir() -> void:
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak") or FileAccess.file_exists(save_path + ".tmp") or OS.has_feature("web") or _test_profile:
		return
	var old := OS.get_data_dir().path_join("Godot/app_userdata/吃白饭的大肥鱼/save.json")   # notr
	_import_legacy_save(old)


func _import_legacy_save(old: String) -> bool:
	for suffix in ["", ".tmp", ".bak"]:
		if not _read_save(old + suffix).is_empty():
			if DirAccess.copy_absolute(old + suffix, save_path) == OK:
				print("save recovered from legacy directory")
				return true
	return false


func load_game() -> void:
	_save_read_only = false
	var d := _read_save(save_path)
	if d.is_empty():
		for suffix in [".tmp", ".bak"]:
			d = _read_save(save_path + suffix)
			if not d.is_empty():
				save_status = "Recovered progress from " + suffix
				push_warning(save_status)
				break
	if d.is_empty():
		if FileAccess.file_exists(save_path):
			_save_error("Save and backups could not be read.")
		return
	if int(d.get("version", 1)) < 2:
		print("old prototype save (version %d) reset for the canteen version" % int(d.get("version", 1)))
		return
	if int(d.version) > SAVE_VERSION:
		_save_read_only = true
		_save_error("This save belongs to a newer game version; please use that version to continue.")
		return
	d = _migrate(d)
	tokens = maxf(0.0, float(d.get("tokens", 0.0)))
	total_tokens = maxf(tokens, float(d.get("total_tokens", 0.0)))
	runs = maxi(0, int(d.get("runs", 0)))
	best_run = maxf(0.0, float(d.get("best_run", 0.0)))
	version = clampi(int(d.get("fish_version", 0)), 0, VERSIONS.size() - 1)
	trial_fails = _count_dict(d.get("trial_fails", {}), 3)
	recipes = _count_dict(d.get("recipes", {}))
	for id in recipes.keys():
		if not _recipe_ids.has(id):
			recipes.erase(id)
	signatures = _food_list(d.get("signatures", []))
	struck = _food_list(d.get("struck", []))
	_load_helper_preferences(d)
	var saved_order: Variant = d.get("stall_order", null)
	stall_order = saved_order.duplicate() if _valid_stall_order(saved_order) else DEFAULT_STALL_ORDER.duplicate()
	seen_buttons = {}
	for id in d.get("seen_buttons", {}):
		if d.seen_buttons[id] is bool:
			seen_buttons[id] = d.seen_buttons[id]
	achievements = {}
	for def in _achievement_defs:
		var timestamp: Variant = d.get("achievements", {}).get(def.id, 0)
		if _number(timestamp) and float(timestamp) > 0.0:
			achievements[def.id] = float(timestamp)
	lifetime = _count_dict(d.get("lifetime", {}))
	ending_seen = d.get("ending_seen", false) == true
	levels = {}
	var saved: Dictionary = d.get("levels", {})
	for id in saved:
		if _by_id.has(id) and _number(saved[id]):
			levels[id] = clampi(int(saved[id]), 0, int(_by_id[id]["max"]))
	levels["start"] = 1
	_recompute()
	struck = active_struck()
	_check_achievements({}, false)


func _load_helper_preferences(data: Dictionary) -> void:
	helper_plan = {}
	automation = {}
	var source: Variant = data.get("helper_plan", {})
	if source is Dictionary:
		for id in HELPER_IDS:
			var entry: Variant = source.get(id, null)
			if not entry is Dictionary or not entry.get("active", null) is bool:
				continue
			var role: Variant = entry.get("role", "sweep")
			var recipe: Variant = entry.get("recipe", "")
			helper_plan[id] = {"active": entry.active,
				"role": role if role is String and role in ["sweep", "recipe", "nutrition"] else "sweep",
				"recipe": recipe if recipe is String and _recipe_ids.has(recipe) else ""}
	var switches: Variant = data.get("automation", {})
	if switches is Dictionary:
		for key in AUTOMATION_KEYS:
			if switches.get(key, null) is bool:
				automation[key] = switches[key]


func _count_dict(source: Dictionary, maximum := 2000000000) -> Dictionary:
	var out := {}
	for id in source:
		if id is String and _number(source[id]):
			out[id] = clampi(int(source[id]), 0, maximum)
	return out


func _food_list(source: Array) -> Array:
	var out: Array = []
	for id in source:
		if id is String and _food_ids.has(id) and not out.has(id):
			out.append(id)
	return out


## Upgrade older saves step by step: add a branch per SAVE_VERSION bump.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", SAVE_VERSION))
	if v == 2:
		d["achievements"] = {}
		d["lifetime"] = {"eaten": 0, "full_boxes": 0}
		d["ending_seen"] = false
		d["version"] = 3
	return d


func reset_save() -> void:
	tokens = 0.0
	total_tokens = 0.0
	runs = 0
	best_run = 0.0
	version = 0
	trial_fails = {}
	recipes = {}
	signatures = []
	struck = []
	helper_plan = {}
	automation = {}
	seen_buttons = {}
	stall_order = DEFAULT_STALL_ORDER.duplicate()
	achievements = {}
	lifetime = {"eaten": 0, "full_boxes": 0}
	ending_seen = false
	_save_read_only = false
	levels = {"start": 1}
	_recompute()
	if save_game():
		# An explicit reset must not resurrect old progress after a damaged fresh save.
		DirAccess.copy_absolute(save_path, save_path + ".bak")
	changed.emit()


func achievement_catalog() -> Array:
	return _achievement_defs.duplicate(true)


func ending_pending() -> bool:
	return version == VERSIONS.size() - 1 and not ending_seen


func mark_ending_seen() -> void:
	ending_seen = true
	save_game()
	changed.emit()


func _unlock(id: String, announce := true) -> void:
	if achievements.has(id):
		return
	achievements[id] = Time.get_unix_time_from_system()
	if announce:
		achievement_unlocked.emit(id)


## Called once at settlement, after runs/best_run are updated. Unknown historical
## per-shift metrics are never inferred when migrating an older save.
func record_run(summary: Dictionary) -> void:
	for key in ["eaten", "full_boxes"]:
		lifetime[key] = int(lifetime.get(key, 0)) + maxi(0, int(summary.get(key, 0)))
	_check_achievements(summary)


func _check_achievements(summary: Dictionary = {}, announce := true) -> void:
	var conditions := {
		"first_meal": runs >= 1, "regular": runs >= 10, "resident": runs >= 30,
		"release_r1": version >= 1, "release_v31": version >= 2, "release_v32": version >= 3,
		"release_v4": version >= 4, "release_agi": version >= 5,
		"tokens_10k": total_tokens >= 10000.0, "tokens_1m": total_tokens >= 1000000.0,
		"recipe_first": recipes.size() >= 1, "recipe_ten": recipes.size() >= 10,
		"recipe_twentyfive": recipes.size() >= 15,
		"recipe_all": not _recipe_ids.is_empty() and recipes.size() >= _recipe_ids.size(),
		"bites_100": int(lifetime.get("eaten", 0)) >= 100,
		"bites_1000": int(lifetime.get("eaten", 0)) >= 1000,
		"full_boxes": int(lifetime.get("full_boxes", 0)) >= 25,
		"balanced": float(summary.get("balance", 0.0)) >= 1.9 and int(summary.get("eaten", 0)) >= 20,
		"grokked": summary.get("grokked", false) == true,
		"steady_hands": int(summary.get("caught", 0)) >= 20 and int(summary.get("spilled", 1)) == 0,
		"feast": int(summary.get("eaten", 0)) >= 100,
		"all_stalls": _stats.get("stall_wok", 0.0) > 0 and _stats.get("stall_dim", 0.0) > 0 and _stats.get("stall_fry", 0.0) > 0 and _stats.get("stall_sweet", 0.0) > 0,
		"full_crew": _stats.get("helper", 0.0) >= 6.0,
		"gold_box": _stats.get("material", 0.0) >= 3.0,
	}
	for id in conditions:
		if conditions[id]:
			_unlock(id, announce)
