extends Node
## Deterministic focus notification fixtures + real GUI input; not a native OS-popup test.

var failures := 0
var run: CanteenRun
var shots := ""

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1

func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func capture(name: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Game.save_path.contains("qa_") or not Settings._testing:
		push_error("Focus tests require an isolated profile")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			shots = arg.trim_prefix("--out=")
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shots)
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Settings.pause_unfocused = false
	Game.runs = 1
	run = CanteenRun.new()
	add_child(run)
	await frames(5)
	Settings.pause_unfocused = true
	Settings.hit_pause = true
	Engine.time_scale = 1.0
	Input.action_press("think")
	Input.action_press("move_right")
	Fx.hitstop(2.0)
	Settings._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	run._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames()
	check(get_tree().paused and is_instance_valid(run._pause), "lost focus opens a visible pause menu")
	check(run._pause.can_process() and not run.can_process(), "pause UI processes while gameplay is frozen")
	check(not Input.is_action_pressed("think") and not Input.is_action_pressed("move_right"), "focus loss clears held gameplay actions")
	check(is_equal_approx(Engine.time_scale, 1.0), "focus loss restores hit-stop speed immediately")
	var time_before := run._t
	for i in 8:
		Settings._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		run._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(5)
	check(run.get_children().filter(func(c): return c is PauseMenu).size() == 1, "repeated focus loss never stacks pauses")
	check(is_equal_approx(time_before, run._t), "paused frames do not spend meal time")
	Settings._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await frames()
	check(get_tree().paused, "returning to the app waits for explicit resume")
	check(get_viewport().gui_get_focus_owner() == run._pause._first, "resume button regains keyboard focus")
	await capture("focus_pause")
	run._pause._open_settings()
	run._pause._open_settings()
	await frames()
	check(run._pause.get_children().filter(func(c): return c is SettingsPanel).size() == 1, "pause settings opens only once")
	await key(KEY_ESCAPE)
	check(get_tree().paused and is_instance_valid(run._pause), "closing settings leaves the shift paused")
	run._pause._open_book()
	await frames()
	var book: RecipeBook = run._pause._book
	book._page = "rules"
	book._fill()
	await frames()
	check(book._cards.size() == 10, "in-game handbook includes ten explained mechanics")
	await capture("handbook_top")
	book._cards.back().grab_focus()
	await frames(10)
	check(book._scroll.scroll_vertical > 0, "keyboard focus scrolls to the last handbook card")
	await capture("handbook_bottom")
	await key(KEY_ESCAPE)
	check(get_tree().paused and not is_instance_valid(run._pause._book), "closing handbook returns to paused parent")
	run._pause._first.grab_focus()
	await key(KEY_ENTER)
	await frames(12)
	check(not get_tree().paused and not is_instance_valid(run._pause), "confirm resumes and removes pause UI")
	check(run._t > time_before, "gameplay clock advances after resume")
	check(not run._thinking, "resume confirmation does not trigger thinking")
	Settings.pause_unfocused = false
	run._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames()
	check(not get_tree().paused, "pause-on-focus-loss option can be disabled")
	run.pause()
	await frames()
	run.queue_free()
	await frames()
	check(not get_tree().paused, "removing a paused screen cannot strand global pause")
	Audio._exit_tree()
	await get_tree().create_timer(0.12, true, false, true).timeout
	UiKit.clear_cache()
	print("FOCUS_RECOVERY_TEST failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
