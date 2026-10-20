extends Control
## A temporary selection: inspecting a card never changes a helper's saved assignment.
signal chosen(id: String)
signal cancelled
const INK := Color("4a2914")
const SOFT := Color("79604b")
const PAPER := preload("res://assets/canteen/ui_paper.png")
var selected := ""
var member_name := ""
var _pending := ""
var _tier := 0
var _options: Array = []
var _parts := {}
var _cards := {}
var _filters: Array[Button] = []
var _search: LineEdit
var _grid: GridContainer
var _scroll: ScrollContainer
var _detail: Control
var _confirm: Button
var _back: Button
var _count: Label


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1
	_options = Game.helper_recipe_options()
	var sim := CanteenRun.new()
	for recipe in _options: _parts[recipe.id] = sim._ingredients(int(recipe.kind))
	sim.free()
	_pending = selected
	_label(self, tr("给 %s 点一道套餐") % member_name, Rect2(112, 80, 1390, 68), 42)
	_label(self, tr("只显示当前菜单和饭盒能配齐的套餐。选中查看原料，确认后下顿生效。"), Rect2(114, 160, 1400, 60), 25, SOFT)
	_back = _button(self, tr("返回"), Rect2(1600, 88, 200, 64))
	_back.pressed.connect(func(): cancelled.emit())
	_back.set_meta("ui_back", true)
	_search = LineEdit.new()
	_search.placeholder_text = tr("搜套餐或原料")
	_search.position = Vector2(112, 236)
	_search.size = Vector2(400, 62)
	_search.add_theme_font_size_override("font_size", 24)
	_search.add_theme_stylebox_override("normal", UiKit.box(Color("fff9eb"), UiKit.WOOD, 1, 10, 3))
	_search.add_theme_stylebox_override("focus", UiKit.box(Color.TRANSPARENT, Color("c78c42"), 3, 10))
	_search.add_theme_color_override("font_color", INK)
	_search.add_theme_color_override("font_placeholder_color", SOFT)
	_search.add_theme_color_override("caret_color", INK)
	add_child(_search)
	_search.text_changed.connect(func(_text): _build_cards())
	for i in 5:
		var title: String = tr("全部") if i == 0 else tr(CanteenRun.TIER_NAME[i])
		# Compact tab labels; the full localized tier name remains on every meal card.
		if Settings.is_english(): title = ["All", "Small", "Tier 2", "Tier 3", "Legendary"][i] # notr
		var b := _button(self, title, Rect2(536 + i * 150, 236, 140, 62))
		b.pressed.connect(func():
			_tier = i
			_build_cards())
		_filters.append(b)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(112, 326)
	_scroll.size = Vector2(1160, 594)
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_scroll.add_child(_grid)
	_detail = Control.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	_count = _label(self, "", Rect2(112, 948, 1140, 52), 24, SOFT)
	_confirm = _button(self, tr("就做这道"), Rect2(1320, 934, 452, 72))
	_confirm.pressed.connect(func():
		if _options.any(func(r): return str(r.id) == _pending): chosen.emit(_pending))
	_build_cards()
	_show_detail()
	if _cards.has(selected): _cards[selected].grab_focus.call_deferred()
	elif not _cards.is_empty(): _cards.values()[0].grab_focus.call_deferred()
	else: _back.grab_focus.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.06, 0.035, 0.015, 0.9))
	draw_style_box(UiKit.box(UiKit.CREAM, UiKit.WOOD, 2, 18, 3), Rect2(64, 48, 1792, 984))
	draw_texture_rect_region(PAPER, Rect2(76, 60, 1768, 960), Rect2(70, 70, 180, 110), Color(1, 1, 1, 0.18))
	draw_line(Vector2(1294, 326), Vector2(1294, 910), Color(0.53, 0.34, 0.18, 0.25), 2)


