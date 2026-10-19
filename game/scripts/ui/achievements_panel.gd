class_name AchievementsPanel
extends Control
## The canteen's warm paper collection: six clear medals and one large character detail.
signal closed

const INK := Color("4a2914")
const GOLD := Color("ffcc6b")
const PAPER := Color("fff2d6")
const GROUPS := ["全部奖章", "食堂日常", "成长旅程", "菜谱收藏", "吃饭的学问", "后厨建设"]
const BADGES := {"食堂日常": "meal", "成长旅程": "growth", "菜谱收藏": "recipe", "吃饭的学问": "balance", "后厨建设": "kitchen"}
const PAGE_SIZE := 6
var _back: Button
var _previous: Button
var _next: Button
var _medals: Array[Button] = []
var _category_buttons: Array[Button] = []
var _catalog: Array = []
var _filtered: Array = []
var _group := "全部奖章"
var _spread := 0
var _page_count := 1
var _selected_id := ""
var _grid: Control
var _detail: Control
var _heading: Label
var _progress: Label
var _subtitle: Label
var _page_label: Label
var _hint: Label
var _closed := false
var _return_focus: WeakRef
var _language := ""

const PORTRAITS := {
	"食堂日常": "fish_achievement_trophy",
	"成长旅程": "fish_thinker",
	"菜谱收藏": "fish_menu_curator",
	"吃饭的学问": "fish_signature_chef",
	"后厨建设": "fish_achievement_trophy",
}
const SPECIAL_PORTRAITS := {
	"first_meal": "fish_first_meal", "regular": "fish_first_meal", "resident": "fish_first_meal",
	"bites_100": "fish_first_meal", "bites_1000": "fish_first_meal", "feast": "fish_first_meal",
	"balanced": "fish_balanced", "grokked": "fish_balanced",
	"recipe_twentyfive": "fish_bookworm", "recipe_all": "fish_bookworm",
	"gold_box": "fish_gold_box", "full_boxes": "fish_gold_box",
}


