extends Control
## Painted name plaques; supply details are available through the pause menu.
const INK := UiKit.INK
const PAPER := Color("fff2d9")
const GOLD := Color("e9b85e")
const MUTED := Color("80654c")
const CORAL := Color("bb5033")
const TEAL := Color("6b9271")
const COLORS := [Color("dbab78"), Color("86be98"), Color("ebc16e"), Color("e69a71"), Color("d4a8c9")]
const SIGN_IDS := ["dim", "wok", "main", "fry", "sweet"]
var run: Node2D
var _font: Font
var _signs: Array[Texture2D] = []
var _pause_owner: Control
var _modal: Control
var _body: Control
var _tabs: Array[Button] = []
var _selected := 2
var _selected_id := "main"
var _move_left: Button
var _move_right: Button
var _reset_order: Button
var _close_button: Button
var _layout_hint: Label
var _return_focus: Control
var _closing := false


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = load("res://assets/ui/ui_font.tres")
	_load_signs()
	Settings.changed.connect(_load_signs)


func _load_signs() -> void:
	_signs.clear()
	var locale := "en" if Settings.language == "en" else "zh"
	for id in SIGN_IDS:
		_signs.append(load("res://assets/canteen/signs/%s_%s.png" % [id, locale]))



func _process(_delta: float) -> void:
	visible = not run._checkout
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_instance_valid(_modal) and event.keycode in [KEY_ESCAPE, KEY_P]:
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
	var order: Array = run.stall_order
	var pans: Array = run.stall_pans(order[i])
	var left := float(pans[0]) - 47
	var right := float(pans[-1]) + 47
	if i > 0:
		left = (float(run.stall_pans(order[i - 1])[-1]) + float(pans[0])) * 0.5 + 6
	if i < order.size() - 1:
		right = (float(run.stall_pans(order[i + 1])[0]) + float(pans[-1])) * 0.5 - 6
	return Rect2(left, 321, right - left, 136)


func draw_stalls(ci: CanvasItem) -> void:
	if _font == null:
		return
	for i in run.stall_order.size():
		var id: String = run.stall_order[i]
		var identity := SIGN_IDS.find(id)
		var r := stall_rect(i)
		var level: int = run.stall_lv.get(id, 0)
		var arms: Array = run._arms.filter(func(a): return a.stall == id)
		var accent: Color = COLORS[identity] if level > 0 else MUTED
		# Each sign is authored at its final small-screen purpose, with no level prose.
		_image(ci, _signs[identity], Rect2(r.get_center().x - minf(260, r.size.x) * 0.5, 315, minf(260, r.size.x), 87), Color.WHITE if level > 0 else Color(0.64, 0.60, 0.54))

		if level == 0 or arms.is_empty():
			continue
		var columns := mini(arms.size(), 4)
		var step := minf(60, (r.size.x - 22) / columns)
		var rows := ceili(float(arms.size()) / columns)
		for j in arms.size():
			var a: Dictionary = arms[j]
			var c := Vector2(r.get_center().x + (j % columns - (columns - 1) * 0.5) * step, r.position.y + 99 + (j / columns) * 31 - (14 if rows > 1 else 0))
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


