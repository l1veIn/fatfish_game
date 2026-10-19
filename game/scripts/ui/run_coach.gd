class_name RunCoach
extends Control
## A non-modal first-meal ticket. Only confirmed gameplay events advance the lesson.
## Input shortcuts bypass focus so Enter / A can keep serving food, never skip by accident.

signal completed(skipped: bool)

enum Step { TAKE, CATCH, SERVE, DONE }
const HOME := Vector2(32, 904)

var step := Step.TAKE
var active := true
var _device := "mouse"
var _dismiss_in := 0.0
var _title: Label
var _instruction: Label
var _footer: Label
var _skip: Button
var _raised := false


func _ready() -> void:
	position = HOME
	size = Vector2(1170, 150)
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UiKit.label("", 29, Color("233d46"))
	_title.position = Vector2(26, 12)
	_title.size = Vector2(850, 42)
	add_child(_title)
	_instruction = UiKit.label("", 26, Color("233d46"))
	_instruction.position = Vector2(26, 55)
	_instruction.size = Vector2(1118, 62)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_instruction)
	_footer = UiKit.label("", 21, Color("65736e"))
	_footer.position = Vector2(26, 120)
	_footer.size = Vector2(1118, 28)
	add_child(_footer)
	for label in [_title, _instruction, _footer]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip = UiKit.button("", 22, Vector2(258, 44))
	_skip.position = Vector2(886, 10)
	_skip.size = Vector2(258, 44)
	for state in ["normal", "hover", "pressed"]:
		_skip.add_theme_stylebox_override(state, UiKit.box(Color("e9e4d6"), Color("b89758"), 1, 8, 1))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_skip.add_theme_color_override(state, Color("233d46"))
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip)
	add_child(_skip)
	Settings.changed.connect(_refresh)
	_refresh()


func _draw() -> void:
	draw_style_box(UiKit.box(Color("f6efdf"), Color("b89758"), 1, 12, 1), Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(0, 14, 5, size.y - 28), Color("193b49"))


func _process(delta: float) -> void:
	_avoid_hand()
	if _dismiss_in > 0.0:
		_dismiss_in -= delta
		if _dismiss_in <= 0.0:
			hide()


func _avoid_hand() -> void:
	# Presentation only: leave the actual mouse range and collision rules untouched.
	var run := get_parent() as CanteenRun
	if not visible or run == null or run._hand == null:
		_raised = false
		position = HOME
		return
	var n := run._cols()
	var tex: Texture2D = run._box_tex[n]
	var grid: Rect2 = run._box_grid[n]
	var width := n * CanteenRun.CELL / grid.size.x
	var height := width * tex.get_height() / tex.get_width()
	var box_rect := Rect2(run._hand.pos - Vector2(width * (grid.position.x + grid.size.x * 0.5), height * (grid.position.y + grid.size.y * 0.5)), Vector2(width, height)).grow(18)
	# An extra 80px release margin prevents repeated up/down jumps near the entry boundary.
	_raised = Rect2(HOME, size).grow(80 if _raised else 18).intersects(box_rect)
	position = Vector2(HOME.x, maxf(450, box_rect.position.y - size.y - 24)) if _raised else HOME


func _input(event: InputEvent) -> void:
	if not active or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T:
		skip()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		skip()
		get_viewport().set_input_as_handled()
		return
	var device := _device
	if event is InputEventMouseMotion and event.relative.length_squared() > 4.0:
		device = "mouse"
	elif event is InputEventMouseButton:
		device = "mouse"
	elif event is InputEventKey and event.pressed:
		device = "keyboard"
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		device = "pad"
	if device != _device:
		_device = device
		_refresh()


func took_box() -> void:
	if active and step == Step.TAKE:
		step = Step.CATCH
		_refresh()


func caught_food() -> void:
	if active and step == Step.CATCH:
		step = Step.SERVE
		_refresh()


func served_food() -> void:
	if active and step == Step.SERVE:
		_finish(false)


## Returning the empty box or spilling the last dish never leaves an impossible instruction.
func reconcile_hand(has_box: bool, has_food: bool) -> void:
	if not active:
		return
	var next := step
	if not has_box:
		next = Step.TAKE
	elif step == Step.SERVE and not has_food:
		next = Step.CATCH
	if next != step:
		step = next
		_refresh()


func skip() -> void:
	if active:
		_finish(true)


func close() -> void:
	active = false
	hide()


func _finish(skipped: bool) -> void:
	active = false
	step = Step.DONE
	_dismiss_in = 4.5
	_refresh()
	completed.emit(skipped)


func _refresh() -> void:
	if not is_instance_valid(_title):
		return
	_skip.visible = active
	_skip.text = tr("跳过引导 · View") if _device == "pad" else tr("跳过引导 · T")
	if not active:
		_title.text = tr("开饭啦！计时开始")
		_instruction.text = tr("继续接菜、送餐；关门后再来升级。")
		_footer.text = tr("随时按 Esc / Start 暂停。")
		return
	var titles := [tr("先拿一个饭盒"), tr("接住一份菜"), tr("把饭盒送上桌")]
	_title.text = "%02d / 03   %s" % [step + 1, titles[step]]
	var instructions: Array
	match _device:
		"keyboard":
			instructions = [tr("方向键 / WASD 移到餐桌，E / Enter 拿盒。"),
				tr("方向键 / WASD 接住落下的菜。"),
				tr("移回餐桌，按 E / Enter 送餐。")]
		"pad":
			instructions = [tr("左摇杆移到餐桌，按 A 拿盒。"),
				tr("左摇杆移动饭盒，接住落下的菜。"),
				tr("移回餐桌，按 A 送餐。")]
		_:
			instructions = [tr("移到右下餐桌，点击拿盒。"),
				tr("移动鼠标，把饭盒放到落下的菜下面。"),
				tr("移回餐桌，点击送餐。")]
	_instruction.text = instructions[step]
	_footer.text = tr("首次送餐后开始计时；不用装满。")
