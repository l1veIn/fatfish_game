class_name MealPlanner
extends Control
## One meal-planning modal, two pages. Game remains the owner of all selections.

signal closed

const INK := Color(0.29, 0.16, 0.08)
const SOFT := Color(0.48, 0.34, 0.23)
const RED := Color(0.68, 0.2, 0.14)
const PAPER := preload("res://assets/canteen/ui_paper.png")

var mode := "menu"
var _cards: Array[Button] = []
var _by_id := {}
var _tabs: Array[Button] = []
var _scroll: ScrollContainer
var _grid: GridContainer
var _count: Label
var _summary: Label
var _detail_name: Label
var _detail_body: Label
var _subtitle: Label
var _rule: Label
var _close: Button
var _done: Button
var _portrait: TextureRect
var _fallback: FishRig
var _closed := false
var _focused_id := ""
var _active: Array = []


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	CanteenRun.load_menu()
	var heading := _label(tr("这顿吃什么？"), Vector2(112, 82), 48, INK, 1190)
	heading.name = "Heading"
	_subtitle = _label("", Vector2(114, 156), 25, SOFT, 1200)
	for i in 2:
		var tab := UiKit.button(tr("今日菜单") if i == 0 else tr("招牌菜"), 30, Vector2(280, 68))
		tab.position = Vector2(112 + i * 300, 210)
		tab.toggle_mode = true
		tab.pressed.connect(func(): show_mode("menu" if i == 0 else "signatures"))
		add_child(tab)
		_tabs.append(tab)
	_close = UiKit.button(tr("返回"), 27, Vector2(200, 64))
	_close.position = Vector2(1600, 90)
	_close.set_meta("ui_back", true)
	_close.pressed.connect(close)
	add_child(_close)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(108, 300)
	_scroll.size = Vector2(1184, 600)
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_scroll.add_child(_grid)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(1320, 238)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_portrait.size = Vector2(470, 326)
	_fallback = FishRig.new()
	_fallback.emote = Game.emotion()
	_fallback.basin = _fallback.emote < 2
	_fallback.idle_clip = "title_basin" if _fallback.basin else "title_idle"
	_fallback.position = Vector2(1544, 560)
	_fallback.height = 390
	add_child(_fallback)
	_fallback.set_process(not Settings.reduced_motion)
	_count = _label("", Vector2(1335, 580), 31, INK, 430)
	_summary = _label("", Vector2(1335, 635), 23, SOFT, 430)
	_summary.max_lines_visible = 3
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_name = _label("", Vector2(1335, 738), 27, INK, 430)
	_detail_name.max_lines_visible = 2
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_body = _label("", Vector2(1335, 816), 23, SOFT, 430)
	_rule = _label("", Vector2(112, 928), 22, SOFT, 1170)
	_done = UiKit.button(tr("准备好了"), 31, Vector2(440, 76))
	_done.position = Vector2(1330, 934)
	_done.set_meta("ui_back", true)
	_done.pressed.connect(close)
	add_child(_done)
	show_mode(mode)
	Game.changed.connect(_refresh)


func _draw() -> void:
	draw_rect(ScreenLayout.full_rect(self), Color(0.06, 0.035, 0.015, 0.83))
	# The window is ordinary warm paper with a thin wooden edge, not an enlarged meal ticket.
	draw_style_box(UiKit.box(UiKit.CREAM, UiKit.WOOD, 2, 18, 3), Rect2(64, 48, 1792, 984))
	draw_texture_rect_region(PAPER, Rect2(76, 60, 1768, 960), Rect2(70, 70, 180, 110), Color(1, 1, 1, 0.18))
	draw_line(Vector2(1306, 292), Vector2(1306, 906), Color(0.53, 0.34, 0.18, 0.25), 2)
	draw_texture_rect(UiKit.glow(), Rect2(1270, 195, 560, 420), false, Color(1.0, 0.74, 0.31, 0.25))


func _label(text: String, at: Vector2, font_size: int, color: Color, width: float) -> Label:
	var label := UiKit.label(text, font_size, color)
	label.position = at
	label.size.x = width
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func show_mode(next: String) -> void:
	mode = "signatures" if next == "signatures" else "menu"
	if not is_node_ready():
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	_by_id.clear()
	_focused_id = ""
	_scroll.scroll_vertical = 0
	_tabs[0].set_pressed_no_signal(mode == "menu")
	_tabs[1].set_pressed_no_signal(mode == "signatures")
	_subtitle.text = tr("把不想吃的划掉，让喜欢的菜多出一点。") if mode == "menu" else tr("把喜欢的菜选为招牌，让这一顿吃出自己的风格。")
	var art := "res://assets/portraits/release/fish_menu_curator.png" if mode == "menu" else "res://assets/portraits/release/fish_signature_chef.png"
	_portrait.texture = load(art) if ResourceLoader.exists(art) else null
	_fallback.visible = _portrait.texture == null
	for id in CanteenRun.KIND:
		var k: int = CanteenRun.KIND[id]
		if CanteenRun.IS_SET[k] or CanteenRun.STALL[k] == "":
			continue
		if mode == "signatures" and CanteenRun.SIG[k] == null:
			continue
		var card := _make_card(id, k)
		_grid.add_child(card)
		_cards.append(card)
		_by_id[id] = card
	_refresh()
	_link_focus()
	_tabs[0 if mode == "menu" else 1].grab_focus.call_deferred()


