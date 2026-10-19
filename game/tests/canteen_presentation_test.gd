extends Node
## Fixed states plus actual GUI input; screenshots are native-size evidence, not balance tests.
var failures: Array[String] = []
var checks := 0
var out := ""
var window := Vector2i(1280, 720)
var run: CanteenRun


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame


func key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await frames()


func click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		get_viewport().push_input(e, true)
		await frames()


func shot(id: String) -> void:
	run.queue_redraw()
	run._front.queue_redraw()
	await frames()
	if DisplayServer.get_name() == "headless" or out == "": return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	check(img.get_size() == window, "native dimensions " + id)
	img.save_png(out.path_join(id + ".png"))


func labels(node: Node) -> void:
	if node is TextureRect:
		check(node.size == Vector2(90, 90), "dish art keeps its authored icon bounds")
	if node is Label:
		check(node.get_line_count() * node.get_line_height() <= node.size.y + 4, "label height: " + node.text)
		check(Rect2(0, 0, 1920, 1080).encloses(node.get_global_rect()), "label viewport: " + node.text)
	for child in node.get_children(): labels(child)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Game.save_path.begins_with("user://qa_canteen_presentation"):
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg == "--small": window = Vector2i(960, 540)
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	Settings.window_size = window
	Settings.fullscreen = false
	Settings.pause_unfocused = false
	Settings.reduced_motion = true
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Game.reset_save()
	Game.runs = 20
	Game.seen_buttons = {"intro_canteen_complete": true, "intro_warm": true, "intro_grok": true, "intro_think": true}
	run = CanteenRun.new()
	add_child(run)
	run.set_process(false)
	run._bark_t = 0
	run._abark_t = 0
	await shot("early_shift")
	var hud = run._service_ui
	check(hud._clock_text(59.9) == "01:00" and hud._clock_text(59.0) == "00:59", "countdown remains continuous across minute boundary")
	for i in 5:
		check(not hud.stall_rect(i).intersects(Rect2(610, 26, 270, 270)), "stall clear of cook %d" % i)
		if i > 0: check(not hud.stall_rect(i).intersects(hud.stall_rect(i - 1)), "adjacent stall signs do not overlap")
	# Supply all stalls and all passive effects to exercise the densest legitimate HUD.
	for id in run.STALLS: run.stall_lv[id] = int(run.STALLS[id].max)
	run.tentacles = 8
	run._setup_arms()
	run.can_think = true
	run._think = run.think_time
	run.stream = 1
	run.crave = 1
	run.combo = 0.2
	run.grok = true
	run.critic = 0.2
	run.cache_bonus = 0.25
	run._cache_ready = true
	run._shown = 999999999
	run._banners.clear()
	await shot("late_shift")
	for r in hud.text_bounds:
		check(Rect2(0, 0, 1920, 1080).encloses(r), "bounded HUD text")
	run._set_thinking(true)
	await shot("thinking")
	# Tab opens once and the world remains frozen until an intentional close.
	await key(KEY_TAB)
	check(get_tree().paused and is_instance_valid(hud._modal), "Tab opens paused service guide")
	check(not run._thinking and not Audio._slow, "guide interrupts thinking and sound")
	var original = hud._modal
	hud.open_guide()
	check(hud._modal == original, "service guide singleton")
	var time_before: float = run._t
	for i in 5:
		await click(hud._tabs[i].get_global_rect().get_center())
		check(hud._selected == i, "mouse selects stall %d" % i)
		labels(hud._body)
		await shot("guide_%d" % i)
	check(is_equal_approx(run._t, time_before), "guide freezes meal timer")
	Settings.pause_unfocused = true
	run._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not is_instance_valid(run._pause), "focus loss does not stack a pause menu over guide")
	await key(KEY_ESCAPE)
	check(not get_tree().paused and not is_instance_valid(hud._modal), "Escape resumes service")
	check(run._resume_input_guard > 0, "resume prevents held-input actions")
	await click(hud._info.get_global_rect().get_center())
	check(get_tree().paused, "mouse opens stall guide")
	await key(KEY_ESCAPE)
	check(get_viewport().gui_get_focus_owner() != hud._info, "closing mouse-opened guide cannot steal deliver focus")
	run._resume_input_guard = 0
	run._aim = run.STACK_AT
	await key(KEY_ENTER)
	check(not get_tree().paused and run._hand != null, "Enter still takes a box after reading the guide")
	await key(KEY_TAB)
	check(get_tree().paused, "Tab reopens guide after mouse use")
	await key(KEY_ESCAPE)
	run._think_cooldown = 0.7
	await shot("cooldown")
	run._hand = run._new_basin(Vector2(800, 550))
	run._hand.items = [run.make(run.I.BALL, 2)]
	run._banner("深度思考", tr("按住空格或右键，时间变慢"), "clock")
	check(run._front.z_index < run.z_index, "notice layer remains behind all food and the hand")
	await shot("announcement_behind_box")
	run._checkout = true
	await frames()
	check(not hud.visible, "ledger hidden during checkout")
	run.queue_free()
	await frames()
	Audio._exit_tree()
	await get_tree().create_timer(0.15, true, false, true).timeout
	UiKit.clear_cache()
	var report := {"checks": checks, "failures": failures, "language": Settings.language, "window": str(window), "scope": "fixed early/late states and real keyboard/mouse modal input", "source_sha256": {}}
	for file in ["scripts/ui/canteen_overlay.gd", "scripts/run/canteen_run.gd", "tests/canteen_presentation_test.gd"]:
		report.source_sha256[file] = FileAccess.get_sha256("res://" + file)
	if out != "":
		FileAccess.open(out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("CANTEEN_PRESENTATION_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
