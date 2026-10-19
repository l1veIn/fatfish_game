class_name PauseMenu
extends Control
## Losing focus pauses visibly; resuming always requires a player action.

signal resumed
signal end_shift
signal to_title

var focus_pause := false
var _settings: SettingsPanel
var _book: RecipeBook
var _first: Button
var _buttons: Array[Button] = []
var _title: Label
var _hint: Label
var _closing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	size = Vector2(1920, 1080)
	z_index = 150
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.07, 0.11, 0.82)
	dim.size = size
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(580, 110)
	panel.custom_minimum_size = Vector2(760, 860)
	var skin := UiKit.box(Color(0.07, 0.19, 0.26), Color(0.71, 0.59, 0.37), 2, 22)
	skin.content_margin_left = 64
	skin.content_margin_right = 64
	skin.content_margin_top = 44
	skin.content_margin_bottom = 44
	panel.add_theme_stylebox_override("panel", skin)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	_title = UiKit.label("", 48, UiKit.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_title)
	_hint = UiKit.label("", 27, Color(0.77, 0.83, 0.82))
	_hint.custom_minimum_size = Vector2(632, 94)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	_first = _add(col, "继续上班", resume)
	_add(col, "菜谱图鉴", _open_book)
	_add(col, "设置", _open_settings)
	_add(col, "提前结束这顿饭", func(): _leave(end_shift))
	_add(col, "回到标题", func(): _leave(to_title))
	for i in _buttons.size():
		var b := _buttons[i]
		b.focus_neighbor_top = b.get_path_to(_buttons[posmod(i - 1, _buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(_buttons[(i + 1) % _buttons.size()])
		b.focus_previous = b.focus_neighbor_top
		b.focus_next = b.focus_neighbor_bottom
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)
	Settings.changed.connect(_translate)
	Settings.focus_changed.connect(_focus_changed)
	_translate()
	_first.grab_focus.call_deferred()
	Audio.duck(true)


func _add(col: VBoxContainer, source: String, fn: Callable) -> Button:
	var b := UiKit.button(tr(source), 32, Vector2(632, 78))
	var primary := _buttons.is_empty()
	var quiet := _buttons.size() >= 3
	var bg := Color(0.92, 0.78, 0.49) if primary else Color(0.10, 0.25, 0.32) if quiet else Color(0.96, 0.94, 0.86)
	var ink := Color(0.90, 0.91, 0.83) if quiet else Color(0.10, 0.23, 0.29)
	b.add_theme_stylebox_override("normal", UiKit.box(bg, Color(0.59, 0.55, 0.39), 1, 10, 2))
	b.add_theme_stylebox_override("hover", UiKit.box(bg.lightened(0.07), Color(0.89, 0.76, 0.47), 2, 10, 2))
	b.add_theme_stylebox_override("pressed", UiKit.box(bg.darkened(0.06), Color(0.89, 0.76, 0.47), 2, 10))
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	b.set_meta("source", source)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(fn)
	col.add_child(b)
	_buttons.append(b)
	return b


func _translate() -> void:
	_title.text = tr("暂停一下")
	_hint.text = tr("窗口失去焦点，已为你暂停。\n点击继续上班，饭菜不会凉。") if focus_pause else tr("饭菜不会凉的")
	_hint.text = _hint.text.replace("\n", " ")
	for b in _buttons:
		b.text = tr(str(b.get_meta("source")))


func _has_child_panel() -> bool:
	return is_instance_valid(_settings) or is_instance_valid(_book)


func _open_book() -> void:
	if _has_child_panel():
		return
	_book = RecipeBook.new()
	_book.closed.connect(func():
		_book = null
		_buttons[1].grab_focus.call_deferred())
	add_child(_book)


func _open_settings() -> void:
	if _has_child_panel():
		return
	_settings = SettingsPanel.new()
	_settings.closed.connect(func():
		_settings = null
		_buttons[2].grab_focus.call_deferred())
	add_child(_settings)


func _focus_changed(focused: bool) -> void:
	if focused and not _has_child_panel() and not _closing:
		_first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _has_child_panel():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume()


func resume() -> void:
	if _closing or _has_child_panel():
		return
	_closing = true
	Settings.release_gameplay_inputs()
	get_tree().paused = false
	Audio.duck(false)
	resumed.emit()
	queue_free()


func _leave(sig: Signal) -> void:
	if _closing or _has_child_panel():
		return
	_closing = true
	Settings.release_gameplay_inputs()
	get_tree().paused = false
	Audio.duck(false)
	sig.emit()
	queue_free()


func _exit_tree() -> void:
	if not _closing and is_inside_tree():
		get_tree().paused = false
		Audio.duck(false)
