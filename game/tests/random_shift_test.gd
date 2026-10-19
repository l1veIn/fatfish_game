extends Node
## Three continuous normal shifts. Legal stats; no food/box injection and no forced procs.
## The existing bot controls the basin; this is integration evidence, not human balance.
const STEP := 1.0 / 120.0
const JOURNAL := preload("res://scripts/run/meal_journal.gd")
var _out := ""
var _failures: Array = []
var _checks: Array = []
var _reports: Array = []
var _finished := false

class ObservedRun:
	extends CanteenRun
	var contacts := 0
	var invalid_boxes := 0
	var arrivals := 0
	func _catch(b: Dictionary, it: int, show: bool) -> void:
		super._catch(b, it, show)
		contacts += 1
		inspect(b)
	func _serve(b: Dictionary) -> void:
		super._serve(b)
		arrivals += 1
		inspect(b)
	func inspect(b: Dictionary) -> void:
		if not b.items.is_empty() and (_space(b) > _cap() or _pack(b.items).is_empty()):
			invalid_boxes += 1


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=random_shift") or Game.save_path != "user://qa_random_shift.json":
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://../build/qa/random-shift-%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_out)
	Game.reset_save() # only the explicitly checked QA profile; real player files stay untouched
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.screen_shake = false
	Settings.fullscreen = false
	Settings.window_size = Vector2i(1280, 720)
	Settings.vsync = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	CanteenRun.load_menu()
	_journal_checks()
	for cols in [2, 3, 4]:
		await _shift(cols)
	Audio.set_process(false)
	Audio._exit_tree()
	UiKit.clear_cache()
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.15, true, false, true).timeout
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "shifts": _reports,
		"scope": "Normal ladles, trajectories, collision catches and settlement; fixed small steps, existing bot, not human play or equal-budget balance."}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("RANDOM_SHIFT_TEST %s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _journal_checks() -> void:
	Game.levels = {"start": 1, "eat": 2}
	Game._recompute()
	var run := CanteenRun.new()
	run._read_stats()
	var journal = JOURNAL.new()
	seed(137)
	var expected_rng := randi()
	seed(137)
	journal.begin(run)
	journal.count("caught_input", CanteenRun.I.LEG, run, "player")
	journal.count("caught_input", CanteenRun.make(CanteenRun.I.LEG, 0, false, true), run, "player")
	_check(randi() == expected_rng, "passive recording consumes no gameplay RNG")
	_check(journal.data.build.skill_spend == 180.0, "skill spend uses actual per-level floors and excludes root/tickets")
	_check(journal.data.food.caught_input.player == {"leg": 1, "leg:ghost": 1}, "ghosts remain separate from real ingredients")
	Game.levels.eat = 4
	_check(journal.data.build.levels.eat == 2, "opening build snapshot is not aliased to live game state")
	for i in JOURNAL.MAX_EVENTS + 2:
		journal.event("probe", float(i))
	_check(journal.data.events.size() == JOURNAL.MAX_EVENTS and journal.data.dropped_events == 2, "event storage is bounded and reports truncation")
	var folder := _out.path_join("retention-fixture")
	DirAccess.make_dir_recursive_absolute(folder)
	var untouched := FileAccess.open(folder.path_join("notes.json"), FileAccess.WRITE)
	untouched.store_string("keep")
	untouched.close()
	for i in 31:
		var file := FileAccess.open(folder.path_join("meal_%016d_000000000000.json" % i), FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	_check(journal.save_record(folder) == OK, "journal persists with a temporary file and atomic rename")
	var files := DirAccess.get_files_at(folder)
	_check(Array(files).filter(func(name): return name.begins_with("meal_") and name.ends_with(".json")).size() == 30, "only the latest thirty meal records are retained")
	_check(FileAccess.get_file_as_string(folder.path_join("notes.json")) == "keep", "retention leaves unrelated files alone")
	run.free()


func _grant(id: String, amount: int) -> void:
	var node: Dictionary = Game.node(id)
	for parent in node.get("parents", []):
		if Game.level(str(parent)) == 0:
			_grant(str(parent), 1)
	Game.levels[id] = maxi(Game.level(id), mini(amount, int(node.get("max", 1))))


func _shift(cols: int) -> void:
	Game.levels = {"start": 1}
	Game.version = 4
	Game.automation = {}
	Game.helper_plan = {}
	Game.struck = []
	Game.signatures = []
	Game.seen_buttons["intro_canteen_complete"] = true
	for pair in [["temp", 5], ["regen", 2], ["hot", 3], ["halluc", 2], ["hodge", 1],
		["stall_fry", 1], ["stall_sweet", 1], ["conc", 5], ["api", 5], ["batch", 3],
		["eat", 10], ["skills", 1], ["hire", 3], ["grok", 1], ["warmup", 3], ["eos", 1], ["sleep", 1]]:
		_grant(str(pair[0]), int(pair[1]))
	if cols > 2:
		_grant("vram", cols - 2)
	Game._recompute()
	for id in Game.levels:
		_check(Game.level(id) <= int(Game.node(id).get("max", 1)) and Game.is_visible(id), "legal skill level/prerequisite: %d columns %s" % [cols, id])
	var fixture_seed := 2026102000 + cols
	seed(fixture_seed)
	var run := ObservedRun.new()
	run.autotest = true
	_finished = false
	run.finished.connect(func(_earned): _finished = true)
	add_child(run)
	run.set_process(false)
	_check(run._cols() == cols and is_equal_approx(run.temp, 0.4) and is_equal_approx(run.regen, 0.2), "legal capacity and unforced probabilities: %d columns" % cols)
	var rng := RandomNumberGenerator.new()
	rng.seed = fixture_seed
	var steps := 0
	var samples := 0
	var shot_taken := false
	while not run._ended and steps < 100000:
		for i in 12:
			if run._ended:
				break
			seed(rng.randi())
			run._process(STEP)
			steps += 1
			var boxes: Array = run._leftover_boxes()
			if run._warm != null and not boxes.any(func(b): return is_same(b, run._warm)):
				boxes.append(run._warm)
			for b in boxes:
				run.inspect(b)
				samples += 1
		await get_tree().process_frame
		if not shot_taken and run._meal_elapsed() > 55.0 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_out.path_join("random-%d.png" % cols))
			shot_taken = true
	_check(run._ended and run._end_reason == "食堂关门了", "normal full shift reaches closing: %d columns" % cols)
	_check(run.contacts > 50 and run.arrivals > 10 and samples > 1000, "sustained ordinary catches, deliveries and continuous container observations: %d columns" % cols)
	_check(run.invalid_boxes == 0, "every caught, delivered, queued, held and reserved box remains packable: %d columns" % cols)
	var journal: Dictionary = run._journal.data
	var saved_records := DirAccess.get_files_at(Game.save_path.get_basename() + "_meals")
	_check(not saved_records.is_empty(), "normal settlement saves only to the isolated profile journal: %d columns" % cols)
	var transforms: Dictionary = journal.transforms
	_check(int(transforms.get("temperature_changed_kind", 0)) > 0 and int(transforms.get("regenerate_changed_kind", 0)) > 0, "both random transformation mechanisms actually occurred: %d columns" % cols)
	_check(journal.mode == "autotest" and journal.dropped_events == 0, "full trace is explicitly automated and untruncated: %d columns" % cols)
	var total_bites := int(journal.paid_bites.live) + int(journal.paid_bites.warm) + int(journal.paid_bites.sleep)
	_check(total_bites == run._bites, "live, warm and leftover paid bites reconcile with gameplay: %d columns" % cols)
	var score: Dictionary = journal.result.score
	var subtotal := 0.0
	for key in ["base", "warm", "eos", "sleep", "clip"]:
		subtotal += float(score.get(key, 0.0))
	_check(is_equal_approx(subtotal, float(journal.result.subtotal)) and is_equal_approx(subtotal * float(score.balance) * float(score.review), run.earned), "income components and meal multipliers reconcile exactly: %d columns" % cols)
	_check(journal.nutrition.size() >= 22 and journal.result.recipes_eaten.size() == run._kinds_eaten.size(), "nutrition timeline and actually eaten recipe identities recorded: %d columns" % cols)
	var file := FileAccess.open(_out.path_join("meal-random-%d.json" % cols), FileAccess.WRITE)
	file.store_string(JSON.stringify(journal, "\t"))
	file.close()
	_reports.append({"cols": cols, "seed": fixture_seed, "steps": steps, "samples": samples,
		"contacts": run.contacts, "arrivals": run.arrivals, "invalid_boxes": run.invalid_boxes, "transforms": transforms})
	print("RANDOM_SHIFT ", JSON.stringify(_reports.back()))
	var deadline := Time.get_ticks_msec() + 6000
	while not _finished and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05, true, false, true).timeout
	_check(_finished, "normal receipt completes before cleanup: %d columns" % cols)
	Fx.world = null
	run.queue_free()
	for i in 3:
		await get_tree().process_frame


func _check(ok: bool, description: String) -> void:
	_checks.append({"ok": ok, "description": description})
	if not ok:
		_failures.append(description)
		push_error(description)
