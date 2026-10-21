class_name CanteenRun
extends Node2D
## One shift in the canteen (docs/core_design_v3.md). 梁阿姨, an octopus dinner lady
## behind the counter, flings food over it with her tentacles; you catch it in an iron basin,
## put the basin on the table, and 大肥鱼 wolfs it down into tokens. The "basin" is a square
## 铁饭盒 (lunch box), an n x n grid (2x2 -> 3x3 -> 4x4) drawn from a fixed 45° top-down view.
##   move mouse   the basin follows with limited speed and acceleration; the fuller (and bigger)
##                it is, the heavier and more sluggish. Yanking it around makes the food slosh,
##                and a sloshing, well-filled basin spills
##   LMB          over the table: take an empty box from the stack, or put the one in your hand
##                down (a full one joins the queue she eats from, an empty one goes back on the stack).
##                She puts every box she has emptied back on the stack. The table keeps two piles:
##                the stack of empty boxes and the queue of full ones (docs/fish_actions_design.md).
##   keyboard / gamepad: WASD / arrows / left stick move, E / Enter / A put it down,
##                Space / Shift / B / RB / RT think, Esc / P / Start pause (PauseMenu)
## A shift ends at 吃饱了 (stomach full) or 食堂关门 (the meal clock runs out); then a result
## card, then `finished`. All numbers come from Game.stat() (the skill tree).
##   Space / RMB  深度思考 (from R1): the world slows down; energy and cooldown limit it.
## Later versions add DSA (V3.2: the
## magnet only pulls good food, greens bounce off, golden 「极」 hop around in normal shifts).
## `trial` = a 评测: an ordinary shift that must earn `target` tokens (docs/core_design_v4.md).
## The old special trial rules below hang on `legacy`, which is never set any more:
## "spring" 春节前夜·服务器繁忙, "hybrid" 嗯，用户想要…… (think only when it pays), "ji" 极字大清扫.
## With `debug` (command line --debug): 1/2 basin smaller/bigger, 3 one more basin,
## 4 material, 5 外包, 6/7 eating slower/faster, 8 tentacle, 9 steady hand, 0 peak hours,
## F1 stats, F2 stress test.
## Art (game/assets/canteen, made by pipeline/prep_canteen.py) is drawn in layers: the wall and
## 梁阿姨 (z -4), her tentacles (Line2D, z -3, rising from behind the counter), the counter and the
## ladles (z -2), 大肥鱼 (z -1), then this node: the table, the lunch boxes, the food and the HUD.

signal finished(earned: float)
signal card_shown
signal to_title

const MEAL_JOURNAL := preload("res://scripts/run/meal_journal.gd")
const FISH_MEAL_VISUAL := preload("res://scripts/ui/fish_meal_visual.gd")
const TOUCH_UI := preload("res://scripts/ui/touch_controls.gd")
const PLAYER_HAND := preload("res://scripts/ui/player_hand.gd")
var _touch_finger := -1
var _touch_at := Vector2.ZERO
var _touch_hand_visible := false
var _touch_start := Vector2.ZERO
var _touch_started_ms := 0
var _touch_tap_target := ""
var _touch_box: Variant
const TOUCH_TAP_SLOP := 18.0
const TOUCH_TAP_MS := 450
var _meal_visual = null
var _journal = null
var _journal_bite_phase := "live"

# --- tuning that is not on the skill tree -----------------------------------------------------
const GRAVITY := 900.0
const FLOOR_Y := 1010.0
const SLOTS := 8                      # most tentacles 梁阿姨 can have
const STALL_ORDER := ["dim", "wok", "main", "fry", "sweet"]   # the five windows, 主食 in the middle
var stall_order: Array = STALL_ORDER.duplicate() # identities occupying the five fixed slots
## One long canteen counter (counter_long.png at COUNTER_RECT): its food pans, by window, as x
## centres; a window's dishes sit in its pans, a closed window has a shutter over them.
const COUNTER_RECT := Rect2(35, 34, 1420, 474)
const PANS := {"dim": [157.0, 258.0, 358.0], "wok": [470.0, 570.0], "main": [662.0, 747.0, 829.0],
	"fry": [919.0, 1019.0], "sweet": [1123.0, 1226.0, 1327.0]}
const PAN_W := 100.0
const PAN_Y := 258.0                  # where a dish sits in its pan
const SHUTTER_Y := Vector2(108.0, 284.0)   # the shutter runs from the glass shelf to the counter top
const WIN_W := 200.0                  # how far apart a window's tentacles spread at most
const COUNTER_Y := 256.0                # where the food comes up out of the pans
const THROW_EVERY := Vector2(1.5, 2.8)
const RAISE_TIME := 0.45              # the ladle goes up before she flings: a tell for the player
const OFF_PEAK := 10.0                # seconds between peaks
const CELL := 58.0                    # one grid cell of the lunch box, px
const BOX_PAD := 8.0
const SPEED := Vector2(2400.0, 1000.0)     # max speed: empty / heavy
const ACCEL := Vector2(16000.0, 4500.0)    # max acceleration: empty / heavy
const SLOSH_SPILL := 0.45
const THINK_COOLDOWN := 1.0
const THINK_MIN_CHARGE := 0.5
const PULL_MAX_RANGE := 220.0
const PULL_HEIGHT := 180.0
const PULL_ACCEL := 360.0
const PULL_MAX_SPEED := 150.0
const MATERIALS := [
	{"name": "铁饭盒", "mult": 1.0, "tint": Color(0.84, 0.86, 0.9)},
	{"name": "铜饭盒", "mult": 1.5, "tint": Color(1.0, 0.66, 0.46)},
	{"name": "银饭盒", "mult": 2.0, "tint": Color(1.08, 1.1, 1.18)},
	{"name": "金饭盒", "mult": 3.0, "tint": Color(1.15, 0.88, 0.4)},
]
const TABLE := Rect2(1300, 842, 605, 150)  # the table top (click area for taking / putting boxes)
const FISH_POS := Vector2(1600, 990)      # her spot (popups are placed from here); she sits in the middle
const MAX_ITEMS := 160
const COACH_UI = preload("res://scripts/ui/run_coach.gd")
const SERVICE_UI = preload("res://scripts/ui/canteen_overlay.gd")
const MEAL_RULES = preload("res://scripts/run/meal_rules.gd")

## Q = a 难题 (hybrid trial), JI = the 「极」 glitch (ji trial: it spoils a whole box), JI_GOLD = the
## golden 「极」 of normal shifts from V3.2 (worth a lot, hops around). The last three reuse food art
## with a tint and a glyph drawn on top.
## Every food (and every 套餐, appended after the foods) is an index into the tables below,
## loaded once from res://data/menu.json (docs/menu_design.md). The first nine keep these
## fixed numbers, the code names them through I.
enum I { BALL, BOWL, LEG, GOLD, VEG, DUMP, Q, JI, JI_GOLD }
static var NAMES: Array = []
static var VALUE: Array = []        # tokens
static var SPACE: Array = []        # grid cells it takes in the box
static var EAT: Array = []          # bites to eat it (a 套餐 is one bite)
static var FILL: Array = []         # stomach it fills (a 套餐: all its ingredients)
static var FALL: Array = []         # how fast it falls (x GRAVITY)
static var PICKY: Array = []        # eaten on its own she spits it out (bok choy)
static var STALL: Array = []        # "" for trial-only items and 套餐
static var LEVEL: Array = []        # stall level that adds it to the menu
static var WEIGHT: Array = []
static var RARE: Array = []
static var SIZE_PX: Array = []      # flying size (long side)
static var FOOD_ART: Array = []
static var FOOD_TINT: Array = []
static var FOOD_GLYPH: Array = []
static var IS_SET: Array = []
static var CATS: Array = []         # kind -> {主: n, 荤: n, ...} (a 套餐: its ingredients)
static var SIG: Array = []          # kind -> its 招牌菜 effect, or null
static var SND: Array = []          # landing sound: "catch" (rice, buns), "catch_crisp", "catch_slosh", ...
static var KIND := {}               # id -> index
static var STALLS := {}             # id -> {name, speed, max, base}
static var RECIPES: Array = []      # {id, name, kind, needs: [index...], result: index, hint}
static var TIER: Array = []         # 套餐 tier 1 小炒 / 2 二级 / 3 三级 / 4 神级 (0 for a plain dish)
static var PARTS: Array = []        # ingredients a 套餐 opens up to (a plain dish: 1)
static var USEFUL := {}             # kinds that go into some 套餐 (收敛思维 lets the rest through)
const HOPPY := [I.JI, I.JI_GOLD]                        # 「极」 hops about in the air
const TIER_MULT := [1.0, 1.2, 1.5, 2.0, 3.0]            # value of a 套餐 = its ingredients x this
const TIER_NAME := ["", "小炒", "二级套餐", "三级大餐", "神级"]

## An item in a box (or in the air) is one int: the kind in the low byte, then its grade
## (0 普通 / 1 优质 / 2 金牌), whether a random effect touched it (高温), whether it is a ghost that
## takes no cell (幻觉, 投机解码), how many greens were injected into it (提示词注入), and for a
## 套餐 the value of its ingredients x 100 (套餐等级 multiplies only the outermost 套餐).
static func K(it: int) -> int:
	return it & 0xFF


static func grade(it: int) -> int:
	return (it >> 8) & 3


static func is_hot(it: int) -> bool:
	return (it >> 10) & 1 == 1


static func is_ghost(it: int) -> bool:
	return (it >> 11) & 1 == 1


static func injected(it: int) -> int:
	return (it >> 12) & 3


static func raw_of(it: int) -> float:
	return float(it >> 16) / 100.0


static func make(k: int, g := 0, hot := false, ghost := false, inj := 0, raw := 0.0) -> int:
	return k | (g << 8) | (int(hot) << 10) | (int(ghost) << 11) | (mini(inj, 3) << 12) | (int(round(raw * 100.0)) << 16)


static func with_grade(it: int, g: int) -> int:
	return (it & ~(3 << 8)) | (clampi(g, 0, 2) << 8)


static func with_hot(it: int) -> int:
	return it | (1 << 10)


## Index of the first item of kind k in items, or -1.
static func find_kind(items: Array, k: int) -> int:
	for i in items.size():
		if K(items[i]) == k:
			return i
	return -1


static func load_menu() -> void:
	if not NAMES.is_empty():
		return
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu.json"))
	for f in m.foods:
		KIND[f.id] = NAMES.size()
		NAMES.append(f.name)
		VALUE.append(float(f.value))
		SPACE.append(int(f.cells))
		EAT.append(int(f.cells))
		FILL.append(int(f.cells))
		FALL.append(float(f.get("fall", 1.0)))
		PICKY.append(bool(f.get("picky", false)))
		STALL.append(str(f.get("stall", "")))
		LEVEL.append(int(f.get("level", 0)))
		WEIGHT.append(float(f.get("w", 0.0)))
		RARE.append(bool(f.get("rare", false)))
		SIZE_PX.append(58.0 if int(f.cells) > 1 else 52.0)
		# a dish's own sprite (food_<id>.png) wins over the placeholder art + tint + glyph
		if ResourceLoader.exists("res://assets/canteen/food_%s.png" % f.id) and f.art != f.id and f.has("glyph"):
			FOOD_ART.append(f.id)
			FOOD_TINT.append(Color.WHITE)
			FOOD_GLYPH.append("")
		else:
			FOOD_ART.append(f.art)
			var t: Array = f.get("tint", [1, 1, 1])
			FOOD_TINT.append(Color(t[0], t[1], t[2]))
			FOOD_GLYPH.append(str(f.get("glyph", "")))
		IS_SET.append(false)
		var cats := {}
		var cl: Array = f.get("cat", [])
		for cn in cl:
			cats[cn] = float(cats.get(cn, 0.0)) + 1.0 / cl.size()
		CATS.append(cats)
		SIG.append(f.get("sig", null))
		SND.append("catch_" + str(f.snd) if f.has("snd") else "catch")
		TIER.append(0)
		PARTS.append(1)
	STALLS = m.stalls
	# 套餐: their needs may name other 套餐, so the list is read in order (define a set first)
	for r in m.recipes:
		var needs: Array = []
		var value := 0.0
		var fill := 0
		var parts := 0
		for id in r.needs:
			var k: int = KIND[id]
			needs.append(k)
			value += raw_value_static(k)   # bok choy counts once it is in a 套餐
			fill += FILL[k]
			parts += PARTS[k]
			USEFUL[k] = true
		var tier := 4 if r.kind == "hidden" else (1 if parts <= 2 else (2 if parts == 3 else (3 if parts <= 5 else 4)))
		if r.kind == "special":
			tier = int(r.get("tier", 2))
			fill = 3
		TIER.append(tier)
		PARTS.append(maxi(parts, 1))
		KIND[r.id] = NAMES.size()
		NAMES.append(r.name)
		VALUE.append(value * TIER_MULT[tier])
		SPACE.append(int(r.cells))
		EAT.append(1)
		FILL.append(fill)
		FALL.append(1.0)
		PICKY.append(false)
		STALL.append("")
		LEVEL.append(0)
		WEIGHT.append(0.0)
		RARE.append(false)
		SIZE_PX.append(64.0)
		var art := "set_" + str(r.id)
		var has_art := ResourceLoader.exists("res://assets/canteen/food_%s.png" % art)
		FOOD_ART.append(art if has_art else "bowl")   # placeholder until gen_assets.sh menu has run
		FOOD_TINT.append(Color.WHITE if has_art else (Color(1.2, 1.0, 0.75) if r.kind != "hidden" else Color(1.25, 0.95, 1.2)))
		FOOD_GLYPH.append("" if has_art else str(r.get("glyph", "套")))
		IS_SET.append(true)
		var cats := {}
		for need in needs:
			for cn in CATS[need]:
				cats[cn] = float(cats.get(cn, 0.0)) + float(CATS[need][cn])
		CATS.append(cats)
		SIG.append(null)
		SND.append("catch")
		if r.kind != "special":
			RECIPES.append({"id": r.id, "name": r.name, "kind": r.kind, "needs": needs, "result": KIND[r.id], "hint": r.get("hint", "")})


## The ingredient value of a plain dish or a 套餐 (before any grade or skill): what it adds to a
## 套餐 it goes into (bok choy counts 1; a 套餐 inside a 套餐 adds its ingredients, not its tier).
static func raw_value_static(k: int) -> float:
	if IS_SET[k]:
		return VALUE[k] / TIER_MULT[TIER[k]]
	return maxf(VALUE[k], 1.0)


## trial endings: [passed, failed (also walking out), time up without passing]
const TRIAL_ENDS := {
	"spring": ["新年快乐！", "宕机了……", "新年快乐！"],
	"hybrid": ["用户满意！", "用户怒了……", "题没做完……"],
	"ji": ["清扫完毕！", "满屏都是极……", "时间到，没扫完……"],
}
# where the art goes (see the layer note at the top)
const ART := "res://assets/canteen/"
const COUNTER_AT := Vector2(35, 180)      # top-left of the counter: plate s under _slot_x(s), trays at COUNTER_Y
const AUNTIE_AT := Vector2(745, 285)      # apron behind the counter; face clears its back edge
const TABLE_AT := Vector2(1290, 826)      # top-left of the table art, drawn TABLE_SCALE times bigger
const TABLE_SCALE := 1.3
const LADLE_GRIP := Vector2(104, 7)       # the handle end in ladle.png, held by the tentacle tip
const LADLE_AXIS := 2.46                  # angle from the grip to the bowl in ladle.png
const LADLE_LEN := 95.0

var autotest := false
var debug := false
var trial := ""                       # "" = a normal shift, else the 评测 being taken (a token target)
var legacy := ""                      # the old special trial rules (spring / hybrid / ji): never set now
var target := 0.0                     # 评测: tokens this shift must reach
var balance_max := 2.0
var stream := 0.0
var _bites := 0                       # bites this shift (流式输出)
var _cat := {"主": 0.0, "荤": 0.0, "素": 0.0, "饮": 0.0, "甜": 0.0}   # what she ate (套餐 by ingredients)
var _sigs := {}                       # active 招牌菜: kind -> its effect
var _sig_count := {}                  # kind -> how many eaten this shift
var _sig_balance := 0.0
var _sig_bonus := 0.0                 # tokens from 招牌菜 this shift (for the result card)
var _base := 0.0                      # tokens before the end-of-shift multipliers
var auto_push := false
var auto_return := false
var _push_cd := 0.0
# --- the scoring model (docs/tree_model.md): 口 -> 盒 -> 顿 ---------------------------------------
## 上下文窗口 by version: the caps on what piles up within one shift (only a release raises them)
const STREAM_CAP := [2.0, 2.5, 3.5, 4.5, 6.5, 6.5]
const COMBO_CAP := [3, 5, 7, 9, 12, 12]
const SIG_CAP := [0.3, 0.5, 0.7, 0.85, 1.0, 1.0]
const WINDOW_NAME := ["32K", "64K", "128K", "256K", "1M", "1M"]
const MEAL_TIME := [60.0, 70.0, 80.0, 90.0, 105.0, 120.0]   # the canteen closes later every version
var stream_from := 40                 # 首 Token 延迟: bites before 越吃越香 starts
var mtp := 0.0                        # MTP: + tokens per bite
var g_good := 0.0                     # SFT: chance a dish is 优质 (LoRA adds per struck dish)
var g_gold := 0.0                     # DPO: chance an 优质 dish is 金牌 instead
var gold_x := 4.0                     # FP32: 金牌 x5
var temp := 0.0                       # Temperature: chance a dish turns into a better one in the box
var hot_x := 1.5                      # 高温: what a randomly touched dish is worth
var halluc := 0.0
var regen := 0.0
var emerge := false
var overfit := false
var batch := 0.0                      # Batch Size: chance per scoop of one more dish
var box_bonus := 0.0                  # 光学压缩 (+% pool of a box)
var fill_bonus := 0.0                 # 上下文填满
var tier_up := [0.0, 0.0, 0.0, 0.0, 0.0]   # 套餐等级 bonus per tier (Prompt 模板 / Few-shot / Agent 工作流 / AGI 菜谱)
var inject := false                   # 提示词注入
var compress := 0                     # 上下文压缩
var fuse3 := false                    # 模型融合
var hodge := false                    # MoE 大杂烩
var cot := 0.0                        # 思维链: + per chain merge in a box
var rag := 0.0                        # RAG: + per 优质 / 金牌 ingredient
var spec := 0.0                       # 投机解码
var crave := 0.0                      # 服务器繁忙: 馋 1 + crave x (1 - e^(-t / crave_tau))
var crave_tau := 6.0
var combo := 0.0                      # 多轮对话: + per box in a row with two 二级+ 套餐
var memory := 0                       # 上下文记忆
var warm := false                     # KV Cache 保温箱
var warm_x := 2.0                     # Final Answer
var best_of_n := false
var grok := false                     # 顿悟
var grok_need := 30
var veg_x := 6.0                      # what a green is worth once she has grokked it (回甘)
var drift := false                    # 向量漂移
var veg_std := 0.0                    # 食堂标配: chance per scoop of a spoon of greens
var nutri := false
var clip := false
var async_feed := false
var sleep_eat := false
var fc := false
var diverge := 0.0
var converge := false
var critic := 0.0                     # 美食评鉴: + per kind of 套餐 from the 5th
var struck := {}                      # 今日菜单: kinds she never serves this shift
var _g := 1.0                         # 全局: material x version
var _crave_t := 0.0                   # seconds she has had nothing to eat (feeds 馋)
var _combo_n := 0                     # boxes in a row with two 二级+ 套餐
var _combo_safe := false              # 上下文记忆 2: the first break each shift is free
var _warm = null                      # the box in the 保温箱 (Dictionary) or null
var _grok_n := 0
var _grokked := false
var _kinds_eaten := {}                # 套餐 kinds eaten (美食评鉴)
var _box_vals: Array = []             # tokens of every box eaten (梯度裁剪)
var _fc_kind := -1                    # retained for old debug fixtures; orders are per helper
var _helper_configs := {}              # effective roles frozen when the shift starts
var _helper_recipe_cache := {}
var crew_relay := 0.0
var _helper_relay := {}                # one stored hand-off per useful role
var _helper_feedback_at := -10.0
var _score := {}                      # result card lines: name -> tokens / multiplier
var _care_t := 0.0                    # 阿姨的关心: her last 「多吃点菜！」
const WARM_AT := Vector2(1190, 905)   # the 保温箱, left of the table
const WARM_RECT := Rect2(1105, 830, 170, 150)

# this shift's numbers, read from the skill tree in _ready (debug keys may change them)
var box_n := 2                        # columns: the lunch box is 2 rows x box_n columns (2x2 -> 2x3 -> 2x4)
var basins_total := 2
var mat_level := 0
var hired: Array = []                 # 外包 helpers on the payroll (ids in CREW order)
var helper_speed := 1.0
var eat_rate := 2.0
var stomach := 70
var meal_time := 60.0
var tentacles := 3
var shake := 1.0
var scoop := 0
var peaks := false
var peak_time := 8.0
var peak_good := 3.0
var crit_chance := 0.05
var magnet := 0.0
var floor_back := 0.0
var can_think := false
var think_time := 2.5
var think_slow := 0.35
var think_regen := 0.4
var dsa := false                      # DSA (V3.2): the magnet ignores greens and 「极」, greens bounce off
var crit_mult := 2.0
var app_rate := 0.0                   # takeout boxes per minute (帮我做个 App)
var dream := 0.0
var throw_rate := 1.0
var think_eat := false
var ji_rate := 0.0
var token_mult := 1.0

# flying food: parallel packed arrays
var _fp := PackedVector2Array()
var _fv := PackedVector2Array()
var _fk := PackedInt32Array()   # item codes (see make())
var _fr := PackedFloat32Array()      # spin angle
var _fg := PackedFloat32Array()      # gravity of each piece (its kind's fall speed, jittered)
var stall_lv := {}                    # stall id -> level (0 = closed)
var _flash: Array = []                # 合成 flashes: {pos, t, name}
var _food_tex: Array = []             # one texture per kind
var _rim_tex: Array = []              # per kind: a glow hugging its outline (prep_canteen.food_rims), padded RIM_PAD
var _sheen_tex: Array = []            # per kind: SHEEN_FRAMES frames of a light band crossing it
const RIM_PAD := 14.0
const SHEEN_FRAMES := 10
var _box_tex := {}                    # n -> lunch box art
var _box_grid := {}                   # n -> Rect2: the compartment grid, as fractions of the art
var _auntie := {}                     # mood -> 梁阿姨 art
var _bg: Texture2D
var _counter: Texture2D
var _counter_long: Texture2D          # the continuous counter (round 3b), or null: the old one
var _shutter: Texture2D
var _table: Texture2D
var _back: Node2D                     # draws the wall and 梁阿姨
var _front: Node2D                    # draws the counter, in front of her and her tentacles
var _arm_lines: Array = []            # Line2D per arm
var _arm_ladles: Array = []           # Sprite2D per arm
var _shaky_t := 0.0                   # she just flung with shaky hands

