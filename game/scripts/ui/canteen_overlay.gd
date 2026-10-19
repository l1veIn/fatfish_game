extends Control
## Small enamel stall labels and an optional guide, using the canteen's original materials.
const INK := UiKit.INK
const PAPER := Color("fff2d9")
const GOLD := Color("e9b85e")
const MUTED := Color("80654c")
const CORAL := Color("bb5033")
const TEAL := Color("6b9271")
const COLORS := [Color("dbab78"), Color("86be98"), Color("ebc16e"), Color("e69a71"), Color("d4a8c9")]
const SYMBOLS := ["dump", "veg", "bowl", "leg", "pudding"]
var run: Node2D
var _font: Font
var _info: Button
var _modal: Control
var _body: Control
var _tabs: Array[Button] = []
var _selected := 2
var _return_focus: Control
var _closing := false


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = load("res://assets/ui/ui_font.tres")
	_info = UiKit.button(tr("档口指南 · Tab"), 20, Vector2(190, 46))
	_info.focus_mode = Control.FOCUS_NONE
	_info.position = Vector2(408, 28)
	_info.pressed.connect(open_guide)
	add_child(_info)
	for i in run.STALL_ORDER.size():
		var b := Button.new()
		b.position = stall_rect(i).position
		b.size = stall_rect(i).size
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tr("查看备菜与升级")
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
		b.pressed.connect(func(): open_guide(i))
		add_child(b)


func _process(_delta: float) -> void:
	visible = not run._checkout
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB and not is_instance_valid(_modal) and not get_tree().paused and not run._ended:
			open_guide()
			get_viewport().set_input_as_handled()
		elif is_instance_valid(_modal) and event.keycode in [KEY_ESCAPE, KEY_P]:
			close_guide()
			get_viewport().set_input_as_handled()
	if is_instance_valid(_modal) and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		close_guide()
		get_viewport().set_input_as_handled()


func _text(ci: CanvasItem, r: Rect2, value: String, px := 25, color := PAPER, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	# Bounds are explicit even for changing numbers and English text.
	var fitted := px
	while fitted > 18 and _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > r.size.x:
		fitted -= 1
	var shown := value
	while _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > r.size.x and shown.length() > 1:
		shown = shown.left(shown.length() - 2) + "…"
	var baseline := r.position + Vector2(0, (r.size.y - _font.get_height(fitted)) * 0.5 + _font.get_ascent(fitted))
	ci.draw_string(_font, baseline, shown, align, r.size.x, fitted, color)


func _image(ci: CanvasItem, tex: Texture2D, r: Rect2, tint := Color.WHITE) -> void:
	if tex == null:
		return
	var s := tex.get_size() * minf(r.size.x / tex.get_width(), r.size.y / tex.get_height())
	ci.draw_texture_rect(tex, Rect2(r.get_center() - s * 0.5, s), false, tint)


func stall_rect(i: int) -> Rect2:
	var pans: Array = run.PANS[run.STALL_ORDER[i]]
	var left := float(pans[0]) - 47
	var right := float(pans[-1]) + 47
	if i > 0:
		left = (float(run.PANS[run.STALL_ORDER[i - 1]][-1]) + float(pans[0])) * 0.5 + 6
	if i < run.STALL_ORDER.size() - 1:
		right = (float(run.PANS[run.STALL_ORDER[i + 1]][0]) + float(pans[-1])) * 0.5 - 6
	return Rect2(left, 321, right - left, 136)


func draw_stalls(ci: CanvasItem) -> void:
	if _font == null:
		return
	for i in run.STALL_ORDER.size():
		var id: String = run.STALL_ORDER[i]
		var r := stall_rect(i)
		var level: int = run.stall_lv.get(id, 0)
		var arms: Array = run._arms.filter(func(a): return a.stall == id)
		var accent: Color = COLORS[i] if level > 0 else MUTED
		# The original painted enamel plate belongs on the wooden counter.
		UiKit.nine(ci, run._ui.sign_plate, Rect2(r.position + Vector2(0, 4), Vector2(r.size.x, 46)), 20, 0.7)
		var symbol: int = run.KIND.get(SYMBOLS[i], 1)
		_image(ci, run._food_tex[symbol], Rect2(r.position + Vector2(10, 10), Vector2(32, 32)), Color.WHITE if level > 0 else Color(0.65, 0.65, 0.65))
		_text(ci, Rect2(r.position + Vector2(48, 7), Vector2(r.size.x - 61, 35)), tr(run.STALLS[id].name), 24, INK)
		var status := tr("未营业") if level == 0 else tr("Lv.%d · %d 把勺子") % [level, arms.size()]
		_text(ci, Rect2(r.position + Vector2(10, 51), Vector2(r.size.x - 20, 27)), status, 20, INK, HORIZONTAL_ALIGNMENT_CENTER)
		if level == 0 or arms.is_empty():
			continue
		var columns := mini(arms.size(), 4)
		var step := minf(60, (r.size.x - 22) / columns)
		var rows := ceili(float(arms.size()) / columns)
		for j in arms.size():
			var a: Dictionary = arms[j]
			var c := Vector2(r.get_center().x + (j % columns - (columns - 1) * 0.5) * step, r.position.y + 100 + (j / columns) * 31 - (14 if rows > 1 else 0))
			var radius := 12.0 if rows > 1 else 18.0
			var done := 1.0 if a.raise > 0.0 else clampf(1.0 - a.t / maxf(a.t0, 0.01), 0.0, 1.0)
			ci.draw_circle(c, radius + 3, PAPER)
			ci.draw_arc(c, radius + 2, -PI / 2, TAU - PI / 2, 32, MUTED, 3, true)
			if done > 0.001:
				ci.draw_arc(c, radius + 2, -PI / 2, done * TAU - PI / 2, 32, CORAL if a.raise > 0 else accent, 4, true)
			if a.dish >= 0:
				_image(ci, run._food_tex[a.dish], Rect2(c - Vector2.ONE * radius * 0.84, Vector2.ONE * radius * 1.68))
			if a.raise > 0:
				ci.draw_circle(c + Vector2(radius, -radius), 5, CORAL)


func open_guide(index := 2) -> void:
	if is_instance_valid(_modal) or run._ended or get_tree().paused:
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	run._interrupt_thinking()
	get_tree().paused = true
	_modal = Control.new()
	_modal.size = size
	_modal.z_index = 110
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.065, 0.025, 0.75)
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(160, 80)
	panel.size = Vector2(1600, 920)
	panel.add_theme_stylebox_override("panel", UiKit.box(PAPER, GOLD, 2, 20))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(panel)
	_add_label(_modal, Rect2(210, 110, 1150, 56), tr("梁阿姨的档口"), 44, INK)
	_add_label(_modal, Rect2(210, 173, 1390, 50), tr("每把勺子独立备菜。圆环满了，勺子举起，再把菜抛出来。"), 26, INK)
	_tabs.clear()
	for i in run.STALL_ORDER.size():
		var b := UiKit.button(tr(run.STALLS[run.STALL_ORDER[i]].name), 28, Vector2(274, 60))
		b.position = Vector2(210 + i * 292, 242)
		b.pressed.connect(func(): _show_stall(i))
		_modal.add_child(b)
		_tabs.append(b)
	var close := UiKit.button(tr("继续开饭"), 28, Vector2(230, 60))
	close.position = Vector2(1470, 112)
	close.pressed.connect(close_guide)
	_modal.add_child(close)
	var navigation: Array[Button] = _tabs.duplicate()
	navigation.append(close)
	for i in navigation.size():
		var previous := navigation[(i - 1 + navigation.size()) % navigation.size()]
		var next := navigation[(i + 1) % navigation.size()]
		navigation[i].focus_previous = previous.get_path()
		navigation[i].focus_next = next.get_path()
		navigation[i].focus_neighbor_left = previous.get_path()
		navigation[i].focus_neighbor_right = next.get_path()
		navigation[i].focus_neighbor_top = previous.get_path()
		navigation[i].focus_neighbor_bottom = next.get_path()
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(_body)
	_show_stall(index)
	_tabs[index].grab_focus()


