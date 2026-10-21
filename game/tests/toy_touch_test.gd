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
	"tests/toy_touch_test.gd", "data/i18n/en.json", "scripts/ui/recipe_book.gd",
	"scripts/ui/settings_panel.gd", "scripts/ui/touch_layout_panel.gd", "scripts/ui/player_hand.gd", "assets/canteen/box_2.png", "scripts/ui/rollback_confirm.gd", "data/skill_tree.json", "assets/ui/NotoSansSC-VF.ttf", "assets/ui/ZCOOLKuaiLe.ttf"]


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
	Settings.touch_layout = Settings.TOUCH_DEFAULT.duplicate(true)
	Settings.touch_arm_distance = 200.0
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
	Game.seen_buttons = {"intro_think": true, "intro_canteen_started": true, "crew": true, "crew_card": true}
	Game._recompute()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await wait_frames(8)
	await _key(KEY_ENTER)
	_check(_main._screen is TreeScreen, "main title confirmation opens the production tree")
	if not _main._screen is TreeScreen:
		await _finish(player_save, player_settings)
		return
	await _mobile_preferences(_main._screen)
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
	_check(ui.joystick.get_global_rect().position.is_equal_approx(Settings.touch_rect("joystick").position) and is_equal_approx(ui.joystick.scale.x, Settings.touch_layout.joystick.scale) and is_equal_approx(ui.deliver_button.scale.x, Settings.touch_layout.interact.scale) and is_equal_approx(ui.think_button.scale.x, Settings.touch_layout.think.scale) and ui.deliver_button.scale.x > 1.0, "saved custom layout is applied to live gameplay controls")
	_check(Settings.touch_arm_distance > 200, "custom arm reach is loaded for gameplay")
	Settings.touch_layout = Settings.TOUCH_DEFAULT.duplicate(true)
	Settings.touch_arm_distance = 200.0
	Settings.save_settings()
	Settings.changed.emit()
	await wait_frames()
	_check(is_instance_valid(ui) and run._learning(), "meal mounts touch controls and existing tutorial")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	_check(run._hand != null and run._coach.step == RunCoach.Step.CATCH, "touch pickup GUI takes one real box and advances tutorial")
	if run._hand == null:
		return
	_check(run._coach._device == "touch", "tutorial describes the actual touch device")
	_check(ui.joystick is VirtualJoystick, "engine joystick drives the shared gamepad actions")
	await shot("run_touch_lesson")
	await _hand_route(run)
	var empty_before := run._empty
	var initial: Vector2 = run._hand.pos
	var dock: Vector2 = run._coach.position
	var center: Vector2 = ui.joystick.get_global_rect().get_center()
	_check(not ui.joystick.get_global_rect().intersects(run._coach.get_global_rect()) and not ui.think_button.get_global_rect().intersects(run._coach.get_global_rect()), "fixed lesson leaves both thumbs clear")
	_check(ui.deliver_button.size.x * ui.deliver_button.size.y > ui.think_button.size.x * ui.think_button.size.y, "primary action is larger than held secondary action")
	await _touch(0, center, true)
	await _drag(0, center, center + Vector2(3, 0))
	await _wait(0.12)
	_check(run._hand.pos.distance_to(initial) < 1, "stick dead zone ignores small resting-thumb motion")
	await _touch(0, center, false)
	await _steer_to(run, Vector2(800, 700))
	await _wait(0.3) # Existing gamepad hand physics settle toward the last aim.
	var stopped: Vector2 = run._hand.pos
	await _wait(0.15)
	_check(run._hand.pos.distance_to(stopped) < 1 and run._empty == empty_before, "releasing stick stops movement without returning or serving")
	var fake_motion := InputEventMouseMotion.new()
	fake_motion.device = InputEvent.DEVICE_ID_EMULATION
	fake_motion.position = Vector2(1400, 500)
	fake_motion.relative = Vector2(600, -200)
	get_viewport().push_input(fake_motion, true)
	await wait_frames()
	await _emulated_mouse(Vector2(1385, 865))
	_check(run._hand != null and run._hand.pos.distance_to(stopped) < 1, "synthetic mouse cannot move or deliver a touch-held box")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	_check(run._hand != null and run._hand.pos.distance_to(stopped) < 1, "unavailable primary action cannot remotely serve or steal steering")
	run._add_item(run._hand.pos + Vector2(0, -8), Vector2(0, 140), CanteenRun.I.BALL)
	await _wait(0.18)
	_check(run.caught > 0 and run._coach.step == RunCoach.Step.SERVE, "real food collision advances touch lesson")
	await _steer_to(run, Vector2(1385, 820))
	_check(run._hand != null and run._coach.position == dock, "lesson remains at bottom while tray returns to table")
	await shot("run_touch_serve")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	_check(run._hand == null and not run._learning(), "same primary button serves and completes the tutorial")
	_check(run._coach.position == dock, "completion message uses the same bottom dock")
	await _touch_tap(ui.deliver_button.get_global_rect().get_center())
	await _steer_to(run, Vector2(800, 700))
	await _touch(0, center, true)
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _wait(0.10)
	_check(run._thinking and ui.think_held, "second finger holds thought while first finger owns stick")
	var before: Vector2 = run._hand.pos
	await _drag(0, center, center + Vector2(76, 0))
	await _wait(0.12)
	_check(run._thinking and run._hand.pos.x > before.x + 80, "multitouch stick movement and thought coexist")
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	await _touch(0, center + Vector2(76, 0), false)
	_check(not run._thinking and not ui.think_held, "releasing secondary button stops thought")
	await _touch(0, center, true)
	await _drag(0, center, center + Vector2(-76, 0))
	var owned_value: Vector2 = _movement()
	await _touch(1, center, true)
	await _drag(1, center, center + Vector2(76, 0))
	await _touch(1, center + Vector2(76, 0), false)
	_check(_movement() == owned_value, "second finger cannot steal or release the stick")
	await _touch(0, center, false, true)
	_check(_movement() == Vector2.ZERO, "canceled contact releases steering")
	await _touch(0, center, true)
	await _drag(0, center, Vector2(1100, 500))
	await _touch(0, Vector2(1100, 500), false)
	_check(_movement() == Vector2.ZERO, "release outside the stick and over gameplay cannot leave movement stuck")
	await _wait(1.15)
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _wait(0.08)
	await _drag(1, ui.think_button.get_global_rect().get_center(), Vector2(1000, 850))
	_check(not run._thinking and not ui.think_held, "dragging thought finger off button cancels held action")
	await _touch(1, Vector2(1000, 850), false)
	await _wait(1.15)
	await _touch(0, center, true)
	await _drag(0, center, center + Vector2(-76, 0))
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _wait(0.08)
	await _touch_tap(ui.pause_button.get_global_rect().get_center(), 2)
	_check(get_tree().paused and is_instance_valid(run._pause), "pause touch GUI freezes gameplay through production pause")
	_check(not ui.think_held and not run._thinking and _movement() == Vector2.ZERO, "pause releases thought and steering fingers")
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	await _touch(0, center, false)
	await _touch_tap(run._pause._first.get_global_rect().get_center())
	await _wait(0.25)
	_check(not get_tree().paused and not run._thinking and _movement() == Vector2.ZERO, "touch resume cannot resurrect held controls")
	Settings.pause_unfocused = false
	await _wait(1.05)
	await _touch(0, center, true)
	await _drag(0, center, center + Vector2(-76, 0))
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_frames()
	_check(not ui.think_held and not run._thinking and _movement() == Vector2.ZERO, "focus loss clears both held controls even when auto-pause is disabled")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _drag(0, center, center + Vector2(76, 0))
	_check(_movement() == Vector2.ZERO, "old finger cannot restart joystick after focus returns")
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	await _touch(0, center, false)
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