var _arms: Array = []                 # {slot, t, raise}
var _service_ui: Control
var _peak_on := false
var _peak_t := 0.0
var _hand = null                      # Dictionary or null: {items: Array, pos, vel, slosh}
var _aim := Vector2(800, 800)
var _empty := 0                       # empty boxes stacked on the table
var _queue: Array = []                # full boxes waiting on the table
var _eating = null
var _flying: Array = []
var _eat_acc := 0.0
var _chew_pause := 0.0
var _token_pop := 0.0
var _t := 0.0
var _ended := false
var _end_reason := ""
var _show_stats := false
var _bark := ""
var _bark_t := 0.0
var _spill_acc := 0.0
var _fish: FishRig
var _texts: Array = []
var _think := 0.0                     # gauge, seconds of slow motion left
var _thinking := false
# trial: 春节前夜·服务器繁忙
var _rate := 1.0                      # legacy throw-rate multiplier; review failures do not change difficulty
var _pile := PackedVector2Array()     # food left on the floor = server load
var _pile_k := PackedByteArray()
var pile_max := 50
var clean_rate := 1.5                 # floor items swept away per second
var _clean_acc := 0.0
var _busy_t := 0.0                    # 服务器繁忙: the table refuses basins for a moment
var fails := 0
var passed := false
# trial: 嗯，用户想要…… (quick rounds and hard rounds take turns)
const ROUND := [12.0, 13.0]           # seconds of a quick round, then of a hard round
var _hard := false
var _round_t := 0.0
var _volley_t := 0.0
var volley_every := 3.2               # a 难题 volley every so often in a hard round
var volley_n := 3                     # 难题 per volley, flung apart
var q_speed := 1.0
var sat := 100.0                      # 用户满意度: 0 = 用户怒了
var think_penalty := 22.0             # 满意度 lost per second of thinking in a quick round
var q_penalty := 4.0                  # 满意度 lost per 难题 on the floor
var solved := 0
var need_solved := 14
# trial: 极字大清扫
var ji_chance := 0.16                 # share of thrown food that is 「极」
var ji_hop := 2.4                     # hops per second
var ji_hits := 0                      # boxes spoiled by a 「极」
var ji_max := 3
var ji_shaken := 0
var _app_t := 0.0
const PAD_SPEED := 1500.0             # keyboard / stick aim speed, px/s
var _was_thinking := false
var _think_cooldown := 0.0
var _think_input_held := false
var _resume_input_guard := 0.0
var _mouse_steering := true
var _hint_input_device := "keyboard"
var _think_transitions := 0           # state transitions, also useful for bounded audio QA
var _pause: PauseMenu
var _focus_pause_pending := false
var _touch_controls: Control
var _coach = null
var _learning_time := 0.0             # tutorial time never consumes the first meal's clock
var _recipes_made := 0
var _full_boxes := 0                 # player boxes actually submitted full, counted once
var _previous_mono_kind := -1
var _cache_ready := false
var _rule_income := 0.0              # actual credited build bonuses, before meal multipliers
var mono_bonus := 0.0
var cache_bonus := 0.0
var rotation_bonus := 0.0

# stats of this shift
var earned := 0.0
var eaten := 0
var caught := 0
var wasted := 0
var wasted_value := 0.0
var spilled := 0
var fish_wait := 0.0
var _wait := 0.0                      # how long she has been waiting for food (her mood escalates)
var _dig_in := 0.0                    # a new box: she perks up before she starts eating
var _crew: Array = []                 # the helpers: {id, spr, box, state, x, hop}
var _crew_layer: Node2D               # draws the helpers' boxes in front of them
## The table has three zones: empty boxes stacked on the left, her place in the middle (the box
## she is eating from), full boxes stacked on the right.
const STACK_AT := Vector2(1385, 900)  # the empty-box stack (bottom box)
const EAT_AT := Vector2(1600, 918)     # the box she is eating from
const FULL_AT := Vector2(1815, 900)   # the full-box stack (bottom box)
const PLATE_Y := 340.0                # the cream name plates on the counter front (cooking bars)
const BAND := Vector2(520.0, 880.0)   # the box moves in this band of heights (the floor is the helpers')
const FALL_JITTER := 0.12             # every piece falls up to 12% faster or slower than its kind
const HELPER_SPEED := 300.0           # px/s at helper_speed 1
const CREW_H := 150.0                 # helper height on screen
const HELPER_BOX_Y := 158.0           # their box rides this far above their feet
## 外包 helpers: original chibi girls with a nod to an AI's colours (nicknames only, no logos,
## nobody is "stronger": each has her own trick). stat = the skill-tree stat that hires her.
const CREW := {
	"wen": {"name": "问问", "stat": "helper", "trick": "wide"},     # a wider catch
	"pu": {"name": "谱谱", "stat": "crew_pu", "trick": "magnet"},  # pulls food in
	"g": {"name": "小G", "stat": "crew_g", "trick": "jump"},       # hops up for food (catches higher)
	"ke": {"name": "克劳", "stat": "crew_ke", "trick": "floor"},   # picks food up off the floor
	"zi": {"name": "双子", "stat": "crew_zi", "trick": "fast"},    # runs faster
	"ge": {"name": "格格", "stat": "crew_ge", "trick": "swat"},    # protects useful food by swatting only 「极」
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	load_menu()
	Fx.world = self
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # the art is drawn scaled down
	_load_art()
	_fish = FishRig.new()
	_fish.seated = true                   # from the waist up, behind the table, with her iron basin
	_fish.position = Vector2(FISH_POS.x, TABLE.position.y + 14)   # in the middle, her waist just below the table top
	_fish.height = 430.0
	_fish.beat.connect(func(): Audio.sfx("clang", -7.0))
	_fish.z_index = -1
	add_child(_fish)
	_meal_visual = FISH_MEAL_VISUAL.new()
	_meal_visual.run = self
	_meal_visual.fish = _fish
	add_child(_meal_visual)
	_read_stats()
	if trial != "":
		_setup_trial()
	_journal = MEAL_JOURNAL.new()
	_journal.begin(self)
	_think = think_time
	_setup_arms()
	_peak_t = OFF_PEAK
	_empty = basins_total
	_hand = null
	_fish.play("basin")
	_crew_layer = Node2D.new()
	_crew_layer.z_index = 1
	_crew_layer.draw.connect(_draw_crew_layer)
	add_child(_crew_layer)
	var i := 0
	for id in hired:
		var spr := Sprite2D.new()
		spr.texture = load("res://assets/crew/%s.png" % id)
		spr.centered = false
		var k := CREW_H / spr.texture.get_height()
		spr.scale = Vector2(k, k)
		spr.offset = Vector2(-spr.texture.get_width() * 0.5, -spr.texture.get_height())
		add_child(spr)
		var x := STACK_AT.x - 140.0 - i * 90.0
		spr.position = Vector2(x, FLOOR_Y + 40)
		var config: Dictionary = _helper_configs.get(id, {"role": "sweep", "recipe": ""})
		_crew.append({"id": id, "role": config.role, "recipe": int(KIND.get(str(config.recipe), -1)), "spr": spr, "box": null, "state": "fetch", "x": x, "hop": 0.0,
			"wait": 0.0, "rest": 1180.0 - i * 150.0, "awake": spr.texture, "sleep": load("res://assets/crew/%s_sleep.png" % id),
			"run_tex": _maybe("res://assets/crew/%s_run.png" % id), "cheer_tex": _maybe("res://assets/crew/%s_cheer.png" % id), "seen": 0, "cheer": 0.0})
		i += 1
	_say("开饭了！")
	Audio.vo("auntie_start", 1)
	# the first shift with a new in-shift feature: say so once, on the banner
	for f in [["warm", warm, "新：保温箱", "端着饭盒碰一下左边的保温箱，留到最后吃", "box"],
			["think", can_think, "新：深度思考", tr("按住 %s，时间变慢") % Settings.binding_label("think").get_slice(" / ", 0), "clock"],
			["grok", grok, "新：顿悟", "让她把青菜硬咽下去，咽够就开窍", "leaf"]]:
		if f[1] and not Game.seen_buttons.has("intro_" + f[0]):
			Game.seen_buttons["intro_" + f[0]] = true
			_banner(f[2], tr(f[3]), f[4])
	Audio.music("bgm_trial" if trial != "" else "bgm_run")
	Audio.ambience("amb_canteen", -20.0)
	Audio.sfx("shift_start", -4.0)
	_setup_coach()
	_service_ui = SERVICE_UI.new()
	_service_ui.run = self
	add_child(_service_ui)
	_maybe_stall_layout_intro()
	if TOUCH_UI.available():
		_enable_touch_controls()


func _enable_touch_controls() -> void:
	if is_instance_valid(_touch_controls) or autotest:
		return
	_touch_controls = TOUCH_UI.new()
	_touch_controls.run = self
	_touch_controls.pause_requested.connect(pause)
	add_child(_touch_controls)
	Settings.changed.connect(_cancel_touch)


func _touch_target(at: Vector2) -> String:
	if _hand == null:
		return "stack" if _empty > 0 and Rect2(STACK_AT - Vector2(80, 70), Vector2(160, 125)).has_point(at) else ""
	if warm and WARM_RECT.has_point(at): return "warmer"
	return "table" if TABLE.has_point(at) else ""


func _touch_activate(target: String, at: Vector2) -> void:
	if _ended or get_tree().paused or _hand != _touch_box or _touch_target(at) != target:
		return
	_touch_hand_visible = true
	_mouse_steering = true
	# A deliberate tap carries the box to the selected surface, then reuses the
	# same empty-box, serving, busy-table and warmer rules as desktop input.
	_aim = WARM_AT if target == "warmer" else Vector2(at.x, _hand_bottom())
	if _hand != null: _hand.pos = _aim
	_try_deliver()


func _cancel_touch() -> void:
	_touch_finger = -1
	_touch_tap_target = ""
	_touch_box = null
	if is_instance_valid(_touch_controls):
		_touch_controls.cancel_touch()


func _hand_bottom() -> float:
	# A stable bottom dock replaces the old tutorial that chased the held tray.
	if is_instance_valid(_touch_controls) or (is_instance_valid(_coach) and _coach.visible):
		return TOUCH_UI.PLAY_BOTTOM
	return BAND.y


func _exit_tree() -> void:
	_cancel_touch()
	Settings.release_gameplay_inputs()
	Audio.slowmo(false)


func _maybe_stall_layout_intro() -> void:
	if autotest or trial != "" or _learning() or not Game.stall_layout_intro_due():
		return
	_banner("档口也能换位置", tr("按 Esc → 档口指南，把常接的菜摆在一起"), "box")
	Game.seen_buttons["intro_stall_layout"] = true
	Game.save_game()


func _setup_coach() -> void:
	if autotest or trial != "" or Game.seen_buttons.has("intro_canteen_complete"):
		return
	# Existing saves keep their familiar flow. An interrupted lesson is offered again.
	if Game.runs > 0 and not Game.seen_buttons.has("intro_canteen_started"):
		return
	_coach = COACH_UI.new()
	_coach.completed.connect(func(_skipped: bool):
		Game.seen_buttons["intro_canteen_complete"] = true
		Game.save_game()
		Audio.sfx("ticket", -6.0))
	add_child(_coach)
	_aim = Vector2(STACK_AT.x, BAND.y)
	Game.seen_buttons["intro_canteen_started"] = true
	Game.save_game()


func _learning() -> bool:
	return is_instance_valid(_coach) and _coach.active


func _meal_elapsed() -> float:
	return maxf(_t - _learning_time, 0.0)


func _read_stats() -> void:
	box_n = clampi(int(Game.stat("box_n")), 2, 4)   # columns
	basins_total = int(Game.stat("basins"))
	mat_level = clampi(int(Game.stat("material")), 0, MATERIALS.size() - 1)
	hired = Game.active_helpers().duplicate()
	_helper_configs.clear()
	for id in hired:
		_helper_configs[id] = Game.helper_config(id).duplicate(true)
	crew_relay = Game.stat("crew_relay")
	helper_speed = Game.stat("helper_speed")
	eat_rate = Game.stat("eat_rate")
	meal_time = MEAL_TIME[mini(Game.version, MEAL_TIME.size() - 1)]
	stream_from = int(40 - 10 * Game.stat("ttft"))
	mtp = Game.stat("mtp")
	g_good = Game.stat("sft")
	g_gold = Game.stat("dpo")
	gold_x = 5.0 if Game.stat("fp32") > 0.0 else 4.0
	temp = Game.stat("temp") if Game.automation_enabled("temp") else 0.0
	hot_x = 1.5 + Game.stat("hot")
	halluc = Game.stat("halluc")
	regen = Game.stat("regen") if Game.automation_enabled("regen") else 0.0
	emerge = Game.stat("emerge") > 0.0
	overfit = Game.automation_enabled("overfit")
	batch = Game.stat("batch")
	box_bonus = Game.stat("box_bonus")
	fill_bonus = Game.stat("fill_bonus")
	tier_up = [0.0, Game.stat("tier1"), Game.stat("tier2"), Game.stat("tier3"), Game.stat("tier4")]
	inject = Game.stat("inject") > 0.0
	compress = int(Game.stat("compress"))
	fuse3 = Game.automation_enabled("fuse3")
	hodge = Game.stat("hodge") > 0.0
	cot = Game.stat("cot")
	rag = Game.stat("rag")
	spec = Game.stat("spec")
	crave = Game.stat("crave") + 0.5 if Game.stat("crave") > 0.0 else 0.0   # x2 at level 1
	crave_tau = Game.stat("crave_tau")
	combo = Game.stat("combo") + 0.05 if Game.stat("combo") > 0.0 else 0.0   # +0.1 a box at level 1
	memory = int(Game.stat("memory"))
	warm = Game.stat("warm") > 0.0
	warm_x = 2.0 + Game.stat("final")
	best_of_n = Game.automation_enabled("bon")
	grok = Game.stat("grok") > 0.0
	grok_need = int(Game.stat("grok_need"))
	veg_x = 6.0 + Game.stat("aftertaste")
	drift = Game.stat("drift") > 0.0
	veg_std = Game.stat("veg_std")
	nutri = Game.stat("nutri") > 0.0
	clip = Game.stat("clip") > 0.0
	async_feed = Game.stat("async") > 0.0
	sleep_eat = Game.stat("sleep") > 0.0
	fc = Game.stat("fc") > 0.0
	diverge = Game.stat("diverge")
	converge = Game.stat("converge") > 0.0
	critic = Game.stat("critic")
	mono_bonus = Game.stat("mono_bonus")
	cache_bonus = Game.stat("cache_bonus")
	rotation_bonus = Game.stat("rotation_bonus")
	_combo_safe = memory >= 2
	var cut := int(Game.stat("menu_cut"))
	for id in Game.active_struck():
		if struck.size() < cut and KIND.has(id):
			struck[KIND[id]] = true
	g_good += Game.stat("lora") * struck.size()
	var windows := 0
	for id in STALLS:
		if int(Game.stat("stall_" + id)) > 0:
			windows += 1
	tentacles = clampi(windows + int(Game.stat("tentacles")), 1, SLOTS)   # one per open window, plus 并发请求
	shake = Game.stat("shake")
	scoop = int(Game.stat("scoop"))
	peaks = Game.stat("peaks") > 0.0
	peak_time = Game.stat("peak_time")
	peak_good = Game.stat("peak_good")
	crit_chance = Game.stat("crit_chance")
	magnet = Game.stat("magnet")
	floor_back = 0.0
	can_think = Game.version >= 1
	think_time = Game.stat("think_time")
	think_slow = Game.stat("think_slow")
	think_regen = Game.stat("think_regen")
	stall_order = Game.active_stall_order()
	dsa = Game.version >= 3
	crit_mult = Game.stat("crit_mult")
	app_rate = 0.0
	dream = 0.0
	throw_rate = Game.stat("throw_rate")
	think_eat = false
	ji_rate = 0.0
	token_mult = 1.0
	_g = MATERIALS[mat_level].mult   # 全局 (a release raises the caps and the meal time instead)
	balance_max = Game.stat("balance_max")
	stream = Game.stat("stream")
	auto_push = Game.automation_enabled("auto_push")
	auto_return = Game.automation_enabled("auto_return")
	for id in Game.active_signatures():
		_sigs[KIND[id]] = SIG[KIND[id]]
	for id in STALLS:
		stall_lv[id] = clampi(int(Game.stat("stall_" + id)), 0, int(STALLS[id].max))


## Release reviews use the same serving rules and owned skills as an ordinary meal.
## The target comes from Game; fails is history only and does not lower difficulty.
func _setup_trial() -> void:
	fails = int(Game.trial_fails.get(trial, 0))
	target = Game.trial_target(trial)


# --- art --------------------------------------------------------------------------------------

func _maybe(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _load_art() -> void:
	for k in FOOD_ART:
		_food_tex.append(load(ART + "food_%s.png" % k))
		_rim_tex.append(_maybe(ART + "rim/food_%s.png" % k))
		_sheen_tex.append(_maybe(ART + "sheen/food_%s.png" % k))
	var grid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/canteen_art.json")).box_grid
	for n in [2, 3, 4]:   # 2 rows x n columns
		var key := "box_2" if n == 2 else "box_2x%d" % n
		_box_tex[n] = load(ART + key + ".png")
		var g: Array = grid[key]
		_box_grid[n] = Rect2(g[0], g[1], g[2] - g[0], g[3] - g[1])
	for m in ["normal", "shaky", "busy", "panic", "happy"]:
		_auntie[m] = load(ART + "auntie_%s.png" % m)
	_bg = load(ART + "bg_wall.png")
	_counter = load(ART + "counter.png")
	_counter_long = _maybe(ART + "counter_open.png")
	_load_hud()
	_shutter = _maybe(ART + "counter_shutter.png")
	_table = load(ART + "table.png")
	_back = Node2D.new()
	_back.z_index = -4
	_back.draw.connect(_draw_back)
	add_child(_back)
	_front = Node2D.new()
	_front.z_index = -2
	_front.draw.connect(_draw_front)
	add_child(_front)


# --- helpers ----------------------------------------------------------------------------------

func _setup_arms() -> void:
	_arms.clear()
	# Allocate by stable identity order, independently of where the stalls were moved.
	# Swapping windows must not increase any stall's supply or reset its preparation.
	var open: Array = []
	for id in STALL_ORDER:
		if stall_lv.get(id, 0) > 0:
			open.append(id)
	var per := {}
	for i in tentacles:
		var st: String = open[i % open.size()] if not open.is_empty() else "main"
		per[st] = int(per.get(st, 0)) + 1
	var seen := {}
	for i in tentacles:
		var st: String = open[i % open.size()] if not open.is_empty() else "main"
		var n: int = per[st]
		var k: int = seen.get(st, 0)
		seen[st] = k + 1
		var x := _win_x(stall_slot(st)) + (k - (n - 1) * 0.5) * minf(70.0, _win_span(st) / maxf(n - 1, 1))
		var t0 := randf_range(0.3, 2.0)
		_arms.append({"x": x, "t": t0, "t0": t0, "raise": 0.0, "stall": st, "ladle": k + 1})
	for a in _arms:
		a.dish = _next_dish(a)
	for x in _arm_lines + _arm_ladles:
		x.queue_free()
	_arm_lines.clear()
	_arm_ladles.clear()
	var thin := Curve.new()
	thin.add_point(Vector2(0, 1))
	thin.add_point(Vector2(1, 0.5))
	for a in _arms:
		var ladle := Sprite2D.new()
		ladle.texture = load(ART + "ladle.png")
		ladle.centered = false
		ladle.offset = -LADLE_GRIP
		ladle.z_index = -3   # behind the stalls: the ladle dips in behind the glass
		add_child(ladle)
		_arm_ladles.append(ladle)
		var line := Line2D.new()
		line.texture = load(ART + "tentacle.png")
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.width = 38.0
		line.width_curve = thin
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.z_index = -3
		add_child(line)
		_arm_lines.append(line)
	_update_arm_art()


## Where a tentacle is: [root on her body, tip (holding the ladle's handle), ladle direction].
## `lift` 0..1 is the wind-up before a fling: the tip rises and the ladle scoops up and outward.
func _arm_pose(a: Dictionary, lift: float) -> Array:
	var tip := Vector2(a.x, COUNTER_Y - 95 - 60.0 * lift)
	var side := 1.0 if tip.x >= AUNTIE_AT.x else -1.0
	var root := AUNTIE_AT + Vector2(side * 115.0, -25.0 + sin(_t * 3.0) * 4.0)   # behind the counter
	var dir := Vector2(side * 0.5, 1.0).lerp(Vector2(side * 0.9, -0.8), lift)
	return [root, tip, dir.normalized()]


func _arm_lift(a: Dictionary) -> float:
	return 1.0 - a.raise / RAISE_TIME if a.raise > 0.0 else 0.0


func _update_arm_art() -> void:
	for i in _arms.size():
		var pose := _arm_pose(_arms[i], _arm_lift(_arms[i]))
		var root: Vector2 = pose[0]
		var tip: Vector2 = pose[1]
		var mid := root.lerp(tip, 0.5)
		mid.y = minf(root.y, tip.y) - 70.0 - 0.1 * absf(tip.x - root.x)   # arch up from behind the counter
		var pts := PackedVector2Array()
		for j in 17:
			var k := j / 16.0
			pts.append(root.lerp(mid, k).lerp(mid.lerp(tip, k), k))
		_arm_lines[i].points = pts
		_arm_ladles[i].position = tip
		_arm_ladles[i].rotation = (pose[2] as Vector2).angle() - LADLE_AXIS


## The middle of physical counter slot i; the counter artwork never moves.
func _win_x(i: int) -> float:
	var p: Array = PANS[STALL_ORDER[i]]
	return (p[0] + p[p.size() - 1]) * 0.5


## How far a window's tentacles may spread.
func _win_span(st: String) -> float:
	var p := stall_pans(st)
	return float(p[p.size() - 1]) - float(p[0])


func stall_slot(id: String) -> int:
	return stall_order.find(id)


func stall_pans(id: String) -> Array:
	var slot := stall_slot(id)
	return PANS[STALL_ORDER[slot]].duplicate() if slot >= 0 else []


## An in-place pause edit. Existing arms retain their timers, dish, lift and allocation.
func apply_stall_order(order: Array) -> bool:
	if not is_inside_tree() or not is_node_ready() or not get_tree().paused or _ended or not Game._valid_stall_order(order):
		return false
	if not Game.set_stall_order(order):
		return false
	stall_order = Game.active_stall_order()
	if _journal != null:
		_journal.event("stall_layout", _meal_elapsed(), {"order": stall_order.duplicate()})
	var per := {}
	for a in _arms:
		per[a.stall] = int(per.get(a.stall, 0)) + 1
	var seen := {}
	for a in _arms:
		var n: int = per[a.stall]
		var k: int = seen.get(a.stall, 0)
		seen[a.stall] = k + 1
		a.x = _win_x(stall_slot(a.stall)) + (k - (n - 1) * 0.5) * minf(70.0, _win_span(a.stall) / maxf(n - 1, 1))
	_update_arm_art()
	if is_instance_valid(_front):
		_front.queue_redraw()
	if is_instance_valid(_service_ui):
		_service_ui.queue_redraw()
	queue_redraw()
	return true


func _new_basin(at: Vector2) -> Dictionary:
	return {"items": [], "pos": at, "vel": Vector2.ZERO, "slosh": 0.0}


func _space(b: Dictionary) -> int:
	var n := 0
	for it in b.items:
		n += _cells(it)
	return n


## Cells an item takes: a ghost none, a 套餐 one less with 上下文压缩.
func _cells(it: int) -> int:
	if is_ghost(it):
		return 0
	var k := K(it)
	return maxi(SPACE[k] - compress, 1) if IS_SET[k] else SPACE[k]


## What an item adds to a 套餐 it goes into: its ingredient value, x its grade and 高温, plus RAG
## for an 优质 / 金牌 dish (a 套餐 inside: its stored ingredient value).
func _part_value(it: int) -> float:
	var k := K(it)
	if IS_SET[k]:
		return raw_of(it)
	var v := maxf(VALUE[k], 1.0) * _grade_x(it) * (hot_x if is_hot(it) else 1.0)
	if grade(it) > 0:
		v += rag
	return v


func _grade_x(it: int) -> float:
	return [1.0, 2.0, gold_x][grade(it)]


## A 套餐's value multiplier for its tier (with the tier skills).
func _tier_x(k: int) -> float:
	var t: int = TIER[k]
	return TIER_MULT[t] + tier_up[t] * [0.0, 0.2, 0.3, 0.4, 0.6][t]


## What one bite of this item is worth before the box / meal multipliers (bok choy: see _bite).
func _item_value(it: int) -> float:
	var k := K(it)
	if IS_SET[k]:
		return raw_of(it) * _tier_x(k)
	var v: float = VALUE[k]
	if k == I.VEG:
		v = veg_x if _grokked else 0.0
	return v * _grade_x(it) * (hot_x if is_hot(it) else 1.0)


## A box's worth before multipliers (保温箱 / Best-of-N compare boxes by it).
func _box_worth(b: Dictionary) -> float:
	var t := 0.0
	for it in b.items:
		t += _item_value(it)
	return t


func _cols() -> int:
	return box_n


func _rows() -> int:
	return 2


func _cap() -> int:
	return _cols() * _rows()


func _width() -> float:
	return _cols() * CELL + BOX_PAD * 2.0


## Lays the items out in the grid, bottom row first, left to right; a 2-cell item needs two free
## cells side by side in one row. Returns [[cell, span], ...] or [] if something does not fit.
func _pack(items: Array) -> Array:
	var cols := _cols()
	var used := []
	used.resize(_cap())
	used.fill(false)
	var out := []
	for it in items:
		var span: int = _cells(it)
		if span == 0:
			out.append([-1, 0])   # a ghost: drawn over the box, takes no cell
			continue
		var at := -1
		for i in used.size():
			if i % cols + span > cols:
				continue
			var ok := true
			for j in span:
				if used[i + j]:
					ok = false
					break
			if ok:
				at = i
				break
		if at < 0:
			return []
		for j in span:
			used[at + j] = true
		out.append([at, span])
	return out


func _fits(b: Dictionary, kind: int) -> bool:
	var items: Array = b.items.duplicate()
	items.append(kind)
	return not _pack(items).is_empty()


## Would kind k go into box b, counting the 套餐 it would complete (a merge frees cells)?
func _accepts(b: Dictionary, k: int) -> bool:
	var items: Array = b.items.duplicate()
	items.append(k)
	_merge_items(items)
	return not _pack(items).is_empty()


## The best 套餐 these items complete (highest value), or {} if none.
func _best_recipe(items: Array) -> Dictionary:
	var best := {}
	for r in RECIPES:
		var left: Array = items.duplicate()
		var ok := true
		for need in r.needs:
			var at := find_kind(left, need)
			if at < 0:
				ok = false
				break
			left.remove_at(at)
		if ok and (best.is_empty() or VALUE[r.result] > VALUE[best.result]):
			best = r
	return best


## Merges every 套餐 the items complete, chains included; returns the recipes made. A 套餐 keeps
## its ingredients' value (grades, 高温, RAG); a ghost is never an ingredient.
func _merge_items(items: Array) -> Array:
	var made: Array = []
	while true:
		var r := _best_recipe(items.filter(func(it): return not is_ghost(it)))
		if r.is_empty():
			break
		var raw := 0.0
		var inj := 0
		for need in r.needs:
			var at := -1
			for i in items.size():
				if K(items[i]) == need and not is_ghost(items[i]):
					at = i
					break
			raw += _part_value(items[at])
			inj += injected(items[at])
			items.remove_at(at)
		items.append(make(r.result, 0, false, false, inj, raw))
		made.append(r)
	return made


## 合成: the box's ingredients become 套餐 (the player's box shows it and records new recipes).
## Then 提示词注入 hides a green in the new 套餐, 思维链 counts chain merges and 投机解码 may
## guess the next ingredient.
func _merge(b: Dictionary, show: bool) -> void:
	var made := _merge_items(b.items)
	if made.is_empty():
		return
	_recipes_made += made.size()
	if show:
		Fx.hitstop(0.025)
	b["made"] = int(b.get("made", 0)) + made.size()   # (a helper cheers when her box makes one)
	for r in made:
		for need in r.needs:
			if IS_SET[need]:
				b["chains"] = int(b.get("chains", 0)) + 1   # a 套餐 went into a 套餐
	if inject:
		var v := -1
		for i in b.items.size():
			if K(b.items[i]) == I.VEG and not is_ghost(b.items[i]):
				v = i
				break
		if v >= 0 and b.get("crew_role", "") == "recipe":
			var without_green: Array = b.items.duplicate()
			without_green.remove_at(v)
			if int(_helper_recipe_missing({"items": without_green}, int(b.get("crew_recipe", -1))).get(I.VEG, 0)) > 0:
				v = -1   # keep the green reserved for this order
		if v >= 0:
			var veg: int = b.items[v]
			b.items.remove_at(v)
			var last: int = b.items.back()
			b.items[b.items.size() - 1] = make(K(last), 0, is_hot(last), false, injected(last) + 1, raw_of(last) + _part_value(veg))
			if show:
				_chip(b.pos, "leaf")
	if spec > 0.0 and randf() < spec:
		if b.get("crew_role", "") == "recipe":
			var target_kind := int(b.get("crew_recipe", -1))
			var missing := _helper_recipe_missing(b, target_kind)
			var guessed := -1
			for kind in missing:
				var candidate := with_hot(make(int(kind)))
				if int(missing[kind]) > 0 and _helper_accepts({"role": "recipe", "recipe": target_kind, "box": b}, candidate):
					guessed = candidate
					break
			if guessed >= 0:
				b.items.append(guessed)
				_merge(b, show)
			else:
				b.items.append(make(I.BALL, 0, true, true))
		else:
			var close := _closest_recipe(b.items)
			if not close.is_empty() and close[1].size() == 1:
				b.items.append(with_hot(make(close[1][0])))
				if show:
					_chip(b.pos, "bolt")
				_merge(b, show)
			else:
				b.items.append(make(I.BALL, 0, true, true))

	for r in made:
		var first := Game.find_recipe(r.id)
		if show or first:
			_flash.append({"pos": b.pos, "t": 0.0})
			if first:
				_banner("新菜谱！", tr(r.name), "crown")
			else:
				_float(b.pos + Vector2(-60, -130), tr(r.name), "set")
			Audio.sfx("version_up" if first else "combo", -6.0)


## A dish lands in box b (`show`: the player's box, with popups). In order: Temperature may turn
## it into a better dish (never an ingredient the box is collecting), 过拟合 may turn it green,
## 幻觉 may add a ghost bite, 模型融合 fuses three alike, the 套餐 merge, then 涌现 and 大杂烩.
func _catch(b: Dictionary, it: int, show: bool) -> void:
	if _journal != null:
		_journal.count("caught_input", it, self, MEAL_JOURNAL.source(b))
	# 格格 inspects the first eligible ordinary dish in each of her own boxes.
	# Already graded food keeps the inspection available for a later plain ingredient.
	if b.get("crew", false) and b.get("crew_id", "") == "ge" and not b.get("crew_inspected", false) and grade(it) == 0 and not is_ghost(it) and not IS_SET[K(it)] and K(it) != I.JI:
		it = with_grade(it, 1)
		b["crew_inspected"] = true
		_helper_feedback(b.get("pos", FULL_AT), "质检：升为银牌")
	var ordered: bool = b.get("crew_role", "") == "recipe"
	if b.get("crew_role", "") == "nutrition":
		var needed := _nutrition_lacking()
		var nutrients := _item_nutrition(it)
		var tracked: Dictionary = b.get("crew_needed", {})
		tracked[needed] = float(tracked.get(needed, 0.0)) + float(nutrients.get(needed, 0.0))
		b["crew_needed"] = tracked
	var k := K(it)
	if not IS_SET[k] and not is_ghost(it):
		if not ordered and temp > 0.0 and randf() < temp:
			var close := _closest_recipe(b.items)
			if close.is_empty() or not close[1].has(k):
				var up := _upgrade(k)
				var upgraded := with_hot(make(up, grade(it))) if up >= 0 else it
				var original := it
				# Admission used the falling dish's footprint. A larger replacement must
				# still fit after recipes merge; otherwise improve the original dish.
				var keep_green := k == I.VEG and _grokked
				var fits := up >= 0 and not keep_green and _accepts(b, upgraded)
				if fits:
					it = upgraded
					if show:
						_chip(b.pos, "dice")
				else:
					it = with_hot(with_grade(it, grade(it) + 1))
				if _journal != null:
					_journal.transform("temperature", original, it, up >= 0 and not keep_green and not fits, self)
				k = K(it)
		if not ordered and overfit and _grokked and k != I.VEG and randf() < 0.15:
			it = with_hot(make(I.VEG))
			k = I.VEG
	b.items.append(it)
	if show and _learning():
		_coach.caught_food()
	if halluc > 0.0 and not IS_SET[k] and STALL[k] != "" and randf() < halluc:
		b.items.append(make(_stall_kind(STALL[k]), 0, true, true))
		if show:
			_chip(b.pos, "dice")
	if not ordered and fuse3 and not IS_SET[k] and grade(it) < 2:
		var same: Array = []
		for i in b.items.size():
			if b.items[i] & 0x7FF == it & 0x7FF and not is_ghost(b.items[i]):   # same dish, grade and 高温
				same.append(i)
		if same.size() >= 3:
			for j in [2, 1, 0]:
				b.items.remove_at(same[j])
			b.items.append(with_grade(it, grade(it) + 1))
			if show:
				_chip(b.pos, "bolt")
	_merge(b, show)
	if emerge and not ordered:
		var hot: Array = []
		for i in b.items.size():
			var x: int = b.items[i]
			if is_hot(x) and not IS_SET[K(x)] and not is_ghost(x):
				hot.append(i)
		if hot.size() >= 3 and randf() < 0.25:
			var raw := 0.0
			for j in [2, 1, 0]:
				raw += _part_value(b.items[hot[j]])
				b.items.remove_at(hot[j])
			b.items.append(make(KIND["emerge_stew"], 0, true, false, 0, raw))
			_banner("涌现！", tr("神级乱炖"), "dice")
			Audio.sfx("version_up", -6.0)
	if hodge and not ordered and _space(b) >= _cap():
		var close2 := _closest_recipe(b.items)
		if close2.is_empty() or close2[1].size() > 1:
			var pick: Array = []
			var stalls := {}
			for i in b.items.size():
				var x: int = b.items[i]
				var s: String = STALL[K(x)]
				if not IS_SET[K(x)] and not is_ghost(x) and s != "" and not stalls.has(s):
					stalls[s] = true
					pick.append(i)
					if pick.size() == 3:
						break
			if pick.size() == 3:
				var raw2 := 0.0
				var inj := 0
				for j in [2, 1, 0]:
					var x: int = b.items[pick[j]]
					raw2 += _part_value(x)
					inj += 1 if K(x) == I.VEG else 0
					b.items.remove_at(pick[j])
				b.items.append(make(KIND["stew"], 0, true, false, inj, raw2))
				if show:
					_chip(b.pos, "dice")


## Temperature: a better dish of the same stall and kind (主 / 荤 / 素), the next level up; -1 if none.
func _upgrade(k: int) -> int:
	var cat: String = CATS[k].keys()[0] if not CATS[k].is_empty() else ""
	var best: Array = []
	var best_lv := 99
	for j in NAMES.size():
		if STALL[j] != STALL[k] or LEVEL[j] <= LEVEL[k] or IS_SET[j] or struck.has(j) or not CATS[j].has(cat):
			continue
		if LEVEL[j] < best_lv:
			best_lv = LEVEL[j]
			best = [j]
		elif LEVEL[j] == best_lv:
			best.append(j)
	return best.pick_random() if not best.is_empty() else -1


## The 套餐 this box is closest to among those the open stalls can make: [recipe, missing kinds].
func _closest_recipe(items: Array) -> Array:
	var best := []
	var best_n := 0
	for r in RECIPES:
		if not _can_make(r.result):
			continue
		var left: Array = items.duplicate()
		var missing: Array = []
		for need in r.needs:
			var at := find_kind(left, need)
			if at >= 0:
				left.remove_at(at)
			else:
				missing.append(need)
		var have: int = r.needs.size() - missing.size()
		if have > best_n and not missing.is_empty():
			best_n = have
			best = [r, missing]
	return best


## Can the open stalls serve this kind (a 套餐: all its ingredients)?
func _can_make(k: int) -> bool:
	if IS_SET[k]:
		for r in RECIPES:
			if r.result == k:
				for need in r.needs:
					if not _can_make(need):
						return false
				return true
		return false
	return STALL[k] != "" and stall_lv.get(STALL[k], 0) >= LEVEL[k]


func _magnet() -> float:
	# Material changes income only. Attraction must come from an explicitly learned skill.
	return clampf(magnet, 0.0, PULL_MAX_RANGE)


# --- input --------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Once acquired outside GUI, this finger keeps ownership even over a button.
	if _touch_finger < 0 or _ended or autotest: return
	if event is InputEventScreenDrag and event.index == _touch_finger:
		_touch_at = get_canvas_transform().affine_inverse() * event.position
		if _touch_at.distance_to(_touch_start) > TOUCH_TAP_SLOP:
			_touch_tap_target = ""
		if _touch_tap_target.is_empty() and _hand != null:
			_aim = _touch_basin_target(_touch_at)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == _touch_finger and (not event.pressed or event.canceled):
		var at: Vector2 = get_canvas_transform().affine_inverse() * event.position
		if not event.canceled and not _touch_tap_target.is_empty() and at.distance_to(_touch_start) <= TOUCH_TAP_SLOP and Time.get_ticks_msec() - _touch_started_ms <= TOUCH_TAP_MS:
			_touch_activate(_touch_tap_target, at)
		_touch_finger = -1
		_touch_tap_target = ""
		_touch_box = null
		get_viewport().set_input_as_handled()


func _touch_basin_target(at: Vector2) -> Vector2:
	var art := _basin_art_rect(Vector2.ZERO, 1.0)
	var offset := Vector2.ONE * Settings.touch_arm_distance
	var maximum := Vector2(1904 - art.end.x, _hand_bottom())
	# Retract near the bottom/right edge so even the longest arm can serve a meal.
	var edge := ((at - Vector2(1784, 944)) / 120.0).clamp(Vector2.ZERO, Vector2.ONE)
	var retract := (maximum + offset - Vector2(1904, 1064)).max(Vector2.ZERO) * edge
	return (at - offset + retract).clamp(Vector2(16 - art.position.x, BAND.x), maximum)


func _player_arm_end(at: Vector2) -> Vector2:
	return (_touch_at if _touch_finger >= 0 else at + Vector2.ONE * Settings.touch_arm_distance).clamp(Vector2(16, 16), Vector2(1904, 1064))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _ended or autotest or _resume_input_guard > 0.0:
			return
		_enable_touch_controls()
		_hint_input_device = "touch"
		if _journal != null:
			_journal.data.input_devices["touch"] = true
		if event is InputEventScreenTouch and event.pressed and not event.canceled and _touch_finger < 0:
			_touch_at = get_canvas_transform().affine_inverse() * event.position
			_touch_tap_target = _touch_target(_touch_at)
			if _hand != null or not _touch_tap_target.is_empty():
				_touch_finger = event.index
				_touch_start = _touch_at
				_touch_started_ms = Time.get_ticks_msec()
				_touch_box = _hand
				_touch_hand_visible = true
				_mouse_steering = true
				if _hand != null and _touch_tap_target.is_empty():
					_aim = _touch_basin_target(_touch_at)
		get_viewport().set_input_as_handled()
		return
	if _journal != null and not _ended:
		if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.2):
			_journal.data.input_devices["gamepad"] = true
		elif event is InputEventKey and event.pressed:
			_journal.data.input_devices["keyboard"] = true
		elif event is InputEventMouseButton or event is InputEventMouseMotion:
			_journal.data.input_devices["mouse"] = true
	if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		_hint_input_device = "gamepad"
	elif (event is InputEventKey and event.pressed) or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length_squared() > 0.01):
		_hint_input_device = "keyboard"
	if event.is_action_pressed("pause") and not _ended:
		get_viewport().set_input_as_handled()
		pause()
		return
	if event is InputEventMouseMotion:
		if not autotest:   # a real mouse over the window must not steer the bot
			if _touch_finger >= 0: return
			_touch_hand_visible = false
			_aim = get_canvas_transform().affine_inverse() * event.position
			if event.relative.length_squared() > 0.01:
				_mouse_steering = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _ended:
			if _touch_finger >= 0: return
			_touch_hand_visible = false
			if not autotest:
				_aim = get_canvas_transform().affine_inverse() * event.position
				_mouse_steering = true
			_try_deliver()
	elif event.is_action_pressed("deliver") and not _ended:
		_try_deliver()
	elif debug and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: box_n = maxi(box_n - 1, 2); _say("饭盒：2×%d" % box_n)   # notr
			KEY_2: box_n = mini(box_n + 1, 4); _say("饭盒：2×%d" % box_n)   # notr
			KEY_3: basins_total += 1; _empty += 1; _say("再来一盒：共 %d 个" % basins_total)   # notr
			KEY_4: mat_level = (mat_level + 1) % MATERIALS.size(); _say("换成%s" % MATERIALS[mat_level].name)   # notr
			KEY_5: _say("小模型数量在技能树里升级")   # notr
			KEY_6: eat_rate = maxf(eat_rate * 0.8, 0.5); _say("炫饭速度 %.1f/秒" % eat_rate)   # notr
			KEY_7: eat_rate *= 1.25; _say("炫饭速度 %.1f/秒" % eat_rate)   # notr
			KEY_8: tentacles = tentacles % SLOTS + 1; _setup_arms(); _say("梁阿姨：%d 条触手" % tentacles)   # notr
			KEY_9: shake = 0.35 if shake > 0.5 else 1.0; _say("梁阿姨" + ("手稳了" if shake < 0.5 else "又手抖了"))   # notr
			KEY_0: peaks = not peaks; _peak_on = false; _peak_t = OFF_PEAK; _say("峰谷时段 " + ("开" if peaks else "关"))   # notr
			KEY_F1: _show_stats = not _show_stats
			KEY_F2: _stress()


