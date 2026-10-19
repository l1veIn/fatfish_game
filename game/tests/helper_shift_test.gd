extends Node
## Continuous shift integration fixture: normal ladles, falling food, movement, catches and
## serving. The only player is the existing autotest bot. No boxes or food are injected.
## --headless --path game res://tests/helper_shift_test.tscn -- --test-profile=helper_shift
## GPU (coordinated separately): --out=<absolute directory> [--small] [--lang=en]
## Fixed 1/120 s gameplay steps, 12 per engine frame; world time still respects thinking.
## This measures integration, not human feel, production FPS, or build balance.
const PROFILE := "helper_shift"
const STEP := 1.0 / 120.0
const STEPS_PER_FRAME := 12
const FIXTURE_SEED := 2026101904

class ObservedRun:
	extends CanteenRun
	var catches_by_id := {}
	var deliveries_by_id := {}
	var deliveries_by_role := {"sweep": 0, "recipe": 0, "nutrition": 0}
	var delivered_orders := 0
	var invalid_orders := 0
	var relay_uses := 0
	var relay_by_role := {"sweep": 0, "recipe": 0, "nutrition": 0}
	var relay_bonus_total := 0.0
	var inspections := 0
	var player_deliveries := 0
	var throws := 0
	var events: Array = []

	func _throw(a: Dictionary, kind: int) -> void:
		throws += 1
		super._throw(a, kind)

	func _catch(b: Dictionary, it: int, show: bool) -> void:
		var inspected_before: bool = b.get("crew_inspected", false)
		super._catch(b, it, show)
		if b.get("crew", false):
			var id := str(b.crew_id)
			catches_by_id[id] = int(catches_by_id.get(id, 0)) + 1
			if not inspected_before and b.get("crew_inspected", false):
				inspections += 1
				_record("inspection", id)

	func _serve(b: Dictionary) -> void:
		if b.get("crew", false) and not b.items.is_empty():
			var id := str(b.crew_id)
			var role := str(b.crew_role)
			deliveries_by_id[id] = int(deliveries_by_id.get(id, 0)) + 1
			deliveries_by_role[role] = int(deliveries_by_role.get(role, 0)) + 1
			if role == "recipe":
				if b.items.any(func(it): return K(it) == int(b.crew_recipe) and not is_ghost(it)):
					delivered_orders += 1
				else:
					invalid_orders += 1
			_record("delivery", id, role)
		elif not b.get("takeout", false) and not b.items.is_empty():
			player_deliveries += 1
		super._serve(b)

	func _award_helper_relay(b: Dictionary) -> bool:
		var awarded := super._award_helper_relay(b)
		if awarded:
			var role := str(b.crew_role)
			relay_by_role[role] = int(relay_by_role.get(role, 0)) + 1
			_record("relay_stored", str(b.crew_id), role)
		return awarded

	func _consume_helper_relay(b: Dictionary) -> float:
		var bonus := super._consume_helper_relay(b)
		if bonus > 0.0:
			relay_uses += 1
			relay_bonus_total += bonus
			_record("relay_consumed", "player", str(bonus))
		return bonus

	func _record(event: String, id: String, detail := "") -> void:
		if events.size() < 500:
			events.append({"world_time": snappedf(_t, 0.001), "event": event, "id": id, "detail": detail})


