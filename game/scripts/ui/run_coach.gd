class_name RunCoach
extends Control
## A non-modal first-meal ticket. Only confirmed gameplay events advance the lesson.
## Input shortcuts bypass focus so Enter / A can keep serving food, never skip by accident.

signal completed(skipped: bool)

enum Step { TAKE, CATCH, SERVE, DONE }
const HOME := Vector2(24, 890)

var step := Step.TAKE
var active := true
var _device := "mouse"
var _dismiss_in := 0.0
var _title: Label
var _instruction: Label
var _footer: Label
var _skip: Button
var _paper: Texture2D
var _raised := false


func _ready() -> void:
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--force-touch"):
		_device = "touch"
	position = HOME
	size = Vector2(1080, 174)
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper = load("res://assets/canteen/ui_paper.png")
	_title = UiKit.label("", 30, UiKit.INK)
	_title.position = Vector2(30, 13)
	_title.size = Vector2(760, 42)
	add_child(_title)
	_instruction = UiKit.label("", 24, UiKit.INK)
	_instruction.position = Vector2(30, 62)
	_instruction.size = Vector2(1020, 74)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_instruction)
	_footer = UiKit.label("", 20, Color(0.47, 0.29, 0.15))
	_footer.position = Vector2(30, 140)
	_footer.size = Vector2(1020, 28)
	add_child(_footer)
	for label in [_title, _instruction, _footer]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip = UiKit.button("", 22, Vector2(242, 48))
	_skip.position = Vector2(810, 14)
	_skip.size = Vector2(242, 48)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip)
	add_child(_skip)
	Settings.changed.connect(_refresh)
	_refresh()


func _draw() -> void:
	UiKit.nine(self, _paper, Rect2(Vector2.ZERO, size), 26.0)


func _process(delta: float) -> void:
	_avoid_hand()
	if _dismiss_in > 0.0:
		_dismiss_in -= delta
		if _dismiss_in <= 0.0:
			hide()


func _avoid_hand() -> void:
	# Keep the original warm-paper lesson clear of the actual box, including its done message.
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
	_raised = Rect2(HOME, size).grow(80 if _raised else 18).intersects(box_rect)
	position = Vector2(HOME.x, maxf(450, box_rect.position.y - size.y - 24)) if _raised else HOME


func _input(event: InputEvent) -> void:
	if not active or not visible:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
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
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		device = "touch"
	elif event is InputEventMouseMotion and event.relative.length_squared() > 4.0:
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
	_skip.text = tr("跳过引导") if _device == "touch" else (tr("跳过引导 · View") if _device == "pad" else tr("跳过引导 · T"))
	if not active:
		_title.text = tr("开饭啦！计时开始")
		_instruction.text = tr("继续接菜、送桌；关门后用 token 升级。")
		_footer.text = tr("随时点「暂停」休息一下。") if _device == "touch" else tr("随时按 Esc / Start 暂停。")
		return
	var titles := [tr("先拿一个饭盒"), tr("接住一份菜"), tr("把饭盒送上桌")]
	_title.text = "%02d / 03   %s" % [step + 1, titles[step]]
	var instructions: Array
	match _device:
		"touch":
			instructions = [tr("点右下角「拿起饭盒」。"),
				tr("在接菜区拖动，把饭盒放在落下的菜下面。"),
				tr("拖回右下角餐桌，再点「送饭」。")]
		"keyboard", "pad":
			var device := "gamepad" if _device == "pad" else "keyboard"
			var deliver := Settings.binding_label("deliver", device)
			var move := _movement_label(device)
			instructions = [tr("移到右下角餐桌，按 %s 拿盒。\n移动：%s") % [deliver, move],
				tr("移动饭盒，接住一份落下的菜。\n移动：%s") % move,
				tr("移回右下角餐桌，按 %s 送给她。\n移动：%s") % [deliver, move]]
		_:
			instructions = [tr("把鼠标移到右下角餐桌，点击拿盒。"),
				tr("移动鼠标，把饭盒放在落下的菜下面。"),
				tr("把饭盒移回右下角餐桌，点击送给她。")]
	_instruction.text = instructions[step]
	_footer.text = tr("先完成一次送餐，再开始计时。不用装满也能送。")


func _movement_label(device: String) -> String:
	return "↑ %s  ↓ %s  ← %s  → %s" % [Settings.binding_label("move_up", device),
		Settings.binding_label("move_down", device), Settings.binding_label("move_left", device),
		Settings.binding_label("move_right", device)]