func pause(from_focus := false) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or is_instance_valid(_pause) or _ended or get_tree().paused:
		return
	_interrupt_thinking()
	_cancel_touch()
	Settings.release_gameplay_inputs()
	_pause = PauseMenu.new()
	_pause.focus_pause = from_focus
	_pause.stall_guide = _service_ui
	_pause.resumed.connect(func():
		_resume_input_guard = 0.18
		_think_input_held = true)
	_pause.end_shift.connect(func(): _end("提前下班"))
	_pause.to_title.connect(func():
		_end("提前下班", false)
		to_title.emit())
	add_child(_pause)
	# Never freeze gameplay unless the player can actually reach a resume control.
	if not _pause.is_inside_tree():
		_pause.queue_free()
		_pause = null
		return
	get_tree().paused = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_touch()
		if is_node_ready():
			_interrupt_thinking()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Settings.pause_unfocused and not autotest and not _ended and is_inside_tree() and not _focus_pause_pending:
		# OS focus notifications lock the child list while walking the scene tree.
		# Installing a menu here fails, leaving a paused game with no way to resume.
		_focus_pause_pending = true
		_pause_after_focus_loss.call_deferred()


func _pause_after_focus_loss() -> void:
	_focus_pause_pending = false
	if Settings.pause_unfocused and is_node_ready():
		pause(true)


func _set_thinking(on: bool) -> void:
	if _thinking == on:
		return
	_thinking = on
	_was_thinking = on
	_think_transitions += 1
	Audio.sfx("think_start" if on else "think_end", -6.0)
	Audio.slowmo(on)
	if not on:
		_think_cooldown = THINK_COOLDOWN


func _interrupt_thinking() -> void:
	_set_thinking(false)
	_think_input_held = true
	_resume_input_guard = 0.18
	Audio.slowmo(false)


## A press starts one thinking session. Holding through exhaustion never restarts it.
func _update_thinking(delta: float, want: bool) -> void:
	_think_cooldown = maxf(_think_cooldown - delta, 0.0)
	if _resume_input_guard > 0.0:
		_resume_input_guard = maxf(_resume_input_guard - delta, 0.0)
		_think_input_held = true
		_think = minf(_think + think_regen * delta, think_time)
		return
	var pressed := want and not _think_input_held
	_think_input_held = want
	if _thinking:
		if want:
			_think = maxf(_think - delta, 0.0)
		if not want or _think <= 0.0 or not can_think:
			_set_thinking(false)
		return
	_think = minf(_think + think_regen * delta, think_time)
	if can_think and pressed and _think_cooldown <= 0.0 and _think >= minf(THINK_MIN_CHARGE, think_time):
		_set_thinking(true)


func _think_hint() -> String:
	if _thinking:
		return tr("松手结束 · 冷却 1 秒")
	if _think_cooldown > 0.0:
		return tr("冷却 %.1f 秒") % _think_cooldown
	if _think_input_held:
		return tr("松开后再按")
	if _think < minf(THINK_MIN_CHARGE, think_time):
		return tr("思考恢复中")
	if _hint_input_device == "touch" or is_instance_valid(_touch_controls):
		return tr("按住思考")
	var binding := Settings.binding_label("think", _hint_input_device).get_slice(" / ", 0)
	return (tr("按住 %s") if _hint_input_device == "gamepad" else tr("按住 %s / 右键")) % binding


## Left click / A over the table: empty hand -> take a box off the stack; an empty box in hand ->
## back on the stack; a box with food -> into the queue she eats from.
## Skills: 自动推送 (she tosses you an empty box) and 自动回收 (a full box flies home by itself).
func _update_skills(delta: float) -> void:
	_push_cd = maxf(_push_cd - delta, 0.0)
	if auto_push and _hand == null and _empty > 0 and _push_cd <= 0.0:
		_empty -= 1
		_hand = _new_basin(STACK_AT + Vector2(0, -20))
		_hand.pos = Vector2(_aim.x, clampf(_aim.y, BAND.x, _hand_bottom()))
		if _learning():
			_coach.took_box()
		_push_cd = 0.6
		Audio.sfx("box_return", -8.0)
	if auto_return and _hand != null and _space(_hand) >= _cap():
		_flying.append({"from": _hand.pos, "to": _table_slot(_queue.size() + _flying.size()), "t": 0.0, "basin": _hand})
		Audio.sfx("box_return", -6.0)
		_hand = null


func _try_deliver() -> void:
	if _hand == null:
		if TABLE.grow(60).has_point(_aim) and _empty > 0:
			_empty -= 1
			_hand = _new_basin(STACK_AT + Vector2(0, -20))
			if _learning():
				_coach.took_box()
			Audio.sfx("deliver", -8.0)
		return
	if warm and WARM_RECT.grow(20).has_point(_hand.pos) and not _hand.items.is_empty():
		_put_warm(_hand)
		_hand = null
		return
	if not TABLE.grow(60).has_point(_hand.pos):
		return
	if _hand.items.is_empty():
		_empty += 1
		_hand = null
		Audio.sfx("deliver", -8.0)
		return
	if _busy_t > 0.0:
		Audio.sfx("server_busy", -6.0)
		return
	if legacy != "":
		_busy_t = 1.2
	Audio.sfx("deliver", -3.0)
	_serve(_hand)
	_hand = null


## A full box reaches the table: 重新生成 may reroll its dishes, Best-of-N may keep it warm,
## otherwise it joins the queue she eats from.
func _serve(b: Dictionary) -> void:
	if not b.has("full"):
		b["full"] = _space(b) >= _cap()
	_note_served(b)
	_award_helper_relay(b)
	if regen > 0.0 and not b.get("crew", false) and randf() < regen:
		_reroll_box(b)
		_chip(Vector2(1600, 860), "dice")
	if _journal != null:
		_journal.box("arrive", b, self)
	if warm and best_of_n and (_warm == null or _box_worth(b) > _box_worth(_warm)):
		_put_warm(b)
		return
	_queue.append(b)


## Rerolling happens after delivery rules are frozen. It does not run recipe merges;
## every replacement must fit the actual two-row grid alongside the remaining food.
func _reroll_box(b: Dictionary) -> void:
	for i in b.items.size():
		var it: int = b.items[i]
		if IS_SET[K(it)] or is_ghost(it):
			continue
		var up := _upgrade(K(it))
		if up < 0:
			continue
		var candidate: Array = b.items.duplicate()
		candidate[i] = with_hot(make(up, grade(it)))
		if not _pack(candidate).is_empty():
			b.items[i] = candidate[i]
		else:
			b.items[i] = with_hot(with_grade(it, grade(it) + 1))
		if _journal != null:
			_journal.transform("regenerate", it, b.items[i], b.items[i] != candidate[i], self)


## KV Cache 保温箱: this box waits until closing time (a box already in it goes to the queue).
func _put_warm(b: Dictionary) -> void:
	if not b.has("full"):
		b["full"] = _space(b) >= _cap()
	_note_served(b)
	if _warm != null:
		if _journal != null:
			_journal.box("warm_released", _warm, self)
		_queue.append(_warm)
	_warm = b
	if _journal != null:
		_journal.box("warm_stored", b, self)
	_float(WARM_AT + Vector2(-80, -110), "留到最后吃", "set")
	Audio.sfx("deliver", -4.0)


