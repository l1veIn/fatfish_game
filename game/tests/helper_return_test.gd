extends Node
## One level-one sweep helper, normal food, a player tray parked by engine mouse events.
## Fixed simulation steps test autonomy after delivery, not FPS or human play quality.
const STEP := 1.0 / 120.0
const SEED := 2026102101
const DURATION := 45.0

class ObservedRun extends CanteenRun:
	var catches := 0
	var delivery_times: Array = []
	var catches_after_first := 0
	func _catch(b: Dictionary, it: int, show: bool) -> void:
		super._catch(b, it, show)
		if b.get("crew", false):
			catches += 1
			if not delivery_times.is_empty(): catches_after_first += 1
	func _serve(b: Dictionary) -> void:
		if b.get("crew", false) and not b.items.is_empty(): delivery_times.append(_t)
		super._serve(b)

var checks: Array = []
var failures: Array = []
var out := ""
var shots := {}

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	if not ok:
		failures.append(label)
		push_error(label)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=helper_return") or Game.save_path != "user://qa_helper_return.json":
		push_error("Refusing helper-return test outside isolated profile")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): out = ProjectSettings.globalize_path("res://../build/qa/helper-return")
	DirAccess.make_dir_recursive_absolute(out)
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.screen_shake = false
	Settings.reduced_motion = true
	Settings.vsync = false
	Settings.apply()
	Game.reset_save()
	Game.runs = 1
	Game.version = 0
	Game.levels = {"start":1,"hire":1}
	Game._recompute()
	Game.seen_buttons["intro_canteen_complete"] = true
	Game.seen_buttons["intro_stall_layout"] = true
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	seed(SEED)
	var run := ObservedRun.new()
	add_child(run)
	run.set_process(false)
	await get_tree().process_frame
	check(run.hired == ["wen"] and run._crew.size() == 1 and is_equal_approx(run.helper_speed,1.0),"one unaccelerated level-one sweep helper spawns")
	for point in [Vector2(1385,865),Vector2(1300,650)]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.relative = Vector2(50,10)
		get_viewport().push_input(motion,true)
		if point.x == 1385:
			for pressed in [true,false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = point
				click.pressed = pressed
				get_viewport().push_input(click,true)
	check(run._hand != null and run._aim == Vector2(1300,650),"engine mouse events pick up and park the player tray")
	# Ignore incidental real desktop input after this fixture's two motions.
	run.set_process_unhandled_input(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var frames := 0
	var moved_back := false
	var stationary := true
	while run._t < DURATION and not run._ended:
		for i in 12:
			seed(rng.randi())
			run._process(STEP)
			if run._hand != null: stationary = stationary and run._hand.pos.distance_to(Vector2(1300,650)) < 0.1
			if not run.delivery_times.is_empty() and run._crew[0].state == "catch" and run._crew[0].x < 1400.0:
				moved_back = true
		frames += 1
		await get_tree().process_frame
		if not run.delivery_times.is_empty() and not shots.has("first_delivery"):
			await shot("first_delivery",run)
		if moved_back and not shots.has("returned_to_catching"):
			await shot("returned_to_catching",run)
	check(not run._ended and run._t >= DURATION,"normal production loop runs the entire 45-second observation")
	check(run.catches > 0 and not run.delivery_times.is_empty(),"helper catches normal food and completes the first delivery")
	check(stationary,"player tray stays parked without further mouse movement")
	check(moved_back,"after delivery helper independently walks back into the catch area")
	check(run.catches_after_first > 0,"helper catches more food after her first delivery")
	check(run.delivery_times.size() >= 2,"helper completes at least two deliveries without mouse intervention")
	check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before,"player settings stay byte-identical")
	await shot("final",run)
	var hashes := {}
	for name in ["scripts/run/canteen_run.gd","scripts/run/meal_rules.gd","scripts/autoload/game.gd","scripts/autoload/settings.gd","scripts/ui/fish_meal_visual.gd","data/menu.json","data/skill_tree.json","tests/helper_return_test.gd","project.godot"]:
		hashes[name] = FileAccess.get_sha256("res://"+name)
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_sha256":hashes,
		"scope":"Normal production food/physics/helper loop for 45 fixed-step seconds; injected mouse events pick up/park one tray, then no input. No food/box/position injection, bot or skill boost.",
		"seed":SEED,"world_seconds":run._t,"engine_frames":frames,"step":STEP,"levels":Game.levels,
		"catches":run.catches,"catches_after_first":run.catches_after_first,"delivery_times":run.delivery_times,
		"helper_x":run._crew[0].x,"helper_state":run._crew[0].state,"screenshots":shots,"renderer":DisplayServer.get_name()}
	var file := FileAccess.open(out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("HELPER_RETURN_TEST %s catches=%d deliveries=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",run.catches,run.delivery_times.size(),failures.size()])
	Fx.world = null
	run.queue_free()
	await get_tree().process_frame
	Audio.set_process(false)
	Audio._exit_tree()
	UiKit.clear_cache()
	await get_tree().create_timer(0.15,true,false,true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func shot(label: String,run: CanteenRun) -> void:
	shots[label] = {"world_time":run._t,"captured":false}
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := out.path_join(label+".png")
	check(image.save_png(path) == OK,"save runtime screenshot "+label)
	shots[label].merge({"captured":true,"path":path})
