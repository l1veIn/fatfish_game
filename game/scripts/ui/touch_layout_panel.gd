extends Control
## A draft layout: dragging and size changes only persist when Save is pressed.
signal closed

const TOUCH_UI := preload("res://scripts/ui/touch_controls.gd")
const NAMES := {"joystick": "摇杆", "interact": "交互", "think": "思考"}
var draft: Dictionary
var selected := "joystick"
var previews := {}
var _size_slider: HSlider
var _size_label: Label
var _drag_id := ""
var _finger := -1
var _offset := Vector2.ZERO
var _toolbar: PanelContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP
	draft = Settings.touch_layout.duplicate(true)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.02, 0.64)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	for id in NAMES:
		var control: Control
		if id == "joystick":
			var stick := VirtualJoystick.new()
			stick.joystick_size = 152
			stick.tip_size = 68
			control = stick
		else:
			var button := Button.new()
			button.text = tr("交互") if id == "interact" else tr("按住\n思考")
			button.add_theme_font_size_override("font_size", 36 if id == "interact" else 26)
			TOUCH_UI.style_action(button)
			control = button
		control.size = Settings.TOUCH_BASE[id]
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(control)
		previews[id] = control
	_toolbar = PanelContainer.new()
	_toolbar.position = Vector2(430, 24)
	_toolbar.size = Vector2(1060, 300)
	add_child(_toolbar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_toolbar.add_child(col)
	var title := UiKit.label(tr("触控布局"), 34, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := UiKit.label(tr("拖动控件调整位置，选择控件后调整大小。"), 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var choices := HBoxContainer.new()
	col.add_child(choices)
	for id in NAMES:
		var b := UiKit.button(tr(NAMES[id]), 26, Vector2(0, 54))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _select(id))
		choices.add_child(b)
		_buttons.append(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	_size_label = UiKit.label("", 25)
	_size_label.custom_minimum_size.x = 250
	row.add_child(_size_label)
	_size_slider = HSlider.new()
	_size_slider.min_value = 65
	_size_slider.max_value = 160
	_size_slider.step = 5
	_size_slider.custom_minimum_size = Vector2(480, 48)
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_slider.value_changed.connect(func(value):
		draft[selected].scale = value / 100.0
		draft = Settings.sanitize_touch_layout(draft)
		_refresh())
	row.add_child(_size_slider)
	var actions := HBoxContainer.new()
	col.add_child(actions)
	for spec in [["恢复默认", _defaults], ["取消", close], ["保存布局", _save]]:
		var b := UiKit.button(tr(spec[0]), 26, Vector2(0, 54))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		actions.add_child(b)
		_buttons.append(b)
	var focus: Array[Control] = []
	focus.append_array(_buttons.slice(0, 3))
	focus.append(_size_slider)
	focus.append_array(_buttons.slice(3))
	for i in focus.size():
		focus[i].focus_next = focus[i].get_path_to(focus[(i + 1) % focus.size()])
		focus[i].focus_previous = focus[i].get_path_to(focus[(i - 1 + focus.size()) % focus.size()])
	_select(selected)
	_buttons[0].grab_focus.call_deferred()


func _select(id: String) -> void:
	selected = id
	_size_slider.set_value_no_signal(draft[id].scale * 100)
	_refresh()


func _refresh() -> void:
	for id in previews:
		previews[id].position = Settings.touch_rect(id, draft).position
		previews[id].scale = Vector2.ONE * draft[id].scale
	_size_label.text = "%s · %d%%" % [tr(NAMES[selected]), roundi(draft[selected].scale * 100)]
	queue_redraw()


func _draw() -> void:
	if draft != null and not draft.is_empty():
		draw_style_box(UiKit.box(Color.TRANSPARENT, UiKit.GOLD, 3, 26), Settings.touch_rect(selected, draft).grow(8))


func _gui_input(event: InputEvent) -> void:
	var at: Vector2
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		if _drag_id != "": return
		_finger = event.index
		at = event.position
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _drag_id != "": return
		_finger = -1
		at = event.position
	else:
		return
	for id in NAMES:
		var rect := Settings.touch_rect(id, draft)
		if rect.has_point(at):
			_select(id)
			_drag_id = id
			_offset = rect.get_center() - at
			accept_event()
			return


func _input(event: InputEvent) -> void:
	if _drag_id == "": return
	var move := false
	var at := Vector2.ZERO
	if event is InputEventScreenDrag and event.index == _finger:
		move = true
		at = event.position
	elif event is InputEventMouseMotion and _finger == -1:
		move = true
		at = event.position
	elif (event is InputEventScreenTouch and event.index == _finger and (not event.pressed or event.canceled)) or (event is InputEventMouseButton and _finger == -1 and not event.pressed):
		_drag_id = ""
		get_viewport().set_input_as_handled()
	if move:
		at += _offset
		draft[_drag_id].x = at.x / 1920.0
		draft[_drag_id].y = at.y / 1080.0
		draft = Settings.sanitize_touch_layout(draft)
		_refresh()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		_drag_id = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _defaults() -> void:
	draft = Settings.TOUCH_DEFAULT.duplicate(true)
	_select(selected)


func _save() -> void:
	Settings.touch_layout = Settings.sanitize_touch_layout(draft)
	Settings.save_settings()
	Settings.changed.emit()
	close()


func close() -> void:
	closed.emit()
	queue_free()