func _note_served(b: Dictionary) -> void:
	if b.get("crew", false) or b.get("takeout", false) or b.items.is_empty() or b.get("run_counted", false):
		return
	b["run_counted"] = true
	_consume_helper_relay(b)
	var rule := _plan_box(b)
	b["meal_rule"] = rule
	_previous_mono_kind = int(rule.next_mono_kind)
	_cache_ready = bool(rule.cache_ready)
	_commit_delivery_chain(b, bool(rule.combo_eligible))
	if _journal != null:
		_journal.box("player_submit", b, self)
	if rule.cache_primed:
		_float(b.pos + Vector2(-70, -130), "缓存接力" if rule.get("cache_bridge", false) else "缓存已备好", "mult")
	elif float(rule.add_bonus) > 0.0:
		_float(b.pos + Vector2(-70, -130), tr("搭配 +%d%%") % int(round(float(rule.add_bonus) * 100)), "mult")
	if b.get("full", false):
		_full_boxes += 1
		Fx.hitstop(0.018)
	if _learning():
		_coach.served_food()


func _box_profile(b: Dictionary) -> Dictionary:
	var items: Array = []
	for it in b.items:
		var k := K(it)
		items.append({"kind": k, "cells": _cells(it), "ghost": is_ghost(it), "is_set": IS_SET[k], "tier": TIER[k]})
	return MEAL_RULES.profile(items, _cap())


func _plan_box(b: Dictionary) -> Dictionary:
	return MEAL_RULES.plan(_box_profile(b), _previous_mono_kind, _cache_ready, mono_bonus, cache_bonus, rotation_bonus)


func _box_rule_bonus(b: Dictionary) -> float:
	return float(b.get("meal_rule", {}).get("add_bonus", 0.0)) + float(b.get("crew_relay_bonus", 0.0))


## Freeze the chain at submission time: the table is a stack, so eating order can differ.
func _commit_delivery_chain(b: Dictionary, eligible: bool) -> void:
	b["chain_multiplier"] = 1.0
	if combo <= 0.0:
		return
	if eligible:
		_combo_n += 1
		b.chain_multiplier = 1.0 + combo * mini(_combo_n - 1, _combo_cap())
	elif _combo_n > 0:
		if _combo_safe:
			_combo_safe = false
		else:
			_combo_n = _combo_n / 2 if memory >= 1 else 0
			_float(Vector2(1700, 440), "连击断了", "info")


func _combo_eligible(b: Dictionary) -> bool:
	if b.has("meal_rule"):
		return bool(b.meal_rule.combo_eligible)
	# Unsubmitted player boxes are previews only; helper/takeout never change build state.
	if not b.get("crew", false) and not b.get("takeout", false):
		return bool(_plan_box(b).combo_eligible)
	return int(_box_profile(b).high_sets) >= 2


func _stress() -> void:
	for i in MAX_ITEMS:
		_add_item(Vector2(randf_range(100, 1400), randf_range(-200, 400)), Vector2(randf_range(-150, 150), randf_range(-150, 50)), _roll_kind())


# --- main loop ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_bark_t = maxf(_bark_t - delta, 0.0)
	_shaky_t = maxf(_shaky_t - delta, 0.0)
	for f in _flash:
		f.t += delta
	_flash = _flash.filter(func(f): return f.t < 0.5)
	for x in _texts:
		x.t += delta
	_texts = _texts.filter(func(x): return x.t < 1.0)
	_update_hud(delta)
	_back.queue_redraw()
	_front.queue_redraw()
	if _ended:
		queue_redraw()
		return
	# 深度思考 slows the world down; the basin (your hand) keeps real time
	var want_think: bool = can_think and (Input.is_action_pressed("think") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or (is_instance_valid(_touch_controls) and _touch_controls.think_held))
	if autotest:
		want_think = can_think and _bot_think()
	_update_thinking(delta, want_think)
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if stick != Vector2.ZERO and not autotest and _touch_finger < 0:
		_mouse_steering = false
		_aim = (_aim + stick * PAD_SPEED * delta).clamp(Vector2(40, BAND.x), Vector2(1880, _hand_bottom()))
	var wdt := delta * (think_slow if _thinking else 1.0)
	_t += wdt
	if _journal != null and not _learning():
		_journal.data.active_seconds += delta
	if _learning():
		_learning_time += wdt
	_busy_t = maxf(_busy_t - wdt, 0.0)
	if autotest:
		_bot()
	_update_peaks(wdt)
	_update_rounds(wdt, delta)
	_update_app(wdt)
	if not _learning() or _coach.step != COACH_UI.Step.TAKE:
		_update_arms(wdt)
	_update_arm_art()
	_update_hand(delta)
	_update_items(wdt)
	_update_pile(wdt)
	_update_flying(wdt)
	_update_crew(wdt)
	_update_skills(delta)
	if _learning():
		_coach.reconcile_hand(_hand != null, _hand != null and not _hand.items.is_empty())
	_update_fish(wdt, delta if think_eat and _thinking else wdt)   # 边想边用工具: she eats in real time
	if _journal != null:
		_journal.sample(self)
	if _ended:
		return
	_update_music()
	if _meal_elapsed() >= meal_time:
		_end("食堂关门了")
	queue_redraw()


## The music follows the shift: rush hour (and a trial's quick rounds) adds a drum layer, the
## last FINAL_SECONDS add a ticking clock and push the tempo up a little, 深度思考 slows and
## muffles it (Audio, layers from pipeline/make_music_layers.py).
const FINAL_SECONDS := 10.0
const EOS_X := [1.0, 3.0, 5.0, 8.0]      # <EOS> 最后一个 token, by level
func _update_music() -> void:
	Audio.music_layer("peak", _peak_on or (legacy == "hybrid" and not _hard))
	var left := meal_time - _meal_elapsed()
	Audio.music_layer("final", left < FINAL_SECONDS)
	Audio.music_tempo(1.0 + 0.05 * clampf(1.0 - left / FINAL_SECONDS, 0.0, 1.0))
	Audio.slowmo(_thinking)


## 嗯，用户想要……: quick and hard rounds take turns; thinking in a quick round annoys the users.
## `real` is unscaled time (thinking does not slow the users' patience down).
func _update_rounds(delta: float, real: float) -> void:
	if legacy != "hybrid" or _ended:
		return
	_round_t -= delta
	if _round_t <= 0.0:
		_hard = not _hard
		_round_t = ROUND[1] if _hard else ROUND[0]
		_volley_t = 0.8
		_say("难题来了！这题得想想" if _hard else "快问快答：别想了，直接接！")
		Audio.sfx("peak_start" if _hard else "peak_end", -4.0)
	if _hard:
		_volley_t -= delta
		if _volley_t <= 0.0:
			_volley_t = volley_every
			var a: Dictionary = _arms.pick_random()
			a.raise = RAISE_TIME
			a.q = true
	elif _thinking:
		sat -= think_penalty * real
		if randf() < real * 2.0:
			_text(_hand.pos + Vector2(-80, -150) if _hand != null else _aim, "用户：想什么想，快点！", Color(1, 0.55, 0.45))
	if sat <= 0.0:
		sat = 0.0
		_end(TRIAL_ENDS[legacy][1])


## 帮我做个 App: now and then a takeout box lands on the table by itself (never in trials).
func _update_app(delta: float) -> void:
	if app_rate <= 0.0:
		return
	_app_t += delta * app_rate / 60.0
	if _app_t < 1.0:
		return
	_app_t -= 1.0
	if _queue.size() + _flying.size() >= 4:
		return   # the table is full: the courier leaves it at the door
	var box := _new_basin(Vector2(2000, 700))
	for i in _cap() / 2:
		box.items.append(I.BALL)
	box.items.append(I.LEG)
	box["takeout"] = true
	_flying.append({"from": Vector2(1980, 640), "to": _table_slot(_queue.size() + _flying.size()), "t": 0.0, "basin": box})
	_text(Vector2(1500, 800), "外卖到了！", Color(1.0, 0.85, 0.5))
	Audio.sfx("box_return", -6.0)


func _update_pile(delta: float) -> void:
	if legacy != "spring" or _ended:
		return
	_clean_acc += clean_rate * delta
	while _clean_acc >= 1.0:
		_clean_acc -= 1.0
		if _pile.is_empty():
			_clean_acc = 0.0
			break
		_pile.remove_at(0)
		_pile_k.remove_at(0)
	if _pile.size() >= pile_max:
		_end(TRIAL_ENDS[legacy][1])


func _update_peaks(delta: float) -> void:
	if not peaks:
		_peak_on = false
		return
	_peak_t -= delta
	if _peak_t <= 0.0:
		_peak_on = not _peak_on
		_peak_t = peak_time if _peak_on else OFF_PEAK
		if _peak_on:
			_banner("高峰来了！", tr("阿姨加速出菜"), "bell")
			Audio.vo("auntie_rush", 2)
		Audio.sfx("peak_start" if _peak_on else "peak_end", -4.0)


func _update_arms(delta: float) -> void:
	for a in _arms:
		if a.raise > 0.0:
			a.raise -= delta
			if a.raise <= 0.0:
				_fling(a)
			continue
		var speed := (2.5 if _peak_on else 1.0) * _rate * throw_rate   # rush hour: she cooks much faster
		if a.stall != "":
			speed *= float(STALLS[a.stall].speed)
			for k in _sigs:
				if _sigs[k].has("slow") and STALL[k] == a.stall:
					speed *= 1.0 - float(_sigs[k].slow)
		if legacy == "hybrid":
			speed *= 0.6 if _hard else 1.5   # quick rounds rush you; hard rounds are about the 难题
		a.t -= delta * speed
		if a.t <= 0.0:
			a.raise = RAISE_TIME
			a.t = randf_range(THROW_EVERY.x, THROW_EVERY.y)
			a.t0 = a.t


## One scoop over the counter. 手抖: how far apart and how far out the food lands.
func _fling(a: Dictionary) -> void:
	var pose := _arm_pose(a, 1.0)
	var from: Vector2 = pose[1] + pose[2] * LADLE_LEN
	Audio.sfx("fling", -10.0)
	if a.get("q", false):
		# a 难题 volley: flung hard and far apart, in both directions
		a.q = false
		for i in volley_n:
			var side := -1.0 if i % 2 == 0 else 1.0
			var vx := side * randf_range(180.0, 560.0) * q_speed
			_add_item(from, Vector2(vx, randf_range(-620.0, -380.0) * q_speed), I.Q)
		return
	var n := 1 + randi() % 3 + scoop + (1 if randf() < batch else 0)
	if shake > 0.6:
		_shaky_t = 0.6
	for i in n:
		# out of the tray: a little hop up, then down its own window's column (手抖: how far off)
		var k: int = _roll_kind()
		if a.stall != "":
			k = a.dish if i == 0 else _stall_kind(a.stall)
		_throw(a, k)
	if veg_std > 0.0 and randf() < veg_std and stall_lv.get("wok", 0) > 0 and not struck.has(I.VEG):
		_throw(a, I.VEG)   # 食堂标配: a spoon of greens with every dish
	a.dish = _next_dish(a)


## One dish out of a window's tray, with its grade rolled (SFT / DPO).
func _throw(a: Dictionary, k: int) -> void:
	var tray := Vector2(a.x + randf_range(-14.0, 14.0), COUNTER_Y - 10.0)
	var vx := randf_range(-50.0, 50.0) * shake
	var g := 0
	if not IS_SET[k] and randf() < g_good:
		g = 2 if randf() < g_gold else 1
	var admitted := _fp.size() < MAX_ITEMS
	_add_item(tray, Vector2(vx, -randf_range(150.0, 260.0)), make(k, g))
	if _journal != null and admitted:
		_journal.count("thrown", make(k, g), self)


## What a stall's window serves next (shown on its name plate).
func _next_dish(a: Dictionary) -> int:
	return _stall_kind(a.stall) if a.get("stall", "") != "" else -1


## A random dish off a stall's menu: everything up to its level, by weight; rush hour makes the
## rare ones (金饭团) peak_good times likelier.
func _stall_kind(stall: String) -> int:
	var lv: int = stall_lv.get(stall, 0)
	var total := 0.0
	var pick: Array = []
	for k in NAMES.size():
		if STALL[k] == stall and LEVEL[k] <= lv and not struck.has(k):
			var w: float = WEIGHT[k] * (peak_good if _peak_on and RARE[k] else 1.0)
			if k == I.VEG:
				w *= 1.0 + _care()
			pick.append([k, w])
			total += w
	if pick.is_empty():   # every dish struck: she serves the menu anyway
		for k in NAMES.size():
			if STALL[k] == stall and LEVEL[k] <= lv:
				pick.append([k, WEIGHT[k]])
				total += WEIGHT[k]
	var r := randf() * total
	for e in pick:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return pick[0][0] if not pick.is_empty() else I.BALL


## The kind of food (主 / 荤 / 素) furthest below the 4 : 3 : 3 target this shift.
func _lacking() -> String:
	var tot: float = maxf(_cat["主"] + _cat["荤"] + _cat["素"], 1.0)
	var best := "主"
	var gap := -INF
	for cn in [["主", 0.4], ["荤", 0.3], ["素", 0.3]]:
		var g: float = cn[1] - _cat[cn[0]] / tot
		if g > gap:
			gap = g
			best = cn[0]
	return best


## 阿姨的关心: the less 素 she has eaten this shift (below 30%), the more greens 梁阿姨 serves
## (up to twice as many). 0..1.
func _care() -> float:
	var tot: float = _cat["主"] + _cat["荤"] + _cat["素"]
	if tot < 4.0:
		return 0.0
	var c := clampf((0.3 - _cat["素"] / tot) / 0.3, 0.0, 1.0)
	if c > 0.5 and _t - _care_t > 12.0:
		_care_t = _t
		_say_auntie("多吃点菜！")
		Audio.vo("auntie_care", 1)
	return c


func _roll_kind() -> int:
	var good := peak_good if _peak_on else 1.0   # peak hours: more of the good stuff
	var r := randf()
	if legacy == "spring" and r < 0.6:
		return I.DUMP
	if legacy == "ji" and randf() < ji_chance:
		return I.JI
	if r < 0.01 * good:
		return I.GOLD
	if r < 0.05 * good:
		return I.LEG
	if r < 0.05 * good + 0.08:
		return I.BOWL
	if r < 0.05 * good + 0.16:
		return I.VEG
	return I.BALL


func _update_hand(delta: float) -> void:
	if _hand == null:
		return
	_aim.y = clampf(_aim.y, BAND.x, _hand_bottom())
	_hand["previous_pos"] = _hand.pos
	var fill := float(_space(_hand)) / _cap()
	var heavy := clampf(fill * box_n / 4.0, 0.0, 1.0)   # a full 2x4 box is the heaviest
	var old_vel: Vector2 = _hand.vel
	if _mouse_steering and not autotest:
		# The pointer is the hand. Weight is conveyed by a little food sway, not input lag.
		_hand.pos = _aim.clamp(Vector2(40, BAND.x), Vector2(1880, _hand_bottom()))
		var measured: Vector2 = (_hand.pos - _hand.previous_pos) / maxf(delta, 0.0001)
		_hand.vel = old_vel.lerp(measured.limit_length(SPEED.x), minf(1.0, delta * 18.0))
	else:
		var want: Vector2 = (_aim - _hand.pos) * minf(18.0, 0.9 / maxf(delta, 0.0001))
		want = want.limit_length(lerpf(SPEED.x, 1600.0, heavy))
		_hand.vel = old_vel.move_toward(want, lerpf(ACCEL.x, 9000.0, heavy) * delta)
		_hand.pos += _hand.vel * delta
	if _hand.pos.y < BAND.x or _hand.pos.y > _hand_bottom():
		_hand.pos.y = clampf(_hand.pos.y, BAND.x, _hand_bottom())
		_hand.vel.y = 0.0
	var acc_x: float = (_hand.vel.x - old_vel.x) / maxf(delta, 0.0001)
	var sway := 0.4 if _mouse_steering and not autotest else 1.0
	_hand.slosh = _hand.slosh * exp(-5.0 * delta) + clampf(acc_x, -12000.0, 12000.0) * delta / 1500.0 * sway
	var slosh: float = absf(_hand.slosh)
	if fill > 0.6 and slosh > SLOSH_SPILL:
		_spill_acc += (slosh - SLOSH_SPILL) * 12.0 * delta
		while _spill_acc >= 1.0 and not _hand.items.is_empty():
			_spill_acc -= 1.0
			var k: int = _hand.items.pop_back()
			if is_ghost(k):
				continue
			spilled += 1
			Audio.sfx("spill", -6.0)
			var side := -signf(_hand.slosh)
			_add_item(_hand.pos + Vector2(side * _width() * 0.45, -10), Vector2(side * randf_range(150, 350), randf_range(-320, -160)) + _hand.vel * 0.3, k)
	else:
		_spill_acc = 0.0
	# a 「极」 is light: a hard shake flings it out of the box
	if slosh > 0.3 and find_kind(_hand.items, I.JI) >= 0:
		_hand.items.remove_at(find_kind(_hand.items, I.JI))
		ji_shaken += 1
		var side2 := -signf(_hand.slosh)
		_add_item(_hand.pos + Vector2(side2 * _width() * 0.45, -10), Vector2(side2 * randf_range(250, 400), randf_range(-380, -240)), I.JI)
		_text(_hand.pos + Vector2(-90, -120), "甩掉了「极」！", Color(1.0, 0.85, 0.5))
		Audio.sfx("spill", -4.0)


## Local skill attraction: only descending food just above the box, with tapered strength.
## It nudges toward a bounded target speed instead of accumulating unlimited sideways speed.
func _steer_food(p: Vector2, v: Vector2, it: int, delta: float, clock: float) -> Vector2:
	var k := K(it)
	if PICKY[k] and v.y > 60.0:
		v.x += sin(clock * 5.0 + p.y * 0.02) * 90.0 * delta
	if _hand == null or v.y <= 0.0:
		return v
	var pull := clampf(_magnet() + (diverge if _thinking else 0.0), 0.0, PULL_MAX_RANGE)
	var ignored := (dsa and not grok and (k == I.VEG or k == I.JI)) or (_thinking and converge and not _wanted(it))
	var dx: float = _hand.pos.x - p.x
	var dy: float = _hand.pos.y - p.y
	if pull > 0.0 and not ignored and absf(dx) < pull and dy > 0.0 and dy < PULL_HEIGHT:
		var strength := (1.0 - absf(dx) / pull) * (1.0 - dy / PULL_HEIGHT)
		var target_vx := clampf(dx * 3.0, -PULL_MAX_SPEED, PULL_MAX_SPEED)
		v.x = move_toward(v.x, target_vx, PULL_ACCEL * strength * delta)
	if dsa and k == I.JI and absf(dx) < _width() * 0.5 + 40.0 and dy > 0.0 and dy < 120.0:
		v.x = move_toward(v.x, -signf(dx + 0.01) * PULL_MAX_SPEED, PULL_ACCEL * delta)
	return v


## A swept opening in food-minus-box coordinates catches both falling and lateral crossings.
## Returning the contact fraction also keeps the bounce at the actual point of contact.
static func _swept_opening(p: Vector2, np: Vector2, box_from: Vector2, box_to: Vector2, half_width: float) -> float:
	var start := p - box_from
	var motion := (np - box_to) - start
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		var radius := half_width if axis == 0 else 12.0
		if absf(motion[axis]) < 0.00001:
			if absf(start[axis]) > radius:
				return -1.0
			continue
		var a: float = (-radius - start[axis]) / motion[axis]
		var b: float = (radius - start[axis]) / motion[axis]
		enter = maxf(enter, minf(a, b))
		leave = minf(leave, maxf(a, b))
		if enter > leave:
			return -1.0
	return enter if leave >= 0.0 and enter <= 1.0 else -1.0


func _update_items(delta: float) -> void:
	var w := _width()
	var i := 0
	while i < _fp.size():
		var p := _fp[i]
		var v := _fv[i]
		var it := int(_fk[i])
		var k := K(it)
		var initial_vy := v.y
		v.y += _fg[i] * delta
		v = _steer_food(p, v, it, delta, _t)
		if k in HOPPY and randf() < ji_hop * delta:
			v.x = randf_range(-280.0, 280.0)   # 「极」 hops about
			v.y = minf(v.y, randf_range(-160.0, 40.0))
		if not _crew.is_empty():
			v = _crew_tricks(p, v, it, delta)
		var np := p + v * delta
		if k not in HOPPY and is_equal_approx(v.y, initial_vy + _fg[i] * delta):
			np.y = p.y + initial_vy * delta + 0.5 * _fg[i] * delta * delta
		_fr[i] += delta * v.x * 0.01
		var contact := -1.0
		var pass_through := _thinking and converge and not _wanted(it)
		if _hand != null and v.y > 0.0 and not pass_through:
			contact = _swept_opening(p, np, _hand.get("previous_pos", _hand.pos), _hand.pos, w * 0.47 + 8.0)
		# A long frame may cross both boxes; the earliest physical contact wins.
		var crew_box = _crew_catch(p, np, v, it, contact if contact >= 0.0 else INF)
		if crew_box != null:
			_catch(crew_box, it, false)
			caught += 1
			_catch_sound(it, -8.0)
			_remove_item(i)
			continue
		if contact >= 0.0:
			if not (dsa and not grok and k == I.VEG) and _accepts(_hand, it):
				_catch_sound(it)
				_catch(_hand, it, true)
				caught += 1
				if k == I.Q:
					solved += 1
					_text(_hand.pos + Vector2(-60, -120), "解出来了！", Color(0.85, 0.75, 1.0))
				elif k == I.JI:
					_text(_hand.pos + Vector2(-60, -120), "「极」掉进饭盒了！甩掉它！", Color(1.0, 0.45, 0.4))
					Audio.sfx("server_busy", -6.0)
				_remove_item(i)
				continue
			v = Vector2(v.x + randf_range(-160, 160), -absf(v.y) * 0.35)   # full (or a green, with DSA): bounces off
			Audio.sfx("bounce", -8.0)
			np = Vector2(p.lerp(np, contact).x, _hand.pos.y - 16)
		if np.y >= FLOOR_Y and _crew_floor(np.x, it):
			caught += 1
			_catch_sound(it, -8.0)
			_remove_item(i)
			continue
		if np.y >= FLOOR_Y or np.x < -40 or np.x > 1960:
			if np.y >= FLOOR_Y:
				Audio.sfx("floor", -14.0)
				if _is_good(it) and _eating == null and _fish.clip != "surprised":
					_fish.play("surprised")   # 啊！ the good stuff hit the floor
			if k != I.VEG and k != I.JI:
				wasted += 1
				wasted_value += VALUE[k]
			if k == I.Q:
				sat -= q_penalty
				_text(Vector2(clampf(np.x, 60, 1700), FLOOR_Y - 60), "这题没解出来", Color(1, 0.55, 0.45))
			if legacy == "spring" and np.y >= FLOOR_Y:
				_pile.append(Vector2(clampf(np.x, 20, 1900), FLOOR_Y - 10))
				_pile_k.append(k)
			_remove_item(i)
			continue
		_fp[i] = np
		_fv[i] = v
		i += 1


## Can this dish be of use (收敛思维 lets the rest fall through)? Greens only once she likes them.
func _wanted(it: int) -> bool:
	var k := K(it)
	if k == I.VEG:
		return grok or _grokked or inject
	return k != I.JI and (USEFUL.has(k) or _helper_item_value(it) >= 4.0)


## The landing sound of item `it` in a box: by what the food is (menu.json snd: soft rice, crisp
## fried things, sloshing soup and drinks, saucy stir-fries, wobbly desserts), with a sparkle on
## top for 金牌 and gold dishes. `quieter`: a helper's box, further away.
func _catch_sound(it: int, quieter := 0.0) -> void:
	var k := K(it)
	if k != I.Q:
		Audio.sfx(SND[k], -1.0 + quieter)   # the catch family sits at -26 LUFS (gen_audio LEVEL_LUFS)
	if k == I.GOLD or k == I.JI_GOLD or k == I.Q or grade(it) == 2:
		Audio.sfx("catch_gold", -9.0 + quieter)


func _is_good(it: int) -> bool:
	return K(it) == I.Q or _helper_item_value(it) >= 5.0


func _add_item(p: Vector2, v: Vector2, it: int) -> void:
	if _fp.size() >= MAX_ITEMS:
		return
	_fp.append(p); _fv.append(v); _fk.append(it); _fr.append(randf_range(-0.4, 0.4))
	_fg.append(GRAVITY * FALL[K(it)] * randf_range(1.0 - FALL_JITTER, 1.0 + FALL_JITTER))