func open_guide(index := -1, pause_owner: Control = null) -> void:
	if is_instance_valid(_modal) or run._ended or not get_tree().paused or not is_instance_valid(pause_owner):
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	_pause_owner = pause_owner
	_modal = Control.new()
	_modal.size = size
	_modal.z_index = 110
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_owner.add_child(_modal)
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
	_add_label(_modal, Rect2(210, 104, 1150, 64), tr("梁阿姨的档口"), 42, INK)
	_add_label(_modal, Rect2(210, 173, 1390, 50), tr("每把勺子独立备菜。圆环满了，勺子举起，再把菜抛出来。"), 26, INK)
	_tabs.clear()
	for i in run.stall_order.size():
		var b := UiKit.button("", 28, Vector2(274, 118))
		b.position = Vector2(210 + i * 292, 232)
		b.pressed.connect(func(): _show_stall(i))
		_modal.add_child(b)
		var sign := TextureRect.new()
		sign.name = "Sign"
		sign.position = Vector2(9, 3)
		sign.size = Vector2(256, 82)
		sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sign.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sign)
		var status := _add_label(b, Rect2(16, 81, 242, 30), "", 21, INK)
		status.name = "Status"
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tabs.append(b)
	_move_left = _action(tr("向左换位"), Rect2(210, 370, 220, 62), func(): _move_selected(-1))
	_move_right = _action(tr("向右换位"), Rect2(446, 370, 220, 62), func(): _move_selected(1))
	_reset_order = _action(tr("恢复默认位置"), Rect2(682, 370, 278, 62), _restore_order)
	_layout_hint = _add_label(_modal, Rect2(984, 370, 706, 76), tr("选中档口，左右换位。立即保存，本顿生效。"), 23, MUTED)
	_close_button = _action(tr("返回暂停菜单"), Rect2(1440, 112, 260, 60), close_guide)
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(_body)
	if index < 0:
		index = run.stall_order.find(_selected_id)
	_show_stall(clampi(index, 0, _tabs.size() - 1))
	_tabs[_selected].grab_focus()


func _action(text: String, rect: Rect2, callback: Callable) -> Button:
	var button := UiKit.button(text, 26, rect.size)
	button.position = rect.position
	button.pressed.connect(callback)
	_modal.add_child(button)
	return button


func _wire_focus() -> void:
	var actions: Array[Button] = []
	for b in [_move_left, _move_right, _reset_order]:
		if not b.disabled:
			actions.append(b)
	var all: Array[Button] = _tabs.duplicate()
	all.append_array(actions)
	all.append(_close_button)
	for i in all.size():
		all[i].focus_previous = all[i].get_path_to(all[posmod(i - 1, all.size())])
		all[i].focus_next = all[i].get_path_to(all[(i + 1) % all.size()])
	for i in _tabs.size():
		var b := _tabs[i]
		b.focus_neighbor_left = b.get_path_to(_tabs[posmod(i - 1, _tabs.size())])
		b.focus_neighbor_right = b.get_path_to(_tabs[(i + 1) % _tabs.size()])
		b.focus_neighbor_top = b.get_path_to(_close_button)
		b.focus_neighbor_bottom = b.get_path_to(actions[0])
	for i in actions.size():
		var b := actions[i]
		b.focus_neighbor_left = b.get_path_to(actions[posmod(i - 1, actions.size())])
		b.focus_neighbor_right = b.get_path_to(actions[(i + 1) % actions.size()])
		b.focus_neighbor_top = b.get_path_to(_tabs[_selected])
		b.focus_neighbor_bottom = b.get_path_to(_close_button)
	_close_button.focus_neighbor_left = _close_button.get_path_to(_tabs[-1])
	_close_button.focus_neighbor_right = _close_button.get_path_to(_tabs[0])
	_close_button.focus_neighbor_top = _close_button.get_path_to(actions[-1])
	_close_button.focus_neighbor_bottom = _close_button.get_path_to(_tabs[_selected])


func _move_selected(direction: int) -> void:
	var next := _selected + direction
	if next < 0 or next >= run.stall_order.size():
		return
	var order: Array = run.stall_order.duplicate()
	order[_selected] = order[next]
	order[next] = _selected_id
	_apply_layout(order)


func _restore_order() -> void:
	_apply_layout(Game.DEFAULT_STALL_ORDER.duplicate())


func _apply_layout(order: Array) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if not run.apply_stall_order(order):
		_layout_hint.text = tr("换位未完成，请稍后重试。")
		_layout_hint.add_theme_color_override("font_color", CORAL)
		return
	_show_stall(run.stall_order.find(_selected_id))
	_layout_hint.text = tr("已保存位置，本顿立即生效。")
	_layout_hint.add_theme_color_override("font_color", MUTED)
	if is_instance_valid(focus) and focus is Button and not focus.disabled:
		focus.grab_focus()
	else:
		_tabs[_selected].grab_focus()