func _add_label(parent: Node, r: Rect2, value: String, px: int, color: Color) -> Label:
	var label := UiKit.label(value, px, color)
	label.position = r.position
	label.size = r.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _show_stall(index: int) -> void:
	_selected = index
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	for i in _tabs.size():
		_tabs[i].add_theme_stylebox_override("normal", UiKit.box(GOLD if i == index else PAPER, INK, 2, 10))
	var id: String = run.STALL_ORDER[index]
	var level: int = run.stall_lv.get(id, 0)
	var arms: Array = run._arms.filter(func(a): return a.stall == id)
	_add_label(_body, Rect2(210, 330, 1420, 45), tr("档口等级 %d / %d · %d 把勺子独立工作") % [level, int(run.STALLS[id].max), arms.size()], 30, INK)
	var explanation := tr("新增触手按已营业档口轮流分配；同一档口出现多个圆环，就会有多把勺子同时备菜。")
	_add_label(_body, Rect2(210, 385, 1420, 70), explanation, 25, Color("80654c"))
	var foods: Array = []
	for k in run.NAMES.size():
		if run.STALL[k] == id and not run.IS_SET[k]:
			foods.append(k)
	foods.sort_custom(func(a, b): return run.LEVEL[a] < run.LEVEL[b])
	for j in foods.size():
		var k: int = foods[j]
		var cell := Rect2(210 + (j % 4) * 366, 480 + (j / 4) * 185, 342, 165)
		var unlocked: bool = level >= run.LEVEL[k]
		var card := Panel.new()
		card.position = cell.position
		card.size = cell.size
		card.add_theme_stylebox_override("panel", UiKit.box(Color("f9e5bc") if unlocked else Color("e0dfd4"), Color("cab98f"), 1, 12))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(card)
		var art := TextureRect.new()
		art.texture = run._food_tex[k]
		art.position = Vector2(12, 18)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = Color.WHITE if unlocked else Color(0.6, 0.6, 0.6)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		art.size = Vector2(90, 90)
		_add_label(card, Rect2(114, 16, 215, 62), tr(run.NAMES[k]), 26, INK)
		_add_label(card, Rect2(114, 81, 215, 36), tr("%d 格 · %s token") % [run.SPACE[k], Game.fmt(run.VALUE[k])], 22, INK)
		var status := tr("供应中") if unlocked else tr("Lv.%d 解锁") % run.LEVEL[k]
		if unlocked and run.struck.has(k): status = tr("今日划掉")
		_add_label(card, Rect2(16, 126, 310, 32), status, 23, Color("756240"))
	_add_label(_body, Rect2(210, 877, 1420, 68), tr("升级会扩充本档口的菜谱。每勺先预告一道菜，其余同勺食材随机抽取；圆环颜色变红时即将抛出。"), 25, INK)


func close_guide() -> void:
	if not is_instance_valid(_modal) or _closing:
		return
	_closing = true
	_modal.queue_free()
	_modal = null
	get_tree().paused = false
	run._resume_input_guard = 0.18
	run._think_input_held = true
	if is_instance_valid(_return_focus): _return_focus.grab_focus()
	_closing = false