func _remove_item(i: int) -> void:
	var last := _fp.size() - 1
	_fp[i] = _fp[last]; _fv[i] = _fv[last]; _fk[i] = _fk[last]; _fr[i] = _fr[last]; _fg[i] = _fg[last]
	_fp.resize(last); _fv.resize(last); _fk.resize(last); _fr.resize(last); _fg.resize(last)


## Seconds until piece i falls to height y (with its own gravity), or INF if it is below.
func _time_to(i: int, y: float) -> float:
	var p := _fp[i]
	var v := _fv[i]
	if p.y > y:
		return INF
	var g := _fg[i]
	if g <= 0.00001:
		return (y - p.y) / v.y if v.y > 0.0 else INF
	return (-v.y + sqrt(v.y * v.y + 2.0 * g * (y - p.y))) / g


## Full boxes wait right of the empty stack, slightly overlapping when there are many.
func _table_slot(i: int) -> Vector2:
	return FULL_AT + Vector2(0, -11.0 * i)


func _update_flying(delta: float) -> void:
	for f in _flying:
		f.t += delta / 0.6
		if f.t >= 1.0:
			if f.basin == null:
				_empty += 1   # an emptied box lands back on the stack
			else:
				_serve(f.basin)
	_flying = _flying.filter(func(f): return f.t < 1.0)


## One item policy is used by planning, magnets, jumping, floor pickups and the player guide.
## Training greens have future value even before their first token is earned.
func _helper_item_value(it: int) -> float:
	var k := K(it)
	if k == I.JI:
		return 0.0
	if k == I.VEG:
		if grok or _grokked:
			return maxf(veg_x, 4.0) * _grade_x(it) * (hot_x if is_hot(it) else 1.0)
		return _part_value(it) if inject else 0.0
	return maxf(_item_value(it), 0.0)


func _helper_recipe_missing(b: Dictionary, target_kind: int) -> Dictionary:
	var missing := {}
	if target_kind < 0 or target_kind >= NAMES.size():
		return missing
	for kind in _ingredients(target_kind):
		missing[kind] = int(missing.get(kind, 0)) + 1
	for it in b.items:
		if is_ghost(it):
			continue
		for kind in _ingredients(K(it)):
			if missing.has(kind):
				missing[kind] = maxi(int(missing[kind]) - 1, 0)
	return missing


## A candidate must leave an actual assembly route, not just a matching ingredient count.
## Cache per cargo/candidate; the search runs only when a box's contents change.
func _helper_recipe_reachable(items: Array, target_kind: int) -> bool:
	var key := JSON.stringify([target_kind, items])
	if _helper_recipe_cache.has(key):
		return bool(_helper_recipe_cache[key])
	var missing := _helper_recipe_missing({"items": items}, target_kind)
	var remaining: Array = []
	for kind in missing:
		for i in int(missing[kind]):
			remaining.append(int(kind))
	var can_finish := Game._helper_recipe_route(self, target_kind, items, remaining, {})
	if _helper_recipe_cache.size() > 2048:
		_helper_recipe_cache.clear()
	_helper_recipe_cache[key] = can_finish
	return can_finish


func _item_nutrition(it: int) -> Dictionary:
	var k := K(it)
	if k == I.JI or (PICKY[k] and not grok and not _grokked):
		return {}
	var cats: Dictionary = CATS[k].duplicate()
	if k == I.VEG and drift and _grokked:
		cats = {"素": 0.5, "荤": 0.5}
	cats["素"] = float(cats.get("素", 0.0)) + injected(it)
	return cats


func _add_projected_item(projected: Dictionary, it: int) -> void:
	var cats := _item_nutrition(it)
	for category in ["主", "荤", "素"]:
		projected[category] = float(projected.get(category, 0.0)) + float(cats.get(category, 0.0))


## Include food already committed to the meal, without counting an aliased box twice.
func _projected_nutrition() -> Dictionary:
	var projected := _cat.duplicate()
	var boxes: Array = []
	for b in [_hand, _eating, _warm] + _queue:
		if b != null:
			boxes.append(b)
	for flight in _flying:
		if flight.basin != null:
			boxes.append(flight.basin)
	for c in _crew:
		if c.box != null:
			boxes.append(c.box)
	var seen: Array = []
	for b in boxes:
		if seen.any(func(other): return is_same(other, b)):
			continue
		seen.append(b)
		for it in b.items:
			_add_projected_item(projected, it)
	return projected


func _nutrition_lacking(projected: Dictionary = {}) -> String:
	if projected.is_empty():
		projected = _projected_nutrition()
	var total := maxf(float(projected.get("主", 0)) + float(projected.get("荤", 0)) + float(projected.get("素", 0)), 1.0)
	var best := "主"
	var largest := -INF
	for pair in [["主", 0.4], ["荤", 0.3], ["素", 0.3]]:
		var deficit: float = pair[1] - float(projected.get(pair[0], 0)) / total
		if deficit > largest:
			largest = deficit
			best = pair[0]
	return best


func _helper_accepts(c: Dictionary, it: int, projected: Dictionary = {}) -> bool:
	if c.get("box") == null or K(it) == I.JI or not _accepts(c.box, it):
		return false
	var role := str(c.get("role", "sweep"))
	if role == "recipe":
		var target_kind := int(c.get("recipe", -1))
		if target_kind < 0 or find_kind(c.box.items, target_kind) >= 0:
			return false
		var missing := _helper_recipe_missing(c.box, target_kind)
		if int(missing.get(K(it), 0)) <= 0:
			return false
		var next: Array = c.box.items.duplicate()
		next.append(it)
		_merge_items(next)
		return _helper_recipe_reachable(next, target_kind)
	if _helper_item_value(it) <= 0.0:
		return false
	if role == "nutrition":
		return float(_item_nutrition(it).get(_nutrition_lacking(projected), 0.0)) > 0.0
	return true


func _helper_player_column(x: float) -> bool:
	return _hand != null and absf(x - _hand.pos.x) < _width() * 0.8 + 12.0


## Every helper box keeps its reservation from first collection until eating begins.
func _helper_box_count() -> int:
	var boxes: Array = []
	for c in _crew:
		if c.get("box") != null:
			boxes.append(c.box)
	for b in _queue + [_warm]:
		if b != null and b.get("crew", false):
			boxes.append(b)
	for flight in _flying:
		if flight.basin != null and flight.basin.get("crew", false):
			boxes.append(flight.basin)
	var unique: Array = []
	for b in boxes:
		if not unique.any(func(other): return is_same(other, b)):
			unique.append(b)
	return unique.size()


func _helper_box_budget() -> int:
	return maxi(3, hired.size())


func _pop_next_box() -> Dictionary:
	if _queue.is_empty():
		return {}
	if async_feed:
		for i in _queue.size():
			if not _queue[i].get("crew", false) and not _queue[i].get("takeout", false):
				var player_box: Dictionary = _queue[i]
				_queue.remove_at(i)
				return player_box
	return _queue.pop_front()


func _award_helper_relay(b: Dictionary) -> bool:
	if crew_relay <= 0.0 or not b.get("crew", false) or b.get("relay_checked", false):
		return false
	b["relay_checked"] = true
	var role := str(b.get("crew_role", "sweep"))
	var useful := 0
	var nutrition := {}
	for it in b.items:
		if is_ghost(it):
			continue
		if _helper_item_value(it) > 0.0 and (not PICKY[K(it)] or grok or _grokked):
			useful += maxi(_ingredients(K(it)).size(), 1)
		_add_projected_item(nutrition, it)
	var valid := role == "sweep" and useful >= 2
	if role == "recipe":
		valid = int(b.get("crew_recipe", -1)) >= 0 and b.items.any(func(it): return K(it) == int(b.crew_recipe) and not is_ghost(it))
	elif role == "nutrition":
		var supplied := 0.0
		var needed: Dictionary = b.get("crew_needed", {})
		for category in needed:
			supplied += minf(float(needed[category]), float(nutrition.get(category, 0.0)))
		valid = supplied >= 2.0
	if not valid or _helper_relay.has(role):
		return false
	_helper_relay[role] = true
	_helper_feedback(b.get("pos", FULL_AT), {"sweep": "补漏接力已备好", "recipe": "配餐接力已备好", "nutrition": "营养接力已备好"}[role])
	return true


func _consume_helper_relay(b: Dictionary) -> float:
	if b.get("crew", false) or b.get("takeout", false) or b.items.is_empty() or b.get("relay_consumed", false):
		return 0.0
	b["relay_consumed"] = true
	var bonus := _helper_relay.size() * crew_relay
	b["crew_relay_bonus"] = bonus
	_helper_relay.clear()
	if bonus > 0.0:
		_helper_feedback(b.get("pos", FULL_AT), tr("接力 +%d%%") % int(round(bonus * 100.0)))
	return bonus


func _helper_feedback(at: Vector2, message: String) -> void:
	if _t - _helper_feedback_at >= 2.5:
		_helper_feedback_at = _t
		_float(Vector2(clampf(at.x - 70, 60, 1730), clampf(at.y - 110, 550, 920)), message, "info")


func _helper_status(c: Dictionary) -> String:
	if c.state == "return":
		return tr("送餐中")
	if c.state == "fetch":
		return tr("等空位")
	return tr({"sweep": "补漏", "recipe": "配餐", "nutrition": "补营养"}.get(c.get("role", "sweep"), "补漏"))