func _build_cards() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	_scroll.scroll_vertical = 0
	for i in _filters.size(): _style(_filters[i], i == _tier)
	var query := _search.text.strip_edges().to_lower()
	for r in _options:
		var k := int(r.kind)
		if _tier > 0 and CanteenRun.TIER[k] != _tier: continue
		var search_text := tr(str(r.name)) + " " + str(r.name)
		for part in _parts[r.id]: search_text += " " + tr(CanteenRun.NAMES[part]) + " " + CanteenRun.NAMES[part]
		if query != "" and not search_text.to_lower().contains(query): continue
		var card := _button(_grid, "", Rect2(0, 0, 368, 166))
		_style(card, str(r.id) == _pending)
		_picture(card, k, Rect2(12, 20, 94, 94))
		_label(card, tr(str(r.name)), Rect2(116, 16, 238, 78), 25)
		_label(card, tr(CanteenRun.TIER_NAME[CanteenRun.TIER[k]]), Rect2(116, 106, 238, 38), 22, SOFT)
		card.pressed.connect(_inspect.bind(str(r.id)))
		_cards[r.id] = card
	_count.text = tr("可选 %d 道 · 共 %d 道可配齐") % [_cards.size(), _options.size()]
	if _cards.is_empty():
		_label(_grid, tr("没有匹配的套餐，试试其他原料或分类。"), Rect2(0, 0, 1100, 100), 27, SOFT)
	_wire_focus()


func _inspect(id: String) -> void:
	_pending = id
	for key in _cards: _style(_cards[key], key == id)
	_show_detail()


func _show_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var matches := _options.filter(func(r): return str(r.id) == _pending)
	_confirm.disabled = matches.is_empty()
	if matches.is_empty(): return
	var recipe: Dictionary = matches[0]
	var k := int(recipe.kind)
	_picture(_detail, k, Rect2(1444, 326, 200, 160))
	_label(_detail, tr(str(recipe.name)), Rect2(1320, 496, 452, 84), 32)
	_label(_detail, tr("所需原料"), Rect2(1320, 590, 452, 40), 26, SOFT)
	var counts := {}
	for part in _parts[recipe.id]: counts[part] = int(counts.get(part, 0)) + 1
	var i := 0
	var rare := false
	for part in counts:
		var at := Vector2(1320 + (i % 2) * 232, 642 + (i / 2) * 66)
		_picture(_detail, part, Rect2(at, Vector2(46, 46)))
		var caption := tr(CanteenRun.NAMES[part])
		if counts[part] > 1: caption += " ×%d" % counts[part]
		_label(_detail, caption, Rect2(at + Vector2(54, 0), Vector2(170, 60)), 21)
		rare = rare or CanteenRun.RARE[part]
		i += 1
	_label(_detail, tr("配齐才送；稀有原料等得更久。") if rare else tr("配齐这道套餐后送餐，再开始下一盒。"), Rect2(1320, 852, 452, 70), 23, SOFT)


func _wire_focus() -> void:
	var controls: Array = [_search]
	controls.append_array(_filters)
	controls.append_array(_cards.values())
	controls.append(_confirm)
	controls.append(_back)
	controls = controls.filter(func(c): return not (c is BaseButton and c.disabled))
	for i in controls.size():
		var c: Control = controls[i]
		c.focus_next = c.get_path_to(controls[(i + 1) % controls.size()])
		c.focus_previous = c.get_path_to(controls[posmod(i - 1, controls.size())])
		c.focus_neighbor_right = c.focus_next
		c.focus_neighbor_left = c.focus_previous
		c.focus_neighbor_bottom = c.focus_next
		c.focus_neighbor_top = c.focus_previous
	var cards := _cards.values()
	for i in cards.size():
		if i >= 3: cards[i].focus_neighbor_top = cards[i].get_path_to(cards[i - 3])
		if i + 3 < cards.size(): cards[i].focus_neighbor_bottom = cards[i].get_path_to(cards[i + 3])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		cancelled.emit()


func _label(parent: Node, text: String, rect: Rect2, fs: int, color := INK) -> Label:
	var label := UiKit.label("", fs, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	if parent is Container: label.custom_minimum_size = rect.size
	label.set_meta("crew_rect", rect.size)
	return label


func _picture(parent: Node, k: int, rect: Rect2) -> void:
	var picture := TextureRect.new()
	picture.texture = load("res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[k])
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	picture.position = rect.position
	picture.size = rect.size
	picture.set_meta("crew_rect", rect.size)


func _button(parent: Node, text: String, rect: Rect2) -> Button:
	var button := UiKit.button(text, 25, rect.size)
	parent.add_child(button)
	var fs := 25
	while fs > 14 and button.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x - 52:
		fs -= 1
	button.add_theme_font_size_override("font_size", fs)
	button.position = rect.position
	button.size = rect.size
	button.set_meta("crew_rect", rect.size)
	return button


func _style(button: Button, selected_card: bool) -> void:
	button.add_theme_stylebox_override("normal", UiKit.box(Color("f4dfac") if selected_card else UiKit.CREAM, Color("a35c31") if selected_card else UiKit.WOOD, 3 if selected_card else 1, 12, 3))
