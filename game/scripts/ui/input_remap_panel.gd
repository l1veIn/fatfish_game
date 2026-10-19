extends Control
## Gameplay remapping; menus keep their independent, fixed navigation and escape controls.
signal closed
const INK := Color("4a2914")
const SOFT := Color("79604b")
var _panel: PanelContainer
var _scroll: ScrollContainer
var _buttons: Dictionary = {}
var _chain: Array[Button] = []
var _status: Label
var _reset: Button
var _back: Button
var _capture_action := ""
var _capture_device := ""
var _capture_button: Button
var _opening_held := false
var _pending_event: InputEvent
var _closed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 240
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.035, 0.015, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	var paper := UiKit.box(UiKit.CREAM, UiKit.WOOD, 2, 18, 3)
	for side in ["left", "right", "top", "bottom"]: paper.set("content_margin_" + side, 30.0)
	_panel.add_theme_stylebox_override("panel", paper)
	add_child(_panel)
	_panel.minimum_size_changed.connect(_layout.call_deferred)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_panel.add_child(column)
	column.add_child(_label(tr("键盘与手柄改键"), 44))
	column.add_child(_label(tr("选择一格后按新输入。每次替换该设备的全部绑定，另一种设备保持不变。"), 24, SOFT))
	var headers := HBoxContainer.new()
	headers.add_theme_constant_override("separation", 18)
	for title in ["操作", "键盘", "手柄"]:
		var label := _label(tr(title), 27)
		label.custom_minimum_size.x = 370 if title == "操作" else 360
		if title != "操作": label.size_flags_horizontal = Control.SIZE_FILL
		headers.add_child(label)
	column.add_child(headers)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The first focus arrives before the wrapped labels finish container layout.
	# Following it then would scroll against temporary row coordinates.
	_scroll.follow_focus = false
	column.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	_scroll.add_child(rows)
	for action in Settings.BINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		rows.add_child(row)
		var label := _label(tr(Settings.BINDABLE_ACTIONS[action]), 27)
		label.custom_minimum_size.x = 370
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_buttons[action] = {}
		for device in ["keyboard", "gamepad"]:
			var button := UiKit.button(Settings.binding_label(action, device), 25, Vector2(360, 68))
			button.set_meta("binding_action", action)
			button.set_meta("binding_device", device)
			row.add_child(button)
			button.pressed.connect(_begin_capture.bind(action, device, button))
			_buttons[action][device] = button
			_chain.append(button)
	_status = _label(tr("菜单按键固定：方向键 / 十字键选择，Enter / A 确认，Esc / B 返回；Esc / Start 暂停。"), 24, SOFT)
	_status.custom_minimum_size.y = 100
	column.add_child(_status)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 32)
	column.add_child(footer)
	_reset = UiKit.button(tr("恢复默认键位"), 27, Vector2(400, 68))
	_reset.pressed.connect(func():
		Settings.reset_bindings()
		_refresh_labels()
		_status.text = tr("已恢复默认键位。"))
	footer.add_child(_reset)
	_back = UiKit.button(tr("返回"), 28, Vector2(330, 68))
	_back.set_meta("ui_back", true)
	_back.pressed.connect(close)
	footer.add_child(_back)
	_chain.append_array([_reset, _back])
	for i in _chain.size():
		var button := _chain[i]
		button.focus_next = button.get_path_to(_chain[(i + 1) % _chain.size()])
		button.focus_previous = button.get_path_to(_chain[posmod(i - 1, _chain.size())])
		button.focus_neighbor_bottom = button.focus_next
		button.focus_neighbor_top = button.focus_previous
		button.focus_neighbor_right = button.focus_next
		button.focus_neighbor_left = button.focus_previous
	resized.connect(_layout)
	Settings.focus_changed.connect(_on_window_focus)
	_layout()
	_focus_first_binding.call_deferred()


func _focus_first_binding() -> void:
	_chain[0].grab_focus()
	await get_tree().process_frame
	if not is_inside_tree(): return
	_scroll.scroll_vertical = 0
	_scroll.follow_focus = true
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and _scroll.is_ancestor_of(focused) and focused != _chain[0]:
		_scroll.ensure_control_visible(focused)


