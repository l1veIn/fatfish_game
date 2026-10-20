extends Node
## Injected meals through the production eating loop. GPU images are real rendered frames;
## these fixtures test presentation and conservation, not catching skill or human enjoyment.
var run: CanteenRun
var out := ""
var failures: Array = []
var checks: Array = []
var shots: Array = []
var hashes := {}
var player_before: PackedByteArray
var settings_before: PackedByteArray
const SOURCES := ["scripts/ui/fish_rig.gd", "scripts/ui/fish_meal_visual.gd", "scripts/run/canteen_run.gd",
	"data/menu.json", "tests/fish_meal_visual_test.gd", "assets/fatfish/rig/rig.gdshader",
	"assets/fatfish/rig_seat/pose_meal_take.png", "assets/fatfish/rig_seat/pose_meal_comic.png",
	"assets/canteen/food_mantou.png", "assets/canteen/food_bun.png", "assets/canteen/food_lotus_rice.png"]


func _ready() -> void:
	if Game.save_path != "user://qa_fish_meal.json" or not Settings._testing:
		push_error("Use --test-profile=fish_meal")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	for source in SOURCES: hashes[source] = FileAccess.get_sha256("res://" + source)
	player_before = FileAccess.get_file_as_bytes("user://save.json")
	settings_before = FileAccess.get_file_as_bytes(Settings.PATH)
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.screen_shake = false
	Settings.reduced_motion = false
	Settings.window_size = Vector2i(1280, 720)
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Game.seen_buttons["intro_canteen_complete"] = true
	Game.seen_buttons["intro_stall_layout"] = true
	Game.levels = {}
	Game._recompute()
	run = CanteenRun.new()
	add_child(run)
	run.set_process(false)
	run._fish.set_process(false)
	run._journal = null
	run.box_n = 4
	run._empty = 2
	run.crit_chance = 0.0
	run.grok = true
	run._grokked = true
	run.veg_x = 3.0
	run.meal_time = 1000.0
	for frame in 4: await get_tree().process_frame
	var visuals = run._meal_visual
	_check(CanteenRun.NAMES[CanteenRun.I.GOLD] == "荷叶饭" and CanteenRun.FOOD_ART[CanteenRun.I.GOLD] == "lotus_rice", "legacy rare food ID maps to the new distinct staple")
	_check(CanteenRun.NAMES[CanteenRun.KIND.bun] == "肉包", "meat bun is named explicitly")
	_check(run._food_tex[CanteenRun.KIND.mantou].get_width() <= 128 and run._food_tex[CanteenRun.I.GOLD].get_width() <= 128, "large generated masters import as small runtime food textures")
	var before := [run.earned, Game.tokens, run._bites, run._cat.duplicate(), run._queue.duplicate(true)]
	seed(2468)
	var next_random := randf()
	seed(2468)
	visuals.consume(CanteenRun.make(CanteenRun.I.VEG, 2), CanteenRun.EAT_AT)
	visuals.advance(0.1)
	_check(is_equal_approx(randf(), next_random), "presentation consumes no gameplay random numbers")
	_check(before == [run.earned, Game.tokens, run._bites, run._cat, run._queue], "visuals alone do not change score, nutrition or inventory")
	run._fish.meal_active = false
	run._fish.play("basin", true)
	run._fish._blink_in = 0.0
	seed(1357)
	next_random = randf()
	seed(1357)
	run._fish._process(0.1)
	_check(is_equal_approx(randf(), next_random), "rig blinking uses its own cosmetic RNG")
	visuals.clear()
	visuals.observed_bites = 0
	visuals.represented_bites = 0
	await _meal("greens", ["veg", "veg", "veg", "veg"], 3.0, "gobble")
	await _meal("hand", ["bun", "ball", "mantou", "leg"], 3.0, "gobble")
	await _meal("sip", ["congee", "soymilk", "cola", "milktea"], 4.0, "sip")
	await _meal("mixed", ["porkrice", "egg", "pork", "gold"], 3.0, "gobble")
	Settings.reduced_motion = true
	await _meal("reduced", ["veg", "veg", "veg", "veg"], 3.0, "gobble")
	Settings.reduced_motion = false
	await _meal("rapid", ["veg", "veg", "veg", "veg", "veg", "veg", "veg", "veg"], 120.0, "gobble")
	_check(visuals.peak_marks <= visuals.MAX_MARKS and visuals._pending.is_empty() and visuals._current.is_empty(), "rapid eating has bounded cues and drains its visual backlog")
	run.grok = false
	run._grokked = false
	var paid_before := run._bites
	await _meal("reject", ["veg"], 3.0, "reject")
	_check(run._bites == paid_before, "rejected greens never become paid bites")
	_check(visuals.observed_bites == visuals.represented_bites, "every observed bite belongs to a completed gesture or rejection")
	visuals.consume(CanteenRun.make(CanteenRun.I.VEG), CanteenRun.EAT_AT)
	visuals.advance(0.3)
	for reaction in ["spit", "grok", "think", "full_belly"]:
		run._fish.play(reaction, true)
		run._fish._process(0.016)
		_check(run._fish._meal_pose.is_empty(), "comic eating does not mask priority reaction: " + reaction)
	run._fish.play("basin", true)
	Settings.reduced_motion = true
	run._fish._process(0.016)
	_check(run._fish._mat.get_shader_parameter("comic_hand") == Vector2.ZERO, "reduced motion disables comic hand deformation")
	Settings.reduced_motion = false
	visuals.clear()
	run._eating = run._new_basin(CanteenRun.EAT_AT)
	run._eating.items = [CanteenRun.make(CanteenRun.KIND.bun)]
	visuals.consume(run._eating.items[0], CanteenRun.EAT_AT)
	run._fish._process(0.016)
	var phase_before: float = run._fish.meal_phase
	run.set_process(true)
	run._fish.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.1, true).timeout
	_check(is_equal_approx(run._fish.meal_phase, phase_before), "pause freezes bite presentation")
	get_tree().paused = false
	for frame in 3: await get_tree().process_frame
	_check(not is_equal_approx(run._fish.meal_phase, phase_before), "resuming a live run resumes the same bite presentation")
	run.set_process(false)
	run._fish.set_process(false)
	visuals.clear()
	_check(not run._fish.meal_active and visuals._marks.is_empty(), "clearing a meal removes comic accents and restores waiting")
	for source in SOURCES: _check(hashes[source] == FileAccess.get_sha256("res://" + source), "source stable: " + source)
	_check(player_before == FileAccess.get_file_as_bytes("user://save.json"), "player progress bytes unchanged")
	_check(settings_before == FileAccess.get_file_as_bytes(Settings.PATH), "player settings bytes unchanged")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "shots": shots,
		"source_sha256": hashes, "engine": Engine.get_version_info(), "renderer": DisplayServer.get_name(),
		"observed_bites": visuals.observed_bites, "completed_gestures": visuals.completed_gestures, "peak_marks": visuals.peak_marks,
		"scope": "Injected meal fixtures, production eating loop, fixed 60 Hz presentation steps; not a full human playthrough."}
	if out != "": FileAccess.open(out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("FISH_MEAL_VISUAL_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks.size(), " failures=", failures.size())
	run.queue_free()
	await get_tree().process_frame
	Audio._exit_tree()
	await get_tree().create_timer(0.15).timeout
	UiKit.clear_cache()
	get_tree().quit(failures.size())


func _meal(id: String, foods: Array, rate: float, style: String) -> void:
	run._meal_visual.clear()
	run._eating = null
	run._queue.clear()
	run._chew_pause = 0.0
	run._dig_in = 0.0
	run._eat_acc = 0.0
	run.eat_rate = rate
	var box := run._new_basin(CanteenRun.EAT_AT)
	for name in foods: box.items.append(CanteenRun.make(CanteenRun.KIND[name]))
	var origin := run._boxed_item_origin(box, 0, CanteenRun.EAT_AT, 0.55)
	run._queue.append(box)
	var start: int = run._meal_visual.observed_bites
	var paid_before := run._bites
	var saw_style := false
	var saw_comic := false
	var saw_settle := false
	var saw_fast := false
	var frame_after_bite := -1
	var before_flight_checked := false
	for i in 420:
		run._update_fish(1.0 / 60.0, 1.0 / 60.0)
		run._fish._process(1.0 / 60.0)
		if run._meal_visual.observed_bites > start and frame_after_bite < 0: frame_after_bite = 0
		if frame_after_bite >= 0: frame_after_bite += 1
		if not before_flight_checked and frame_after_bite == 1:
			before_flight_checked = true
			_check(run._meal_visual._marks[0].from.is_equal_approx(origin), id + " pick-up accent belongs to the actual rendered food cell")
			if id == "mixed":
				_check(run._meal_visual._current.count == 1, "one mixed meal remains one performance event and one paid bite")
		if not run._meal_visual._current.is_empty(): saw_style = saw_style or run._fish.meal_style == style
		saw_comic = saw_comic or run._fish._meal_pose == "comic"
		saw_settle = saw_settle or (run._fish.meal_active and run._fish.meal_phase > 0.70 and run._fish._meal_pose == "take")
		saw_fast = saw_fast or run._fish.meal_fast
		if frame_after_bite in [5, 15, 24, 32]: await _shot(id + "_%02d" % frame_after_bite)
		# Fixed 60 Hz simulation, every third frame saved: encode at 20 fps for true-time motion.
		if id in ["greens", "rapid", "sip"] and frame_after_bite > 0 and frame_after_bite <= 120 and frame_after_bite % 3 == 0:
			await _shot(id + "_motion_%03d" % (frame_after_bite / 3), true)
		if i > 90 and frame_after_bite > 120 and run._eating == null and run._queue.is_empty() and run._meal_visual._current.is_empty() and run._meal_visual._marks.is_empty(): break
	_check(run._meal_visual.observed_bites - start == foods.size(), id + " every real removed item emits one visual event")
	_check(run._bites - paid_before == (0 if style == "reject" else foods.size()), id + " animation does not add or lose paid bites")
	_check(saw_style or style == "reject", id + " uses the correct comic eating rhythm")
	_check((saw_comic and saw_settle) or style == "reject", id + " includes covered-basin action and a final chewing hold")
	if id == "rapid": _check(saw_fast, "high throughput becomes a grouped fast performance")
	_check(run._eating == null, id + " empty box return is not held by the visual animation")


func _shot(name: String, crop := false) -> void:
	if out == "" or DisplayServer.get_name() == "headless": return
	run.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if crop: image = image.get_region(Rect2i(900, 330, 360, 350))
	image.save_png(out.path_join(name + ".png"))
	shots.append(name)


func _check(ok: bool, message: String) -> void:
	checks.append({"ok": ok, "message": message})
	if not ok:
		failures.append(message)
		push_error(message)