func _draw_crew_layer() -> void:
	var font := ThemeDB.fallback_font
	for c in _crew:
		if c.box != null:
			_draw_basin_on(_crew_layer, c.box.pos, c.box, 0.6)
		elif c.spr.texture == c.sleep:
			var height: float = c.sleep.get_height() * c.spr.scale.y
			for j in 3:
				var phase := fmod(_t * 0.6 + j / 3.0 + c.rest * 0.001, 1.0)
				var at := Vector2(c.x + 20.0 + phase * 40.0, FLOOR_Y + 40 - height - 10.0 - phase * 60.0)
				_crew_layer.draw_string_outline(font, at, "z" if j < 2 else "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 18 + j * 6, 4, Color(0.1, 0.06, 0.04, 1.0 - phase))
				_crew_layer.draw_string(font, at, "z" if j < 2 else "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 18 + j * 6, Color(0.85, 0.9, 1.0, 1.0 - phase))
	# Compact, text-free task pins share the clear strip below the characters' feet.
	for tag in _helper_task_layout():
		var r: Rect2 = tag.rect
		var edge := Color("795133")
		for layer in [0, 1]:
			var face: Rect2 = r.grow(-float(layer) * 2.0)
			var radius := face.size.y * 0.5
			var color := edge if layer == 0 else Color("fff2d9")
			_crew_layer.draw_rect(Rect2(face.position + Vector2(radius, 0), Vector2(face.size.x - radius * 2, face.size.y)), color)
			_crew_layer.draw_circle(Vector2(face.position.x + radius, face.get_center().y), radius, color)
			_crew_layer.draw_circle(Vector2(face.end.x - radius, face.get_center().y), radius, color)
		draw_helper_role(_crew_layer, tag.role_rect, tag.role)
		if tag.recipe >= 0:
			_crew_layer.draw_texture_rect(_food_tex[tag.recipe], tag.recipe_rect, false)
		draw_helper_state(_crew_layer, tag.state_rect, tag.state)


## Read-only presentation layout: never moves a helper or swaps her assigned catch goal.
## Kept measurable so crossing helpers can be checked without a draw call. No labels or
## tethers: shape encodes the duty, the actual dish encodes an order, and a tiny state pin
## distinguishes collecting / delivering / waiting. The planner uses these exact glyphs.
func _helper_task_layout() -> Array:
	var ordered: Array = _crew.duplicate()
	ordered.sort_custom(func(a, b): return a.x < b.x if not is_equal_approx(a.x, b.x) else str(a.id) < str(b.id))
	var tags: Array = []
	for c in ordered:
		var recipe := int(c.get("recipe", -1)) if c.get("role", "sweep") == "recipe" else -1
		var width := 86.0 if recipe >= 0 else 58.0
		var x := clampf(float(c.x) - width * 0.5, 16.0, 1500.0 - width)
		if not tags.is_empty():
			x = maxf(x, float(tags[-1].rect.end.x) + 8.0)
		tags.append({"id": c.id, "role": str(c.get("role", "sweep")), "state": str(c.state), "recipe": recipe,
			"rect": Rect2(x, 1044, width, 32)})
	# Backward pass fits a crossing group near the table without squeezing its badges.
	var right := 1500.0
	for i in range(tags.size() - 1, -1, -1):
		var r: Rect2 = tags[i].rect
		r.position.x = minf(r.position.x, right - r.size.x)
		tags[i].rect = r
		right = r.position.x - 8.0
	for tag in tags:
		var r: Rect2 = tag.rect
		tag.role_rect = Rect2(r.position + Vector2(5, 3), Vector2(26, 26))
		tag.recipe_rect = Rect2(r.position + Vector2(33, 3), Vector2(26, 26)) if tag.recipe >= 0 else Rect2()
		tag.state_rect = Rect2(r.end.x - 21, r.position.y + 7, 14, 18)
	return tags


## Shared drawn legend: a receiving tray, an order ticket, and a three-part meal plate.
## No font glyphs, language-dependent letters or colour-only distinctions.
static func draw_helper_role(ci: CanvasItem, rect: Rect2, role: String) -> void:
	var unit := rect.size.x / 26.0
	var at := rect.position
	var ink := Color("66432b")
	var stroke := 1.8 * unit
	var accents := {"sweep": Color("e5bd77"), "recipe": Color("edc6a3"), "nutrition": Color("abc6a0")}
	ci.draw_circle(rect.get_center(), rect.size.x * 0.48, accents.get(role, Color("e5bd77")))
	match role:
		"recipe":
			var ticket := Rect2(at + Vector2(6, 3) * unit, Vector2(15, 20) * unit)
			ci.draw_rect(ticket, Color("fff8e8"))
			ci.draw_rect(ticket, ink, false, stroke)
			for row in 3:
				ci.draw_line(at + Vector2(9, 8 + row * 5) * unit, at + Vector2(18, 8 + row * 5) * unit, ink, stroke, true)
		"nutrition":
			var center := rect.get_center()
			ci.draw_circle(center, 9.0 * unit, Color("fff8e8"))
			ci.draw_arc(center, 9.0 * unit, 0, TAU, 24, ink, stroke, true)
			for angle in [-PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]:
				ci.draw_line(center, center + Vector2.from_angle(angle) * 9.0 * unit, ink, stroke, true)
		_:
			ci.draw_polyline(PackedVector2Array([at + Vector2(4, 14) * unit, at + Vector2(7, 21) * unit,
				at + Vector2(19, 21) * unit, at + Vector2(22, 14) * unit]), ink, stroke, true)
			ci.draw_line(at + Vector2(4, 14) * unit, at + Vector2(22, 14) * unit, ink, stroke, true)
			ci.draw_circle(at + Vector2(13, 8) * unit, 3.0 * unit, ink)
			ci.draw_line(at + Vector2(13, 3) * unit, at + Vector2(13, 1) * unit, ink, stroke, true)


static func draw_helper_state(ci: CanvasItem, rect: Rect2, state: String) -> void:
	var center := rect.get_center()
	var ink := Color("795133")
	var unit := minf(rect.size.x / 14.0, rect.size.y / 18.0)
	match state:
		"return":
			ci.draw_line(center + Vector2(-5, 0) * unit, center + Vector2(5, 0) * unit, ink, 2.2 * unit, true)
			ci.draw_polyline(PackedVector2Array([center + Vector2(0, -5) * unit, center + Vector2(5, 0) * unit, center + Vector2(0, 5) * unit]), ink, 2.2 * unit, true)
		"fetch":
			var points := PackedVector2Array([center + Vector2(-5, -6) * unit, center + Vector2(5, -6) * unit,
				center + Vector2(-5, 6) * unit, center + Vector2(5, 6) * unit, center + Vector2(-5, -6) * unit])
			ci.draw_polyline(points, ink, 1.8 * unit, true)
		_:
			ci.draw_circle(center, 3.4 * unit, ink)
			ci.draw_arc(center, 6.0 * unit, 0, TAU, 16, Color(ink, 0.5), 1.0 * unit, true)


## A helper's box catches food crossing its rim line (only boxes in the "catch" state).
func _crew_catch(p: Vector2, np: Vector2, v: Vector2, it: int, before := INF):
	var k := K(it)
	if v.y <= 0.0 or k == I.JI or _helper_player_column(np.x):
		return null
	var first = null
	var earliest := before
	for c in _crew:
		if c.state != "catch" or c.box == null:
			continue
		var trick: String = CREW[c.id].trick
		var hw := _width() * 0.6 * 0.47 * (1.5 if trick == "wide" else 1.0)
		var y: float = c.box.pos.y - (70.0 if trick == "jump" else 0.0)   # 小G hops up for it
		var contact := _swept_opening(p, np, Vector2(c.x, y), Vector2(c.x, y), hw + 5.0)
		if contact >= 0.0 and contact < earliest and _helper_accepts(c, it):
			earliest = contact
			first = c
	if first != null:
		if CREW[first.id].trick == "jump":
			first.hop = 0.35
		return first.box
	return null


## Helper tricks that act on food in the air (谱谱 pulls food in, 格格 swats the bad stuff away).
func _crew_tricks(p: Vector2, v: Vector2, it: int, delta: float, feedback := true) -> Vector2:
	var k := K(it)
	if _helper_player_column(p.x):
		return v
	for c in _crew:
		if c.state != "catch" or c.box == null:
			continue
		var by: float = c.box.pos.y
		var dx: float = c.x - p.x
		match CREW[c.id].trick:
			"magnet":
				if absf(dx) < 150.0 and p.y < by and by - p.y < 140.0 and v.y > 0.0 and _helper_accepts(c, it):
					var strength: float = (1.0 - absf(dx) / 150.0) * (1.0 - (by - p.y) / 140.0)
					v.x = move_toward(v.x, clampf(dx * 3.0, -PULL_MAX_SPEED, PULL_MAX_SPEED), PULL_ACCEL * strength * delta)
			"swat":
				# Greens are also recipe and training ingredients. Never bat them out of a build.
				if k == I.JI and absf(dx) < 80.0 and p.y < by and by - p.y < 60.0 and v.y > 0.0:
					v = Vector2(-signf(dx + 0.01) * 380.0, -420.0)
					if feedback:
						c.hop = 0.3
						Audio.sfx("bounce", -10.0)
	return v


## Floor pickups follow the same role/admission policy as airborne catches.
func _crew_floor(x: float, it: int) -> bool:
	if _helper_player_column(x):
		return false
	for c in _crew:
		if CREW[c.id].trick == "floor" and c.state == "catch" and c.box != null and absf(x - c.x) < 110.0 and _helper_accepts(c, it):
			_catch(c.box, it, false)
			c.hop = 0.25
			return true
	return false


## 本地小模型: distilled mini 大肥鱼. Each takes an empty box off the stack, runs about on the
## floor under where food will land, and brings the box back to the queue when it is full.
func _update_crew(delta: float) -> void:
	var floor_y := FLOOR_Y + 40
	var waiting: Array = _crew.filter(func(c): return c.state == "fetch" and c.box == null)
	for c in waiting:
		c.wait += delta
	waiting.sort_custom(func(a, b): return float(a.wait) > float(b.wait))
	for c in waiting:
		if float(c.wait) <= 0.6 or _helper_box_count() >= _helper_box_budget():
			continue
		c.wait = 0.0
		c.box = _new_basin(Vector2(c.x, floor_y - HELPER_BOX_Y))
		c.box["crew"] = true
		c.box["crew_id"] = c.id
		c.box["crew_role"] = c.get("role", "sweep")
		c.box["crew_recipe"] = c.get("recipe", -1)
		c.box["crew_needed"] = {}
		c.state = "catch"
		c["still"] = 0.0
		c["n"] = 0
	var plan := _plan_crew(floor_y - HELPER_BOX_Y)
	for c in _crew:
		var speed := HELPER_SPEED * helper_speed * (1.6 if CREW[c.id].trick == "fast" else 1.0)
		var goal: float = c.x
		match c.state:
			"fetch":
				# helpers bring their own boxes (they never take yours); with a long queue on the
				# table there is no hurry: she naps at her spot
				goal = c.rest
			"catch":
				goal = float(plan.get(c.id, c.x))
				if c.box.items.size() != int(c.n):
					c.n = c.box.items.size()
					c.still = 0.0
				c.still = float(c.still) + delta
				# full, or half full with nothing coming her way for a while: take it to the table
				if _helper_ready_to_deliver(c):
					c.state = "return"
					if c.get("role", "sweep") == "recipe":
						_helper_feedback(c.box.pos, "订单完成")
			"return":
				goal = FULL_AT.x - 60
				if absf(c.x - goal) < 8.0:
					_flying.append({"from": Vector2(c.x, floor_y - HELPER_BOX_Y), "to": _table_slot(_queue.size() + _flying.size()), "t": 0.0, "basin": c.box})
					c.box = null
					c.state = "fetch"
					c.hop = 0.3
					Audio.sfx("box_return", -10.0)
		var step := clampf(goal - c.x, -speed * delta, speed * delta)
		c.x += step
		c.hop = maxf(c.hop - delta, 0.0)
		var moving := minf(absf(step) / maxf(speed * delta, 0.001), 1.0)
		var lift: float = absf(sin(_t * 14.0 + c.x * 0.01)) * 7.0 * moving + sin(c.hop / 0.35 * PI) * 46.0 * float(c.hop > 0.0)
		var spr: Sprite2D = c.spr
		var asleep: bool = c.state == "fetch" and c.box == null and _helper_box_count() >= _helper_box_budget() and absf(c.x - c.rest) < 8.0
		if c.box != null and int(c.box.get("made", 0)) > int(c.get("seen", 0)):
			c.seen = int(c.box.made)
			c.cheer = 0.7   # her box made a 套餐
		c.cheer = maxf(float(c.get("cheer", 0.0)) - delta, 0.0)
		var tex: Texture2D = c.awake
		if asleep:
			tex = c.sleep
		elif c.cheer > 0.0 and c.cheer_tex != null:
			tex = c.cheer_tex
		elif moving > 0.5 and c.run_tex != null:
			tex = c.run_tex
		spr.texture = tex
		spr.offset = Vector2(-spr.texture.get_width() * 0.5, -spr.texture.get_height())
		spr.position = Vector2(c.x, floor_y - lift)
		if step < -0.5:
			spr.flip_h = true
		elif step > 0.5:
			spr.flip_h = false
		var k := CREW_H / (c.awake as Texture2D).get_height()   # sleep art is made at the awake art's scale
		var sq := 1.0 + sin(_t * 28.0) * 0.03 * moving   # a little squash as she runs
		if asleep:
			sq = 1.0 + sin(_t * 2.0 + c.rest) * 0.02   # slow sleepy breathing
		spr.scale = Vector2(k / sq, k * sq)
		if c.box != null:
			c.box.pos = Vector2(c.x, floor_y - lift - HELPER_BOX_Y)


## Where each catching helper should stand, planned for all of them at once (id -> x):
## the food that will cross their box height is shared out (the best catch per helper first, one
## helper per piece), they keep a box apart from each other, and nobody stands under the
## player's box: what falls there is the player's.
func _plan_crew(y: float) -> Dictionary:
	var helpers: Array = _crew.filter(func(c): return c.state == "catch" and c.box != null)
	var plan := {}
	if helpers.is_empty():
		return plan
	var gap := _width() * 0.6 + 12.0
	var food: Array = []
	for i in _fp.size():
		var p := _fp[i]
		var it := int(_fk[i])
		if p.y > y or K(it) == I.JI:
			continue
		var time := _time_to(i, y)
		var x := p.x + _fv[i].x * time
		if not is_finite(time) or time > 1.6 or x < 60.0 or x > 1400.0 or _helper_player_column(x):
			continue
		food.append({"x": x, "time": time, "item": it, "index": i})
	var taken: Array = []
	var free: Array = helpers.duplicate()
	var projected := _projected_nutrition()
	while not free.is_empty() and not food.is_empty():
		var best_score := -1.0
		var selected: Dictionary = {}
		var dish: Dictionary = {}
		for c in free:
			var speed := HELPER_SPEED * helper_speed * (1.6 if CREW[c.id].trick == "fast" else 1.0)
			for f in food:
				if (float(f.time) + 0.1) * speed < absf(float(f.x) - c.x):
					continue
				if taken.any(func(tx): return absf(tx - float(f.x)) < gap) or not _helper_accepts(c, int(f.item), projected):
					continue
				var worth := _helper_item_value(int(f.item)) + 0.5
				if c.get("role", "sweep") == "recipe":
					worth += 10.0
				elif c.get("role", "sweep") == "nutrition":
					worth += 6.0
				var score: float = worth / (1.0 + absf(float(f.x) - c.x) / speed)
				if score > best_score:
					best_score = score
					selected = c
					dish = f
		if selected.is_empty():
			break
		plan[selected.id] = float(dish.x)
		taken.append(float(dish.x))
		free.erase(selected)
		_add_projected_item(projected, int(dish.item))
		food = food.filter(func(f): return absf(float(f.x) - float(dish.x)) >= gap * 0.5)
	# Idle helpers may wait beneath a relevant window, but never exchange the assigned
	# catch positions to preserve left/right order. Each goal stays with its own recipe.
	for c in free:
		var pick: float = c.x
		var nearest := INF
		var spots: Array = []
		for arm in _arms:
			if arm.has("dish") and _helper_accepts(c, int(arm.dish), projected):
				for offset in [0.0, gap, -gap]:
					spots.append([clampf(float(arm.x) + offset, 60.0, 1400.0), maxf(float(arm.t), 0.0) * 60.0])
		spots.append([c.x, 500.0])
		for slot in 10:
			spots.append([60.0 + slot * (1340.0 / 9.0), 600.0])
		for spot in spots:
			var x: float = spot[0]
			if _helper_player_column(x) or taken.any(func(tx): return absf(tx - x) < gap):
				continue
			var distance: float = absf(x - c.x) + float(spot[1])
			if distance < nearest:
				nearest = distance
				pick = float(x)
		plan[c.id] = pick
		taken.append(pick)
	return plan


func _helper_ready_to_deliver(c: Dictionary) -> bool:
	if c.box.items.is_empty():
		return false
	if c.get("role", "sweep") == "recipe":
		return find_kind(c.box.items, int(c.get("recipe", -1))) >= 0
	return _space(c.box) >= _cap() or (_space(c.box) * 2 >= _cap() and float(c.get("still", 0.0)) > 4.0) or float(c.get("still", 0.0)) > 9.0


## Spots `xs` moved as little as possible to lie within lo..hi and at least `gap` apart, sorted.
static func _spread(xs: Array, lo: float, hi: float, gap: float) -> Array:
	var g: Array = xs.duplicate()
	g.sort()
	for i in g.size():
		g[i] = clampf(g[i], lo, hi)
	for i in range(1, g.size()):
		g[i] = maxf(g[i], g[i - 1] + gap)
	for i in range(g.size() - 2, -1, -1):
		g[i] = minf(g[i], g[i + 1] - gap)
	if not g.is_empty() and g[-1] > hi:
		var d: float = g[-1] - hi
		for i in g.size():
			g[i] -= d
	if not g.is_empty() and g[0] < lo:   # too many for the room: share it out evenly
		for i in g.size():
			g[i] = lerpf(lo, hi, float(i) / maxf(g.size() - 1, 1))
	return g



## `wdt` is world time; she eats and chews in `delta` (real time while you think, with 边想边用工具).
func _update_fish(wdt: float, delta: float) -> void:
	_meal_visual.advance(delta)
	_chew_pause = maxf(_chew_pause - delta, 0.0)
	_fish.belly = 0.12 * (1.0 - exp(-float(eaten) / 160.0))   # rounder and rounder, no limit
	if _eating == null and not _queue.is_empty():
		_eating = _pop_next_box()
		_start_box(_eating)
		Audio.vo("fish_dig_in", 1, 0.35)
		_dig_in = 0.55
		_fish.play("dig_in")
		if _wait >= 6.0:   # (a bubble every box would be noise)
			_say("终于来了！开炫！")
		Audio.sfx("chomp", -4.0)
		_wait = 0.0
	if _eating == null:
		if _learning():
			return   # let the player learn without impatient barks or a growing wait penalty
		fish_wait += wdt
		_wait += wdt
		_crave_t += wdt
		# waiting: hopeful, then begging, then sulking (docs/fish_actions_design.md); with
		# 服务器繁忙 that is the 馋 meter
		var mood := "basin" if _wait < 3.0 else ("bang" if _wait < 10.0 else "sulk")
		if _thinking:
			mood = "think"
		if _fish.clip != mood and _fish.clip not in ["surprised", "happy", "dig_in"]:
			_fish.play(mood, true)
			if mood == "bang":
				_say("饭呢？饭呢？")
				Audio.vo("fish_bang", 1)
			elif mood == "sulk":
				_say("哼！不理你了")
				Audio.sfx("helmet", -4.0)
				Audio.vo("fish_hmph", 2)
			elif mood == "basin" and _wait > 1.0:
				Audio.vo("fish_wait", 0, 0.4)
		return
	if _dig_in > 0.0:
		_dig_in -= delta
		if _dig_in <= 0.0:
			_fish.play("slurp", true)
		return
	if _chew_pause > 0.0:
		return
	if _fish.clip != "slurp" and _fish.clip not in ["spit", "yum", "think", "grimace", "grok"]:
		_fish.play("slurp", true)
	_eat_acc += eat_rate * delta
	var gained := 0.0
	while not _eating.items.is_empty() and _eat_acc >= EAT[K(_eating.items[0])]:
		var origin := _boxed_item_origin(_eating, 0, EAT_AT, 0.55)
		var it: int = _eating.items.pop_front()
		var k := K(it)
		_meal_visual.consume(it, origin, (PICKY[k] and not _grokked and not grok) or k == I.JI)
		_eat_acc -= EAT[k]
		if PICKY[k] and not _grokked:
			if not grok:
				if _journal != null:
					_journal.count("rejected", it, self)
				_chew_pause = 0.8
				_fish.play("spit")
				_say("挑食！不吃青菜！")
				Audio.sfx("veg_reject", -8.0)   # the buzz: "rejected" (user: keep it, it reads like an error)
				Audio.vo("fish_spit", 2)
				break
			# 顿悟: she forces it down (no tokens), and one day she gets it
			_chew_pause = 0.5
			_grok_n += 1
			if _journal != null:
				_journal.count("training_eaten", it, self)
			_cat["素"] = float(_cat["素"]) + 1.0
			_fish.play("grimace")
			Audio.vo("fish_grimace", 1)
			_say("……咽下去了")
			if _grok_n >= grok_need:
				_grokked = true
				if _journal != null and float(_journal.data.first_grok_seconds) < 0.0:
					_journal.data.first_grok_seconds = _meal_elapsed()
				_fish.play("grok")
				Audio.vo("fish_grok", 3)
				_say("原来青菜这么好吃！")
				_banner("顿悟！", tr("青菜从现在起很值钱"), "leaf")
				Audio.sfx("version_up", -3.0)
			break
		if k == I.JI:
			_eating.items.clear()
			_chew_pause = 1.0
			_fish.play("spit")
			break
		gained += _bite(it, _eating.get("mult", 1.0), true)
		if TIER[k] >= 3 or grade(it) == 2:
			Audio.vo("fish_bliss", 2, 0.8)   # something really good
		elif IS_SET[k] or VALUE[k] >= 5.0:
			Audio.vo("fish_savor", 1, 0.45)
		else:
			Audio.vo("fish_munch", 0, 0.06)
		if IS_SET[k] or VALUE[k] >= 5.0 or grade(it) == 2:
			_fish.play("yum")
	if gained > 0.0:
		_credit(gained)
		_rule_income += gained * float(_eating.get("rule_share", 0.0))
		_eating["earned"] = float(_eating.get("earned", 0.0)) + gained
	if _eating.items.is_empty():
		_box_vals.append(float(_eating.get("earned", 0.0)))
		if not _eating.get("takeout", false) and not _eating.get("crew", false):   # takeout and helper boxes are not yours to get back
			_flying.append({"from": EAT_AT, "to": STACK_AT + Vector2(0, -10.0 * _empty), "t": 0.0, "basin": null})
			Audio.sfx("box_return", -10.0)
		_eating = null
		_eat_acc = 0.0
		_fish.play("basin", true)


## Tokens of one bite: (its value + MTP) x 越吃越香 x a crit x the box multiplier x 全局, and the
## bookkeeping of what she ate. `live` false: counted at closing time (no 越吃越香 for 我去睡了).
func _bite(it: int, box_mult: float, live: bool) -> float:
	var k := K(it)
	if _journal != null:
		var phase := "live" if live else _journal_bite_phase
		_journal.count("paid_eaten", it, self, phase)
		_journal.data.paid_bites[phase] += 1
	eaten += FILL[k]
	_bites += 1
	var cats: Dictionary = CATS[k]
	if k == I.VEG and drift:
		cats = {"素": 0.5, "荤": 0.5}
	for cn in cats:
		_cat[cn] = float(_cat.get(cn, 0.0)) + float(cats[cn])
	_cat["素"] = float(_cat["素"]) + injected(it)
	if IS_SET[k]:
		_kinds_eaten[k] = true
	var crit := randf() < crit_chance
	var v := _item_value(it) + mtp + _sig_value(k)
	var got := v * (_stream_mult() if live else 1.0) * box_mult * _g
	if crit:
		got *= crit_mult + (hot_x - 1.5)   # 中午吃什么 counts as a random touch: 高温 adds to it
		if live:
			_float(FISH_POS + Vector2(-260, -440), tr("暴击 ×%.1f") % (crit_mult + (hot_x - 1.5)), "crit")
			Audio.vo("fish_crit", 1, 0.6)
			Audio.sfx("crit", -4.0)
			_fish.play("yum")
	if live:
		Audio.sfx("chomp", -8.0)
	return got


func _credit(gained: float) -> void:
	earned += gained
	_base += gained
	Game.add_tokens(gained)
	_token_pop += gained
	if _token_pop >= 4.0:
		_float(FISH_POS + Vector2(randf_range(-220, -140), -400), "+%s" % Game.fmt(_token_pop), "money")
		Audio.sfx("token", -10.0)
		_token_pop = 0.0


## A box reaches her: its multiplier = (1 + its +% pool) x 馋 x 连击 (docs/tree_model.md §2.2).
func _start_box(b: Dictionary) -> void:
	var m := 1.0 + box_bonus
	if b.get("full", false):
		m += fill_bonus
	m += cot * mini(int(b.get("chains", 0)), 3)
	var rule_add := _box_rule_bonus(b)
	m += rule_add
	b["rule_share"] = rule_add / m
	var h := 1.0
	var crew_box: bool = b.get("crew", false)
	if crave > 0.0:
		if crew_box and async_feed:
			pass   # 异步调用: the helpers' boxes don't use up her 馋
		else:
			h = _crave_x(_crave_t)
			_crave_t = 0.0
	var c: float = b.get("chain_multiplier", 1.0)
	b["mult"] = m * h * c
	if _journal != null:
		_journal.box("eat_start", b, self)
	if h >= 1.3:
		_float(FISH_POS + Vector2(-250, -330), "馋 ×%.1f" % h, "mult")


func _crave_x(t: float) -> float:
	return 1.0 + crave * (1.0 - exp(-t / crave_tau)) if crave > 0.0 else 1.0


func _combo_cap() -> int:
	return COMBO_CAP[mini(Game.version, COMBO_CAP.size() - 1)]


## 流式输出: grows fast at first, then levels off (log2: x2 bites -> one more step).
## 首 Token 延迟: nothing for the first stream_from bites; capped by the 上下文窗口.
func _stream_mult() -> float:
	var x := 1.0 + stream * log(1.0 + maxf(_bites - stream_from, 0) / 20.0) / log(2.0)
	return minf(x, STREAM_CAP[mini(Game.version, STREAM_CAP.size() - 1)])


## 招牌菜: extra value of one bite of kind k (a 套餐 counts each 招牌菜 in it), and the
## running counts (stack) and the balance bonus they give.
func _sig_value(k: int) -> float:
	if _sigs.is_empty():
		return 0.0
	var parts := _ingredients(k)
	var extra := 0.0
	for d in parts:
		if not _sigs.has(d):
			continue
		var e: Dictionary = _sigs[d]
		var n := int(_sig_count.get(d, 0))
		if e.has("stack"):   # capped by the 上下文窗口 (it used to grow without end)
			extra += maxf(VALUE[d], 1.0) * minf(float(e.stack) * n, SIG_CAP[mini(Game.version, SIG_CAP.size() - 1)])
		if e.has("mult"):
			extra += maxf(VALUE[d], 1.0) * (float(e.mult) - 1.0)
		if e.has("balance"):
			_sig_balance += float(e.balance)
		_sig_count[d] = n + 1
	_sig_bonus += extra
	return extra


## The basic dishes in kind k (a 套餐 is opened up, recursively).
func _ingredients(k: int) -> Array:
	if not IS_SET[k]:
		return [k]
	for r in RECIPES:
		if r.result == k:
			var out: Array = []
			for need in r.needs:
				out.append_array(_ingredients(need))
			return out
	return [k]


## 均衡倍率: 1 when she ate one kind only, balance_max at 主 : 荤 : 素 = 4 : 3 : 3 (+ 招牌菜 bonus).
func balance_score() -> float:
	var tot: float = _cat["主"] + _cat["荤"] + _cat["素"]
	if tot <= 0.0:
		return 0.0
	var off: float = absf(_cat["主"] / tot - 0.4) + absf(_cat["荤"] / tot - 0.3) + absf(_cat["素"] / tot - 0.3)
	return clampf(1.0 - off / 1.2, 0.0, 1.0)   # 1.2 = eating only 主食


## 美食评鉴: + critic per kind of 套餐 she ate this shift, from the 5th kind on.
func review_mult() -> float:
	return 1.0 + critic * maxi(_kinds_eaten.size() - 4, 0)


func balance_mult() -> float:
	var curve := 1.2 if Game.stat("constit") > 0.0 else 1.5   # 宪法 AI: nearly balanced counts more
	return 1.0 + (balance_max - 1.0) * pow(balance_score(), curve) + minf(_sig_balance, 0.5)   # 招牌菜 add at most +0.5


## 吃饱躺平: closing time on a full belly, she slides down behind the table and flops onto it,
## flat on her back (fatfish/lie_full.png, also on the result card).
func _flop() -> void:
	var lie := Sprite2D.new()
	lie.texture = load("res://assets/fatfish/lie_full.png")
	lie.z_index = 1
	lie.scale = Vector2.ONE * (TABLE.size.x * 0.8 / lie.texture.get_width())
	var at := Vector2(TABLE.get_center().x, TABLE.position.y - 25.0)   # her back on the table top
	lie.position = at + Vector2(0, -90)
	lie.modulate.a = 0.0
	add_child(lie)
	var tw := create_tween()
	tw.tween_property(_fish, "position:y", _fish.position.y + 120.0, 0.25).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_fish, "modulate:a", 0.0, 0.25)
	tw.tween_property(lie, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(lie, "position", at, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Audio.sfx("deliver", -6.0))   # thud on the table


## Remaining real boxes, including a box submitted just before closing but still in flight.
## Warm storage has its own settlement. A shared reference can only be eaten once.
func _leftover_boxes(settled: Array = []) -> Array:
	var candidates: Array = _queue.duplicate()
	candidates.append_array([_eating, _hand])
	for flight in _flying:
		candidates.append(flight.basin)
	for c in _crew:
		candidates.append(c.box)
	var boxes: Array = []
	for box in candidates:
		if box != null and not is_same(box, _warm) and not box.items.is_empty() and not settled.any(func(known): return is_same(known, box)) and not boxes.any(func(known): return is_same(known, box)):
			boxes.append(box)
	return boxes


## Ends the shift: "吃饱了！", "食堂关门了", "提前下班" (pause menu) or, in a trial, "新年快乐！"
## (passed) / "宕机了……". `card` false skips the result card (leaving for the title).
func _end(reason: String, card_too := true) -> void:
	if _ended:
		return
	_ended = true
	_cancel_touch()
	_meal_visual.clear()
	if is_instance_valid(_coach):
		_coach.close()
	_end_reason = reason
	_interrupt_thinking()
	Audio.settle()
	# closing time (docs/tree_model.md §2.2, docs/settlement_design.md): everything is counted
	# here at once (so nothing is lost if the player skips or quits); the checkout receipt then
	# plays it back step by step from `_steps`. Order: the 保温箱 box (and its <EOS> last bite),
	# 我去睡了, 梯度裁剪, then the meal multipliers 均衡 and 美食评鉴. Earnings are never capped.
	_score = {"base": _base}
	var meal := earned   # what she ate during the shift
	var warm_step := {}
	var eos_step := {}
	var settled: Array = []
	if _warm != null:
		var wb: Dictionary = _warm
		if _journal != null:
			_journal.box("warm_settled", wb, self)
		_journal_bite_phase = "warm"
		_warm = null
		settled.append(wb)
		var mult := (1.0 + box_bonus + (fill_bonus if wb.get("full", false) else 0.0) + cot * mini(int(wb.get("chains", 0)), 3) + _box_rule_bonus(wb))
		var rule_share := _box_rule_bonus(wb) / mult
		mult *= _crave_x(INF) * float(wb.get("chain_multiplier", 1.0)) * warm_x
		# <EOS>: she keeps the best bite of the box for last, and it counts again
		var best := -1
		for i in wb.items.size():
			var it: int = wb.items[i]
			if (K(it) != I.VEG or _grokked) and (best < 0 or _item_value(it) > _item_value(wb.items[best])):
				best = i
		var got := 0.0
		var best_got := 0.0
		for i in wb.items.size():
			var it: int = wb.items[i]
			if K(it) == I.VEG and not _grokked:
				continue
			var b := _bite(it, mult, false) * _stream_mult()
			got += b
			if i == best:
				best_got = b
		_credit(got)
		_rule_income += got * rule_share
		_score["warm"] = got
		warm_step = {"icon": "clock", "text": tr("揭开保温箱"), "mark": "×%.0f" % warm_x, "add": got, "sfx": "version_up"}
		var ex: float = EOS_X[clampi(int(Game.stat("eos")), 0, EOS_X.size() - 1)]
		if best >= 0 and ex > 1.0:
			var extra := best_got * (ex - 1.0)
			_credit(extra)
			_rule_income += extra * rule_share
			_score["eos"] = extra
			var k := K(wb.items[best])
			eos_step = {"icon": "crown", "text": tr("最后一口：%s") % tr(NAMES[k]), "mark": "×%.0f" % ex, "add": extra,
				"dish": _food_tex[k], "dish_name": tr(NAMES[k])}
	var boxes := _leftover_boxes(settled)
	_journal_bite_phase = "sleep"
	var left_step := {}
	if not boxes.is_empty():
		var left := 0.0
		var worth := 0.0
		for bx in boxes:
			for it in bx.items:
				if K(it) != I.VEG or _grokked:
					worth += _item_value(it)
					if sleep_eat:
						left += _bite(it, 0.5, false)
		if sleep_eat:   # eaten in her dreams: the boxes are empty now, the one in hand is put down
			for bx in boxes:
				bx.items.clear()
			_hand = null
		if sleep_eat and left > 0.0:
			_credit(left)
			_score["sleep"] = left
			left_step = {"icon": "box", "text": tr("梦里吃掉 %d 盒") % boxes.size(), "add": left, "sleep": true}
		elif worth > 0.0:
			left_step = {"icon": "box", "text": tr("没吃完 %d 盒：浪费了约") % boxes.size(), "lost": worth}
	if clip and _box_vals.size() >= 5:
		var vals: Array = _box_vals.duplicate()
		vals.sort()
		var avg := 0.0
		for x in vals:
			avg += x
		avg /= vals.size()
		var lift := 0.0
		for i in int(vals.size() * 0.2):
			lift += maxf(avg - vals[i], 0.0)
		if lift > 0.0:
			_credit(lift)
			_score["clip"] = lift
	var steps: Array = [{"icon": "token", "text": tr("这顿吃的：%d 份") % eaten, "add": meal}]
	if _sig_bonus > 0.0:
		steps.append({"note": tr("其中招牌菜"), "add": _sig_bonus})
	if _rule_income > 0.0:
		steps.append({"note": tr("其中搭配 / 接力加成"), "add": _rule_income})
	for st in [left_step, warm_step, eos_step]:
		if not st.is_empty():
			steps.append(st)
	if _score.has("clip"):
		steps.append({"icon": "shield", "text": tr("最差的几盒按平均算"), "add": _score.clip})
	var subtotal := earned
	var bm := balance_mult()
	var jm := review_mult()
	var bonus := earned * (bm * jm - 1.0)
	if bonus > 0.0:
		earned += bonus
		Game.add_tokens(bonus)
	_score["balance"] = bm
	_score["review"] = jm
	var mults: Array = [[tr("均衡"), bm]]
	if critic > 0.0:
		mults.append([tr("评鉴"), jm])
	var extra := ""
	if trial != "":
		passed = earned >= target and reason != "提前下班"
		if passed:
			Game.pass_trial()
			extra = tr("%s 发布！获得 %s") % [tr(Game.plate()), tr(Game.VERSIONS[Game.version].get("reward", ""))]
		else:
			Game.fail_trial(trial)
			extra = tr("评测没过：差 %s token（门票已花掉，随时可以再来）") % Game.fmt(maxf(target - earned, 0.0))
	Audio.sfx("trial_pass" if passed else ("shift_closed" if trial == "" else "trial_fail"), -3.0)
	Audio.ambience("")
	var full := passed or reason == "食堂关门了"
	if full:
		_flop()
	else:
		_fish.play("beg", true)
	Audio.vo("fish_full" if full else "fish_broke", 3)
	if passed:
		Audio.vo("auntie_laugh", 2)
	Game.runs += 1
	var record := earned > Game.best_run
	var stuffed := full and Game.best_run > 0.0 and earned >= Game.best_run * 2.0
	Game.best_run = maxf(Game.best_run, earned)
	Game.record_run({"earned": earned, "eaten": eaten, "caught": caught, "spilled": spilled,
		"wasted": wasted, "recipes": _recipes_made, "balance": bm, "grokked": _grokked,
		"trial": trial, "passed": passed, "full_boxes": _full_boxes})
	Game.save_game()
	if _journal != null:
		_journal.finish(self, subtotal)
		if not Game._save_read_only:
			var journal_error: Error = _journal.save_record(Game.save_path.get_basename() + "_meals")
			if journal_error != OK:
				push_warning("Local meal record could not be saved: %s" % error_string(journal_error))
	if not card_too:
		return
	await get_tree().create_timer(1.0).timeout
	var card := CheckoutReceipt.new()
	_checkout = true
	card.title = reason
	card.heading = tr("第 %d 顿 · 结账") % Game.runs
	card.sub = "%s · %s %s" % [tr(Game.plate()), _clock_text(), tr(reason)]
	card.steps = steps
	card.subtotal = subtotal
	card.mults = mults
	card.total = earned
	card.target = target
	card.passed = passed
	card.record = record
	card.stuffed = stuffed
	card.extra = extra
	card.sleeping = full and _score.has("sleep")
	card.fast = autotest
	card.closed.connect(func(): finished.emit(earned))
	add_child(card)
	card_shown.emit()
	if autotest:   # leave the receipt up briefly, then carry on
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(card):
			card.closed.emit()


## How the shift went, for the autotest log.
func trial_log() -> String:
	var t := "目标 %s，%s" % [Game.fmt(target), "过了" if passed else "没过"] if trial != "" else ""   # notr
	return "%s均衡 %d%% ×%.2f，评鉴 %d 种 ×%.2f，保温箱 +%s，顿悟 %s，连击 %d" % [t + "，" if t != "" else "", int(balance_score() * 100), balance_mult(), _kinds_eaten.size(), review_mult(), Game.fmt(float(_score.get("warm", 0.0))), "是" if _grokked else "否", _combo_n]   # notr


func catch_rate() -> float:
	return float(caught) / maxf(caught + wasted, 1)


func _clock_text() -> String:
	var m := 11 * 60 + 30 + int(minf(_meal_elapsed(), meal_time))
	return "%02d:%02d" % [m / 60, m % 60]


func _say(text: String) -> void:
	_bark = tr(text)
	_bark_t = 1.6


func _text(pos: Vector2, text: String, _color: Color) -> void:
	_float(pos, text, "info")


# --- bot (autotest) ---------------------------------------------------------------------------

func _bot_think() -> bool:
	if legacy == "hybrid":   # think only in a hard round, while a 难题 is in the air
		return _hard and _think > 0.2 and Array(_fk).has(I.Q)
	return _fp.size() > 18 and _think > 0.5

func _bot() -> void:
	if _hand == null:
		_aim = _aim.move_toward(STACK_AT, 90.0)   # go and take a box off the stack
		if TABLE.grow(60).has_point(_aim) and _empty > 0:
			_try_deliver()
		return
	if find_kind(_hand.items, I.JI) >= 0:   # shake the 「极」 out
		var x := clampf(_hand.pos.x, 400.0, 1300.0)
		_aim = Vector2(x + (300.0 if int(_t * 6.0) % 2 == 0 else -300.0), _hand.pos.y)
		return
	var fill := float(_space(_hand)) / _cap()
	var fish_idle := _eating == null and _queue.is_empty()
	if fill >= 0.85 or (fill >= 0.35 and fish_idle and crave <= 0.0):
		# the 保温箱 gets a box better than the one in it (unless Best-of-N does it anyway)
		var to_warm := warm and not best_of_n and fill >= 0.85 and (_warm == null or _box_worth(_hand) > _box_worth(_warm)) and _t > meal_time * 0.3
		var goal := WARM_AT if to_warm else TABLE.get_center()
		_aim = _hand.pos.move_toward(goal, 90.0)   # a gentle carry
		if (to_warm and WARM_RECT.has_point(_hand.pos)) or (not to_warm and TABLE.grow(60).has_point(_hand.pos)):
			_try_deliver()
		return
	var y := 780.0
	var bins := {}
	var close := _closest_recipe(_hand.items)
	var wanted: Array = close[1] if not close.is_empty() else []
	for i in _fp.size():
		var p := _fp[i]
		var v := _fv[i]
		var fk := K(_fk[i])
		if p.y > y or (fk == I.VEG and not (grok or inject)):
			continue
		var t := _time_to(i, y)
		if t > 1.0:
			continue
		var b := int((p.x + v.x * t) / 60.0)
		var worth: float = VALUE[fk] * _grade_x(_fk[i]) + 0.5 + (6.0 if fk in wanted else 0.0)
		if fk == I.VEG:
			worth = 3.0
		if fk == I.Q:
			worth = 30.0
		elif fk == I.JI:   # keep clear of a 「极」 (it hops, so give it room)
			for d in [-2, -1, 1, 2]:
				bins[b + d] = float(bins.get(b + d, 0.0)) - 6.0
			worth = -12.0
		bins[b] = float(bins.get(b, 0.0)) + worth
	var best := -1
	var best_n := 0.0
	for b in bins:
		if bins[b] > best_n:
			best_n = bins[b]
			best = b
	if best >= 0:
		_aim = Vector2(best * 60.0 + 30.0, y)
	else:
		var next = null
		for a in _arms:
			if next == null or a.t < next.t:
				next = a
		if next != null:
			_aim = Vector2(next.x, y)


# --- drawing --------------------------------------------------------------------------------------

func _draw_back() -> void:
	_back.draw_texture(_bg, Vector2.ZERO)
	# The counter's open middle reveals her face while its front hides her lower body.
	var tex: Texture2D = _auntie[_mood()]
	var bob := 0.0 if Settings.reduced_motion else sin(_t * 3.0) * 4.0
	var art_size := tex.get_size() * 0.78
	_back.draw_texture_rect(tex, Rect2(AUNTIE_AT + Vector2(-art_size.x * 0.5, bob - art_size.y), art_size), false)


## A trial is close to failing: the floor pile, the users' patience or the spoiled boxes.
func _in_trouble() -> bool:
	match trial:
		"spring": return float(_pile.size()) / pile_max > 0.7
		"hybrid": return sat < 30.0
		"ji": return ji_hits >= ji_max - 1
	return false


## The counter, and on each working window's name plate a cooking bar: it fills while she cooks
## and flashes when the food is about to fly (rush hour: red and fast).
func _draw_front() -> void:
	if _counter_long == null:
		_front.draw_texture(_counter, COUNTER_AT)
	else:
		_front.draw_texture_rect(_counter_long, COUNTER_RECT, false)
	for id in stall_order:
		var pans := stall_pans(id)
		var lv: int = stall_lv.get(id, 0)
		if lv <= 0:   # not serving yet: empty pans, a little darker
			var x0: float = pans[0] - PAN_W * 0.5
			var x1: float = pans[pans.size() - 1] + PAN_W * 0.5
			_front.draw_rect(Rect2(x0, PAN_Y - 26.0, x1 - x0, 58.0), Color(0.05, 0.03, 0.02, 0.28))
			continue
		# open: its dishes heaped in its pans (each pan one dish of its menu, round and round), steaming
		var menu: Array = []
		for k in NAMES.size():
			if STALL[k] == id and LEVEL[k] <= lv and not IS_SET[k]:
				menu.append(k)
		for j in pans.size():
			if menu.is_empty():
				break
			var k: int = menu[(j + int(id.hash()) % 3) % menu.size()]
			var x: float = pans[j]
			var faded := struck.has(k)
			var col := Color(1, 1, 1, 0.35) if faded else Color.WHITE
			for h in 3:   # a little heap
				var at := Vector2(x + [-22.0, 20.0, 0.0][h], PAN_Y + [4.0, 6.0, -8.0][h])
				_draw_food_tinted(_front, k, at, [-0.2, 0.25, 0.0][h], 44.0 / SIZE_PX[k], col)
			if not faded:   # steam
				for p in 2:
					var ph := fmod(_t * 0.5 + j * 0.37 + p * 0.5 + id.length() * 0.13, 1.0)
					_sprite(_front, "fx_steam", Vector2(x + sin(ph * 6.0 + j) * 8.0, PAN_Y - 24.0 - ph * 60.0), 24.0 + ph * 26.0, sin(ph * 4.0 + j) * 0.2, Color(1, 1, 1, 0.42 * (1.0 - ph) * minf(ph * 5.0, 1.0)))
	if is_instance_valid(_service_ui):
		_service_ui.draw_stalls(_front)
	_draw_announcement(_front)


## 梁阿姨's face for the moment.
func _mood() -> String:
	if trial != "" and _ended and not passed:
		return "panic"
	if trial != "" and not _ended and earned < target * clampf(_t / meal_time, 0.0, 1.0) * 0.6:
		return "panic"   # the 评测 is going badly
	if _ended:
		return "happy"
	if _peak_on:
		return "busy"
	if _shaky_t > 0.0:
		return "shaky"
	return "normal"


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# a darker floor strip, so the bottom HUD line reads
	draw_rect(Rect2(0, FLOOR_Y, 1920, 1080 - FLOOR_Y), Color(0.06, 0.04, 0.03, 0.6))
	# the table in front of 大肥鱼
	draw_texture_rect(_table, Rect2(TABLE_AT, _table.get_size() * TABLE_SCALE), false)
	# a wooden tray for the empty boxes (left), a red serving tray for the full ones (right)
	_sprite(self, "tray_empty", STACK_AT + Vector2(0, 30), 170.0)
	_sprite(self, "tray_full", FULL_AT + Vector2(0, 30), 170.0)
	# the stack of empty boxes, then the queue of full ones
	for i in _empty:
		_draw_basin(STACK_AT + Vector2(0, -11.0 * i), _new_basin(Vector2.ZERO), 0.0, 0.48, font, false)
	if _empty > 1:
		_count_tag(STACK_AT + Vector2(70, 18), _empty)
	if _hand == null and _empty > 0 and not _ended:
		# empty hands and a box to take: a warm glow under the stack, a hand bobbing over it
		var pulse := 0.5 if Settings.reduced_motion else 0.5 + 0.5 * sin(_t * 6.0)
		var top := STACK_AT + Vector2(0, -11.0 * (_empty - 1))
		_glow(self, top + Vector2(0, 6), 230.0, Color(1.0, 0.85, 0.4, 0.35 + 0.3 * pulse), 0.55)
		_sprite(self, "hand", top + Vector2(8, -78 - 12.0 * pulse), 96.0, 0.55)   # fingers pointing down at the stack
		_write(_dfont, top + Vector2(0, -136 - 12.0 * pulse), tr("拿饭盒！"), 30, Color(1.0, 0.92, 0.6), Color(0.3, 0.15, 0.04), true)
	for i in _queue.size():
		_draw_basin(_table_slot(i), _queue[i], 0.0, 0.48, font, false)
	if warm:   # KV Cache 保温箱: a lidded warmer left of the table
		var wr := WARM_RECT
		var wt: Texture2D = _ui.get("warm_box", null)
		if wt != null:
			var wh := wr.size.x * wt.get_height() / wt.get_width()
			draw_texture_rect(wt, Rect2(wr.position.x, wr.end.y - wh, wr.size.x, wh), false)
		var plate := Rect2(wr.position.x + 18, wr.end.y - 4, wr.size.x - 36, 30)   # its name plate under it
		UiKit.nine(self, _ui.get("sign_plate", null), plate, 18.0)
		_write(font, Vector2(plate.get_center().x, plate.end.y - 8), tr("保温箱"), 18, INK, Color(0, 0, 0, 0), true)
		if _warm != null:
			_draw_basin(WARM_AT + Vector2(0, 12), _warm, 0.0, 0.42, font, false)
			for j in 2:   # it keeps warm
				var ph := fmod(_t * 0.6 + j * 0.5, 1.0)
				_sprite(self, "fx_steam", WARM_AT + Vector2(-20 + 40 * j, -70 - ph * 50.0), 22.0 + ph * 18.0, 0.0, Color(1, 1, 1, 0.5 * (1.0 - ph)))
			_badge(Vector2(wr.get_center().x, wr.position.y - 34), "", "×%.0f · %s" % [warm_x, Game.fmt(_box_worth(_warm))], "warm", warm_x)
		elif _hand != null and not _hand.items.is_empty() and not _ended:
			_write(font, Vector2(wr.get_center().x, wr.position.y - 20), tr("放进来，留到最后"), 20, Color(1.0, 0.9, 0.65, 0.85), Color(0.25, 0.12, 0.04, 0.85), true)
	if _queue.size() > 1:
		_count_tag(FULL_AT + Vector2(-70, 18), _queue.size())
	_crew_layer.queue_redraw()
	if _eating != null:
		_draw_basin(EAT_AT, _eating, 0.0, 0.55, font, false)   # she scoops from it
	for f in _flying:
		var p: Vector2 = f.from.lerp(f.to, f.t) + Vector2(0, -sin(f.t * PI) * 120.0)
		_draw_basin(p, f.basin if f.basin != null else _new_basin(p), 0.0, 0.55, font, false)
	for i in _pile.size():
		_draw_food(int(_pile_k[i]), _pile[i], 0.0, 0.9)
	for i in _fp.size():
		_draw_item(_fk[i], _fp[i], _fr[i], 1.0)
	if _busy_t > 0.0:
		draw_rect(Rect2(TABLE.position + Vector2(20, -70), Vector2(330, 54)), Color(0.85, 0.2, 0.2, 0.9))
		_label(font, TABLE.position + Vector2(36, -32), tr("服务器繁忙，请稍后重试"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	if _hand != null:
		_draw_basin(_hand.pos, _hand, _hand.slosh, 1.0, font, true)
	elif not _ended:
		if _empty == 0:
			_label(font, _aim + Vector2(-120, 0), tr("没空饭盒了！等她吃完……"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.7, 0.6))
	_draw_floaters(font)
	if _thinking:
		draw_texture_rect(UiKit.vignette(), Rect2(0, 0, 1920, 1080), false, Color(0.22, 0.12, 0.42, 0.75))
		if _hand != null:
			_label(font, _hand.pos + Vector2(-90, -110), tr("嗯，用户想要") + "……".repeat(1 + int(_t * 3.0) % 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.85, 1.0))
	if not _checkout:
		_draw_hud(font)


## Text with a dark outline, readable on the busy canteen art.
func _label(font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	draw_string_outline(font, pos, text, align, width, size, maxi(4, size / 5), Color(0.1, 0.06, 0.04, 0.85 * color.a))
	draw_string(font, pos, text, align, width, size, color)


## One piece of food, its long side SIZE_PX * scale_k.
func _draw_food(kind: int, at: Vector2, rot: float, scale_k: float) -> void:
	_draw_food_on(self, kind, at, rot, scale_k)


## An item: the dish as it is (its picture never changes), with light that tells its grade:
## 优质 (silver) — a cool white sheen sweeps across it every 1.8 s, now and then a faint star;
## 金牌 (gold) — a warm glow hugging its own outline breathes (1.2 s), a quicker warm sheen, gold
## stars taking turns on its edge. Boxed food keeps a steady silver/gold rim for readability.
## 高温: a little flame.
func _draw_item(it: int, at: Vector2, rot: float, scale_k: float, boxed := false, canvas: CanvasItem = null) -> void:
	var ci: CanvasItem = self if canvas == null else canvas
	var k := K(it)
	var r: float = SIZE_PX[k] * scale_k * 0.55
	var g := grade(it)
	var off := float(it % 97) * 0.137   # each piece on its own beat
	var tex: Texture2D = _food_tex[k]
	var ks: float = SIZE_PX[k] * scale_k / maxf(tex.get_width(), tex.get_height())
	if g > 0 and _rim_tex[k] != null:
		var breath := 0.5 if boxed or Settings.reduced_motion else 0.5 + 0.5 * sin((_t / 1.2 + off) * TAU)
		ci.draw_set_transform(at, rot, Vector2(ks, ks))
		ci.draw_texture(_rim_tex[k], -tex.get_size() * 0.5 - Vector2(RIM_PAD, RIM_PAD), _grade_rim(g, boxed, breath))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_food_on(ci, k, at, rot, scale_k)
	if g > 0 and _sheen_tex[k] != null and not Settings.reduced_motion:
		var period := 1.1 if g == 2 else 1.8
		var ph := fmod(_t / period + off, 1.0)
		if ph < 0.32:   # the sweep takes a third of the period, then it rests
			var fr := int(ph / 0.32 * SHEEN_FRAMES)
			var sz := tex.get_size()
			ci.draw_set_transform(at, rot, Vector2(ks, ks))
			ci.draw_texture_rect_region(_sheen_tex[k], Rect2(-sz * 0.5, sz), Rect2(fr * sz.x, 0, sz.x, sz.y),
				Color(1.0, 0.88, 0.55, 0.95) if g == 2 else Color(0.88, 0.95, 1.0, 0.85 if not boxed else 0.6))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not boxed and not Settings.reduced_motion:
		if g == 2:   # gold stars take turns on its edge
			for j in 3:
				var pj := fmod(_t * 1.3 + off + j / 3.0, 1.0)
				if pj < 0.28:
					var dir := Vector2.from_angle(-2.2 + j * 1.6 + off)
					_sprite(ci, "fx_star", at + dir * r * 0.95, r * 0.75 * sin(pj / 0.28 * PI), pj * 3.0)
		elif g == 1:   # silver: a faint white star now and then
			var pj := fmod(_t * 0.55 + off, 1.0)
			if pj < 0.18:
				_sprite(ci, "fx_star", at + Vector2(r * 0.7, -r * 0.65), r * 0.5 * sin(pj / 0.18 * PI), 0.0, Color(0.85, 0.92, 1.0, 0.8))
	if is_hot(it):
		_sprite(ci, "icon_flame", at + Vector2(r * 0.75, -r * 0.75), maxf(18.0, 30.0 * scale_k), 0.0 if Settings.reduced_motion else sin(_t * 9.0) * 0.12)


static func _grade_rim(g: int, boxed: bool, breath: float) -> Color:
	if g == 2:
		return Color(1.0, 0.75, 0.25, 0.9 if boxed else 0.55 + 0.4 * breath)
	if g == 1:
		return Color(0.76, 0.9, 1.0, 0.85 if boxed else 0.65)
	return Color.TRANSPARENT


func _draw_food_tinted(ci: CanvasItem, kind: int, at: Vector2, rot: float, scale_k: float, col: Color) -> void:
	var tex: Texture2D = _food_tex[kind]
	var sz := tex.get_size()
	var k: float = SIZE_PX[kind] * scale_k / maxf(sz.x, sz.y)
	ci.draw_set_transform(at, rot, Vector2(k, k))
	ci.draw_texture(tex, -sz * 0.5, FOOD_TINT[kind] * col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_food_on(ci: CanvasItem, kind: int, at: Vector2, rot: float, scale_k: float) -> void:
	var tex: Texture2D = _food_tex[kind]
	var sz := tex.get_size()
	var k: float = SIZE_PX[kind] * scale_k / maxf(sz.x, sz.y)
	ci.draw_set_transform(at, rot, Vector2(k, k))
	ci.draw_texture(tex, -sz * 0.5, FOOD_TINT[kind])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if IS_SET[kind] and FOOD_ART[kind] == "bowl":   # a 套餐 without its own art yet: a gold rim
		ci.draw_arc(at, SIZE_PX[kind] * scale_k * 0.5, 0, TAU, 28, Color(1.0, 0.8, 0.3, 0.9), maxf(2.0, 3.0 * scale_k), true)
	if FOOD_GLYPH[kind] != "":
		var fs := int(SIZE_PX[kind] * scale_k * 0.62)
		var col := Color(1.0, 0.3, 0.25) if kind == I.JI else (Color(0.35, 0.15, 0.6) if kind == I.Q else Color(0.55, 0.3, 0.0))
		var font := ThemeDB.fallback_font
		var glyph := tr(FOOD_GLYPH[kind])
		var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := at + Vector2(-w * 0.5, fs * 0.36)
		ci.draw_string_outline(font, p, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 6), Color(1, 1, 1, 0.9))
		ci.draw_string(font, p, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The box drawn on another canvas item (the helpers' layer): art and food, no label.
func _draw_basin_on(ci: CanvasItem, at: Vector2, b: Dictionary, scale_k: float) -> void:
	var n := _cols()
	var tex: Texture2D = _box_tex[n]
	var g: Rect2 = _box_grid[n]
	var gw := n * CELL * scale_k
	var aw := gw / g.size.x
	var ah := aw * tex.get_height() / tex.get_width()
	ci.draw_texture_rect(tex, Rect2(at - Vector2(aw * (g.position.x + g.size.x * 0.5), ah * (g.position.y + g.size.y * 0.5)), Vector2(aw, ah)), false, MATERIALS[mat_level].tint)
	var cw := gw / n
	var slots := _pack(b.items)
	for i in slots.size():
		var span: int = slots[i][1]
		if span == 0:
			continue
		var k := K(b.items[i])
		var centre := _boxed_item_origin(b, i, at, scale_k, slots)
		_draw_item(b.items[i], centre, 0.0, cw * (0.88 + 0.42 * (span - 1)) / SIZE_PX[k], true, ci)


## The lunch box art for n x n (fixed 45° top-down view: no rotation), tinted by the material and
## scaled so its compartment grid is n * CELL wide and centred on `at` (the grid's middle line is
## the catching line). Food sits in its cells, back row first; sloshing only wobbles the food.
func _draw_basin(at: Vector2, b: Dictionary, slosh: float, scale_k: float, font: Font, in_hand: bool) -> void:
	var n := _cols()
	var tex: Texture2D = _box_tex[n]
	var g: Rect2 = _box_grid[n]
	var gw := n * CELL * scale_k
	var aw := gw / g.size.x
	var ah := aw * tex.get_height() / tex.get_width()
	var gh := g.size.y * ah
	var art := _basin_art_rect(at, scale_k)
	var held_by_player := in_hand and _touch_hand_visible and not _ended
	if held_by_player:
		PLAYER_HAND.draw_arm(self, art, _player_arm_end(at))
	draw_texture_rect(tex, art, false, MATERIALS[mat_level].tint)
	var gx0 := at.x - gw * 0.5
	var gy0 := at.y - gh * 0.5
	var cw := gw / n
	var slots := _pack(b.items)
	var items: Array = b.items
	var order := range(slots.size())
	order.sort_custom(func(i, j): return int(slots[i][0]) / n < int(slots[j][0]) / n)
	var wobble := clampf(-slosh, -1.0, 1.0) * 6.0 * scale_k
	var ghosts := 0
	for i in order:
		var span: int = slots[i][1]
		if span == 0:
			ghosts += 1
			continue
		var centre := _boxed_item_origin(b, i, at, scale_k, slots) + Vector2(wobble, 0)
		var want := cw * (0.88 + 0.42 * (span - 1))
		_draw_item(items[i], centre, 0.0, want / SIZE_PX[K(items[i])], true)
	if ghosts > 0:   # 幻觉 / 投机解码: bites that take no cell
		_label(font, Vector2(gx0 + gw - 10, gy0 + 4), "+%d" % ghosts, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * scale_k) + 10, Color(0.85, 0.75, 1.0))
	for f in _flash:   # 合成: a cartoon burst, stars flying out
		if f.pos.distance_to(at) < 4.0 or in_hand:
			var q: float = f.t / 0.5
			var a := 1.0 - q * q
			if Settings.reduced_motion:
				_sprite(self, "fx_steam", at + Vector2(0, -45), gw * 0.75, 0.0, Color(1, 1, 1, 0.65 * a))
				continue
			_sprite(self, "fx_burst", at, gw * (1.35 + 0.7 * q), q * 0.5, Color(1, 1, 1, 0.9 * a))   # a ring round the box, food stays visible
			for j in 6:
				var dir := Vector2.from_angle(j * TAU / 6.0 + 0.4)
				_sprite(self, "fx_star", at + dir * gw * (0.55 + 0.75 * q), 30.0 * (1.0 - 0.5 * q), q * 4.0, Color(1, 1, 1, a))
	if in_hand:
		if held_by_player: PLAYER_HAND.draw_fingers(self, art)
		_draw_hand_tag(Vector2(at.x, art.end.y + 16), b)
		if combo > 0.0 and _combo_eligible(b):
			_icon("chain", Vector2(art.end.x - 6, art.position.y + 6), 40)


func _basin_art_rect(at: Vector2, scale_k: float) -> Rect2:
	var tex: Texture2D = _box_tex[_cols()]
	var grid: Rect2 = _box_grid[_cols()]
	var width := _cols() * CELL * scale_k / grid.size.x
	var height := width * tex.get_height() / tex.get_width()
	return Rect2(at - Vector2(width * (grid.position.x + grid.size.x * 0.5), height * (grid.position.y + grid.size.y * 0.5)), Vector2(width, height))


## Shared by lunchbox rendering and the pick-up cue: the accent belongs to the consumed cell.
func _boxed_item_origin(b: Dictionary, index: int, at: Vector2, scale_k: float, slots: Array = []) -> Vector2:
	if slots.is_empty(): slots = _pack(b.items)
	if index >= slots.size() or int(slots[index][1]) == 0: return at
	var n := _cols()
	var cell_i: int = slots[index][0]
	var span: int = slots[index][1]
	var g: Rect2 = _box_grid[n]
	var tex: Texture2D = _box_tex[n]
	var gw := n * CELL * scale_k
	var gh := g.size.y * gw / g.size.x * tex.get_height() / tex.get_width()
	var cw := gw / n
	var ch := gh / _rows()
	return Vector2(at.x - gw * 0.5 + (cell_i % n + span * 0.5) * cw,
		at.y - gh * 0.5 + (cell_i / n + 0.5) * ch - ch * 0.12)


# --- HUD (docs/hud_design.md): five fixed zones, three kinds of text ---------------------------
## A 小黑板 top left: the closing countdown, the version or the 评测 goal, the thinking gauge.
## B 收银台 top right: tokens this shift and the 主 / 荤 / 素 tray. C her badges (right of her
## head): one enamel badge per scoring skill she has. D at the box: capacity pips and the 套餐 in
## progress as ingredient icons. E the banner (top middle): big moments, one at a time.
## Text: floaters (numbers / short words where things happen), speech bubbles (who says it),
## banners. A skill that fires shows a small icon chip at the box, not a sentence.
const INK := Color(0.29, 0.16, 0.08)
const PAPER := Color(1.0, 0.96, 0.87)
const TICKET_RED := Color(0.78, 0.22, 0.18)
const ENAMEL := Color(0.18, 0.36, 0.62)
const GOLD_C := Color(0.95, 0.76, 0.31)
const CAT_COL := {"主": Color(0.95, 0.76, 0.29), "荤": Color(0.85, 0.34, 0.23), "素": Color(0.36, 0.64, 0.27)}
const BANNER_T := [0.15, 1.35, 0.3]   # stamp in, hold, fade
var _dfont: Font                       # 站酷快乐体: titles and big words
var _nfont: Font                       # 饭票数字 (pipeline/make_numerals.py): money, multipliers, counts
var _checkout := false                 # the closing receipt is up
var _bar_bg: StyleBoxFlat              # the cooking bars on the counter
var _bar_fill: StyleBoxFlat
var _pip: StyleBoxFlat                 # the box's capacity pips
var _ui := {}                          # HUD art by name (icon_* / ui_*)
var _banners: Array = []               # {title, sub, icon, t}
var _chips: Array = []                 # {pos, icon, t}
var _abark := ""                       # 梁阿姨's speech bubble
var _abark_t := 0.0
var _shown := 0.0                      # the token counter rolls up to `earned`
var _badge_val := {}                   # badge id -> last value (a rise makes it bounce)
var _badge_bump := {}


func _load_hud() -> void:
	_dfont = load("res://assets/ui/ZCOOLKuaiLe.ttf") if ResourceLoader.exists("res://assets/ui/ZCOOLKuaiLe.ttf") else ThemeDB.fallback_font
	_nfont = UiKit.numerals()
	for n in ["icon_token", "icon_flame", "icon_drool", "icon_chain", "icon_leaf", "icon_crown", "icon_clock", "icon_box",
			"icon_dice", "icon_shield", "icon_bolt", "icon_bell", "ui_badge", "ui_bubble", "ui_chalkboard", "ui_paper", "ui_banner", "ui_tray",
			"fx_burst", "fx_steam", "fx_star", "tray_empty", "tray_full", "ui_arrow", "sign_plate", "warm_box"]:
		_ui[n] = _maybe(ART + n + ".png")
	_ui["hand"] = _maybe("res://assets/ui/cursor_hand.png")
	_bar_bg = UiKit.box(Color(0.2, 0.12, 0.07, 0.85), Color(0.55, 0.36, 0.2), 2, 6)
	_bar_fill = UiKit.box(Color.WHITE, Color.TRANSPARENT, 0, 4)
	_pip = UiKit.box(Color.WHITE, Color(0.25, 0.14, 0.07, 0.8), 2, 4)


## A sprite from the art kit centred at `c`, its long side `size`, turned `rot`.
func _sprite(ci: CanvasItem, name: String, c: Vector2, size: float, rot := 0.0, col := Color.WHITE) -> void:
	var t: Texture2D = _ui.get(name, null)
	if t == null:
		return
	var k := size / maxf(t.get_width(), t.get_height())
	ci.draw_set_transform(c, rot, Vector2(k, k))
	ci.draw_texture(t, -t.get_size() * 0.5, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A soft glow (or shadow, tinted dark) of `size` x `size` * `squash` at `c`.
func _glow(ci: CanvasItem, c: Vector2, size: float, col: Color, squash := 1.0) -> void:
	var sz := Vector2(size, size * squash)
	ci.draw_texture_rect(UiKit.glow(), Rect2(c - sz * 0.5, sz), false, col)


## A big moment for the banner (queued: one at a time).
func _banner(title: String, sub := "", icon := "") -> void:
	if _banners.size() < 4:
		_banners.append({"title": tr(title), "sub": sub, "icon": icon, "t": 0.0})
		Audio.sfx("ticket", -6.0)


## A skill fired at this box: a small icon pops up over it.
func _chip(pos: Vector2, icon: String) -> void:
	_chips.append({"pos": pos + Vector2(randf_range(-30, 30), -90), "icon": icon, "t": 0.0})


## A floater where something happened. kind: money (gold), crit (red), mult (blue), set (cream),
## info (small, on a dark chip).
func _float(pos: Vector2, text: String, kind := "info") -> void:
	_texts.append({"pos": pos, "text": tr(text), "t": 0.0, "kind": kind})


func _say_auntie(text: String) -> void:
	_abark = tr(text)
	_abark_t = 1.8


func _update_hud(delta: float) -> void:
	for b in _banners.slice(0, 1):
		b.t += delta
	_banners = _banners.filter(func(b): return b.t < BANNER_T[0] + BANNER_T[1] + BANNER_T[2])
	for c in _chips:
		c.t += delta
	_chips = _chips.filter(func(c): return c.t < 0.9)
	_abark_t = maxf(_abark_t - delta, 0.0)
	_shown = lerpf(_shown, earned, minf(1.0, delta * 8.0)) if absf(earned - _shown) > 0.5 else earned
	for k in _badge_bump.keys():
		_badge_bump[k] = maxf(float(_badge_bump[k]) - delta * 4.0, 0.0)


## Text with an outline, any font (the HUD's one way of writing on the busy canteen art).
func _write(f: Font, pos: Vector2, text: String, size: int, col: Color, outline := Color(0.12, 0.06, 0.03), centred := false) -> void:
	if centred:
		pos.x -= f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	if outline.a > 0.0:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, size / 5), Color(outline, outline.a * col.a))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _fit_write(f: Font, pos: Vector2, text: String, px: int, width: float, col: Color) -> void:
	while px > 16 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		px -= 1
	while f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width and text.length() > 1:
		text = text.left(text.length() - 2) + "…"
	_write(f, pos, text, px, col, Color.TRANSPARENT)


func _icon(name: String, centre: Vector2, size: float, a := 1.0) -> void:
	var t: Texture2D = _ui.get("icon_" + name, null)
	if t == null:
		return
	var k := size / maxf(t.get_width(), t.get_height())
	var sz := t.get_size() * k
	draw_texture_rect(t, Rect2(centre - sz * 0.5, sz), false, Color(1, 1, 1, a))


func _piece(name: String, r: Rect2, col := Color.WHITE) -> void:
	var t: Texture2D = _ui.get(name, null)
	if t != null:
		draw_texture_rect(t, r, false, col)
	else:
		draw_rect(r, Color(0.1, 0.07, 0.05, 0.6) * col)




func _draw_hud(font: Font) -> void:
	# A: the chalkboard
	var a := Rect2(24, 14, 372, 196)
	_piece("ui_chalkboard", a)
	var left := maxf(meal_time - _meal_elapsed(), 0.0)
	var urgent := left <= 10.0 and not _ended
	var pulse := 1.0 + (0.08 * sin(_t * 12.0) if urgent and not Settings.reduced_motion else 0.0)
	if _learning():
		_fit_write(font, a.position + Vector2(40, 50), tr("第一次来，慢慢学"), 23, 292, Color(0.92, 0.95, 0.9))
		_write(font, a.position + Vector2(40, 82), tr("计时未开始"), 22, Color(1.0, 0.85, 0.5), Color.TRANSPARENT)
	else:
		_fit_write(font, a.position + Vector2(40, 58), tr("食堂关门还剩"), 22, 146, Color(0.92, 0.95, 0.9))
		var num := "%d" % int(ceil(left))
		_write(_nfont, a.position + Vector2(196, 74), num, int(54 * pulse), Color(1.0, 0.45, 0.4) if urgent else Color(0.98, 0.98, 0.92), Color(0, 0, 0, 0))
		_write(font, a.position + Vector2(206 + _nfont.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, int(54 * pulse)).x, 70), tr("秒"), 22, Color(0.92, 0.95, 0.9), Color.TRANSPARENT)
	var line2 := tr(Game.plate())
	if trial != "":
		line2 = tr("评测：本顿要到 %s") % Game.fmt(target)
		var pr := Rect2(a.position + Vector2(40, 128), Vector2(292, 12))
		draw_rect(pr, Color(1, 1, 1, 0.18))
		draw_rect(Rect2(pr.position, Vector2(pr.size.x * clampf(earned / maxf(target, 1.0), 0.0, 1.0), pr.size.y)), GOLD_C if earned < target else Color(0.55, 0.9, 0.5))
	_fit_write(font, a.position + Vector2(40, 112), line2, 20, 292, Color(0.85, 0.9, 0.82))
	if peaks:
		_icon("bell", a.position + Vector2(52, 166), 30, 1.0 if _peak_on else 0.45)
		_write(font, a.position + Vector2(74, 174), (tr("高峰 %d 秒") if _peak_on else tr("谷时 %d 秒")) % int(ceil(_peak_t)), 20, Color(1.0, 0.6, 0.5) if _peak_on else Color(0.8, 0.85, 0.8), Color(0, 0, 0, 0))
	if can_think:
		var think_panel := Rect2(1000, 14, 455, 154)
		UiKit.nine(self, _ui.ui_chalkboard, think_panel, 48, 0.6)
		var clock_at := think_panel.position + Vector2(60, 77)
		_icon("clock", clock_at, 47)
		draw_arc(clock_at, 34, -PI / 2, TAU - PI / 2, 48, Color(1, 0.97, 0.88, 0.2), 4, true)
		var ready := clampf(_think / maxf(think_time, 0.01), 0, 1)
		if _think_cooldown > 0: ready = clampf(1.0 - _think_cooldown / THINK_COOLDOWN, 0, 1)
		if ready > 0.001:
			draw_arc(clock_at, 34, -PI / 2, ready * TAU - PI / 2, 48, Color("e19a77") if _think_cooldown > 0 else GOLD_C, 4, true)
		_fit_write(font, think_panel.position + Vector2(111, 44), tr("深度思考"), 24, 213, PAPER)
		_fit_write(_nfont, think_panel.position + Vector2(340, 44), "%.1fs" % _think, 21, 84, PAPER)
		_fit_write(font, think_panel.position + Vector2(111, 85), _think_hint(), 20, 313, PAPER)
	# B: the cash register and the 主 / 荤 / 素 tray
	var b := Rect2(1530, 14, 370, 92)
	_piece("ui_paper", b)
	_icon("token", b.position + Vector2(46, 46), 52)
	_fit_write(_nfont, b.position + Vector2(84, 62), Game.fmt(_shown), 46, 172, Color(0.76, 0.46, 0.06))
	_write(font, b.position + Vector2(268, 62), tr("token"), 20, INK, Color(0, 0, 0, 0))
	var tray := Rect2(1545, 112, 340, 101)
	_piece("ui_tray", tray)
	var tot: float = _cat["主"] + _cat["荤"] + _cat["素"]
	var goal := {"主": 0.4, "荤": 0.3, "素": 0.3}
	var i := 0
	for cn in ["主", "荤", "素"]:
		var cx := tray.position.x + tray.size.x * (0.18 + 0.32 * i)
		var share: float = float(_cat[cn]) / tot if tot > 0.0 else 0.0
		var fill := clampf(share / goal[cn], 0.0, 1.0)
		var cell := Rect2(cx - 44, tray.position.y + 22, 88, 58)
		draw_rect(Rect2(cell.position.x, cell.end.y - cell.size.y * fill, cell.size.x, cell.size.y * fill), Color(CAT_COL[cn], 0.55))
		_write(font, Vector2(cx, cell.position.y + 30), tr(cn), 22, INK, Color(1, 1, 1, 0.8), true)
		_write(font, Vector2(cx, cell.position.y + 52), "%d%%" % int(round(share * 100)), 16, INK, Color(1, 1, 1, 0.8), true)
		i += 1
	_badge(Vector2(1715, 246), "", tr("均衡 ×%.2f") % balance_mult(), "balance", balance_mult())
	# C: her badges
	var y := 300.0
	var rows: Array = []
	# [icon, name, value, id, number]: the name says which multiplier it is (the icons alone
	# didn't), right-aligned under the tray
	if stream > 0.0:
		rows.append(["flame", tr("流式"), "×%.2f" % _stream_mult(), "stream", _stream_mult()])
	if crave > 0.0:
		rows.append(["drool", tr("馋"), "×%.2f" % _crave_x(_crave_t), "crave", _crave_x(_crave_t)])
	if combo > 0.0:
		rows.append(["chain", tr("连击"), "%d" % _combo_n, "combo", float(_combo_n)])
	if grok:
		rows.append(["leaf", tr("顿悟"), "✓" if _grokked else "%d/%d" % [_grok_n, grok_need], "grok", float(_grok_n)])
	if critic > 0.0:
		rows.append(["crown", tr("评鉴"), tr("%d 种") % _kinds_eaten.size(), "critic", float(_kinds_eaten.size())])
	if crew_relay > 0.0:
		rows.append(["box", tr("下盒接力"), "%d/3 +%d%%" % [_helper_relay.size(), int(round(_helper_relay.size() * crew_relay * 100))], "crew_relay", float(_helper_relay.size())])
	if cache_bonus > 0.0 and _cache_ready:
		rows.append(["box", tr("缓存"), "+%d%%" % int(round(cache_bonus * 100)), "cache", cache_bonus])
	for r in rows:
		_badge(Vector2(0, y), r[0], r[2], r[3], r[4], r[1], 1890.0, rows.size() > 3)
		y += 42.0 if rows.size() > 3 else 64.0
	if _show_stats:
		var lines := [
			tr("FPS %d · 掉落物 %d") % [Engine.get_frames_per_second(), _fp.size()],   # notr
			tr("接住率 %d%% · 晃出 %d · 掉地上 %d") % [int(catch_rate() * 100), spilled, wasted],   # notr
			tr("她空等 %.1f 秒") % fish_wait,   # notr
		]
		draw_rect(Rect2(420, 20, 460, 34 * lines.size() + 16), Color(0, 0, 0, 0.45))
		for j in lines.size():
			_label(font, Vector2(436, 52 + 34 * j), lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.92, 1.0))


## Keep the original painted ribbon, beneath food and the player's box.
func _draw_announcement(ci: CanvasItem) -> void:
	if _checkout or _banners.is_empty(): return
	var bn: Dictionary = _banners[0]
	var t: float = bn.t
	var alpha := minf(1.0, t / BANNER_T[0])
	if t > BANNER_T[0] + BANNER_T[1]:
		alpha = 1.0 - (t - BANNER_T[0] - BANNER_T[1]) / BANNER_T[2]
	var r := Rect2(650, 390, 620, 161)
	ci.draw_texture_rect(_ui.ui_banner, r, false, Color(1, 1, 1, alpha))
	if bn.icon != "":
		var tex: Texture2D = _ui.get("icon_" + bn.icon)
		if tex != null:
			var sz := tex.get_size() * (48.0 / maxf(tex.get_width(), tex.get_height()))
			ci.draw_texture_rect(tex, Rect2(Vector2(752, 465) - sz * 0.5, sz), false, Color(1, 1, 1, alpha))
	var font: Font = load("res://assets/ui/ui_font.tres")
	for row in 2:
		var text: String = bn.title if row == 0 else bn.sub
		var px := 40 if row == 0 else 22
		var f: Font = _dfont if row == 0 else font
		while px > 16 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > 400: px -= 1
		while f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > 400 and text.length() > 1:
			text = text.left(text.length() - 2) + "…"
		var at := Vector2(790, 468 if row == 0 else 504)
		ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_CENTER, 400, px, 4, Color(0.45, 0.06, 0.04, alpha))
		ci.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_CENTER, 400, px, Color(1, 0.97, 0.88, alpha))


## One enamel badge, centred at `c` (or with its right edge at `right`): an icon, the
## multiplier's name and its value; it bounces when the value goes up.
func _badge(c: Vector2, icon: String, text: String, id: String, value: float, label := "", right := -1.0, compact := false) -> void:
	if value > float(_badge_val.get(id, value)) + 0.001:
		_badge_bump[id] = 1.0
	_badge_val[id] = value
	var k := 1.0 + (0.04 if compact else 0.12) * sin(float(_badge_bump.get(id, 0.0)) * PI) if not Settings.reduced_motion else 1.0
	var layout := _badge_layout(c, icon, text, label, right, compact, k)
	# Scale the badge and all its content together around the same anchor. A right-aligned
	# badge grows leftward, never pushing its enamel edge or last glyph off the viewport.
	draw_set_transform(layout.center, 0.0, Vector2(k, k))
	UiKit.nine(self, _ui.ui_badge, layout.rect, 30, 0.45 if compact else 0.65)
	if icon != "":
		_icon(icon, layout.icon_at, 30 if compact else 38)
	var font := ThemeDB.fallback_font
	if label != "":
		_write(font, layout.label_at, label, layout.label_px, INK, Color.TRANSPARENT)
	_write(_nfont, layout.value_at, text, layout.value_px, ENAMEL, Color.TRANSPARENT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Measure the font that will actually be drawn. The numeral atlas includes its black
## outline and negative side bearings (up to 31/96 em); keep that ink inside the safe area.
func _badge_layout(c: Vector2, icon: String, text: String, label := "", right := -1.0, compact := false, scale_k := 1.0) -> Dictionary:
	var font := ThemeDB.fallback_font
	var label_px := 20 if compact else 22
	var value_px := 24 if compact else 28
	var icon_width := 40.0 if icon != "" else 0.0
	var gap := 10.0 if label != "" else 0.0
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_px).x
	var value_width := _nfont.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_px).x
	var ink_pad := ceilf(value_px * 0.35)
	var content := icon_width + label_width + gap + value_width + ink_pad * 2.0
	while content > 321.0 and value_px > 14:
		value_px -= 1
		label_px = maxi(14, int(round(value_px * (20.0 / 24.0 if compact else 22.0 / 28.0))))
		label_width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_px).x
		value_width = _nfont.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_px).x
		ink_pad = ceilf(value_px * 0.35)
		content = icon_width + label_width + gap + value_width + ink_pad * 2.0
	var w := clampf(content + 44.0, 120.0, 365.0)
	var h := 40.0 if compact else 58.0
	if right > 0.0:
		c.x = minf(right, 1900.0) - w * scale_k * 0.5
	else:
		c.x = clampf(c.x, 20.0 + w * scale_k * 0.5, 1900.0 - w * scale_k * 0.5)
	var rect := Rect2(-w * 0.5, -h * 0.5, w, h)
	var x := rect.position.x + 22.0
	var label_at := Vector2(x + icon_width, label_px * 0.36)
	var value_at := Vector2(label_at.x + label_width + gap + ink_pad, value_px * 0.36)
	return {"center": c, "rect": rect, "icon_at": Vector2(x + 17.0, 0), "label_at": label_at,
		"value_at": value_at, "label_px": label_px, "value_px": value_px,
		"bounds": Rect2(c + rect.position * scale_k, rect.size * scale_k),
		"value_ink_span": Vector2(value_at.x - ink_pad, value_at.x + value_width + ink_pad),
		"label_span": Vector2(label_at.x, label_at.x + label_width),
		"safe_span": Vector2(rect.position.x + 12.0, rect.end.x - 12.0)}


