class_name ResultCard
extends Control
## End-of-shift card, scored like Balatro: the base tokens, the 招牌菜 part of them, the 均衡倍率
## (with the 主 : 荤 : 素 split she ate), then the total counting up to its final number; in a
## 评测 also the target and passed / not yet. A button goes back to the skill tree.

signal closed

var title := "食堂关门了"
var full := true
var earned := 0.0       # total, after the multiplier
var base := 0.0         # before it
var sig_bonus := 0.0    # part of base that came from 招牌菜
var balance := 0.0      # 0..1
var balance_mult := 1.0
var cats := {}
var target := 0.0       # 评测 target (0 = an ordinary shift)
var eaten := 0
var stomach := 1        # (unused since there is no stomach cap)
var catch_rate := 0.0
var record := false
var stuffed := false
var clock := ""
var extra := ""         # 评测 outcome line
var plate := ""
var passed := false
var score := {}         # CanteenRun._score: base, warm, sleep, clip, balance, review, fuse
var kinds := 0          # kinds of 套餐 eaten (美食评鉴)

var _total: Label
var _shown := 0.0
var _goal := 0.0


func _ready() -> void:
	size = Vector2(1920, 1080)   # parent is the CanteenRun Node2D, so anchors have nothing to fill
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.65)
	dim.size = size
	add_child(dim)
	var card := PanelContainer.new()
	card.position = Vector2(500, 110)
	card.custom_minimum_size = Vector2(920, 860)
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var head := tr(title)
	if record:
		head = tr("新纪录！") + head
	col.add_child(_line(head, 48, UiKit.GOLD, true))
	# full: 吃饱躺平; otherwise she holds up her empty basin (waist up, cut by the holder)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 250)
	holder.clip_contents = true
	if full:
		var lie := Sprite2D.new()
		lie.texture = load("res://assets/fatfish/lie_full.png")
		lie.scale = Vector2.ONE * (240.0 / lie.texture.get_height())
		lie.position = Vector2(440, 125)
		holder.add_child(lie)
	else:
		var fish := FishRig.new()
		fish.seated = true
		fish.emote = Game.emotion()
		fish.idle_clip = "beg"
		fish.height = 330.0
		fish.position = Vector2(440, 290)
		holder.add_child(fish)
	col.add_child(holder)
	# the score, one line after another
	var rows: Array = [
		[tr("吃了 %d 份 · 接住率 %d%%") % [eaten, int(catch_rate * 100)], tr("基础 %s token") % Game.fmt(base)],
	]
	if sig_bonus > 0.0:
		rows.append([tr("其中招牌菜"), "%s" % Game.fmt(sig_bonus)])
	if score.has("warm"):
		rows.append([tr("揭开保温箱：好吃的留到最后"), "+ %s" % Game.fmt(score.warm)])
	if score.has("sleep"):
		rows.append([tr("我去睡了：梦里接着吃"), "+ %s" % Game.fmt(score.sleep)])
	if score.has("clip"):
		rows.append([tr("梯度裁剪：最差的几盒按平均算"), "+ %s" % Game.fmt(score.clip)])
	var split := ""
	var tot: float = float(cats.get("主", 0.0)) + float(cats.get("荤", 0.0)) + float(cats.get("素", 0.0))
	if tot > 0.0:
		split = tr("主 %d%% · 荤 %d%% · 素 %d%%") % [int(100 * cats.get("主", 0.0) / tot), int(100 * cats.get("荤", 0.0) / tot), int(100 * cats.get("素", 0.0) / tot)]
	rows.append([tr("饮食均衡 %d%%　%s") % [int(balance * 100), split], "× %.2f" % balance_mult])
	if float(score.get("review", 1.0)) > 1.0:
		rows.append([tr("美食评鉴：吃到 %d 种套餐") % kinds, "× %.2f" % float(score.review)])
	if score.has("fuse"):
		rows.append([tr("上下文溢出：超出的部分按根号算"), "− %s" % Game.fmt(score.fuse)])
	var i := 0
	for r in rows:
		var row := HBoxContainer.new()
		var a := _line(r[0], 26, UiKit.TEXT, false)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := _line(r[1], 30, Color(1.0, 0.9, 0.6), false)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(a)
		row.add_child(b)
		row.modulate.a = 0.0
		col.add_child(row)
		var tw := create_tween()
		tw.tween_interval(0.35 + 0.35 * i)
		tw.tween_property(row, "modulate:a", 1.0, 0.15)
		tw.tween_callback(func(): Audio.sfx("token", -6.0))
		i += 1
	_total = _line("", 56, Color(0.7, 0.95, 1.0), true)
	col.add_child(_total)
	_goal = earned
	var tw2 := create_tween()
	tw2.tween_interval(0.35 + 0.35 * i)
	tw2.tween_property(self, "_shown", _goal, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_callback(func():
		Audio.sfx("version_up" if passed else "result", -3.0)
		_total.pivot_offset = _total.size * 0.5
		var pop := create_tween()
		pop.tween_property(_total, "scale", Vector2.ONE * 1.15, 0.08)
		pop.tween_property(_total, "scale", Vector2.ONE, 0.12))
	if target > 0.0:
		col.add_child(_line(tr("评测目标 %s token") % Game.fmt(target), 26, Color(1.0, 0.8, 0.6), true))
	if extra != "":
		var e := _line(extra, 24, Color(1.0, 0.9, 0.6), true)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(e)
	var back := UiKit.button(tr("回技能树"), 34, Vector2(300, 84))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): closed.emit())
	col.add_child(back)
	back.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if is_instance_valid(_total):
		_total.text = tr("这顿 +%s token") % Game.fmt(_shown)


func _line(text: String, size_px: int, color: Color, centre: bool) -> Label:
	var l := UiKit.label(text, size_px, color)
	if centre:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