func _layout() -> void:
	var area := size if size.x > 1 else get_viewport_rect().size
	_panel.size = Vector2(minf(1320, area.x - 64), minf(940, area.y - 64))
	_panel.position = (area - _panel.size) * 0.5


func _label(text: String, font_size: int, color := INK) -> Label:
	var label := UiKit.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _begin_capture(action: String, device: String, button: Button) -> void:
	if not _capture_action.is_empty(): return
	# This callback can disable the button during its own GUI press dispatch.
	# Explicitly consume that opening event before it reaches gameplay handlers.
	get_viewport().set_input_as_handled()
	_capture_action = action
	_capture_device = device
	_capture_button = button
	_opening_held = Input.is_action_pressed("ui_accept")
	_pending_event = null
	for control in _chain: control.disabled = control != _back
	_back.text = tr("取消改键")
	_status.text = tr("正在修改「%s」：按下并松开新输入，Esc / Start 取消。仅移动和思考支持摇杆与扳机。") % tr(Settings.BINDABLE_ACTIONS[action])
	Settings.release_gameplay_inputs()


func _input(event: InputEvent) -> void:
	if _capture_action.is_empty(): return
	if event is InputEventMouseMotion or event is InputEventMouseButton: return
	get_viewport().set_input_as_handled()
	Settings.release_gameplay_inputs()
	for action in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_focus_next", "ui_focus_prev"]:
		Input.action_release(action)
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START):
		_finish_capture(tr("已取消，键位没有改变。"))
		return
	if _opening_held:
		if event.is_action_released("ui_accept"): _opening_held = false
		return
	if _pending_event != null:
		if _released(event, _pending_event):
			var error := Settings.set_binding(_capture_action, _capture_device, _pending_event)
			_refresh_labels()
			_finish_capture(tr("已保存新键位。") if error.is_empty() else error)
		return
	if event is InputEventKey and (not event.pressed or event.echo): return
	if event is InputEventJoypadButton and not event.pressed: return
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.65: return
	var error := Settings.binding_error(_capture_action, _capture_device, event)
	if not error.is_empty():
		_status.text = error + "\n" + tr("继续按另一个输入，或用 Esc / Start 取消。")
		return
	_pending_event = event.duplicate()
	_status.text = tr("松开按键或让摇杆回中后保存；Esc / Start 仍可取消。")


func _on_window_focus(focused: bool) -> void:
	if not focused and not _capture_action.is_empty():
		_finish_capture(tr("已取消，键位没有改变。"))


func _released(event: InputEvent, pending: InputEvent) -> bool:
	if event is InputEventKey and pending is InputEventKey:
		return not event.pressed and (event.physical_keycode if event.physical_keycode != 0 else event.keycode) == (pending.physical_keycode if pending.physical_keycode != 0 else pending.keycode)
	if event is InputEventJoypadButton and pending is InputEventJoypadButton: return not event.pressed and event.button_index == pending.button_index
	if event is InputEventJoypadMotion and pending is InputEventJoypadMotion: return event.axis == pending.axis and absf(event.axis_value) < 0.25
	return false


func _finish_capture(message: String) -> void:
	_capture_action = ""
	_pending_event = null
	_opening_held = false
	Settings.release_gameplay_inputs()
	for control in _chain: control.disabled = false
	_back.text = tr("返回")
	_status.text = message
	if is_instance_valid(_capture_button): _capture_button.grab_focus.call_deferred()


func _refresh_labels() -> void:
	for action in _buttons:
		for device in _buttons[action]: _buttons[action][device].text = Settings.binding_label(action, device)


func _unhandled_input(event: InputEvent) -> void:
	# Even an unrecognized gameplay key stays inside this modal.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close()


func close() -> void:
	if not _capture_action.is_empty():
		_finish_capture(tr("已取消，键位没有改变。"))
		return
	if _closed: return
	_closed = true
	Settings.release_gameplay_inputs()
	closed.emit()
	queue_free()
