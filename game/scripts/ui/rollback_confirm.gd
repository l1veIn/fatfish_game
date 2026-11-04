extends Control
## Deliberate full-tree refund; short taps never confirm.
signal closed
signal confirmed

var hold_button: Button
var cancel_button: Button
var _progress: ProgressBar
var _held := false
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	ScreenLayout.shade(self, Color(0.03, 0.02, 0.01, 0.8))
	var panel := PanelContainer.new()
	panel.position = Vector2(480, 300)
	panel.size = Vector2(960, 470)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	panel.add_child(col)
	col.add_child(UiKit.label(tr("回滚全部技能"), 40, UiKit.GOLD))
	var note := UiKit.label(tr("所有已购技能全额退款，保留版本和门票。\n长按回滚 3 秒确认；松手或移开即取消本次长按。"), 28)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	_progress = ProgressBar.new()
	_progress.max_value = 3.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 22
	col.add_child(_progress)
	hold_button = preload("res://scripts/ui/touch_controls.gd").make_button(tr("长按回滚 3 秒"), Rect2(0, 0, 860, 90), 30)
	col.add_child(hold_button)
	hold_button.focus_mode = Control.FOCUS_ALL
	hold_button.held_changed.connect(func(held: bool):
		_held = held
		if not held:
			_elapsed = 0.0
			_progress.value = 0
			hold_button.text = tr("长按回滚 3 秒"))
	hold_button.mouse_exited.connect(func(): hold_button.cancel_touch())
	hold_button.focus_exited.connect(func(): hold_button.cancel_touch())
	cancel_button = UiKit.button(tr("取消"), 30, Vector2(0, 70))
	cancel_button.pressed.connect(close)
	col.add_child(cancel_button)
	hold_button.focus_next = hold_button.get_path_to(cancel_button)
	hold_button.focus_previous = hold_button.focus_next
	cancel_button.focus_next = cancel_button.get_path_to(hold_button)
	cancel_button.focus_previous = cancel_button.focus_next
	cancel_button.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if not _held or _done: return
	_elapsed += delta
	_progress.value = _elapsed
	hold_button.text = tr("继续按住 %.1f 秒") % maxf(0, 3.0 - _elapsed)
	if _elapsed >= 3.0:
		_done = true
		hold_button.cancel_touch()
		confirmed.emit()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	hold_button.cancel_touch()
	closed.emit()
	queue_free()