func _make_card(id: String, k: int) -> Button:
	var card := Button.new()
	card.name = "Dish_" + id
	card.custom_minimum_size = Vector2(376, 286)
	card.set_meta("dish_id", id)
	var pic := TextureRect.new()
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = load("res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[k])
	pic.position = Vector2(82, 56)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pic)
	pic.size = Vector2(212, 126)
	card.set_meta("picture", pic)
	var status := UiKit.label("", 20, RED)
	status.position = Vector2(18, 12)
	status.size.x = 338
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(status)
	card.set_meta("status", status)
	var title := UiKit.label(tr(CanteenRun.NAMES[k]), 27, INK)
	title.position = Vector2(18, 187)
	title.size.x = 340
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)
	var subtitle := UiKit.label(tr(CanteenRun.STALLS[CanteenRun.STALL[k]].name), 20, SOFT)
	subtitle.position = Vector2(18, 253)
	subtitle.size.x = 340
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(subtitle)
	var slash := Control.new()
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slash.draw.connect(func():
		if mode == "menu" and _active.has(id):
			slash.draw_line(Vector2(92, 155), Vector2(286, 70), Color(0.72, 0.23, 0.15, 0.88), 7, true))
	card.add_child(slash)
	card.set_meta("slash", slash)
	card.pressed.connect(func(): _choose(id))
	card.focus_entered.connect(func(): _show_detail(id))
	card.mouse_entered.connect(func(): _show_detail(id))
	return card


func _capacity() -> int:
	return maxi(0, int(Game.stat("menu_cut" if mode == "menu" else "sig_slots")))


func _available(id: String) -> bool:
	var k: int = CanteenRun.KIND[id]
	return Game.stat("stall_" + CanteenRun.STALL[k]) >= CanteenRun.LEVEL[k]


func _refresh() -> void:
	_active = Game.active_struck() if mode == "menu" else Game.active_signatures()
	_count.text = (tr("已划掉 %d / %d 道") if mode == "menu" else tr("本顿招牌 %d / %d 道")) % [_active.size(), _capacity()]
	var names: Array[String] = []
	for id in _active:
		if CanteenRun.KIND.has(id):
			names.append(tr(CanteenRun.NAMES[CanteenRun.KIND[id]]))
	_summary.text = " · ".join(names) if not names.is_empty() else tr("还没有划掉任何菜，今天全都保留。") if mode == "menu" else tr("先升级档口，就能把喜欢的菜挂上招牌。")
	_rule.text = tr("即时保存 · Enter / A 选择 · Esc / B 返回") + "\n"
	_rule.text += tr("每档至少留一道；名额用满时，新选择会替换最早划掉的一项。") if mode == "menu" else tr("空位会自动补齐；选择别的菜，就能换掉最早的一道招牌。")
	for card in _cards:
		var id: String = card.get_meta("dish_id")
		var chosen := _active.has(id)
		var available := _available(id)
		var normal := Color(1.0, 0.965, 0.87) if available else Color(0.85, 0.81, 0.72)
		var border := UiKit.WOOD
		if chosen:
			normal = Color(0.91, 0.84, 0.72) if mode == "menu" else Color(1.0, 0.86, 0.51)
			border = RED if mode == "menu" else Color(0.72, 0.4, 0.08)
		card.add_theme_stylebox_override("normal", UiKit.box(normal, border, 3 if chosen else 2, 18, 3))
		card.add_theme_stylebox_override("hover", UiKit.box(normal.lightened(0.07), border, 3, 18, 3))
		card.add_theme_stylebox_override("pressed", UiKit.box(normal.darkened(0.06), border, 3, 18, 2))
		var status: Label = card.get_meta("status")
		status.text = tr("已划掉") if chosen and mode == "menu" else tr("招牌 %d") % (_active.find(id) + 1) if chosen else tr("未解锁") if not available else tr("保留出餐") if mode == "menu" else tr("可选招牌")
		if mode == "menu" and not chosen and available and _capacity() > 0 and Game.struck_toggle_reason(id) != "":
			status.text = tr("档口最后一道 · 保留")
		var pic: TextureRect = card.get_meta("picture")
		pic.modulate = Color(0.65, 0.59, 0.52, 0.6) if chosen and mode == "menu" else Color(0.5, 0.46, 0.4, 0.65) if not available else Color.WHITE
		card.get_meta("slash").queue_redraw()
	if _focused_id == "" and not _cards.is_empty():
		_focused_id = str(_cards[0].get_meta("dish_id"))
	_show_detail(_focused_id)


