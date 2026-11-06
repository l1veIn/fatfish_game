extends Node
## Deterministic visual fixtures, NOT a legal progression path or completed meal.
## GPU owner runs this serially; --headless --short only validates fixture/input wiring.
## --test-profile=canteen_visual_zh --lang=zh_CN --out=<absolute directory> [--short]

const RUN = preload("res://scripts/run/canteen_run.gd")
const FIXTURE_SEED := 20261019
const SOURCES := ["project.godot", "scripts/run/canteen_run.gd", "scripts/run/meal_rules.gd",
	"scripts/autoload/game.gd", "scripts/autoload/settings.gd", "scripts/autoload/audio.gd",
	"scripts/autoload/fx.gd", "tests/canteen_visual_test.gd", "data/menu.json", "data/i18n/en.json"]

var run: Node2D
var output := ""
var hold_seconds := 15.0
var failures: Array[String] = []
var checks := 0
var report: Dictionary = {}
var hold_start := 0
var recording := false
var sample_at := 0.0
var samples: Array = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("CANTEEN_VISUAL: " + label)


func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func wait_real(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds, true, false, true).timeout


func _process(_delta: float) -> void:
	if recording and is_instance_valid(run):
		var elapsed := (Time.get_ticks_msec() - hold_start) / 1000.0
		if elapsed >= sample_at:
			samples.append({"real_seconds": elapsed, "pressed": Input.is_action_pressed("think"),
				"thinking": run._thinking, "charge": run._think, "cooldown": run._think_cooldown,
				"transitions": run._think_transitions})
			sample_at += 0.25


func key_down(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)


func box(items: Array, at := Vector2(810, 675)) -> Dictionary:
	var b: Dictionary = run._new_basin(at)
	b.items = items.duplicate()
	b["previous_pos"] = at
	return b


func redraw() -> void:
	run.queue_redraw()
	run._front.queue_redraw()
	run._back.queue_redraw()
	run._crew_layer.queue_redraw()


func clear_stage() -> void:
	run.set_process(false)
	run._hand = null
	run._eating = null
	run._queue.clear()
	run._flying.clear()
	run._texts.clear()
	run._banners.clear()
	run._chips.clear()
	run._flash.clear()
	run._bark_t = 0.0
	run._abark_t = 0.0
	while not run._fp.is_empty():
		run._remove_item(0)
	run._t = 12.0
	run._wait = -100.0
	run._fish.play("basin", true)
	redraw()


