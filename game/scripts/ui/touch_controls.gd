extends Control
## Touch-only additions use the same serving and thinking code as desktop controls.
## Touch buttons own their finger until release; no global Input action is held.

signal deliver_requested
signal pause_requested

var run: Node
var think_held := false
var deliver_button: Button
var think_button: Button
var pause_button: Button
var hint: Label
var joystick: VirtualJoystick
var _joystick_held := false
var _joystick_reset_pending := false

const PLAY_BOTTOM := 820.0 # Keep the whole tray above the bottom controls and lesson.


class FingerButton extends Button:
	signal held_changed(held: bool)
	var _finger := -1
	var _mouse_held := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		button_down.connect(func():
			if _finger < 0:
				_mouse_held = true
				held_changed.emit(true))
		button_up.connect(func():
			if _mouse_held:
				_mouse_held = false
				held_changed.emit(false))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed and not event.canceled and not disabled and _finger < 0:
			_finger = event.index
			set_pressed_no_signal(true)
			held_changed.emit(true)
			accept_event()

	func _input(event: InputEvent) -> void:
		# Native Button already supports desktop mouse/keyboard. Touch-generated mouse
		# must not duplicate this button's own multitouch activation.
		if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION and is_visible_in_tree() and get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			return
		if _finger < 0:
			return
		if event is InputEventScreenDrag and event.index == _finger:
			if not get_global_rect().has_point(event.position):
				cancel_touch()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.index == _finger and (not event.pressed or event.canceled):
			var activate: bool = not event.canceled and not disabled and is_visible_in_tree() and get_global_rect().has_point(event.position)
			cancel_touch()
			get_viewport().set_input_as_handled()
			if activate:
				pressed.emit()

	func cancel_touch() -> void:
		var was_held := _finger >= 0 or _mouse_held
		_finger = -1
		_mouse_held = false
		set_pressed_no_signal(false)
		if was_held:
			held_changed.emit(false)

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
			cancel_touch()


static func available() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--force-touch")


static func make_button(text: String, rect: Rect2, font_size := 32) -> Button:
	var button := FingerButton.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.custom_minimum_size = rect.size
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _ready() -> void:
	name = "TouchControls"
	size = Vector2(1920, 1080)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_joystick()
	deliver_button = make_button(tr("交互"), Rect2(1648, 888, 236, 176), 36)
	deliver_button.name = "TouchDeliver"
	deliver_button.pressed.connect(func(): deliver_requested.emit())
	add_child(deliver_button)
	think_button = make_button("", Rect2(1474, 936, 150, 128), 26)
	think_button.name = "TouchThink"
	think_button.held_changed.connect(func(held: bool): think_held = held)
	add_child(think_button)
	style_action(deliver_button)
	style_action(think_button)
	pause_button = make_button(tr("暂停游戏"), Rect2(420, 24, 170, 96), 28)
	pause_button.name = "TouchPause"
	pause_button.pressed.connect(func(): pause_requested.emit())
	add_child(pause_button)
	hint = UiKit.label("", 25, UiKit.TEXT, 4)
	hint.position = Vector2(312, 956)
	hint.size = Vector2(1080, 70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	Settings.changed.connect(_apply_layout)
	_apply_layout()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(run) or not is_instance_valid(deliver_button):
		return
	visible = not run._ended
	think_button.disabled = not run.can_think
	think_button.text = tr("按住\n思考") if run.can_think else tr("思考\n未解锁")
	pause_button.text = tr("暂停游戏")
	if not visible:
		cancel_touch()
		return
	var has_box: bool = run._hand != null
	var at_table: bool = has_box and run.TABLE.grow(60).has_point(run._hand.pos)
	var at_warmer: bool = has_box and run.warm and run.WARM_RECT.grow(20).has_point(run._hand.pos) and not run._hand.items.is_empty()
	deliver_button.text = tr("交互")
	deliver_button.disabled = run._empty <= 0 if not has_box else not (at_table or at_warmer)
	hint.visible = not (is_instance_valid(run._coach) and run._coach.visible)
	hint.text = tr("拖动玩家之手或拨动摇杆 · 回到餐桌后点「交互」") if has_box else tr("点「交互」拿盒 · 拖动玩家之手移动")


func cancel_touch() -> void:
	think_held = false
	if _joystick_held:
		_joystick_held = false
		for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
			Input.action_release(action)
		# Godot 4.7.2 has no public joystick reset and retains contact on focus loss.
		# Retire the control, then recreate it outside the notification traversal.
		joystick.hide()
		joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not _joystick_reset_pending:
			_joystick_reset_pending = true
			_replace_joystick.call_deferred()
	for button in [deliver_button, think_button, pause_button]:
		if is_instance_valid(button):
			button.cancel_touch()


func _add_joystick() -> void:
	joystick = VirtualJoystick.new()
	joystick.name = "TouchJoystick"
	joystick.action_left = &"move_left"
	joystick.action_right = &"move_right"
	joystick.action_up = &"move_up"
	joystick.action_down = &"move_down"
	joystick.position = Vector2(56, 884)
	joystick.size = Vector2(184, 184)
	joystick.joystick_size = 152.0
	joystick.tip_size = 68.0
	joystick.joystick_mode = VirtualJoystick.JOYSTICK_FIXED
	# Movement already uses the shared InputMap dead zone, just like a gamepad.
	joystick.deadzone_ratio = 0.0
	joystick.pressed.connect(func(): _joystick_held = true)
	joystick.released.connect(func(_direction: Vector2): _joystick_held = false)
	add_child(joystick)
	_place_control(joystick, "joystick")


func _replace_joystick() -> void:
	_joystick_reset_pending = false
	if not is_inside_tree() or is_queued_for_deletion():
		return
	remove_child(joystick)
	joystick.queue_free()
	_add_joystick()


static func style_action(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var alpha := 0.55 if state == "pressed" else (0.18 if state == "disabled" else 0.32)
		button.add_theme_stylebox_override(state, UiKit.box(Color(0.12, 0.08, 0.05, alpha), Color(1, 0.93, 0.8, 0.5), 2, 24))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color(1, 0.96, 0.86))
	button.add_theme_color_override("font_disabled_color", Color(1, 0.96, 0.86, 0.45))
	button.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.01, 0.7))
	button.add_theme_constant_override("outline_size", 3)


func _place_control(control: Control, id: String) -> void:
	control.position = Settings.touch_rect(id).position
	control.scale = Vector2.ONE * Settings.touch_layout[id].scale


func _apply_layout() -> void:
	cancel_touch()
	for pair in [[joystick, "joystick"], [deliver_button, "interact"], [think_button, "think"]]:
		if is_instance_valid(pair[0]):
			_place_control(pair[0], pair[1])
