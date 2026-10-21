class_name RecipeBook
extends Control
## A real two-page cookbook: one fixed spread at a time, never a scrolling page.
signal closed

const INK := Color("4a2914")
const MUTED := Color("78604b")
const PAPER := Color("f6edda")
const GOLD := Color("b98b46")
const CHAPTERS := ["index", "sets", "foods", "rules"]
const CHAPTER_NAMES := ["目录", "套餐", "食材", "食堂说明"]
const LEFT := Vector2(235, 286)
const RIGHT := Vector2(1065, 286)
const PAGE_WIDTH := 620.0
var _page := "index"
var _spread := 0
var _page_count := 1
var _tabs: Array[Button] = []
var _index_buttons: Array[Button] = []
var _entry_controls: Array[Control] = []
var _leaves: Array = []
var _back: Button
var _previous: Button
var _next: Button
var _content: Control
var _heading: Label
var _hint: Label
var _position_label: Label
var _closed := false
var _return_focus: WeakRef
var _language := ""
var _control_labels := ""


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		_return_focus = weakref(focused)
	CanteenRun.load_menu()
	_language = TranslationServer.get_locale()
	_control_labels = _control_signature()
	_picture(self, "res://assets/canteen/bg_wall.png", Rect2(Vector2.ZERO, size), false)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.16, 0.08, 0.03, 0.42)
	backdrop.size = size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	# The generated spread provides the material; text remains crisp, live and accessible.
	var art_path := "res://assets/ui/premium/recipe_spread.png"
	if ResourceLoader.exists(art_path):
		_picture(self, art_path, Rect2(120, 126, 1680, 945), true)
	else:
		for rect in [Rect2(90, 196, 852, 770), Rect2(978, 196, 852, 770)]:
			_panel(self, rect, PAPER, Color("cdbd9b"), 2, 5)
		_panel(self, Rect2(941, 196, 37, 770), Color("cfbfa0"), Color.TRANSPARENT, 0, 0)
	_heading = _text(self, "", Rect2(115, 25, 730, 78), 48, Color("fff3d5"))
	_heading.add_theme_constant_override("outline_size", 8)
	_heading.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_back = _button(self, "", Rect2(1580, 45, 230, 66), true)
	_back.set_meta("ui_back", true)
	_back.pressed.connect(_close)
	for i in CHAPTERS.size():
		var tab := _button(self, "", Rect2(170 + i * 325, 132, 300, 64), false)
		tab.set_meta("chapter", CHAPTERS[i])
		tab.pressed.connect(_set_chapter.bind(CHAPTERS[i]))
		_tabs.append(tab)
	_previous = _button(self, "", Rect2(150, 994, 240, 62), true)
	_previous.pressed.connect(_turn.bind(-1))
	_next = _button(self, "", Rect2(1530, 994, 240, 62), true)
	_next.pressed.connect(_turn.bind(1))
	_position_label = _text(self, "", Rect2(850, 40, 660, 42), 26, Color("fff3d5"), HORIZONTAL_ALIGNMENT_CENTER)
	_position_label.add_theme_constant_override("outline_size", 5)
	_position_label.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_hint = _text(self, "", Rect2(115, 98, 1300, 30), 21, UiKit.TEXT)
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	Settings.changed.connect(_on_settings_changed)
	_fill()
	_tabs[0].grab_focus.call_deferred()


func _on_settings_changed() -> void:
	var controls := _control_signature()
	if _language != TranslationServer.get_locale() or controls != _control_labels:
		_language = TranslationServer.get_locale()
		_control_labels = controls
		var old_index := _index_buttons.find(get_viewport().gui_get_focus_owner())
		_fill()
		if old_index >= 0 and old_index < _index_buttons.size():
			_index_buttons[old_index].grab_focus.call_deferred()


func _control_signature() -> String:
	var labels: Array[String] = []
	for device in ["keyboard", "gamepad"]:
		for action in ["move_up", "move_down", "move_left", "move_right", "deliver", "think"]:
			labels.append(Settings.binding_label(action, device))
	return "|".join(labels)


func _movement_label(device: String) -> String:
	return "↑ %s  ↓ %s  ← %s  → %s" % [Settings.binding_label("move_up", device),
		Settings.binding_label("move_down", device), Settings.binding_label("move_left", device),
		Settings.binding_label("move_right", device)]


