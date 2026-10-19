class_name RecipeBook
extends Control
## 菜谱图鉴: every 套餐 (made ones show their ingredients and how often she ate them, unknown ones
## a silhouette and, for hidden recipes, their hint) and every dish (which window, at what level,
## its worth and kind). Opens from the pause menu, the title screen and the skill tree.

signal closed

var _page := "sets"
var _list: GridContainer
var _tabs: Array = []
var _scroll: ScrollContainer
var _back: Button
var _cards: Array[Button] = []
var _closed := false


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
	for spec in [["sets", tr("套餐 %d / %d") % [Game.recipes.size(), CanteenRun.RECIPES.size()]], ["foods", tr("食材")], ["rules", tr("食堂说明")]]:
		var b := UiKit.button(spec[1], 28, Vector2(220, 64))
		b.pressed.connect(func():
			_page = spec[0]
			_fill())
		head.add_child(b)
		_tabs.append(b)
	_back = UiKit.button(tr("合上"), 30, Vector2(200, 64))
	_back.set_meta("ui_back", true)
	_back.pressed.connect(_close)
	head.add_child(_back)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(170, 160)
	_scroll.size = Vector2(1580, 850)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override("h_separation", 24)
	_list.add_theme_constant_override("v_separation", 18)
	_scroll.add_child(_list)
	_fill()
	_back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	queue_free()


func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_cards.clear()
	_scroll.scroll_vertical = 0
	if _page == "sets":
		for r in CanteenRun.RECIPES:
			_add_entry(_set_entry(r))
	elif _page == "foods":
		for k in CanteenRun.NAMES.size():
			if not CanteenRun.IS_SET[k] and CanteenRun.STALL[k] != "":
				_add_entry(_food_entry(k))
	else:
		_fill_rules()
	_link_focus()
	for i in _tabs.size():
		_tabs[i].modulate = Color.WHITE if i == ["sets", "foods", "rules"].find(_page) else Color(0.82, 0.77, 0.66)


func _add_entry(content: Control) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(770, maxf(140, content.get_combined_minimum_size().y + 32))
	card.add_theme_stylebox_override("normal", UiKit.box(Color(1, 0.94, 0.79, 0.96), Color(0.64, 0.44, 0.24), 2, 14))
	card.add_theme_stylebox_override("hover", UiKit.box(UiKit.CREAM_HI, UiKit.WOOD, 2, 14))
	content.position = Vector2(16, 16)
	content.size.x = 738
	_ignore_mouse(content)
	card.add_child(content)
	_list.add_child(card)
	_cards.append(card)


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _link_focus() -> void:
	var top: Array = _tabs + [_back]
	for i in top.size():
		var b: Button = top[i]
		b.focus_neighbor_left = b.get_path_to(top[posmod(i - 1, top.size())])
		b.focus_neighbor_right = b.get_path_to(top[(i + 1) % top.size()])
		if not _cards.is_empty():
			b.focus_neighbor_bottom = b.get_path_to(_cards[0])
		b.focus_next = b.get_path_to(top[i + 1] if i + 1 < top.size() else _cards[0])
		b.focus_previous = b.get_path_to(top[i - 1] if i > 0 else _cards.back())
	for i in _cards.size():
		var c := _cards[i]
		c.focus_neighbor_top = c.get_path_to(_cards[i - 2] if i >= 2 else _tabs[0])
		c.focus_neighbor_bottom = c.get_path_to(_cards[i + 2] if i + 2 < _cards.size() else _back)
		c.focus_neighbor_left = c.get_path_to(_cards[i - 1] if i % 2 else c)
		c.focus_neighbor_right = c.get_path_to(_cards[i + 1] if i % 2 == 0 and i + 1 < _cards.size() else c)
		c.focus_next = c.get_path_to(_cards[i + 1] if i + 1 < _cards.size() else _tabs[0])
		c.focus_previous = c.get_path_to(_cards[i - 1] if i > 0 else _back)


func _fill_rules() -> void:
	var rules := [
		["01 · 拿盒、接菜、送饭", "移动鼠标直接控制饭盒；键盘 WASD / 方向键、手柄左摇杆也能移动。到右侧饭桌点击左键 / E / A 拿盒，再把装了菜的盒子送回来。食物吃下后才产生收益。", "icon_box"],
		["02 · 档口为什么有两条进度？", "每条进度对应一只独立备菜的勺子。档口显示出菜数量；多条代表同时备菜，并非食物品质。进度满后出勺，食物沿自己的轨迹落下。升级档口会增加可出菜品。", "icon_clock"],
		["03 · 拼套餐，腾空位", "同一饭盒凑齐菜谱原料会自动合成套餐，原料的品质收益会计入套餐价值。合成后的占格按菜谱决定；上下文压缩再少占一格，至少一格。图鉴会记录真正发现的套餐。", "icon_crown"],
		["04 · 银边和金边是什么？", "银色为优质，散菜价值 ×2；金色为金牌，×4，FP32 解锁后 ×5。入盒后仍保留轮廓光。金饭盒提高整顿收入；思考中的吸附效果来自「发散思维」技能。", "fx_star"],
		["05 · 深度思考", "解锁后按住空格 / 右键 / B，让食物放慢，饭盒保持正常移动。结束后冷却 1 秒；松开并攒够 0.5 秒能量，才能再次按下启动。标记表示食物预计经过饭盒接菜高度的位置。", "icon_clock"],
		["06 · 吃得均衡，收益更高", "已吃下的主食、荤菜、素菜越接近 4∶3∶3，均衡倍率越高。青菜单吃原本会被吐掉，可用套餐、提示词注入或顿悟处理。整顿收入按结账单中的倍率计算，没有隐藏扣款。", "icon_token"],
		["07 · 单品拼盘与换菜连携", "解锁 Prompt 模板后，至少两份同一种散菜装满盒，也算单品拼盘，可触发多轮对话。上下文记忆让相邻两盒单品拼盘换菜获得额外奖励。幽灵食物不算；拼盘不冒充图鉴配方。", "icon_bolt"],
		["08 · 留点空间，下盒加餐", "上下文压缩解锁后，亲手送出含套餐且空至少两格的盒子，可存一份缓存。下一只亲手送出的满盒消耗缓存，收益 +15%。缓存最多一份；小助手不会替你存取。", "icon_box"],
		["09 · 开饭前搭配菜单", "今日菜单划掉的菜不会再出，每个档口至少留一道。招牌菜的特别效果会作用于本顿饭；满名额后新选会替换最早一项。两种设置都在同一面板里，随时切换检查。", "icon_leaf"],
		["10 · 暂停与恢复", "Esc / P / Start 暂停；切到其他窗口默认自动暂停。回来后点击继续上班。设置和图鉴关闭后仍保持暂停，不会突然消耗饭点时间。", "icon_shield"],
	]
	for r in rules:
		var icon := TextureRect.new()
		var path := "res://assets/canteen/%s.png" % r[2]
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		icon.custom_minimum_size = Vector2(78, 78)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var row := _row(icon, [[tr(r[0]), 28, UiKit.INK], [tr(r[1]), 24, Color(0.38, 0.27, 0.17)]])
		row.custom_minimum_size.y = 264
		_add_entry(row)


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
	row.custom_minimum_size = Vector2(738, 110)
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