static func badge_path(item: Dictionary) -> String:
	var icon: String = "gold" if str(item.get("id", "")) == "gold_box" else str(BADGES.get(str(item.get("group", "")), "meal"))
	var path := "res://assets/ui/premium/badge_%s.png" % icon
	# Development fallback only; the final visual review requires the purpose-made badges.
	return path if ResourceLoader.exists(path) else "res://assets/canteen/food_ball.png"


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		_return_focus = weakref(focused)
	_language = TranslationServer.get_locale()
	_catalog = Game.achievement_catalog()
	_picture(self, "res://assets/canteen/bg_wall.png", Rect2(0, 0, 1920, 1080), true)
	_panel(self, Rect2(0, 0, 1920, 1080), Color(0.08, 0.04, 0.02, 0.58), Color.TRANSPARENT, 0, 0)
	_panel(self, Rect2(72, 44, 1776, 992), Color(0.2, 0.13, 0.08, 0.98), UiKit.WOOD, 4, 22)
	_panel(self, Rect2(1278, 217, 542, 753), PAPER, UiKit.WOOD, 3, 14)
	_heading = _text(self, "", Rect2(124, 71, 1080, 78), 48, GOLD)
	_subtitle = _text(self, "", Rect2(126, 155, 1080, 44), 25, Color("e0c9a8"))
	_progress = _text(self, "", Rect2(124, 886, 242, 74), 25, GOLD)
	_back = _button(self, "", Rect2(1570, 92, 224, 66))
	_back.set_meta("ui_back", true)
	_back.pressed.connect(_close)
	for i in GROUPS.size():
		var b := _button(self, "", Rect2(120, 254 + i * 100, 246, 82))
		b.add_theme_font_size_override("font_size", 25)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.set_meta("group", GROUPS[i])
		b.pressed.connect(_set_group.bind(GROUPS[i]))
		_category_buttons.append(b)
	_previous = _button(self, "", Rect2(410, 978, 218, 58))
	_previous.pressed.connect(_turn.bind(-1))
	_next = _button(self, "", Rect2(1020, 978, 218, 58))
	_next.pressed.connect(_turn.bind(1))
	_page_label = _text(self, "", Rect2(640, 988, 368, 34), 25, PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _text(self, "", Rect2(1286, 984, 526, 48), 21, Color("e0c9a8"), HORIZONTAL_ALIGNMENT_CENTER)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	_detail = Control.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	Settings.changed.connect(_on_settings_changed)
	_fill()
	if not _medals.is_empty():
		_medals[0].grab_focus.call_deferred()
	else:
		_back.grab_focus.call_deferred()


func _on_settings_changed() -> void:
	if _language != TranslationServer.get_locale():
		_language = TranslationServer.get_locale()
		var previous_focus := get_viewport().gui_get_focus_owner()
		var focused_medal := previous_focus != null and previous_focus.has_meta("achievement_id")
		_fill()
		if focused_medal:
			for medal in _medals:
				if str(medal.get_meta("achievement_id")) == _selected_id:
					medal.grab_focus.call_deferred()
					break


func _set_group(group: String) -> void:
	_group = group
	_spread = 0
	_selected_id = ""
	_fill()
	_category_buttons[GROUPS.find(group)].grab_focus.call_deferred()


func _turn(direction: int) -> void:
	var next_spread := clampi(_spread + direction, 0, _page_count - 1)
	if next_spread == _spread:
		return
	_spread = next_spread
	_selected_id = ""
	_fill()
	if not _medals.is_empty():
		_medals[0].grab_focus.call_deferred()


func _fill() -> void:
	for node in _grid.get_children():
		_grid.remove_child(node)
		node.queue_free()
	_medals.clear()
	_filtered = _catalog.filter(func(item): return _group == GROUPS[0] or str(item.group) == _group)
	_page_count = maxi(1, ceili(float(_filtered.size()) / PAGE_SIZE))
	_spread = clampi(_spread, 0, _page_count - 1)
	_previous.disabled = _spread == 0
	_next.disabled = _spread >= _page_count - 1
	_heading.text = tr("食堂成就")
	_subtitle.text = tr("每一枚奖章，都记着一起吃过的饭。")
	_back.text = tr("返回") + "  ×"
	_previous.text = "←  " + tr("上一页")
	_next.text = tr("下一页") + "  →"
	_page_label.text = "%02d / %02d" % [_spread + 1, _page_count]
	_hint.text = tr("LB / RB 翻页 · Esc / B 返回")
	var unlocked := 0
	for item in _catalog:
		if Game.achievements.has(item.id):
			unlocked += 1
	_progress.text = tr("已收藏 %d / %d 枚") % [unlocked, _catalog.size()]
	for i in _category_buttons.size():
		_category_buttons[i].text = tr(GROUPS[i])
		_style(_category_buttons[i], GROUPS[i] == _group)
	for i in PAGE_SIZE:
		var index := _spread * PAGE_SIZE + i
		if index >= _filtered.size():
			break
		var item: Dictionary = _filtered[index]
		var medal := _medal(item, Rect2(400 + (i % 2) * 422, 248 + (i / 2) * 232, 400, 214))
		_grid.add_child(medal)
		_medals.append(medal)
	if not _medals.any(func(b): return str(b.get_meta("achievement_id")) == _selected_id):
		_selected_id = str(_medals[0].get_meta("achievement_id")) if not _medals.is_empty() else ""
	_select(_selected_id)
	_wire_focus()


func _medal(item: Dictionary, rect: Rect2) -> Button:
	var unlocked := Game.achievements.has(item.id)
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.set_meta("achievement_id", item.id)
	b.set_meta("unlocked", unlocked)
	_style(b, false)
	_picture(b, badge_path(item), Rect2(18, 36, 112, 112), unlocked)
	_text(b, tr(str(item.name)), Rect2(150, 24, 228, 120), 26, INK)
	_text(b, tr("已达成") if unlocked else tr("待点亮"), Rect2(150, 152, 226, 40), 23, Color("805221") if unlocked else Color("77634f"))
	b.focus_entered.connect(_select.bind(str(item.id)))
	b.pressed.connect(_select.bind(str(item.id)))
	return b


func _select(id: String) -> void:
	_selected_id = id
	for b in _medals:
		_style(b, str(b.get_meta("achievement_id")) == id)
	for node in _detail.get_children():
		_detail.remove_child(node)
		node.queue_free()
	var item := {}
	for entry in _catalog:
		if str(entry.id) == id:
			item = entry
			break
	if item.is_empty():
		return
	var unlocked := Game.achievements.has(id)
	_text(_detail, tr(str(item.group)), Rect2(1310, 246, 478, 40), 24, Color("78604b"), HORIZONTAL_ALIGNMENT_CENTER)
	var art_name: String = SPECIAL_PORTRAITS.get(id, PORTRAITS.get(str(item.group), "fish_achievement_trophy"))
	var art := "res://assets/portraits/release/%s.png" % art_name
	_picture(_detail, art, Rect2(1340, 301, 418, 316), true)
	_text(_detail, tr("已达成") if unlocked else tr("待点亮"), Rect2(1314, 630, 470, 36), 24, Color("8f642d"), HORIZONTAL_ALIGNMENT_CENTER)
	_text(_detail, tr(str(item.name)), Rect2(1312, 682, 474, 100), 35, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(_detail, tr(str(item.desc)), Rect2(1318, 798, 462, 122), 27, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(_detail, tr("保存在这份存档里的小小里程碑"), Rect2(1318, 923, 462, 32), 20, Color("78604b"), HORIZONTAL_ALIGNMENT_CENTER)


func _wire_focus() -> void:
	var active: Array = _category_buttons.duplicate()
	active.append_array(_medals)
	if not _previous.disabled:
		active.append(_previous)
	if not _next.disabled:
		active.append(_next)
	active.append(_back)
	for i in active.size():
		var b: Button = active[i]
		b.focus_next = b.get_path_to(active[(i + 1) % active.size()])
		b.focus_previous = b.get_path_to(active[posmod(i - 1, active.size())])
		b.focus_neighbor_top = b.focus_previous
		b.focus_neighbor_bottom = b.focus_next
		b.focus_neighbor_left = b.focus_previous
		b.focus_neighbor_right = b.focus_next
	for i in _category_buttons.size():
		var b := _category_buttons[i]
		if not _medals.is_empty():
			b.focus_neighbor_right = b.get_path_to(_medals[0])
	for i in _medals.size():
		var b := _medals[i]
		b.focus_neighbor_left = b.get_path_to(_medals[i - 1] if i % 2 else _category_buttons[GROUPS.find(_group)])
		b.focus_neighbor_right = b.get_path_to(_medals[i + 1] if i % 2 == 0 and i + 1 < _medals.size() else _back)
		b.focus_neighbor_top = b.get_path_to(_medals[i - 2] if i >= 2 else _back)
		b.focus_neighbor_bottom = b.get_path_to(_medals[i + 2] if i + 2 < _medals.size() else (_next if not _next.disabled else _back))
	if not _medals.is_empty():
		_back.focus_neighbor_bottom = _back.get_path_to(_medals[0])
		_back.focus_neighbor_left = _back.get_path_to(_medals[0])


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
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
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


func _picture(parent: Node, path: String, rect: Rect2, unlocked: bool) -> TextureRect:
	var picture := TextureRect.new()
	if ResourceLoader.exists(path):
		picture.texture = load(path)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		picture.modulate = Color(0.67, 0.62, 0.54, 0.85)
	parent.add_child(picture)
	picture.position = rect.position
	picture.size = rect.size
	picture.set_meta("collection_rect_size", rect.size)
	return picture


func _panel(parent: Node, rect: Rect2, fill: Color, edge: Color, width: int, radius: int) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UiKit.box(fill, edge, width, radius))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)


func _button(parent: Node, text: String, rect: Rect2) -> Button:
	var button := UiKit.button(text, 26, rect.size)
	button.position = rect.position
	button.size = rect.size
	_style(button, false)
	parent.add_child(button)
	return button


func _style(button: Button, selected: bool) -> void:
	var unlocked: bool = button.get_meta("unlocked", true)
	var paper := UiKit.CREAM if unlocked else Color("c5b89f")
	button.add_theme_stylebox_override("normal", UiKit.box(Color("f4d591") if selected else paper, GOLD if selected else UiKit.WOOD, 3 if selected else 2, 12, 5))
	button.add_theme_stylebox_override("hover", UiKit.box(UiKit.CREAM_HI, UiKit.WOOD, 2, 12, 5))
	button.add_theme_stylebox_override("pressed", UiKit.box(Color("e8c27d"), UiKit.WOOD_DARK, 3, 12, 3))
	button.add_theme_stylebox_override("disabled", UiKit.box(Color("a89a83"), UiKit.WOOD, 2, 12, 3))
	var focus := UiKit.box(Color.TRANSPARENT, Color("ffdf87"), 4, 12)
	focus.draw_center = false
	focus.expand_margin_left = 4
	focus.expand_margin_top = 4
	focus.expand_margin_right = 4
	focus.expand_margin_bottom = 4
	button.add_theme_stylebox_override("focus", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", Color("685542"))