func _set_chapter(chapter: String) -> void:
	_page = chapter
	_spread = 0
	_fill()
	_tabs[CHAPTERS.find(_page)].grab_focus.call_deferred()


func _turn(direction: int) -> void:
	var next_spread := clampi(_spread + direction, 0, _page_count - 1)
	if next_spread == _spread:
		return
	_spread = next_spread
	Audio.sfx("ui_click", -8.0)
	_fill()
	var target := _next if direction > 0 and not _next.disabled else _previous
	if target.disabled:
		target = _tabs[CHAPTERS.find(_page)]
	target.grab_focus.call_deferred()


func _fill() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_index_buttons.clear()
	_entry_controls.clear()
	_heading.text = tr("菜谱图鉴")
	_back.text = tr("合上") + "  ×"
	_previous.text = "←  " + tr("上一页")
	_next.text = tr("下一页") + "  →"
	_hint.text = tr("PgUp / PgDn 或 LB / RB 翻页 · Esc / B 合上")
	var entries := _entries()
	_leaves = _paginate(entries)
	_page_count = maxi(1, ceili(float(_leaves.size()) / 2.0))
	_spread = clampi(_spread, 0, _page_count - 1)
	_previous.disabled = _spread == 0
	_next.disabled = _spread >= _page_count - 1
	var chapter_name := tr(CHAPTER_NAMES[CHAPTERS.find(_page)])
	_position_label.text = tr("%s · 第 %d / %d 跨页") % [chapter_name, _spread + 1, _page_count]
	for i in _tabs.size():
		_tabs[i].text = tr(CHAPTER_NAMES[i])
		_style_button(_tabs[i], CHAPTERS[i] == _page, false)
	for side in 2:
		var origin: Vector2 = LEFT if side == 0 else RIGHT
		_text(_content, chapter_name, Rect2(origin.x, 225, PAGE_WIDTH, 40), 27, MUTED)
		_line(_content, Rect2(origin.x, 274, PAGE_WIDTH, 2), Color("c8b892"))
		_text(_content, "%02d" % (_spread * 2 + side + 1), Rect2(origin.x, 911, PAGE_WIDTH, 36), 25, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	if _page == "index":
		_fill_index()
	else:
		for side in 2:
			var origin: Vector2 = LEFT if side == 0 else RIGHT
			var page_index := _spread * 2 + side
			if page_index >= _leaves.size():
				_text(_content, tr("这一章读完啦"), Rect2(origin.x + 70, 500, 480, 70), 32, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
				continue
			var leaf: Array = _leaves[page_index]
			for row in leaf.size():
				var entry = leaf[row]
				if _page == "sets":
					_recipe(entry, origin + Vector2(0, row * 296), entries.find(entry), leaf.size() == 1 and entry.needs.size() > 3)
				elif _page == "foods":
					_food(int(entry), origin + Vector2(0, row * 202))
				else:
					_rule(entry, origin, entries.find(entry))
	_link_focus()


func _paginate(entries: Array) -> Array:
	var pages: Array = []
	var leaf: Array = []
	var capacity := 2 if _page == "sets" else (3 if _page == "foods" else 1)
	for entry in entries:
		# A grand recipe gets a whole leaf in both languages, rather than shrinking its text.
		var grand: bool = _page == "sets" and entry.needs.size() > 3
		if grand:
			if not leaf.is_empty():
				pages.append(leaf)
				leaf = []
			pages.append([entry])
		else:
			leaf.append(entry)
			if leaf.size() == capacity:
				pages.append(leaf)
				leaf = []
	if not leaf.is_empty():
		pages.append(leaf)
	return pages


func _entries() -> Array:
	if _page == "sets":
		return CanteenRun.RECIPES
	if _page == "foods":
		var out: Array = []
		for stall in CanteenRun.STALL_ORDER:
			for k in CanteenRun.NAMES.size():
				if not CanteenRun.IS_SET[k] and CanteenRun.STALL[k] == stall:
					out.append(k)
		return out
	if _page == "rules":
		return _rules()
	return []


func _fill_index() -> void:
	_text(_content, tr("今天，想翻哪一页？"), Rect2(LEFT.x, 310, PAGE_WIDTH, 60), 38, INK)
	var sources := ["把散菜拼成一道好饭", "认识每个档口的食材", "从第一盒到自己的吃法"]
	for i in 3:
		var key: String = CHAPTERS[i + 1]
		var y := 408 + i * 140
		var b := _button(_content, "", Rect2(LEFT.x, y, PAGE_WIDTH, 116), false)
		_style_button(b, false, false)
		_text(b, "0%d" % (i + 1), Rect2(20, 21, 64, 56), 38, GOLD)
		_text(b, tr(CHAPTER_NAMES[i + 1]), Rect2(100, 12, 490, 44), 32, INK)
		_text(b, tr(sources[i]), Rect2(100, 61, 490, 44), 24, MUTED)
		b.pressed.connect(_set_chapter.bind(key))
		_index_buttons.append(b)
	var discovered := 0
	for r in CanteenRun.RECIPES:
		if Game.recipes.has(r.id):
			discovered += 1
	_picture(_content, "res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[CanteenRun.RECIPES[0].result], Rect2(1280, 312, 260, 215), true)
	_text(_content, tr("一盒一盒，慢慢收藏"), Rect2(RIGHT.x, 544, PAGE_WIDTH, 60), 38, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(_content, tr("已发现 %d / %d 道套餐") % [discovered, CanteenRun.RECIPES.size()], Rect2(RIGHT.x, 622, PAGE_WIDTH, 46), 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_text(_content, tr("每发现一道新套餐，这本书就多一份记录。\n尚未发现的菜保留线索，等你亲手搭出来。"), Rect2(RIGHT.x + 44, 682, PAGE_WIDTH - 88, 208), 28, MUTED, HORIZONTAL_ALIGNMENT_CENTER)


func _recipe(recipe: Dictionary, at: Vector2, index: int, grand := false) -> void:
	var root := _entry(at, Vector2(PAGE_WIDTH, 602 if grand else 278))
	var k: int = recipe.result
	var known := Game.recipes.has(recipe.id)
	var title := tr(CanteenRun.NAMES[k]) if known else tr("未发现的套餐")
	_text(root, "%02d" % (index + 1), Rect2(0, 3, 50, 46), 26, GOLD)
	_text(root, title, Rect2(56, 0, 564, 88), 30, INK)
	_picture(root, "res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[k], Rect2(2, 150, 218, 218) if grand else Rect2(2, 101, 126, 126), true, known)
	_text(root, tr(CanteenRun.TIER_NAME[CanteenRun.TIER[k]]), Rect2(0, 100, PAGE_WIDTH, 36) if grand else Rect2(150, 95, 470, 36), 23, GOLD)
	if known:
		var names: Array = []
		for need in recipe.needs:
			names.append(tr(CanteenRun.NAMES[need]))
		_text(root, " + ".join(names), Rect2(248, 156, 372, 328) if grand else Rect2(150, 137, 470, 100), 28 if grand else 25, INK)
		_text(root, tr("已制作 %d 次") % int(Game.recipes[recipe.id]), Rect2(0, 536, PAGE_WIDTH, 40) if grand else Rect2(150, 241, 470, 32), 23, MUTED)
	else:
		var hint: String = tr(recipe.hint) if recipe.hint != "" else tr("还没吃到过")
		_text(root, hint, Rect2(248, 156, 372, 328) if grand else Rect2(150, 132, 470, 130), 28 if grand else 26, MUTED)
	_line(root, Rect2(0, 600 if grand else 276, PAGE_WIDTH, 1), Color("d6c9b0"))


func _food(k: int, at: Vector2) -> void:
	var root := _entry(at, Vector2(PAGE_WIDTH, 188))
	var stall: Dictionary = CanteenRun.STALLS[CanteenRun.STALL[k]]
	var available: bool = Game.stat("stall_" + CanteenRun.STALL[k]) >= CanteenRun.LEVEL[k]
	_picture(root, "res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[k], Rect2(0, 16, 116, 116), true, available)
	_text(root, tr(CanteenRun.NAMES[k]), Rect2(138, 0, 482, 66), 30, INK)
	_text(root, tr("%s · 档口 %d 级") % [tr(stall.name), CanteenRun.LEVEL[k]], Rect2(138, 70, 482, 36), 24, MUTED)
	var worth := tr("挑食：单吃不赚钱") if CanteenRun.PICKY[k] else tr("每口 %d token") % int(CanteenRun.VALUE[k])
	var kinds: Array = []
	for category in CanteenRun.CATS[k]:
		kinds.append(tr(category))
	_text(root, "%s · %s" % [" / ".join(kinds), worth], Rect2(138, 115, 482, 67), 24, INK)
	_line(root, Rect2(0, 190, PAGE_WIDTH, 1), Color("d6c9b0"))


func _rule(rule: Array, at: Vector2, index: int) -> void:
	var root := _entry(at, Vector2(PAGE_WIDTH, 602))
	_text(root, "%02d" % (index + 1), Rect2(0, 6, 140, 120), 78, GOLD)
	var heading: String = tr(str(rule[0]))
	if heading.contains(" · "):
		heading = heading.substr(heading.find(" · ") + 3)
	_text(root, heading, Rect2(0, 136, PAGE_WIDTH, 110), 36, INK)
	_text(root, tr(str(rule[1])), Rect2(0, 270, PAGE_WIDTH, 328), 28, INK)


func _entry(at: Vector2, dimensions: Vector2) -> Control:
	var root := Control.new()
	root.position = at
	root.size = dimensions
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)
	_entry_controls.append(root)
	return root


func _link_focus() -> void:
	var controls: Array = _tabs.duplicate()
	controls.append(_back)
	controls.append_array(_index_buttons)
	if not _previous.disabled:
		controls.append(_previous)
	if not _next.disabled:
		controls.append(_next)
	for i in controls.size():
		var b: Button = controls[i]
		b.focus_next = b.get_path_to(controls[(i + 1) % controls.size()])
		b.focus_previous = b.get_path_to(controls[posmod(i - 1, controls.size())])
		b.focus_neighbor_left = b.focus_previous
		b.focus_neighbor_right = b.focus_next
		b.focus_neighbor_top = b.focus_previous
		b.focus_neighbor_bottom = b.focus_next


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN:
			get_viewport().set_input_as_handled()
			_turn(-1 if event.keycode == KEY_PAGEUP else 1)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			get_viewport().set_input_as_handled()
			_turn(-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	if _return_focus != null:
		var target = _return_focus.get_ref()
		if is_instance_valid(target) and target.is_visible_in_tree():
			target.grab_focus.call_deferred()
	queue_free()


func _text(parent: Node, text: String, rect: Rect2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := UiKit.label("", font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_meta("collection_rect_size", rect.size)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	return label


func _picture(parent: Node, path: String, rect: Rect2, keep: bool, known := true) -> TextureRect:
	var picture := TextureRect.new()
	if ResourceLoader.exists(path):
		picture.texture = load(path)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep else TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not known:
		picture.modulate = Color(0.22, 0.15, 0.09, 0.65)
	parent.add_child(picture)
	picture.position = rect.position
	picture.size = rect.size
	picture.set_meta("collection_rect_size", rect.size)
	return picture


func _panel(parent: Node, rect: Rect2, fill: Color, edge: Color, width: int, radius: int) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UiKit.box(fill, edge, width, radius))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _line(parent: Node, rect: Rect2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = rect.position
	line.size = rect.size
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _button(parent: Node, text: String, rect: Rect2, dark: bool) -> Button:
	var b := UiKit.button(text, 28, rect.size)
	b.position = rect.position
	b.size = rect.size
	_style_button(b, false, dark)
	parent.add_child(b)
	return b


func _style_button(b: Button, selected: bool, dark: bool) -> void:
	var fill := UiKit.CREAM_HI if selected else (UiKit.CREAM if dark else Color("f4e6c6"))
	b.add_theme_stylebox_override("normal", UiKit.box(fill, UiKit.WOOD, 2, 10, 4))
	b.add_theme_stylebox_override("hover", UiKit.box(UiKit.CREAM_HI, UiKit.WOOD, 2, 10, 4))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color("eac785"), UiKit.WOOD_DARK, 2, 10, 2))
	var focus := UiKit.box(Color.TRANSPARENT, Color("bd6e24"), 4, 10)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", UiKit.box(Color("c0b39b"), Color("89735b"), 2, 10, 3))
	for state in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color("75634f"))


func _rules() -> Array:
	var rules := [
		["01 · 拿盒、接菜、送饭", tr("鼠标直接移动；键盘：%s；手柄：%s。到右侧饭桌，用左键 / 键盘 %s / 手柄 %s 拿盒或送饭。吃下食物才有收益。") % [_movement_label("keyboard"), _movement_label("gamepad"), Settings.binding_label("deliver"), Settings.binding_label("deliver", "gamepad")], "icon_box"],
		["02 · 看懂档口，也能调整位置", "每个圆圈对应一只备菜的勺子，填满就出菜；多个圆圈代表同时备菜，并非食物品质。升级档口会增加可出菜品。按 Esc → 档口指南，可将常接的档口摆在一起；换位立即保存，不会重置备菜进度。", "icon_clock"],
		["03 · 拼套餐，腾空位", "同一饭盒凑齐菜谱原料会自动合成套餐，原料的品质收益会计入套餐价值。合成后的占格按菜谱决定；上下文压缩再少占一格，至少一格。图鉴会记录真正发现的套餐。", "icon_crown"],
		["04 · 银边和金边是什么？", "银色为优质，散菜价值 ×2；金色为金牌，×4，FP32 解锁后 ×5。入盒后仍保留轮廓光。金饭盒提高整顿收入；思考中的吸附效果来自「发散思维」技能。", "fx_star"],
		["05 · 深度思考", tr("解锁后按住右键 / 键盘 %s / 手柄 %s，让食物放慢，饭盒保持正常移动。结束后冷却 1 秒；松开并攒够 0.5 秒能量，才能再次按下启动。利用这段时间调整接菜位置。") % [Settings.binding_label("think"), Settings.binding_label("think", "gamepad")], "icon_clock"],
		["06 · 吃得均衡，收益更高", "已吃下的主食、荤菜、素菜越接近 4∶3∶3，均衡倍率越高。青菜单吃原本会被吐掉，可用套餐、提示词注入或顿悟处理。整顿收入按结账单中的倍率计算，没有隐藏扣款。", "icon_token"],
		["07 · 单品拼盘与换菜连携", "解锁 Prompt 模板后，至少两份同一种散菜装满盒，也算单品拼盘，可触发多轮对话。上下文记忆让相邻两盒单品拼盘换菜获得额外奖励。幽灵食物不算；拼盘不冒充图鉴配方。", "icon_bolt"],
		["08 · 留点空间，下盒加餐", "上下文压缩让含套餐、空至少两格的亲手送餐存一份缓存，下一亲手满盒 +15%。学会换菜后，单品 A → 存缓存的套餐盒 → 单品 B，可同时续连击、拿换菜和缓存奖励。重复存缓存的半盒不能续连。助手不替你存取。", "icon_box"],
		["09 · 开饭前搭配菜单", "今日菜单划掉的菜不会再出，每个档口至少留一道。招牌菜的特别效果会作用于本顿饭；满名额后新选会替换最早一项。两种设置都在同一面板里，随时切换检查。", "icon_leaf"],
		["10 · 暂停与恢复", "Esc / P / Start 暂停；切到其他窗口默认自动暂停。回来后选择「继续上班」。设置和图鉴关闭后仍保持暂停，不会突然消耗饭点时间。", "icon_shield"],
		["11 · 助手有分工，接饭更从容", "开饭前在「自动化」选择出场角色。补漏接好菜；点单后可指定一道套餐；营养师会算上还没吃到的饭，补主荤素缺口。编排让每种完成的职责存一份接力，最多三份；下一盒亲手送出的饭每份再 +15%／30%。", "icon_bolt"],
		["12 · 自动技能，自己决定", "在「自动化 → 技能开关」分别开关推空盒、满盒回收、融合和变菜。关闭满盒回收可以从容放保温箱；关闭融合可保留单品拼盘；青菜流可关闭随机变菜。已买等级与数值保留，设置下顿生效。", "icon_box"],
	]
	if preload("res://scripts/ui/touch_controls.gd").available():
		rules[0][1] = tr("左下摇杆移动饭盒；右侧大按钮「交互」拿盒、送饭或放入保温箱。把饭盒移回餐桌再送饭，吃下食物才有收益。")
		rules[4][1] = tr("解锁后按住右侧小按钮「思考」，让食物放慢；左摇杆仍可移动饭盒。松手后冷却 1 秒，攒够能量后可再次使用。")
		rules[9][1] = tr("点画面上方「暂停游戏」休息，再点「继续上班」恢复。设置和图鉴关闭后仍保持暂停。")
	return rules
