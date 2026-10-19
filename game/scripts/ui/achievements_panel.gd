class_name AchievementsPanel
extends Control
## Local progress only. Cards are focusable so keyboard/gamepad browsing follows the scroll.

signal closed

var _back: Button
var _scroll: ScrollContainer
var _cards: Array[Button] = []
var _closed := false

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


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.02, 0.88)
	dim.size = size
	add_child(dim)
	var board := Panel.new()
	board.position = Vector2(100, 64)
	board.size = Vector2(1720, 952)
	board.add_theme_stylebox_override("panel", UiKit.box(Color(0.2, 0.13, 0.08, 0.99), UiKit.WOOD, 5, 24))
	add_child(board)
	var catalog: Array = Game.achievement_catalog()
	var count := 0
	for item in catalog:
		if Game.achievements.has(item.id):
			count += 1
	var heading := UiKit.label(tr("食堂成就"), 48, UiKit.GOLD)
	heading.position = Vector2(148, 106)
	add_child(heading)
	var progress := UiKit.label(tr("已达成 %d / %d") % [count, catalog.size()], 28, UiKit.TEXT)
	progress.position = Vector2(148 + heading.get_minimum_size().x + 48, 124)
	add_child(progress)
	var local := UiKit.label(tr("记录这份存档里，你和大肥鱼的小小里程碑。"), 25, Color(0.88, 0.79, 0.66))
	local.position = Vector2(150, 183)
	add_child(local)
	_back = UiKit.button(tr("返回"), 29, Vector2(220, 72))
	_back.position = Vector2(1548, 112)
	_back.set_meta("ui_back", true)
	_back.pressed.connect(_close)
	add_child(_back)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(144, 250)
	_scroll.size = Vector2(1630, 652)
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)
	for item in catalog:
		var card := _card(item)
		grid.add_child(card)
		_cards.append(card)
	_wire_focus()
	var footer := UiKit.label(tr("本地成就 · 方向键 / 摇杆浏览 · Esc / B 返回"), 23, Color(0.88, 0.79, 0.66))
	footer.position = Vector2(150, 948)
	add_child(footer)
	_back.grab_focus.call_deferred()


func _card(item: Dictionary) -> Button:
	var unlocked := Game.achievements.has(item.id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(780, 196)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("achievement_id", item.id)
	b.add_theme_stylebox_override("normal", UiKit.box(UiKit.CREAM if unlocked else Color(0.73, 0.68, 0.59), UiKit.WOOD, 2, 14, 5))
	b.add_theme_stylebox_override("hover", UiKit.box(UiKit.CREAM_HI if unlocked else Color(0.8, 0.75, 0.66), UiKit.GOLD, 2, 14, 5))
	var portrait := TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var art_name: String = SPECIAL_PORTRAITS.get(str(item.id), PORTRAITS.get(str(item.get("group", "")), "fish_achievement_trophy"))
	var art := "res://assets/portraits/release/%s.png" % art_name
	if ResourceLoader.exists(art):
		portrait.texture = load(art)
	portrait.position = Vector2(12, 14)
	portrait.size = Vector2(148, 168)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		portrait.modulate = Color(0.67, 0.67, 0.67, 0.85)
	b.add_child(portrait)
	var col := VBoxContainer.new()
	col.position = Vector2(172, 20)
	col.size = Vector2(578, 154)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	b.add_child(col)
	var title := UiKit.label(tr(str(item.name)), 29, UiKit.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var desc := UiKit.label(tr(str(item.desc)), 23, Color(0.39, 0.29, 0.21))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 578
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc)
	var status_text := tr("已达成") if unlocked else tr("尚未达成")
	var status := UiKit.label("%s · %s" % [tr(str(item.get("group", ""))), status_text], 20, Color(0.39, 0.29, 0.21))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(status)
	b.tooltip_text = "%s\n%s\n%s" % [title.text, desc.text, status.text]
	return b


func _wire_focus() -> void:
	if _cards.is_empty():
		return
	_back.focus_neighbor_bottom = _back.get_path_to(_cards[0])
	_back.focus_next = _back.get_path_to(_cards[0])
	_back.focus_neighbor_top = _back.get_path_to(_cards.back())
	_back.focus_previous = _back.get_path_to(_cards.back())
	for i in _cards.size():
		var card: Button = _cards[i]
		card.focus_neighbor_top = card.get_path_to(_cards[i - 2] if i >= 2 else _back)
		card.focus_neighbor_bottom = card.get_path_to(_cards[i + 2] if i + 2 < _cards.size() else _back)
		card.focus_neighbor_left = card.get_path_to(_cards[i - 1] if i % 2 == 1 else card)
		card.focus_neighbor_right = card.get_path_to(_cards[i + 1] if i % 2 == 0 and i + 1 < _cards.size() else card)
		card.focus_previous = card.get_path_to(_cards[i - 1] if i > 0 else _back)
		card.focus_next = card.get_path_to(_cards[i + 1] if i + 1 < _cards.size() else _back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	queue_free()