func _movement() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _hand_route(run: CanteenRun) -> void:
	var ui = run._touch_controls
	var at := Vector2(1040, 850)
	await _touch(0, at, true)
	_check(run._touch_finger == 0 and run._hand.pos.distance_to(at - Vector2(200, 200)) < 1, "touch holds the tray 200 design pixels above-left")
	await _drag(0, at, Vector2(1120, 900))
	at = Vector2(1120, 900)
	_check(run._hand.pos.distance_to(at - Vector2(200, 200)) < 1 and run._touch_hand_visible, "drag moves the arm and held tray together")
	await _touch(2, Vector2(600, 700), true)
	await _drag(2, Vector2(600, 700), Vector2(500, 700))
	await _touch(2, Vector2(500, 700), false)
	_check(run._touch_finger == 0 and run._hand.pos.distance_to(at - Vector2(200, 200)) < 1, "another playfield finger cannot steal the holding hand")
	await _touch(1, ui.think_button.get_global_rect().get_center(), true)
	await _drag(0, at, Vector2(1160, 900))
	at = Vector2(1160, 900)
	_check(run._thinking and run._touch_finger == 0 and run._hand.pos.distance_to(at - Vector2(200, 200)) < 1, "hand dragging and second-finger thinking coexist")
	await _touch(1, ui.think_button.get_global_rect().get_center(), false)
	run._add_item(run._hand.pos + Vector2(0, -8), Vector2(0, 140), CanteenRun.I.BALL) # visible-food fixture
	await _wait(0.18)
	await shot("player_hand_food")
	await _drag(0, at, Vector2(20, 780))
	var art: Rect2 = run._basin_art_rect(run._hand.pos, 1.0)
	_check(art.position.x >= 15 and art.end.x <= 1905, "touch near left edge keeps the full tray visible")
	await _drag(0, Vector2(20, 780), ui.deliver_button.get_global_rect().get_center())
	await _touch(0, ui.deliver_button.get_global_rect().get_center(), false)
	_check(run._hand != null and run._touch_finger < 0, "dragging across and releasing over Interact cannot serve")
	var stopped: Vector2 = run._hand.pos
	await _wait(0.15)
	_check(run._hand.pos.distance_to(stopped) < 1, "lifting the hand leaves the tray still held at its last position")
	Settings.touch_arm_distance = 300
	await _touch(0, Vector2(1150, 900), true)
	_check(run._hand.pos.distance_to(Vector2(850, 600)) < 1, "configured arm reach changes the actual touch offset")
	await _touch(0, Vector2(1150, 900), false, true)
	await _drag(0, Vector2(1150, 900), Vector2(1300, 900))
	_check(run._touch_finger < 0 and run._hand.pos.distance_to(Vector2(850, 600)) < 1, "canceled hand contact cannot resume on a stale drag")
	Settings.touch_arm_distance = 360
	await _touch(0, Vector2(1100, 850), true)
	await _drag(0, Vector2(1100, 850), Vector2(1780, 1064))
	_check(run.TABLE.grow(60).has_point(run._hand.pos), "longest arm retracts near the bottom edge so the table remains reachable")
	await _touch(0, Vector2(1780, 1064), false)
	Settings.touch_arm_distance = 200
	await _touch(0, Vector2(1100, 850), true)
	await _touch_tap(ui.pause_button.get_global_rect().get_center(), 1)
	_check(get_tree().paused and run._touch_finger < 0, "pause clears an active holding finger")
	await _touch(0, Vector2(1100, 850), false)
	await _touch_tap(run._pause._first.get_global_rect().get_center())
	await _wait(0.25)
	await _touch(0, Vector2(1100, 850), true)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	stopped = run._hand.pos
	await _drag(0, Vector2(1100, 850), Vector2(1250, 900))
	_check(run._touch_finger < 0 and run._hand.pos.distance_to(stopped) < 1, "focus loss cancels the hand and rejects stale movement")
	await _touch(0, Vector2(1250, 900), false)
	await _touch(0, Vector2(1000, 900), true)
	await _touch(0, Vector2(1000, 900), false)