var _run: ObservedRun
var _out := ""
var _requested_size := Vector2i(1920, 1080)
var _failures: Array[String] = []
var _checks: Array = []
var _shots := {}
var _report := {}
var _max_boxes := 0
var _budget_violations := 0
var _peak_food := 0
var _moving_distance := {}
var _worst_step_us := 0
var _worst_engine_batch_us := 0
var _steps := 0
var _async_crave_seen := false
var _relay_stored_seen := false
var _caption_layout_samples := 0
var _caption_layout_violations := 0
var _settings_before: PackedByteArray


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=" + PROFILE) or Game.save_path != "user://qa_helper_shift.json":
		push_error("Refusing helper shift fixture outside its isolated profile")
		get_tree().quit(2)
		return
	_settings_before = FileAccess.get_file_as_bytes(Settings.PATH)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--small":
			_requested_size = Vector2i(960, 540)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://../build/qa/helper-shift")
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.window_size = _requested_size
	Settings.fullscreen = false
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.screen_shake = false
	Settings.apply()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(_requested_size)
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	CanteenRun.load_menu()
	_configure()
	_report = {"seed": FIXTURE_SEED, "step_seconds": STEP, "steps_per_engine_frame": STEPS_PER_FRAME,
		"scope": "Continuous normal-food shift with existing autotest player, fixed small gameplay steps; not human feel, FPS or balance evidence",
		"fixture": "Six legal helpers, two per role; egg_veg order from level-one wok. Legal high supply and fast eating, ordinary meal duration. No direct food/box injection.",
		"language": Settings.language, "requested_size": str(_requested_size), "source_sha256": {}, "levels": Game.levels.duplicate(),
		"helper_plan": Game.helper_plan.duplicate(true)}
	for path in ["scripts/run/canteen_run.gd", "scripts/autoload/game.gd", "scripts/run/meal_rules.gd", "data/skill_tree.json", "data/menu.json", "tests/helper_shift_test.gd"]:
		_report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	seed(FIXTURE_SEED)
	_run = ObservedRun.new()
	_run.autotest = true
	add_child(_run)
	_run.set_process(false)
	_check(_run.hired.size() == 6 and _run._crew.size() == 6, "all six selected helpers spawn")
	_check(_run._helper_box_budget() == 6, "six helpers have six bounded reservations")
	_check(_run._helper_configs.values().all(func(c): return c.reason.is_empty()), "all roles and recipe targets are valid")
	var world_rng := RandomNumberGenerator.new()
	world_rng.seed = FIXTURE_SEED
	var max_steps := int(_run.meal_time * 8.0 / STEP)
	while not _run._ended and _steps < max_steps:
		var batch_start := Time.get_ticks_usec()
		for i in STEPS_PER_FRAME:
			if _run._ended:
				break
			# Keep gameplay reproducible even if presentation/Audio consumes the global RNG
			# between engine frames. The RNG is never used to choose a desired outcome.
			seed(world_rng.randi())
			var positions := {}
			for c in _run._crew:
				positions[c.id] = float(c.x)
			var started := Time.get_ticks_usec()
			_run._process(STEP)
			_worst_step_us = maxi(_worst_step_us, Time.get_ticks_usec() - started)
			_steps += 1
			_observe(positions)
		_worst_engine_batch_us = maxi(_worst_engine_batch_us, Time.get_ticks_usec() - batch_start)
		await get_tree().process_frame
		_observe_caption_layout()
		if _run._t >= 8.0 and not _shots.has("early"):
			await _shot("early")
		if _run._helper_relay.size() > 0 and not _shots.has("hud_relay"):
			await _shot("hud_relay")
		if _ge_has_inspected_box() and not _shots.has("ge_inspection"):
			await _shot("ge_inspection")
		if _run._t >= _run.meal_time - 7.0 and not _shots.has("late"):
			await _shot("late")
	_finish_checks()
	await _shot("closed")
	_report.merge({"checks": _checks, "failures": _failures, "passed": _failures.is_empty(), "world_seconds": _run._t,
		"gameplay_steps": _steps, "worst_gameplay_step_ms": _worst_step_us / 1000.0,
		"worst_engine_batch_ms": _worst_engine_batch_us / 1000.0, "max_helper_boxes": _max_boxes,
		"budget_violations": _budget_violations, "peak_falling_food": _peak_food, "normal_throws": _run.throws,
		"caption_layout_samples": _caption_layout_samples, "caption_layout_violations": _caption_layout_violations,
		"catches_by_id": _run.catches_by_id, "deliveries_by_id": _run.deliveries_by_id,
		"deliveries_by_role": _run.deliveries_by_role, "completed_orders": _run.delivered_orders,
		"relay_awards_by_role": _run.relay_by_role, "relay_uses": _run.relay_uses,
		"relay_bonus_total": _run.relay_bonus_total, "ge_inspections": _run.inspections,
		"player_deliveries": _run.player_deliveries, "movement_distance_by_id": _moving_distance,
		"async_retained_crave_seen": _async_crave_seen, "events": _run.events,
		"screenshots": _shots, "window_size": str(DisplayServer.window_get_size())})
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("HELPER_SHIFT observations: ", JSON.stringify({"roles": _run.deliveries_by_role, "ids": _run.deliveries_by_id,
		"relay_uses": _run.relay_uses, "ge_inspections": _run.inspections, "world_seconds": _run._t,
		"max_boxes": _max_boxes, "worst_step_ms": _worst_step_us / 1000.0}))
	Fx.world = null
	_run.queue_free()
	await get_tree().process_frame
	Audio.set_process(false)
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.15, true, false, true).timeout
	print("HELPER_SHIFT_TEST %s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _configure() -> void:
	Game.reset_save()
	Game.version = 4
	Game.levels = {"start": 1}
	# Dependency closure creates an obtainable fixture, without altering production stats.
	for pair in [["hire", 6], ["orch", 2], ["fc", 1], ["nutri", 1], ["busy", 1], ["async", 1],
		["conc", 5], ["api", 5], ["batch", 3], ["eat", 10], ["grok", 1], ["stall_fry", 1]]:
		_grant(str(pair[0]), int(pair[1]))
	Game._recompute()
	Game.seen_buttons["intro_canteen_complete"] = true
	for feature in ["grok", "think", "warm"]:
		Game.seen_buttons["intro_" + feature] = true
	_check(Game.helper_recipe_options().any(func(option): return option.id == "egg_veg"), "simple egg/greens recipe is legally available")
	var roles := {"wen": "sweep", "pu": "recipe", "g": "nutrition", "ke": "sweep", "zi": "recipe", "ge": "nutrition"}
	for id in Game.HELPER_IDS:
		var role: String = roles[id]
		_check(Game.set_helper_config(id, true, role, "egg_veg" if role == "recipe" else ""), "legal helper assignment: " + id)
	for id in Game.levels:
		_check(Game.level(id) <= int(Game.node(id).get("max", 1)) and Game.is_visible(id), "owned skill has legal level and prerequisites: " + id)


func _grant(id: String, amount: int) -> void:
	var node: Dictionary = Game.node(id)
	for parent in node.get("parents", []):
		if Game.level(str(parent)) == 0:
			_grant(str(parent), 1)
	Game.levels[id] = maxi(Game.level(id), mini(amount, int(node.get("max", 1))))


func _observe(previous: Dictionary) -> void:
	var boxes := _run._helper_box_count()
	_max_boxes = maxi(_max_boxes, boxes)
	if boxes > _run._helper_box_budget():
		_budget_violations += 1
	_peak_food = maxi(_peak_food, _run._fp.size())
	_relay_stored_seen = _relay_stored_seen or not _run._helper_relay.is_empty()
	for c in _run._crew:
		_moving_distance[c.id] = float(_moving_distance.get(c.id, 0.0)) + absf(float(c.x) - float(previous[c.id]))
	if _run._eating != null and _run._eating.get("crew", false) and _run.async_feed and _run._crave_t > 0.1:
		_async_crave_seen = true


func _ge_has_inspected_box() -> bool:
	for c in _run._crew:
		if c.id == "ge" and c.box != null and c.box.get("crew_inspected", false):
			return true
	return false


func _observe_caption_layout() -> void:
	var tags: Array = _run._helper_task_layout()
	_caption_layout_samples += 1
	for i in tags.size():
		var rect: Rect2 = tags[i].rect
		if not Rect2(0, 0, 1920, 1080).encloses(rect):
			_caption_layout_violations += 1
		for j in range(i):
			if rect.intersects(tags[j].rect):
				_caption_layout_violations += 1


func _finish_checks() -> void:
	_check(_run._ended and _run._end_reason == "食堂关门了", "normal shift reaches closing through the real process loop")
	_check(_run.throws > 30 and _peak_food > 4, "normal ladles supply real flying food throughout the shift")
	for id in Game.HELPER_IDS:
		_check(int(_run.catches_by_id.get(id, 0)) > 0, "helper really catches falling food: " + id)
		_check(int(_run.deliveries_by_id.get(id, 0)) > 0, "helper really completes a delivery: " + id)
		_check(float(_moving_distance.get(id, 0.0)) > 100.0, "helper traverses the floor: " + id)
	for role in ["sweep", "recipe", "nutrition"]:
		_check(int(_run.deliveries_by_role[role]) > 0, "role completes a physical delivery: " + role)
		_check(int(_run.relay_by_role[role]) > 0, "role delivers a valid relay contribution: " + role)
	_check(_run.delivered_orders > 0 and _run.invalid_orders == 0, "recipe helpers deliver the exact completed order")
	_check(_run.player_deliveries > 0 and _run.relay_uses > 0, "autotest player serves real food and consumes stored relay")
	_check(_relay_stored_seen, "stored relay exists in an observable gameplay state")
	_check(_run.inspections > 0, "Ge improves an ordinary real catch during the shift")
	_check(_budget_violations == 0 and _max_boxes == 6, "helper reservations stay bounded and actually use all six slots")
	_check(_async_crave_seen, "async helper eating preserves nonzero stored appetite")
	_check(_caption_layout_samples > 100 and _caption_layout_violations == 0, "moving helper task captions stay separated and within the viewport throughout the shift")
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == _settings_before, "player settings remain byte-identical")
	if DisplayServer.get_name() != "headless":
		_check(DisplayServer.window_get_size() == _requested_size, "actual render window matches requested size")


func _check(ok: bool, description: String) -> void:
	_checks.append({"ok": ok, "description": description})
	if not ok:
		_failures.append(description)
		push_error("HELPER_SHIFT: " + description)


func _shot(name: String) -> void:
	_shots[name] = {"world_time": _run._t, "captured": false}
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == _requested_size, "native screenshot dimensions: " + name)
	var path := _out.path_join(name + ".png")
	_check(image.save_png(path) == OK, "write screenshot: " + name)
	_shots[name].merge({"captured": true, "path": path, "dimensions": str(image.get_size())})
