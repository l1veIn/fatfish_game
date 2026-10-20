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
	deliver_button = make_button("", Rect2(1480, 954, 394, 100))
	deliver_button.name = "TouchDeliver"
	deliver_button.pressed.connect(func(): deliver_requested.emit())
	add_child(deliver_button)
	think_button = make_button(tr("按住思考"), Rect2(1140, 954, 290, 100))
	think_button.name = "TouchThink"
	think_button.held_changed.connect(func(held: bool): think_held = held)
	add_child(think_button)
	pause_button = make_button(tr("暂停游戏"), Rect2(420, 24, 170, 96), 28)
	pause_button.name = "TouchPause"
	pause_button.pressed.connect(func(): pause_requested.emit())
	add_child(pause_button)
	hint = UiKit.label("", 25, UiKit.TEXT, 4)
	hint.position = Vector2(1140, 910)
	hint.size = Vector2(730, 38)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	Settings.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(run) or not is_instance_valid(deliver_button):
		return
	visible = not run._ended
	think_button.visible = run.can_think
	think_button.text = tr("按住思考")
	pause_button.text = tr("暂停游戏")
	if not visible:
		cancel_touch()
		return
	var has_box: bool = run._hand != null
	var at_table: bool = has_box and run.TABLE.grow(60).has_point(run._hand.pos)
	var at_warmer: bool = has_box and run.warm and run.WARM_RECT.grow(20).has_point(run._hand.pos) and not run._hand.items.is_empty()
	deliver_button.text = tr("拿起饭盒") if not has_box else (tr("放入保温箱") if at_warmer else (tr("放回饭盒") if run._hand.items.is_empty() else tr("送饭")))
	deliver_button.disabled = run._empty <= 0 if not has_box else not (at_table or at_warmer)
	hint.text = tr("拖动接菜 · 移回餐桌后送饭") if has_box else tr("点「拿起饭盒」开始接菜")


func cancel_touch() -> void:
	think_held = false
	for button in [deliver_button, think_button, pause_button]:
		if is_instance_valid(button):
			button.cancel_touch()