func _steer_to(run: CanteenRun, target: Vector2) -> void:
	# A bounded feedback driver operates only real joystick touch events; no position assignment.
	var center: Vector2 = run._touch_controls.joystick.get_global_rect().get_center()
	await _touch(0, center, true)
	var at := center
	for i in 180:
		var remaining: Vector2 = target - run._aim
		if remaining.length() < 8:
			break
		var amount := minf(remaining.length() / 180.0, 1.0)
		var next := center + remaining.normalized() * (0.25 + amount * 0.75) * 76
		await _drag(0, at, next)
		at = next
	await _touch(0, at, false)
	await _wait(0.3)
	_check(run._hand.pos.distance_to(target) < 12, "joystick reaches gameplay target " + str(target))


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


func _mobile_preferences(tree: TreeScreen) -> void:
	# Exactly five tokens and only the root are an explicit affordability fixture.
	var old_levels := Game.levels.duplicate(true)
	var old_tokens := Game.tokens
	Game.levels = {"start": 1}
	Game.tokens = 5
	Game._recompute()
	Game.changed.emit()
	await wait_frames()
	_check(Game.cost("skills") == 5 and Game.is_visible("skills"), "automation costs five tokens and is available from the root")
	await _touch_tap(tree._at(Game.node("skills")))
	await _touch_tap(tree._touch_buy.get_global_rect().get_center())
	_check(Game.level("skills") == 1 and Game.tokens == 0 and Game.automation_enabled("auto_push") and Game.automation_enabled("auto_return"), "five-token player can buy the real automation node through touch GUI")
	await _mouse_click(tree._bar.get_node("Tree_respec").get_global_rect().get_center())
	var dialog = tree._rollback
	_check(is_instance_valid(dialog), "rollback click opens a confirmation dialog")
	if is_instance_valid(dialog):
		var at: Vector2 = dialog.hold_button.get_global_rect().get_center()
		await _touch_tap(at)
		await _touch_tap(at)
		_check(Game.level("skills") == 1 and Game.tokens == 0, "repeated quick taps cannot refund skills")
		await _touch(0, at, true)
		await _wait(2.4)
		_check(Game.level("skills") == 1, "holding less than three seconds never refunds")
		await shot("rollback_hold")
		await _touch(0, at, false)
		await _touch(0, at, true)
		await _wait(0.8)
		await _touch(0, at, false)
		_check(Game.level("skills") == 1, "separate holds do not accumulate")
		await _touch(0, at, true)
		await _drag(0, at, Vector2(200, 200))
		await _wait(3.1)
		_check(Game.level("skills") == 1, "moving off the confirmation button cancels the hold")
		await _touch(0, Vector2(200, 200), false)
		await _touch(0, at, true)
		get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _wait(3.1)
		get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		await _touch(0, at, false)
		_check(Game.level("skills") == 1, "focus loss cancels rollback hold")
		await _touch(0, at, true)
		await _wait(3.15)
		await _touch(0, at, false)
		_check(Game.level("skills") == 0 and Game.tokens == 5 and not is_instance_valid(tree._rollback), "one continuous hold refunds exactly once and closes dialog")
	Game.levels = old_levels
	Game.tokens = old_tokens
	Game._recompute()
	Game.changed.emit()
	await wait_frames()
	await _mouse_click(tree._bar.get_node("Tree_settings").get_global_rect().get_center())
	var panel = tree.get_children().filter(func(c): return c is SettingsPanel)[0]
	await _mouse_click(panel._tabs[3].get_global_rect().get_center())
	var entry = panel._controls.filter(func(c): return c.get_meta("focus_key", "") == "touch_layout")[0]
	await _mouse_click(entry.get_global_rect().get_center())
	var editor = panel._remap
	var targets := {"joystick": Vector2(190, 920), "interact": Vector2(1760, 920), "think": Vector2(1510, 920)}
	for id in targets:
		var at: Vector2 = Settings.touch_rect(id, editor.draft).get_center()
		await _touch(0, at, true)
		await _drag(0, at, targets[id])
		await _touch(0, targets[id], false)
		_check(Settings.touch_rect(id, editor.draft).get_center().distance_to(targets[id]) < 1, "drag repositions layout preview: " + id)
	for i in 3:
		await _mouse_click(editor._buttons[i].get_global_rect().get_center())
		var slider: Rect2 = editor._size_slider.get_global_rect()
		await _mouse_click(slider.position + Vector2(slider.size.x * [0.55, 0.65, 0.25][i], slider.size.y * 0.5))
	_check(editor.draft.interact.scale > 1.0 and editor.draft.joystick.scale > 1.0 and editor.draft.think.scale < 1.0 and Settings.touch_layout.interact.scale == 1.0, "all three size previews change independently without saving")
	var arm_slider: Rect2 = editor._arm_slider.get_global_rect()
	await _mouse_click(arm_slider.position + Vector2(arm_slider.size.x * 0.78, arm_slider.size.y * 0.5))
	_check(editor._arm_distance > 200 and Settings.touch_arm_distance == 200, "arm reach slider previews without saving")
	await _wait(5.0) # Let the fixture's achievement toast leave the preview.
	await shot("touch_layout_editor")
	await _mouse_click(editor._buttons[-1].get_global_rect().get_center())
	var saved := Settings.touch_layout.duplicate(true)
	var saved_reach := Settings.touch_arm_distance
	Settings.touch_layout = Settings.TOUCH_DEFAULT.duplicate(true)
	Settings.touch_arm_distance = 200.0
	Settings.load_settings()
	_check(Settings.touch_layout == saved and saved.interact.scale > 1.0, "saved layout round-trips through the isolated settings file")
	_check(Settings.touch_arm_distance == saved_reach and saved_reach > 200, "arm reach round-trips through isolated settings")
	await _mouse_click(entry.get_global_rect().get_center())
	editor = panel._remap
	await _mouse_click(editor._buttons[3].get_global_rect().get_center())
	_check(editor.draft == Settings.TOUCH_DEFAULT, "restore defaults resets the draft layout")
	await _mouse_click(editor._buttons[4].get_global_rect().get_center())
	_check(Settings.touch_layout == saved, "cancel leaves saved layout unchanged")
	_check(Settings.touch_arm_distance == saved_reach, "cancel also preserves saved arm reach")
	_check(Settings.sanitize_arm_distance(INF) == 200 and Settings.sanitize_arm_distance("bad") == 200 and Settings.sanitize_arm_distance(-20) == 80 and Settings.sanitize_arm_distance(500) == 360, "invalid reach settings fall back or stay in range")
	await _mouse_click(panel._back.get_global_rect().get_center())
	tree._hover = ""
	var bad := Settings.sanitize_touch_layout({"joystick": {"x": -10, "y": INF, "scale": 99}, "interact": "bad"})
	_check(Rect2(0, 0, 1920, 1080).encloses(Settings.touch_rect("joystick", bad)) and bad.interact == Settings.TOUCH_DEFAULT.interact, "malformed layouts cannot put controls off screen")
