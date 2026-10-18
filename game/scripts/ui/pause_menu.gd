class_name PauseMenu
extends Control
## Pause during a shift (Esc / P / Start, or the window losing focus): the game tree is paused
## while this is open. 继续 / 设置 / 提前下班 (end the shift now, keeping what she ate) /
## 回到标题 (also ends the shift first, so nothing is lost).

signal resumed
signal end_shift
signal to_title

var _settings: SettingsPanel
var _first: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	size = Vector2(1920, 1080)
	z_index = 150
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.55)
	dim.size = size
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(700, 190)
	panel.size = Vector2(520, 700)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	var title := UiKit.label(tr("暂停一下"), 50, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := UiKit.label(tr("饭菜不会凉的"), 24, Color(0.85, 0.78, 0.68))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	_first = _add(col, tr("继续上班"), resume)
	_add(col, tr("菜谱图鉴"), func():
		var book := RecipeBook.new()
		book.closed.connect(func(): _first.grab_focus())
		add_child(book))
	_add(col, tr("设置"), _open_settings)
	_add(col, tr("提前下班"), func(): _leave(end_shift))
	_add(col, tr("回到标题"), func(): _leave(to_title))
	_first.grab_focus.call_deferred()
	Audio.duck(true)


func _add(col: VBoxContainer, text: String, fn: Callable) -> Button:
	var b := UiKit.button(text, 34, Vector2(400, 80))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(fn)
	col.add_child(b)
	return b


func _open_settings() -> void:
	_settings = SettingsPanel.new()
	_settings.closed.connect(func(): _first.grab_focus())
	add_child(_settings)


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_settings):
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume()


func resume() -> void:
	get_tree().paused = false
	Audio.duck(false)
	resumed.emit()
	queue_free()


func _leave(sig: Signal) -> void:
	get_tree().paused = false
	Audio.duck(false)
	sig.emit()
	queue_free()
