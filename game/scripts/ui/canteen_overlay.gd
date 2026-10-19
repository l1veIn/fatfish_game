extends Control
## Live service board. World signs stay behind flying food; the ledger stays off the cook.
const NAVY := Color("183746")
const PAPER := Color("fff2d9")
const GOLD := Color("e9b85e")
const MUTED := Color("a8c5cc")
const CORAL := Color("ff927c")
const TEAL := Color("86d8c3")
const COLORS := [Color("dbab78"), Color("86be98"), Color("ebc16e"), Color("e69a71"), Color("d4a8c9")]
const SYMBOLS := ["dump", "veg", "bowl", "leg", "pudding"]
var run: Node2D
var _font: Font
var _bulb: Texture2D
var _info: Button
var _modal: Control
var _body: Control
var _tabs: Array[Button] = []
var _selected := 2
var _return_focus: Control
var _closing := false
var text_bounds: Array[Rect2] = []


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = load("res://assets/ui/ui_font.tres")
	_bulb = load("res://assets/ui/premium/badge_growth.png")
	_info = UiKit.button(tr("档口指南 · Tab"), 24, Vector2(260, 52))
	_info.focus_mode = Control.FOCUS_NONE
	_info.position = Vector2(38, 190)
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


func _clock_text(seconds: float) -> String:
	var rounded := ceili(maxf(seconds, 0))
	return "%02d:%02d" % [rounded / 60, rounded % 60]


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