func shot(name: String, purpose: String) -> void:
	redraw()
	await frames(4)
	var entry := {"name": name, "purpose": purpose, "captured": false,
		"reduced_motion": Settings.reduced_motion, "thinking": run._thinking,
		"think_charge": run._think, "think_cooldown": run._think_cooldown,
		"think_hint": run._think_hint(), "cache_ready": run._cache_ready,
		"previous_mono_kind": run._previous_mono_kind, "chain": run._combo_n}
	if run._hand != null:
		entry["hand_rule_preview"] = run._plan_box(run._hand)
	if DisplayServer.get_name() != "headless" and not output.is_empty():
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		entry["width"] = pixels.get_width()
		entry["height"] = pixels.get_height()
		check(pixels.get_size() == Vector2i(1280, 720), "native capture is 1280x720: " + name)
		var path := output.path_join(name + ".png")
		var err := pixels.save_png(path)
		check(err == OK, "screenshot saved: " + name)
		entry["captured"] = err == OK
		entry["path"] = path
		entry["sha256"] = FileAccess.get_sha256(path)
	report.shots.append(entry)
	print("CANTEEN_VISUAL_SHOT ", name, " captured=", entry.captured)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Game.save_path.begins_with("user://qa_canteen_visual") or not Settings._testing:
		push_error("Visual fixtures require --test-profile=canteen_visual[_suffix]")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg == "--short":
			hold_seconds = 3.0
	if not output.is_empty():
		check(DirAccess.make_dir_recursive_absolute(output) == OK, "output directory available")
	seed(FIXTURE_SEED)
	Game.reset_save()
	Game.version = Game.VERSIONS.size() - 1
	Game.runs = 1
	Game.seen_buttons = {"intro_canteen_complete": true, "intro_think": true, "intro_warm": true, "intro_grok": true}
	Settings.pause_unfocused = false
	Settings.mute_unfocused = false
	Settings.hit_pause = false
	Settings.reduced_motion = false
	Settings.fullscreen = false
	Settings.window_size = Vector2i(1280, 720)
	Settings.apply()
	get_window().title = "Canteen visual fixtures - " + Settings.language
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	report = {"scope": "Explicit state fixtures plus actual Space key events; not legitimate progression, a completed meal, or a physical keyboard/controller test",
		"engine": Engine.get_version_info().string, "renderer": DisplayServer.get_name(),
		"language": Settings.language, "seed": FIXTURE_SEED, "profile": Game.save_path,
		"command_line": OS.get_cmdline_args(), "source_sha256": {}, "shots": [],
		"held_input_requested_seconds": hold_seconds, "full_15_second_hold": hold_seconds >= 15.0}
	for path in SOURCES:
		report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	run = RUN.new()
	add_child(run)
	run.set_process(false)
	run.box_n = 2
	run.mat_level = 3
	run._g = RUN.MATERIALS[3].mult
	run.can_think = true
	run.meal_time = 120.0
	run.stomach = 1000
	run._empty = 1
	run.tentacles = 8
	run.hired.clear()
	run.magnet = 0.0
	for stall in RUN.STALL_ORDER:
		run.stall_lv[stall] = 1
	run._setup_arms()
	for i in run._arms.size():
		run._arms[i].t0 = 10.0
		run._arms[i].t = 2.0 + i * 0.75
	run._update_arm_art()
	await frames(4)
	check(run._arms.size() == 8, "eight independent ladles are visible across five stalls")
	check(is_zero_approx(run._magnet()), "gold material contributes no implicit attraction")
	var grade_items := [RUN.make(RUN.I.BALL, 1), RUN.make(RUN.I.BALL, 2), RUN.make(RUN.I.BALL, 1), RUN.make(RUN.I.BALL, 2)]
	clear_stage()
	run._hand = box(grade_items)
	await shot("01_grade_hand", "Gold lunch box in hand; alternating silver/gold food, normal animation settings")
	Settings.reduced_motion = true
	await shot("02_grade_hand_reduced_motion", "Same food and box with reduced motion; static grade contours must remain visible")
	Settings.reduced_motion = false
	clear_stage()
	run._queue.append(box(grade_items))
	await shot("03_grade_table", "One served box at actual table scale, silver/gold edges remain visible")
	clear_stage()
	run._eating = box(grade_items)
	run._start_box(run._eating)
	run._fish.play("slurp", true)
	await wait_real(0.18)
	await shot("04_grade_eating", "Eating pose with graded food at the actual eating-box scale; contents frozen for inspection")
	clear_stage()
	await shot("05_stall_ladles", "Five open stalls, eight separately numbered progress bars and the per-ladle explanation")
	# Build fixtures call the real serve boundary; box contents are injected, never claimed earned.
	run.mono_bonus = 0.1
	run.cache_bonus = 0.15
	run.rotation_bonus = 0.2
	run.combo = 0.1
	run.memory = 2
	run._combo_safe = true
	var recipe := -1
	for k in RUN.NAMES.size():
		if RUN.IS_SET[k] and RUN.SPACE[k] <= 2:
			recipe = k
			break
	check(recipe >= 0, "fixture has a real recipe leaving at least two empty cells")
	if recipe >= 0:
		run._hand = box([RUN.make(recipe)])
		check(run._plan_box(run._hand).cache_primed, "small real recipe previews cache")
		await shot("06_cache_prime_preview", "A real combo with two or more free cells shows the cache preparation hint")
		run._serve(run._hand)
		run._hand = null
		check(run._cache_ready, "serve boundary actually primes cache")
		await shot("07_cache_ready", "Cache-ready HUD and feedback after the injected recipe box crosses the real serve boundary")
		clear_stage()
		run._hand = box(grade_items)
		var rule: Dictionary = run._plan_box(run._hand)
		check(rule.cache_consumed and float(rule.mono_bonus) > 0, "same-dish full box previews platter plus cache")
		await shot("08_platter_cache_preview", "Full single-dish platter combines its own bonus with one stored cache")
		run._serve(run._hand)
		check(not run._cache_ready, "actual platter submission consumes cache")
		clear_stage()
		run._hand = box([RUN.make(RUN.I.BOWL, 1), RUN.make(RUN.I.BOWL, 2)])
		check(run._plan_box(run._hand).rotation, "second different full platter previews rotation")
		await shot("09_platter_rotation_preview", "A different single-dish full box previews variety bonus and the existing combo count")
	# Real input path: a single physical Space event held over depletion and full recharge.
	clear_stage()
	run.mono_bonus = 0.0
	run.cache_bonus = 0.0
	run.rotation_bonus = 0.0
	run.combo = 0.0
	run.think_time = 0.65
	run._think = 0.65
	run._think_cooldown = 0.0
	run._think_input_held = false
	run._resume_input_guard = 0.0
	run._think_transitions = 0
	run._hand = box([], Vector2(810, 710))
	run._aim = run._hand.pos
	for arm in run._arms:
		arm.t0 = 1000.0
		arm.t = 750.0
	run._add_item(Vector2(640, 485), Vector2(200, 100), RUN.make(RUN.I.BALL, 2))
	run._add_item(Vector2(970, 520), Vector2(-120, 80), RUN.make(RUN.I.BALL, 1))
	run.set_process(true)
	hold_start = Time.get_ticks_msec()
	recording = true
	key_down(true)
	await wait_real(0.18)
	check(run._thinking and Input.is_action_pressed("think"), "real Space press enters deep thought")
	await shot("10_think_active", "Real held input activates thought with the energy gauge and no landing markers")
	# PNG encoding can stall the render thread; engine delta need not track the
	# wall-clock screenshot cost. Observe exhaustion itself with a bounded wait.
	var depletion_deadline := Time.get_ticks_msec() + 3000
	while run._thinking and Time.get_ticks_msec() < depletion_deadline:
		await get_tree().process_frame
	check(not run._thinking and run._think_cooldown > 0.0, "exhaustion enters explicit cooldown while Space remains held")
	await shot("11_think_cooldown", "Explicit cooldown HUD after energy depletion; same Space press remains held")
	await wait_real(maxf(hold_seconds - (Time.get_ticks_msec() - hold_start) / 1000.0, 0.0))
	# SceneTreeTimer can resolve early by one frame; the claim is based on the real monotonic clock.
	while (Time.get_ticks_msec() - hold_start) / 1000.0 < hold_seconds:
		await get_tree().process_frame
	report["held_input_actual_seconds"] = (Time.get_ticks_msec() - hold_start) / 1000.0
	check(not run._thinking and run._think_transitions == 2, "one continuous held press produces exactly one start and one end")
	check(is_equal_approx(run._think, run.think_time), "charge recovers fully without held input restarting thought")
	run.set_process(false)
	await shot("12_think_release_required", "Fully recovered energy still asks for release and repress after the continuous hold")
	recording = false
	key_down(false)
	report["hold_samples"] = samples
	report["thought_transitions"] = run._think_transitions
	await frames(2)
	check(not Input.is_action_pressed("think"), "Space is released after fixture")
	await finish()


func finish() -> void:
	run.queue_free()
	await frames(2)
	await wait_real(0.12)
	Audio._exit_tree()
	await wait_real(0.12)
	UiKit.clear_cache()
	for path in SOURCES:
		check(report.source_sha256[path] == FileAccess.get_sha256("res://" + path), "source remained stable: " + path)
	report["ok"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("canteen_visual_report.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
		else:
			check(false, "report file could be written")
	print("CANTEEN_VISUAL_RESULT ", JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures,
		"shots": report.shots.size(), "language": Settings.language, "headless": DisplayServer.get_name() == "headless",
		"hold_seconds": report.held_input_actual_seconds, "full_15_second_hold": report.full_15_second_hold,
		"thought_transitions": report.thought_transitions, "output": output}))
	get_tree().quit(0 if failures.is_empty() else 1)