## How many boxes are in a stack: a small enamel tag with the number (not a bare "×2").
func _count_tag(c: Vector2, n: int) -> void:
	var r := Rect2(c - Vector2(26, 19), Vector2(52, 38))
	UiKit.nine(self, _ui.get("ui_badge", null), r, 30.0, 0.55)
	_write(_nfont, Vector2(c.x, c.y + 10), str(n), 26, ENAMEL, Color(0, 0, 0, 0), true)


## Floaters, chips and the two speech bubbles (drawn over the play field).
func _draw_floaters(font: Font) -> void:
	for x in _texts:
		var t: float = x.t
		var k := 1.0 + 0.3 * maxf(0.0, 1.0 - t / 0.12)
		var a := 1.0 - maxf(0.0, (t - 0.6) / 0.4)
		var p: Vector2 = x.pos + Vector2(0, -50.0 * t)
		match x.get("kind", "info"):
			"money":
				_write(_nfont, p, x.text, int(34 * k), Color(GOLD_C, a), Color(0.3, 0.15, 0.02, a))
			"crit":
				_write(_nfont, p, x.text, int(42 * k), Color(1.0, 0.36, 0.28, a), Color(0.25, 0.02, 0.02, a))
			"mult":
				_write(_nfont, p, x.text, int(32 * k), Color(0.55, 0.75, 1.0, a), Color(0.05, 0.1, 0.25, a))
			"set":
				_write(_dfont, p, x.text, int(30 * k), Color(1.0, 0.93, 0.7, a), Color(0.3, 0.15, 0.02, a))
			_:
				var w := font.get_string_size(x.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
				UiKit.nine(self, _ui.get("ui_paper", null), Rect2(p + Vector2(-16, -30), Vector2(w + 32, 42)), 26.0, 0.5, Color(1, 1, 1, a))
				_write(font, p, x.text, 22, Color(INK, a), Color(0, 0, 0, 0))
	for c in _chips:
		var t: float = c.t
		var k := 1.0 + 0.5 * maxf(0.0, 1.0 - t / 0.15)
		_icon(c.icon, c.pos + Vector2(0, -40.0 * t), 46.0 * k, 1.0 - maxf(0.0, (t - 0.5) / 0.4))
	if _bark_t > 0.0:   # her speech bubble, its tail pointing down at her
		_bubble(Vector2(1200, 470), _bark, true)
	if _abark_t > 0.0:   # 梁阿姨's, by her hat
		_bubble(Vector2(860, 178), _abark, false)


func _bubble(at: Vector2, text: String, flip: bool) -> void:
	var font: Font = load("res://assets/ui/ui_font.tres")
	var width := minf(330, maxf(140, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x))
	var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, 26)
	var r := Rect2(at, Vector2(width + 100, maxf(120, measured.y + 90)))
	var tex: Texture2D = _ui.ui_bubble
	if flip:
		draw_set_transform(Vector2(r.end.x, r.position.y), 0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(Vector2.ZERO, r.size), false)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_texture_rect(tex, r, false)
	var y := r.position.y + (r.size.y * 0.84 - measured.y) * 0.5 + font.get_ascent(26)
	draw_multiline_string(font, Vector2(r.position.x + 50, y), text, HORIZONTAL_ALIGNMENT_CENTER, width, 26, -1, INK)