func _panel(ci: CanvasItem, r: Rect2, bg := NAVY, edge := GOLD, radius := 16) -> void:
	ci.draw_style_box(UiKit.box(Color(0.03, 0.08, 0.10, 0.28), Color.TRANSPARENT, 0, radius), Rect2(r.position + Vector2(0, 5), r.size))
	ci.draw_style_box(UiKit.box(bg, edge, 2, radius), r)


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
	if ci == self:
		text_bounds.append(r)


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
		var accent: Color = COLORS[i] if level > 0 else Color("8a9692")
		_panel(ci, r, NAVY if level > 0 else Color("334247"), accent, 10)
		var symbol: int = run.KIND.get(SYMBOLS[i], 1)
		_image(ci, run._food_tex[symbol], Rect2(r.position + Vector2(10, 9), Vector2(43, 43)), Color.WHITE if level > 0 else Color(0.65, 0.65, 0.65))
		_text(ci, Rect2(r.position + Vector2(61, 7), Vector2(r.size.x - 69, 35)), tr(run.STALLS[id].name), 27, accent)
		var status := tr("未营业") if level == 0 else tr("Lv.%d · %d 把勺子") % [level, arms.size()]
		_text(ci, Rect2(r.position + Vector2(10, 47), Vector2(r.size.x - 20, 27)), status, 20, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		if level == 0 or arms.is_empty():
			_text(ci, Rect2(r.position + Vector2(10, 89), Vector2(r.size.x - 20, 28)), tr("点击查看升级"), 21, PAPER, HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var columns := mini(arms.size(), 4)
		var step := minf(60, (r.size.x - 22) / columns)
		var rows := ceili(float(arms.size()) / columns)
		for j in arms.size():
			var a: Dictionary = arms[j]
			var c := Vector2(r.get_center().x + (j % columns - (columns - 1) * 0.5) * step, r.position.y + 100 + (j / columns) * 31 - (14 if rows > 1 else 0))
			var radius := 13.0 if rows > 1 else 22.0
			var done := 1.0 if a.raise > 0.0 else clampf(1.0 - a.t / maxf(a.t0, 0.01), 0.0, 1.0)
			ci.draw_circle(c, radius + 3, Color("102631"))
			ci.draw_arc(c, radius + 2, -PI / 2, TAU - PI / 2, 32, Color("57717b"), 3, true)
			if done > 0.001:
				ci.draw_arc(c, radius + 2, -PI / 2, done * TAU - PI / 2, 32, CORAL if a.raise > 0 else accent, 4, true)
			if a.dish >= 0:
				_image(ci, run._food_tex[a.dish], Rect2(c - Vector2.ONE * radius * 0.84, Vector2.ONE * radius * 1.68))
			if a.raise > 0:
				ci.draw_circle(c + Vector2(radius, -radius), 5, CORAL)


func _draw() -> void:
	if _font == null:
		return
	text_bounds.clear()
	# Small clock ticket. No gauge spans the cook's face or the counter's sight line.
	_panel(self, Rect2(30, 22, 334, 152), PAPER, Color("bc8d4c"), 12)
	_text(self, Rect2(50, 34, 290, 28), tr("第一次来，慢慢学") if run._learning() else tr("食堂关门还剩"), 24, NAVY)
	var seconds := maxf(run.meal_time - run._meal_elapsed(), 0)
	_text(self, Rect2(50, 67, 290, 54), tr("计时未开始") if run._learning() else _clock_text(seconds), 45, Color("b84f40") if seconds <= 10 else NAVY)
	var subtitle: String = tr(Game.plate()) if run.trial == "" else tr("目标 %s token") % Game.fmt(run.target)
	_text(self, Rect2(50, 128, 290, 30), subtitle, 23, NAVY)
	if run.peaks:
		_panel(self, Rect2(380, 24, 260, 48), NAVY, CORAL if run._peak_on else MUTED, 10)
		_text(self, Rect2(392, 28, 236, 39), (tr("高峰 %d 秒") if run._peak_on else tr("谷时 %d 秒")) % int(ceil(run._peak_t)), 24, CORAL if run._peak_on else PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	# One compact ledger: score, food balance, thinking, and active build effects.
	_panel(self, Rect2(1498, 22, 400, 470), NAVY, GOLD, 18)
	_text(self, Rect2(1520, 34, 352, 26), tr("本顿收入"), 23, MUTED)
	_text(self, Rect2(1520, 66, 270, 53), Game.fmt(run._shown), 43, GOLD)
	_text(self, Rect2(1795, 80, 78, 32), tr("token"), 22, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(1520, 129), Vector2(1876, 129), Color("52717b"), 1, true)
	_text(self, Rect2(1520, 140, 352, 30), tr("均衡 ×%.2f") % run.balance_mult(), 24, PAPER)
	var total: float = run._cat["主"] + run._cat["荤"] + run._cat["素"]
	var categories := ["主", "荤", "素"]
	for i in 3:
		var key: String = categories[i]
		var share: float = run._cat[key] / total if total > 0 else 0
		var x := 1520 + i * 120
		_text(self, Rect2(x, 176, 110, 27), "%s %d%%" % [tr(key), int(round(share * 100))], 22, run.CAT_COL[key])
		draw_style_box(UiKit.box(Color("304d59"), Color.TRANSPARENT, 0, 3), Rect2(x, 209, 108, 7))
		draw_style_box(UiKit.box(run.CAT_COL[key], Color.TRANSPARENT, 0, 3), Rect2(x, 209, 108 * clampf(share, 0, 1), 7))
	# A physical dial with a large bulb mark; its arc communicates charge and cooldown.
	var c := Vector2(1563, 291)
	_image(self, _bulb, Rect2(c - Vector2(34, 34), Vector2(68, 68)), Color.WHITE if run.can_think else Color(0.4, 0.5, 0.55))
	draw_arc(c, 46, -PI / 2, TAU - PI / 2, 64, Color("3f5965"), 8, true)
	var ratio: float = run._think / maxf(run.think_time, 0.01)
	var col := TEAL
	if run._think_cooldown > 0:
		ratio = 1.0 - run._think_cooldown / run.THINK_COOLDOWN
		col = CORAL
	if run.can_think and ratio > 0.001:
		draw_arc(c, 46, -PI / 2, TAU * ratio - PI / 2, 64, col, 8, true)
	_text(self, Rect2(1625, 238, 246, 35), tr("深度思考"), 27, PAPER)
	var charge := "%.1f / %.1f s" % [run._think, run.think_time] if run.can_think else tr("R1 解锁")
	_text(self, Rect2(1625, 276, 246, 33), charge, 27, col)
	_text(self, Rect2(1625, 314, 246, 29), run._think_hint() if run.can_think else tr("升级后放慢时间"), 21, MUTED)
	draw_line(Vector2(1520, 359), Vector2(1876, 359), Color("52717b"), 1, true)
	var rows: Array = []
	if run.stream > 0: rows.append([tr("流式"), "×%.2f" % run._stream_mult()])
	if run.crave > 0: rows.append([tr("馋"), "×%.2f" % run._crave_x(run._crave_t if run._eating == null else 0.0)])
	if run.combo > 0: rows.append([tr("连击"), str(run._combo_n)])
	if run.grok: rows.append([tr("顿悟"), "✓" if run._grokked else "%d/%d" % [run._grok_n, run.grok_need]])
	if run.critic > 0: rows.append([tr("评鉴"), str(run._kinds_eaten.size())])
	if run.cache_bonus > 0: rows.append([tr("缓存"), "+%d%%" % int(round(run.cache_bonus * 100)) if run._cache_ready else "—"])
	if rows.is_empty():
		_text(self, Rect2(1520, 377, 352, 30), tr("主食 40% · 荤菜 30% · 素菜 30%"), 20, MUTED)
		_text(self, Rect2(1520, 416, 352, 32), tr("搭配三类食材，提升均衡倍率"), 22, PAPER)
	for i in rows.size():
		var x := 1520 + (i % 2) * 183
		var y := 373 + (i / 2) * 34
		_text(self, Rect2(x, y, 82, 29), rows[i][0], 21, MUTED)
		_text(self, Rect2(x + 83, y, 86, 29), rows[i][1], 22, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)


func draw_announcement(ci: CanvasItem) -> void:
	# Render with the counter, behind food and the box: a notice never hides a catch.
	if _font != null and not run._checkout and not run._banners.is_empty():
		var bn: Dictionary = run._banners[0]
		_panel(ci, Rect2(405, 478, 760, 116), NAVY, GOLD, 12)
		_text(ci, Rect2(430, 489, 710, 44), str(bn.title), 32, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		_text(ci, Rect2(430, 539, 710, 37), str(bn.sub), 24, PAPER, HORIZONTAL_ALIGNMENT_CENTER)


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
	shade.color = Color(0.025, 0.065, 0.085, 0.94)
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(160, 80)
	panel.size = Vector2(1600, 920)
	panel.add_theme_stylebox_override("panel", UiKit.box(PAPER, GOLD, 2, 20))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(panel)
	_add_label(_modal, Rect2(210, 110, 1150, 56), tr("梁阿姨的档口"), 44, NAVY)
	_add_label(_modal, Rect2(210, 173, 1390, 50), tr("每把勺子独立备菜。圆环满了，勺子举起，再把菜抛出来。"), 26, NAVY)
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
		_tabs[i].add_theme_stylebox_override("normal", UiKit.box(GOLD if i == index else PAPER, NAVY, 2, 10))
	var id: String = run.STALL_ORDER[index]
	var level: int = run.stall_lv.get(id, 0)
	var arms: Array = run._arms.filter(func(a): return a.stall == id)
	_add_label(_body, Rect2(210, 330, 1420, 45), tr("档口等级 %d / %d · %d 把勺子独立工作") % [level, int(run.STALLS[id].max), arms.size()], 30, NAVY)
	var explanation := tr("新增触手按已营业档口轮流分配；同一档口出现多个圆环，就会有多把勺子同时备菜。")
	_add_label(_body, Rect2(210, 385, 1420, 70), explanation, 25, Color("55717a"))
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
		_add_label(card, Rect2(114, 16, 215, 62), tr(run.NAMES[k]), 26, NAVY)
		_add_label(card, Rect2(114, 81, 215, 36), tr("%d 格 · %s token") % [run.SPACE[k], Game.fmt(run.VALUE[k])], 22, NAVY)
		var status := tr("供应中") if unlocked else tr("Lv.%d 解锁") % run.LEVEL[k]
		if unlocked and run.struck.has(k): status = tr("今日划掉")
		_add_label(card, Rect2(16, 126, 310, 32), status, 23, Color("756240"))
	_add_label(_body, Rect2(210, 877, 1420, 68), tr("升级会扩充本档口的菜谱。每勺先预告一道菜，其余同勺食材随机抽取；圆环颜色变红时即将抛出。"), 25, NAVY)


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
