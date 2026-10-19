extends Node
## Isolated input + collision integration checks; no bot and no player save/settings writes.
## Godot --headless --path game res://tests/onboarding_test.tscn -- --test-profile=onboarding
## Food placement and table positioning are explicit fixtures; input goes through the viewport.

const RUN = preload("res://scripts/run/canteen_run.gd")
const COACH = preload("res://scripts/ui/run_coach.gd")
var failures: Array[String] = []


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("ONBOARDING: " + message)


func _wait(seconds := 0.06) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _wait()


func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _wait()


func _mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = Vector2(20, 20)
	Input.parse_input_event(motion)
	await _wait(0.6)   # the physical box has to reach the pointer before delivery
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _wait()


func _fresh() -> Node2D:
	Game.reset_save()
	var run := RUN.new()
	add_child(run)
	run._arms.clear()   # deterministic fixture: all tested food uses real falling collision
	await _wait()
	return run


func _fall_into_hand(run: Node2D) -> void:
	run._aim = Vector2(800, 700)
	run._hand.pos = run._aim
	run._hand.vel = Vector2.ZERO
	run._hand.slosh = 0.0
	run._add_item(run._hand.pos + Vector2(0, -3), Vector2(0, 100), RUN.I.BALL)
	await _wait(0.1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not "--test-profile=onboarding" in OS.get_cmdline_user_args() or Game.save_path != "user://qa_onboarding.json":
		push_error("Refusing onboarding test outside its isolated profile")
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(1920, 1080)
	get_tree().root.theme = UiKit.build_theme()
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	var run: Node2D = await _fresh()
	_check(run._learning(), "fresh save starts lesson")
	_check(is_zero_approx(run._meal_elapsed()), "clock waits before pickup")
	run._process(run.meal_time + 5.0)   # explicit elapsed-time fixture, no clock pressure
	_check(not run._ended and is_zero_approx(run._meal_elapsed()), "lesson can last longer than a complete timed meal")
	await _key(KEY_E)
	_check(run._hand != null and run._coach.step == COACH.Step.CATCH, "keyboard picks up box")
	await _key(KEY_E)
	_check(run._hand == null and run._coach.step == COACH.Step.TAKE, "returning empty box restores pickup step")
	await _pad(JOY_BUTTON_A)
	_check(run._hand != null and run._coach._device == "pad", "gamepad picks up box and changes prompts")
	await _key(KEY_ESCAPE)
	_check(get_tree().paused, "Escape opens a real pause")
	var paused_time: float = run._t
	await _key(KEY_T)
	_check(run._learning() and is_equal_approx(run._t, paused_time), "paused shortcut cannot skip or advance world")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused and run._learning(), "pause resumes lesson")
	var before_move: float = run._aim.x
	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	left.physical_keycode = KEY_LEFT
	left.pressed = true
	Input.parse_input_event(left)
	await _wait(0.08)
	left = left.duplicate()
	left.pressed = false
	Input.parse_input_event(left)
	_check(run._aim.x < before_move, "keyboard movement drives box target")
	before_move = run._aim.x
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = -0.8
	Input.parse_input_event(axis)
	await _wait(0.08)
	axis = axis.duplicate()
	axis.axis_value = 0.0
	Input.parse_input_event(axis)
	_check(run._aim.x < before_move, "gamepad left stick drives box target")
	await _fall_into_hand(run)
	_check(run.caught == 1 and run._coach.step == COACH.Step.SERVE, "real falling collision advances catch step")
	run._hand.items.clear()   # explicit fixture for all food spilled / removed before serving
	await _wait()
	_check(run._coach.step == COACH.Step.CATCH, "empty hand contents restore catch instruction")
	await _fall_into_hand(run)
	_check(is_zero_approx(run._meal_elapsed()), "catching still does not start clock")
	run._hand.pos = Vector2(RUN.STACK_AT.x, RUN.BAND.y)
	run._hand.vel = Vector2.ZERO
	run._aim = run._hand.pos
	await _pad(JOY_BUTTON_A)
	_check(not run._learning() and run._hand == null, "gamepad delivery completes lesson")
	_check(run._meal_elapsed() > 0.0, "clock starts after first real delivery")
	_check(Game.seen_buttons.has("intro_canteen_complete"), "completion is persisted")
	Game.load_game()
	_check(Game.seen_buttons.has("intro_canteen_complete"), "completion survives save reload")
	# Full-box accounting uses player submissions only and is idempotent.
	var full: Dictionary = run._new_basin(Vector2.ZERO)
	full.items = [RUN.I.BALL, RUN.I.BALL, RUN.I.BALL, RUN.I.BALL]
	full["full"] = true
	run._note_served(full)
	run._note_served(full)
	var crew: Dictionary = full.duplicate(true)
	crew.erase("run_counted")
	crew["crew"] = true
	run._note_served(crew)
	var takeout: Dictionary = full.duplicate(true)
	takeout.erase("run_counted")
	takeout["takeout"] = true
	run._note_served(takeout)
	_check(run._full_boxes == 1, "only genuine player full boxes counted once")
	run._end("提前下班", false)
	_check(Game.runs == 1, "settlement records one run")
	run.queue_free()
	await _wait()
	# Leaving before delivery must offer the lesson again despite incrementing runs.
	run = await _fresh()
	run._end("提前下班", false)
	run.queue_free()
	await _wait()
	run = RUN.new()
	add_child(run)
	await _wait()
	_check(run._learning(), "interrupted first meal offers lesson again")
	await _key(KEY_T)
	_check(not run._learning() and Game.seen_buttons.has("intro_canteen_complete"), "T skips and persists")
	run.queue_free()
	await _wait()
	# Mouse movement / pickup / delivery also traverse the native viewport event path.
	run = await _fresh()
	await _mouse(RUN.STACK_AT)
	_check(run._hand != null and run._coach.step == COACH.Step.CATCH, "mouse picks up box")
	await _fall_into_hand(run)
	await _mouse(RUN.STACK_AT)
	_check(not run._learning() and run._hand == null, "mouse moves box to table and serves")
	run.queue_free()
	await _wait()
	# The mouse button must receive GUI events without stealing gameplay keyboard focus.
	run = await _fresh()
	var skip_at: Vector2 = run._coach._skip.global_position + run._coach._skip.size * 0.5
	await _mouse(skip_at)
	_check(not run._learning(), "mouse skip button uses real GUI path")
	run.queue_free()
	await _wait()
	run = await _fresh()
	await _pad(JOY_BUTTON_BACK)
	_check(not run._learning(), "View / Back skips")
	run.queue_free()
	await _wait()
	Game.reset_save()
	Game.runs = 3
	Game.save_game()
	run = RUN.new()
	add_child(run)
	await _wait()
	_check(run._coach == null and run._meal_elapsed() > 0.0, "existing players start normal timed meal")
	run.queue_free()
	await _wait()
	print("ONBOARDING_RESULT ", JSON.stringify({"ok": failures.is_empty(), "failures": failures,
		"profile": Game.save_path, "input": ["keyboard", "gamepad", "mouse"],
		"fixture": "falling food and table positioning; no bot; viewport input events"}))
	await get_tree().create_timer(0.12, true, false, true).timeout
	Audio._exit_tree()
	await get_tree().create_timer(0.12, true, false, true).timeout
	UiKit.clear_cache()
	get_tree().quit(0 if failures.is_empty() else 1)
