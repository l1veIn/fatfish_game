extends Node
## Real ScreenTouch / ScreenDrag through Viewport GUI and gameplay dispatch.
## Progress and one falling dish are explicit fixtures, not a playthrough.

var _main: Node
var _checks: Array = []
var _failures: Array = []
var _out := ""
var _source := {}
var _shots: Array = []
const SOURCES := ["project.godot", "scripts/main.gd", "scripts/run/canteen_run.gd",
	"scripts/tree/tree_screen.gd", "scripts/ui/touch_controls.gd", "scripts/ui/run_coach.gd",
	"scripts/ui/pause_menu.gd", "scripts/autoload/settings.gd", "scripts/autoload/game.gd",
	"tests/toy_touch_test.gd", "data/i18n/en.json"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Game.save_path.begins_with("user://qa_toy_touch") or not Settings._testing or not OS.get_cmdline_user_args().has("--force-touch"):
		push_error("Requires --test-profile=toy_touch_<suffix> --force-touch")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	for path in SOURCES:
		_source[path] = FileAccess.get_sha256("res://" + path)
	var player_save := FileAccess.get_file_as_bytes("user://save.json")
	var player_settings := FileAccess.get_file_as_bytes(Settings.PATH)
	Settings.reset_bindings()
	Settings.reduced_motion = true
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.fullscreen = false
	Settings.window_size = Vector2i(960, 540)
	Settings.apply()
	Game.reset_save()
	Game.version = 1
	Game.runs = 1
	Game.tokens = 50000
	Game.levels = {"start": 1, "stall_main": 1, "think": 1}
	Game.seen_buttons = {"intro_think": true, "intro_canteen_started": true}
	Game._recompute()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await wait_frames(8)
	await _key(KEY_ENTER)
	_check(_main._screen is TreeScreen, "main title confirmation opens the production tree")
	if not _main._screen is TreeScreen:
		await _finish(player_save, player_settings)
		return
	await _tree_route(_main._screen)
	var tree: TreeScreen = _main._screen
	await _mouse_click(tree._start.get_global_rect().get_center())
	_check(_main._screen is CanteenRun, "tree start GUI enters production meal through main controller")
	if _main._screen is CanteenRun:
		await _meal_route(_main._screen)
	await _finish(player_save, player_settings)


func _tree_route(tree: TreeScreen) -> void:
	_check(is_instance_valid(tree._touch_panel), "touch tree controls mount before first contact")
	var id := "stall_main"
	var point := tree._at(Game.node(id))
	var before_level := Game.level(id)
	var before_tokens := Game.tokens
	await _touch(0, point, true)
	await _touch(0, point, false)
	_check(tree._hover == id and Game.level(id) == before_level and Game.tokens == before_tokens, "touch selects a skill without buying")
	await _emulated_mouse(point)
	_check(Game.level(id) == before_level, "touch-generated mouse cannot buy selected skill twice")
	await _touch_tap(tree._touch_buy.get_global_rect().get_center())
	_check(Game.level(id) == before_level + 1, "separate touch purchase GUI buys exactly one level")
	await _touch_tap(tree._touch_refund.get_global_rect().get_center())
	_check(Game.level(id) == Game.refund_floor(id), "touch refund GUI uses real refund dependency rules")
	var before_pan := tree._pan
	await _touch(0, Vector2(1100, 760), true)
	await _drag(0, Vector2(1100, 760), Vector2(1240, 730))
	await _touch(0, Vector2(1240, 730), false)
	_check(tree._pan.distance_to(before_pan) > 100.0, "one-finger drag pans tree")
	var zoom_before := tree._zoom
	var tokens_before := Game.tokens
	await _touch(0, Vector2(1000, 640), true)
	await _touch(1, Vector2(1300, 640), true)
	await _drag(1, Vector2(1300, 640), Vector2(1450, 640))
	await _touch(1, Vector2(1450, 640), false)
	await _touch(0, Vector2(1000, 640), false)
	_check(tree._zoom > zoom_before and Game.tokens == tokens_before, "two-finger pinch zooms without buying")
	var zoom_after := tree._zoom
	await _touch_tap(tree._touch_zoom_out.get_global_rect().get_center())
	_check(tree._zoom < zoom_after, "zoom-out touch GUI changes scale")
	await _touch(0, Vector2(1000, 740), true)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_frames()
	_check(tree._touch_points.is_empty(), "focus loss cancels every map finger")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _touch(0, Vector2(1000, 740), false)
	await shot("tree_touch")


func _meal_route(run: CanteenRun) -> void:
	run._arms.clear() # deterministic falling dish below replaces random spoons only
	var ui = run._touch_controls
	_check(is_instance_valid(ui) and run._learning(), "meal mounts touch controls and existing tutorial")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	_check(run._hand != null and run._coach.step == RunCoach.Step.CATCH, "touch pickup GUI takes one real box and advances tutorial")
	if run._hand == null:
		return
	_check(run._coach._device == "touch", "tutorial describes the actual touch device")
	await shot("run_touch_lesson")
	var empty_before := run._empty
	await _touch(0, Vector2(1350, 865), true)
	await _drag(0, Vector2(1350, 865), Vector2(800, 700))
	_check(run._hand != null and run._hand.pos.distance_to(Vector2(800, 700)) < 1, "touch drag moves actual box through production hand controller")
	await _touch(0, Vector2(800, 700), false)
	_check(run._hand != null and run._empty == empty_before, "releasing a drag never returns or serves the box")
	await _emulated_mouse(Vector2(1385, 865))
	_check(run._hand != null and run._hand.pos.distance_to(Vector2(800, 700)) < 1, "synthetic mouse cannot move or deliver a touch-held box")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	_check(run._hand != null and run._hand.pos.distance_to(Vector2(800, 700)) < 1, "disabled serve control neither delivers nor steals steering")
	run._add_item(run._hand.pos + Vector2(0, -8), Vector2(0, 140), CanteenRun.I.BALL)
	await _wait(0.18)
	_check(run.caught > 0 and run._coach.step == RunCoach.Step.SERVE, "real food collision advances touch lesson")
	await _touch(0, Vector2(800, 700), true)
	await _drag(0, Vector2(800, 700), Vector2(1385, 865))
	await _touch(0, Vector2(1385, 865), false)
	_check(run._hand != null, "dragging back to table still waits for explicit serve")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	_check(run._hand == null and not run._learning(), "serve touch GUI completes tutorial through real meal event")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	await _touch(0, Vector2(800, 700), true)
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _wait(0.10)
	_check(run._thinking and ui.think_held, "second finger holds thought while first finger steers")
	await _drag(0, Vector2(800, 700), Vector2(960, 690))
	_check(run._thinking and run._hand.pos.x > 950, "multitouch steering and thought coexist")
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	await _touch(0, Vector2(960, 690), false)
	_check(not run._thinking and not ui.think_held, "releasing thinking finger stops thought")
	await _touch(0, Vector2(800, 700), true)
	await _touch(0, Vector2(800, 700), false, true)
	_check(run._touch_finger == -1, "canceled screen contact releases steering")
	await _wait(1.15)
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _wait(0.08)
	await _drag(1, ui.think_button.get_global_rect().get_center(), Vector2(1000, 850))
	_check(not run._thinking and not ui.think_held, "dragging thought finger off button cancels held action")
	await _touch(1, Vector2(1000, 850), false)
	await _wait(1.15)
	await _touch(0, Vector2(800, 700), true)
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _wait(0.08)
	await _touch_tap(ui.pause_button.get_global_rect().get_center(), 2)
	_check(get_tree().paused and is_instance_valid(run._pause), "pause touch GUI freezes gameplay through production pause")
	_check(not ui.think_held and not run._thinking and run._touch_finger == -1, "pause releases thought and steering fingers")
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	await _touch(0, Vector2(800, 700), false)
	await _key(KEY_ESCAPE)
	await _wait(0.25)
	_check(not get_tree().paused and not run._thinking, "resume cannot resurrect held touch")
	Settings.pause_unfocused = false
	await _wait(1.05)
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_frames()
	_check(not ui.think_held and not run._thinking, "focus loss clears thought even when auto-pause is disabled")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	await _desktop_controls(run)
	await shot("run_touch")
	await _touch_tap(ui.pause_button.get_global_rect().get_center())
	var menu: PauseMenu = run._pause
	await _mouse_click(menu._buttons[-1].get_global_rect().get_center())
	await wait_frames(8)
	_check(_main._screen is TitleScreen and not get_tree().paused, "leaving via real pause GUI returns to title without held actions")
	_check(not Input.is_action_pressed("think") and not Input.is_action_pressed("deliver"), "scene exit leaves no held gameplay actions")
	await _key(KEY_ENTER)
	_check(_main._screen is TreeScreen, "re-entering continues through normal main screen flow")


func _desktop_controls(run: CanteenRun) -> void:
	await _mouse_click(Vector2(1385, 865))
	# Mouse press points at the table; movement to the new aim happens on the next
	# frame, as in the original desktop control. The next click returns the box.
	if run._hand != null:
		await _mouse_click(Vector2(1385, 865))
	_check(run._hand == null, "physical mouse click still returns an empty box at the table")
	await _mouse_click(Vector2(1385, 865))
	_check(run._hand != null, "physical mouse pickup still works with touch UI present")
	var before: Vector2 = run._hand.pos
	var move := InputEventKey.new()
	move.keycode = KEY_LEFT
	move.physical_keycode = KEY_LEFT
	move.pressed = true
	Input.parse_input_event(move)
	await _wait(0.15)
	move.pressed = false
	Input.parse_input_event(move)
	await wait_frames()
	_check(run._hand.pos.x < before.x - 50, "physical keyboard direction steers the existing hand controller")
	await _mouse_click(Vector2(1385, 865))
	await _key(KEY_E)
	_check(run._hand == null, "physical keyboard deliver still reaches table action")
	await _pad(JOY_BUTTON_A)
	_check(run._hand != null, "controller A still picks up from the table")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = -1.0
	Input.parse_input_event(stick)
	before = run._hand.pos
	await _wait(0.15)
	stick.axis_value = 0
	Input.parse_input_event(stick)
	await wait_frames()
	_check(run._hand.pos.x < before.x - 50, "controller stick still steers the box")
	await _wait(1.15)
	var think := InputEventKey.new()
	think.keycode = KEY_SPACE
	think.physical_keycode = KEY_SPACE
	think.pressed = true
	Input.parse_input_event(think)
	await _wait(0.08)
	_check(run._thinking, "keyboard thinking remains available after touch")
	think.pressed = false
	Input.parse_input_event(think)
	await wait_frames()
	_check(not run._thinking, "keyboard release still ends thinking")


func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await wait_frames()


func _check(ok: bool, message: String) -> void:
	_checks.append({"pass": ok, "message": message})
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		_failures.append(message)


func wait_frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _touch(index: int, at: Vector2, down: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	event.canceled = canceled
	get_viewport().push_input(event, true)
	await wait_frames()


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to
	event.relative = to - from
	get_viewport().push_input(event, true)
	await wait_frames()


func _touch_tap(at: Vector2, index := 0) -> void:
	await _touch(index, at, true)
	await _touch(index, at, false)


func _mouse_click(at: Vector2, device := 0) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = device
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await wait_frames()


func _emulated_mouse(at: Vector2) -> void:
	await _mouse_click(at, InputEvent.DEVICE_ID_EMULATION)


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await wait_frames()


func shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	_shots.append({"path": path, "sha256": FileAccess.get_sha256(path)})


func _finish(player_save: PackedByteArray, player_settings: PackedByteArray) -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	await wait_frames()
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_save, "player save unchanged")
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == player_settings, "player settings unchanged")
	var after := {}
	for path in SOURCES:
		after[path] = FileAccess.get_sha256("res://" + path)
	_check(_source == after, "tested source remained stable during this run")
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"source_sha256": _source, "source_after": after, "engine": Engine.get_version_info().string,
		"renderer": DisplayServer.get_name(), "language": Settings.language, "shots": _shots,
		"scope": "Real touch/drag through Viewport.push_input and GUI, explicit emulated mouse events, real main screen flow. Starting progress, random spoon suppression and one falling dish are fixtures. Not physical mobile hardware, browser pointer conversion, or human playtesting."}
	if not _out.is_empty():
		FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("TOY_TOUCH_TEST %s checks=%d failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _checks.size(), _failures.size()])
	Audio._exit_tree()
	await _wait(0.15)
	UiKit.clear_cache()
	get_tree().quit(0 if _failures.is_empty() else 1)