## D: the box in hand — capacity pips and the 套餐 it is on its way to, as ingredient icons.
func _draw_hand_tag(at: Vector2, b: Dictionary) -> void:
	var used := _space(b)
	var cap := _cap()
	var x0 := at.x - cap * 9.0
	for i in cap:
		var c := Vector2(x0 + i * 18.0 + 9.0, at.y)
		_pip.bg_color = (Color(1.0, 0.5, 0.4) if used >= cap else GOLD_C) if i < used else Color(1, 0.97, 0.9, 0.3)
		draw_style_box(_pip, Rect2(c - Vector2(7, 7), Vector2(14, 14)))
	var rule := _plan_box(b)
	var rule_text := ""
	if rule.cache_primed:
		rule_text = tr("送出可存缓存")
	elif float(rule.add_bonus) > 0.0:
		var tags: Array[String] = []
		if float(rule.mono_bonus) > 0.0:
			tags.append(tr("单品拼盘"))
		if rule.cache_consumed:
			tags.append(tr("缓存"))
		if rule.rotation:
			tags.append(tr("换菜"))
		rule_text = "%s +%d%%" % [" · ".join(tags), int(round(float(rule.add_bonus) * 100))]
	if rule_text != "":
		_write(ThemeDB.fallback_font, at + Vector2(0, 70), rule_text, 20, PAPER, INK, true)
	var close := _closest_recipe(b.items)
	if not close.is_empty():
		var r: Dictionary = close[0]
		var missing: Array = (close[1] as Array).duplicate()
		var xs: float = at.x - (r.needs.size() + 1) * 22.0
		for need in r.needs:
			var have := not missing.has(need)
			if not have:
				missing.erase(need)
			_draw_food_tinted(self, need, Vector2(xs, at.y + 34), 0.0, 36.0 / SIZE_PX[need], Color.WHITE if have else Color(0.3, 0.3, 0.3, 0.6))
			xs += 44.0
		var ax := xs - 2.0   # an arrow to the 套餐 it makes
		_sprite(self, "ui_arrow", Vector2(ax + 8, at.y + 34), 30.0)
		_draw_food_tinted(self, r.result, Vector2(xs + 30, at.y + 34), 0.0, 44.0 / SIZE_PX[r.result], Color.WHITE)


func _close_text() -> String:
	var m := 11 * 60 + 30 + int(meal_time)
	return "%02d:%02d" % [m / 60, m % 60]
