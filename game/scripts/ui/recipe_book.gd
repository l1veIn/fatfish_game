class_name RecipeBook
extends Control
## 菜谱图鉴: every 套餐 (made ones show their ingredients and how often she ate them, unknown ones
## a silhouette and, for hidden recipes, their hint) and every dish (which window, at what level,
## its worth and kind). Opens from the pause menu, the title screen and the skill tree.

signal closed

var _page := "sets"
var _list: GridContainer
var _tabs: Array = []


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS   # also over the paused shift
	CanteenRun.load_menu()
	var bg := TextureRect.new()
	if ResourceLoader.exists("res://assets/canteen/recipe_page.png"):
		bg.texture = load("res://assets/canteen/recipe_page.png")
	bg.size = size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.03, 0.25)
	dim.size = size
	add_child(dim)
	var head := HBoxContainer.new()
	head.position = Vector2(180, 60)
	head.add_theme_constant_override("separation", 20)
	add_child(head)
	var title := UiKit.label(tr("菜谱图鉴"), 52, Color(1.0, 0.92, 0.75))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.14, 0.05))
	head.add_child(title)
	for spec in [["sets", tr("套餐 %d / %d") % [Game.recipes.size(), CanteenRun.RECIPES.size()]], ["foods", tr("食材")]]:
		var b := UiKit.button(spec[1], 28, Vector2(220, 64))
		b.pressed.connect(func():
			_page = spec[0]
			_fill())
		head.add_child(b)
		_tabs.append(b)
	var back := UiKit.button(tr("合上"), 30, Vector2(200, 64))
	back.set_meta("ui_back", true)
	back.pressed.connect(func():
		closed.emit()
		queue_free())
	head.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(170, 160)
	scroll.size = Vector2(1580, 860)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override("h_separation", 60)
	_list.add_theme_constant_override("v_separation", 18)
	scroll.add_child(_list)
	_fill()
	back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	if _page == "sets":
		for r in CanteenRun.RECIPES:
			_list.add_child(_set_entry(r))
	else:
		for k in CanteenRun.NAMES.size():
			if not CanteenRun.IS_SET[k] and CanteenRun.STALL[k] != "":
				_list.add_child(_food_entry(k))


func _icon(k: int, known: bool) -> TextureRect:
	var t := TextureRect.new()
	var f := "res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[k]
	if ResourceLoader.exists(f):
		t.texture = load(f)
	t.custom_minimum_size = Vector2(96, 96)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not known:
		t.modulate = Color(0.1, 0.07, 0.05, 0.75)   # a silhouette until she has eaten it
	return t


func _row(icon: TextureRect, lines: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(760, 110)
	row.add_theme_constant_override("separation", 16)
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	for l in lines:
		var lab := UiKit.label(l[0], l[1], l[2])
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(620, 0)
		col.add_child(lab)
	return row


func _set_entry(r: Dictionary) -> HBoxContainer:
	var k: int = r.result
	var known := Game.recipes.has(r.id)
	var ink := Color(0.32, 0.17, 0.07)
	var tier: String = tr(CanteenRun.TIER_NAME[CanteenRun.TIER[k]])
	if not known:
		var hint: String = tr(r.hint) if r.hint != "" else tr("还没吃到过")
		return _row(_icon(k, false), [["？？？ · " + tier, 28, ink], [tr("提示：%s") % hint if r.kind == "hidden" else hint, 22, Color(0.45, 0.35, 0.28)]])
	var parts: Array = []
	for need in r.needs:
		parts.append(tr(CanteenRun.NAMES[need]))
	return _row(_icon(k, true), [
		["%s · %s" % [tr(CanteenRun.NAMES[k]), tier], 28, ink],
		[tr("原料：%s") % " + ".join(parts), 22, Color(0.4, 0.25, 0.12)],
		[tr("吃过 %d 次") % int(Game.recipes[r.id]), 20, Color(0.5, 0.38, 0.3)],
	])


func _food_entry(k: int) -> HBoxContainer:
	var ink := Color(0.32, 0.17, 0.07)
	var st: Dictionary = CanteenRun.STALLS[CanteenRun.STALL[k]]
	var open: bool = Game.stat("stall_" + CanteenRun.STALL[k]) >= CanteenRun.LEVEL[k]
	var cats: Array = CanteenRun.CATS[k].keys()
	var kinds := "、".join(cats.map(func(c): return tr(c)))
	var worth := tr("单吃 0（她挑食，会吐掉）") if CanteenRun.PICKY[k] else tr("每口 %d token") % int(CanteenRun.VALUE[k])
	return _row(_icon(k, open), [
		["%s · %s" % [tr(CanteenRun.NAMES[k]), kinds], 28, ink],
		[tr("%s窗口 %d 级出这道菜 · %s") % [tr(st.name), CanteenRun.LEVEL[k], worth], 22, Color(0.4, 0.25, 0.12)],
	])