func _show_detail(id: String) -> void:
	if id == "" or not CanteenRun.KIND.has(id):
		return
	_focused_id = id
	var k: int = CanteenRun.KIND[id]
	_detail_name.text = tr(CanteenRun.NAMES[k])
	if not _available(id):
		_detail_body.text = tr("%s档口升到 %d 级后解锁。") % [tr(CanteenRun.STALLS[CanteenRun.STALL[k]].name), CanteenRun.LEVEL[k]]
	elif mode == "signatures":
		_detail_body.text = _sig_text(CanteenRun.SIG[k])
	else:
		_detail_body.text = tr("这道菜不出餐，原本的机会留给同档口的其他菜。") if _active.has(id) else tr("这道菜照常出餐。点击卡片，可以把它从今日菜单划掉。")
		var reason: String = Game.struck_toggle_reason(id)
		if reason != "":
			_detail_body.text = tr(reason)


func _choose(id: String) -> void:
	if mode == "menu":
		var reason: String = Game.struck_toggle_reason(id)
		if reason != "":
			Audio.sfx("deny", -7)
			_show_detail(id)
			_detail_body.text = tr(reason)
			return
	if not _available(id) and not _active.has(id):
		Audio.sfx("deny", -7)
		_show_detail(id)
		return
	if _capacity() == 0:
		Audio.sfx("deny", -7)
		_detail_name.text = tr("先去点亮技能")
		_detail_body.text = tr("升级「今日菜单」增加划菜名额。") if mode == "menu" else tr("升级「MoE 激活专家」增加招牌名额。")
		return
	var before := _active.duplicate()
	if mode == "menu":
		Game.toggle_struck(id)
	else:
		Game.toggle_signature(id)
	_refresh()
	_show_detail(id)
	if mode == "signatures" and before == _active:
		_detail_body.text = tr("招牌会自动补齐，选择另一道菜即可替换。")
	# Game.changed updates the same cards; the button and its focus never disappear.


func _sig_text(effect: Dictionary) -> String:
	if effect.has("stack"):
		return tr("每吃一份，本顿它的价值 +%d%%（叠加）") % int(float(effect.stack) * 100)
	if effect.has("mult"):
		return tr("价值 ×%.1f，但它的档口出餐慢 %d%%") % [float(effect.mult), int(float(effect.slow) * 100)]
	return tr("每吃一份，均衡倍率 +%.2f") % float(effect.balance)


func _link_focus() -> void:
	var chain: Array[Control] = [_tabs[0], _tabs[1], _close]
	chain.append_array(_cards)
	chain.append(_done)
	for i in chain.size():
		chain[i].focus_next = chain[i].get_path_to(chain[(i + 1) % chain.size()])
		chain[i].focus_previous = chain[i].get_path_to(chain[posmod(i - 1, chain.size())])
	for i in _cards.size():
		var card: Button = _cards[i]
		card.focus_neighbor_top = card.get_path_to(_cards[i - 3] if i >= 3 else _tabs[0 if mode == "menu" else 1])
		card.focus_neighbor_bottom = card.get_path_to(_cards[i + 3] if i + 3 < _cards.size() else _done)
		card.focus_neighbor_left = card.get_path_to(_cards[i - 1] if i % 3 > 0 else card)
		card.focus_neighbor_right = card.get_path_to(_cards[i + 1] if i % 3 < 2 and i + 1 < _cards.size() else _done)
	for tab in _tabs:
		tab.focus_neighbor_bottom = tab.get_path_to(_cards[0] if not _cards.is_empty() else _done)
		tab.focus_neighbor_top = tab.get_path_to(_done)
	_tabs[0].focus_neighbor_left = _tabs[0].get_path_to(_close)
	_tabs[0].focus_neighbor_right = _tabs[0].get_path_to(_tabs[1])
	_tabs[1].focus_neighbor_left = _tabs[1].get_path_to(_tabs[0])
	_tabs[1].focus_neighbor_right = _tabs[1].get_path_to(_close)
	_close.focus_neighbor_left = _close.get_path_to(_tabs[1])
	_close.focus_neighbor_right = _close.get_path_to(_tabs[0])
	_close.focus_neighbor_bottom = _close.get_path_to(_done)
	_done.focus_neighbor_top = _done.get_path_to(_cards.back() if not _cards.is_empty() else _tabs[0])
	_done.focus_neighbor_left = _done.get_path_to(_cards.back() if not _cards.is_empty() else _tabs[0])
	_done.focus_neighbor_bottom = _done.get_path_to(_tabs[0])
	_done.focus_neighbor_right = _done.get_path_to(_close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# No unhandled planning input may reach the skill tree (especially G/Y to start).
		get_viewport().set_input_as_handled()


func close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	queue_free()