func _add_label(parent: Node, r: Rect2, value: String, px: int, color: Color) -> Label:
	var label := UiKit.label(value, px, color)
	label.position = r.position
	label.size = r.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("stall_rect", r.size)
	parent.add_child(label)
	return label


func _show_stall(index: int) -> void:
	_selected = index
	_selected_id = run.stall_order[index]
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	for i in _tabs.size():
		_tabs[i].add_theme_stylebox_override("normal", UiKit.box(GOLD if i == index else PAPER, INK, 2, 10))
		var tab_id: String = run.stall_order[i]
		_tabs[i].set_meta("stall_id", tab_id)
		_tabs[i].tooltip_text = tr(run.STALLS[tab_id].name)
		var sign: TextureRect = _tabs[i].get_node("Sign")
		sign.texture = _signs[SIGN_IDS.find(tab_id)]
		var open: bool = run.stall_lv.get(tab_id, 0) > 0
		sign.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.6)
		var status: Label = _tabs[i].get_node("Status")
		status.text = "%d · %s" % [i + 1, tr("供应中") if open else tr("尚未开张")]
	_move_left.disabled = index == 0
	_move_right.disabled = index == _tabs.size() - 1
	_reset_order.disabled = run.stall_order == Game.DEFAULT_STALL_ORDER
	_wire_focus()
	var id := _selected_id
	var level: int = run.stall_lv.get(id, 0)
	var arms: Array = run._arms.filter(func(a): return a.stall == id)
	_add_label(_body, Rect2(210, 452, 1480, 45), tr("档口等级 %d / %d · %d 把勺子独立工作") % [level, int(run.STALLS[id].max), arms.size()], 28, INK)
	var explanation := tr("新增触手按已营业档口轮流分配；同一档口出现多个圆环，就会有多把勺子同时备菜。")
	_add_label(_body, Rect2(210, 502, 1480, 52), explanation, 23, Color("80654c"))
	var foods: Array = []
	for k in run.NAMES.size():
		if run.STALL[k] == id and not run.IS_SET[k]:
			foods.append(k)
	foods.sort_custom(func(a, b): return run.LEVEL[a] < run.LEVEL[b])
	for j in foods.size():
		var k: int = foods[j]
		var cell := Rect2(210 + (j % 4) * 366, 566 + (j / 4) * 154, 342, 140)
		var unlocked: bool = level >= run.LEVEL[k]
		var card := Panel.new()
		card.position = cell.position
		card.size = cell.size
		card.add_theme_stylebox_override("panel", UiKit.box(Color("f9e5bc") if unlocked else Color("e0dfd4"), Color("cab98f"), 1, 12))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(card)
		var art := TextureRect.new()
		art.texture = run._food_tex[k]
		art.position = Vector2(12, 10)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = Color.WHITE if unlocked else Color(0.6, 0.6, 0.6)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		art.size = Vector2(90, 90)
		_add_label(card, Rect2(114, 12, 215, 58), tr(run.NAMES[k]), 24, INK)
		_add_label(card, Rect2(114, 73, 215, 30), tr("%d 格 · %s token") % [run.SPACE[k], Game.fmt(run.VALUE[k])], 21, INK)
		var status := tr("供应中") if unlocked else tr("Lv.%d 解锁") % run.LEVEL[k]
		if unlocked and run.struck.has(k): status = tr("今日划掉")
		_add_label(card, Rect2(16, 108, 310, 28), status, 21, Color("756240"))
	_add_label(_body, Rect2(210, 877, 1420, 84), tr("升级会扩充本档口的菜谱。每勺先预告一道菜，其余同勺食材随机抽取；圆环颜色变红时即将抛出。"), 25, INK)


func close_guide() -> void:
	if not is_instance_valid(_modal) or _closing:
		return
	_closing = true
	_modal.queue_free()
	_modal = null
	_pause_owner = null
	if is_instance_valid(_return_focus): _return_focus.grab_focus()
	_closing = false
