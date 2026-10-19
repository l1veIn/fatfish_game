extends Node
## Deterministic controller/physics/serving regression fixtures, not a balance bot or GPU test.
## --headless --path game res://tests/canteen_controls_test.tscn -- --test-profile=canteen_controls
const RUN = preload("res://scripts/run/canteen_run.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("CANTEEN_CONTROLS: " + label)


func close_enough(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.01, label + " (%s / %s)" % [actual, expected])


func box(run: Node2D, items: Array) -> Dictionary:
	var result: Dictionary = run._new_basin(Vector2(800, 700))
	result.items = items.duplicate()
	return result


func clear_food(run: Node2D) -> void:
	while not run._fp.is_empty():
		run._remove_item(0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not "--test-profile=canteen_controls" in OS.get_cmdline_user_args() or Game.save_path != "user://qa_canteen_controls.json":
		push_error("Refusing test outside isolated canteen_controls profile")
		get_tree().quit(2)
		return
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Game.reset_save()
	Game.seen_buttons["intro_canteen_complete"] = true
	var run := RUN.new()
	add_child(run)
	run.set_process(false)
	run._arms.clear()
	run.crit_chance = 0.0
	run.can_think = true
	run._think = 0.6
	# Holding through depletion and regeneration must generate exactly one start and one stop.
	for i in 900:
		run._update_thinking(1.0 / 60.0, true)
	check(not run._thinking, "held exhausted thinking stays off")
	check(run._think_transitions == 2, "one start/end pair across 15 seconds of held input")
	close_enough(run._think, run.think_time, "energy recharges without restarting")
	run._update_thinking(0.01, false)
	run._update_thinking(0.01, true)
	check(run._thinking, "release then fresh press restarts after cooldown")
	run._update_thinking(0.01, false)
	close_enough(run._think_cooldown, RUN.THINK_COOLDOWN, "release starts explicit cooldown")
	run._update_thinking(0.01, true)
	check(not run._thinking, "press during cooldown does not restart")
	for i in 120:
		run._update_thinking(1.0 / 60.0, true)
	check(not run._thinking, "holding an early press beyond cooldown still needs release")
	run._update_thinking(0.01, false)
	run._update_thinking(0.01, true)
	check(run._thinking, "new press after cooldown works")
	run._interrupt_thinking()
	for i in 20:
		run._update_thinking(1.0 / 60.0, true)
	check(not run._thinking, "pause/resume input guard cannot re-trigger thinking")
	check(not Audio._slow, "interruption restores normal audio speed")
	# No material silently attracts food. Explicit attraction is local and bounded.
	run._hand = box(run, [])
	run._hand["previous_pos"] = run._hand.pos
	run.magnet = 0.0
	for material in 4:
		run.mat_level = material
		close_enough(run._magnet(), 0.0, "material %d has no hidden magnet" % material)
	run.diverge = 200.0
	run._thinking = false
	var velocity := run._steer_food(Vector2(700, 620), Vector2(0, 200), RUN.I.BALL, 0.1, 0.0)
	close_enough(velocity.x, 0.0, "unpressed attraction skill has no effect")
	run._thinking = true
	velocity = run._steer_food(Vector2(700, 620), Vector2(0, 200), RUN.I.BALL, 0.1, 0.0)
	check(velocity.x > 0 and velocity.x <= RUN.PULL_MAX_SPEED, "explicit nearby skill gives a gentle nudge")
	for point in [Vector2(400, 620), Vector2(700, 400), Vector2(700, 730)]:
		velocity = run._steer_food(point, Vector2(0, 200), RUN.I.BALL, 0.1, 0.0)
		close_enough(velocity.x, 0.0, "attraction is absent outside local field %s" % point)
	velocity = run._steer_food(Vector2(700, 620), Vector2(0, -100), RUN.I.BALL, 0.1, 0.0)
	close_enough(velocity.x, 0.0, "rising food is not bent sideways")
	velocity = Vector2(0, 200)
	for i in 600:
		velocity = run._steer_food(Vector2(700, 620), velocity, RUN.I.BALL, 1.0 / 60.0, 0.0)
	check(absf(velocity.x) <= RUN.PULL_MAX_SPEED, "attraction never accumulates unbounded horizontal speed")
	run._thinking = false
	run.diverge = 0.0
	# Mouse follows the pointer exactly, even with a full box; pad motion stays bounded.
	run._hand = box(run, [RUN.I.BALL, RUN.I.BALL, RUN.I.BALL, RUN.I.BALL])
	run._aim = Vector2(1000, 600)
	run._mouse_steering = true
	run._update_hand(1.0 / 60.0)
	check(run._hand.pos.is_equal_approx(run._aim), "full mouse box follows pointer in one frame")
	run._mouse_steering = false
	run._aim = Vector2(300, 600)
	var before: Vector2 = run._hand.pos
	run._update_hand(1.0 / 60.0)
	check(run._hand.pos.distance_to(before) < RUN.SPEED.x / 60.0 + 1.0, "pad movement retains a bounded speed")
	# Crossing tests use actual _update_items, with fixed flight data rather than a bot.
	run._hand = box(run, [])
	run._hand["previous_pos"] = run._hand.pos
	run._add_item(Vector2(650, 680), Vector2(1500, 200), RUN.I.BALL)
	run._fg[0] = 0.0
	var caught_before := run.caught
	run._update_items(0.2)
	check(run.caught == caught_before + 1, "fast diagonal food crossing catches despite end position outside box")
	clear_food(run)
	run._hand = box(run, [])
	run._hand.pos = Vector2(100, 700)
	run._aim = Vector2(1000, 700)
	run._mouse_steering = true
	run._update_hand(1.0 / 60.0)
	run._add_item(Vector2(550, 696), Vector2(0, 60), RUN.I.BALL)
	run._fg[0] = 0.0
	caught_before = run.caught
	run._update_items(1.0 / 60.0)
	check(run.caught == caught_before + 1, "mouse lateral sweep catches food in its path")
	clear_food(run)
	run._add_item(Vector2(1250, 696), Vector2(0, 60), RUN.I.BALL)
	run._fg[0] = 0.0
	caught_before = run.caught
	run._update_items(1.0 / 60.0)
	check(run.caught == caught_before, "distant food outside swept opening is not caught")
	clear_food(run)
	run._hand = box(run, [])
	run._hand["previous_pos"] = run._hand.pos
	var helper_box := box(run, [])
	helper_box.pos = Vector2(800, 900)
	helper_box["crew"] = true
	run._crew = [{"id": "wen", "state": "catch", "x": 800.0, "box": helper_box, "hop": 0.0}]
	run._add_item(Vector2(800, 650), Vector2(0, 1000), RUN.I.BALL)
	run._fg[0] = 0.0
	run._update_items(0.3)
	check(run._hand.items.size() == 1 and helper_box.items.is_empty(), "earliest player contact wins before lower helper in long frame")
	run._crew.clear()
	clear_food(run)
	# Prediction matches exact ballistic gravity and shares skill steering.
	run._add_item(Vector2(600, 350), Vector2(40, -120), RUN.make(RUN.I.BALL, 2))
	run._fg[0] = 900.0
	var prediction := run._landing_prediction(0, 700)
	var duration := run._time_to(0, 700)
	close_enough(prediction.position.x, 600.0 + 40.0 * duration, "unforced marker x matches trajectory")
	close_enough(prediction.position.y, 700.0, "marker sits at the box catching height")
	clear_food(run)
	run._thinking = true
	run.diverge = 200.0
	run._add_item(Vector2(750, 600), Vector2(0, 100), RUN.make(RUN.I.BALL, 2))
	run._fg[0] = 900.0
	prediction = run._landing_prediction(0, 700)
	check(prediction.position.x > 750.0, "marker includes the same local skill attraction")
	check(run._landing_prediction(0, 500).is_empty(), "no marker above food already below the catching height")
	run._hand.items = [RUN.I.BALL, RUN.I.BALL, RUN.I.BALL, RUN.I.BALL]
	var bounced := false
	for i in 120:
		run._update_items(1.0 / 60.0)
		if run._fp.is_empty():
			break
		if run._fv[0].y < 0.0:
			bounced = true
			check(absf(run._fp[0].x - prediction.position.x) < 8.0, "live attracted flight contacts within opening tolerance of predicted x")
			break
	check(bounced, "prediction fixture reaches a real full-box collision")
	check(RUN._grade_rim(1, true, 0.0).a > 0.8 and RUN._grade_rim(2, true, 0.0).a > 0.8, "silver and gold retain persistent boxed outlines")
	check(RUN._grade_rim(0, true, 0.0).a == 0.0, "ordinary food has no grade outline")
	clear_food(run)
	run._thinking = false
	# The three build mechanics freeze at real submission and ignore helpers and ghosts.
	run.mono_bonus = 0.1
	run.cache_bonus = 0.15
	run.rotation_bonus = 0.2
	run.combo = 0.1
	run.memory = 2
	run._combo_safe = true
	run.compress = 0
	var mono := box(run, [RUN.make(RUN.I.BALL), RUN.make(RUN.I.BALL, 1), RUN.make(RUN.I.BALL, 2), RUN.make(RUN.I.BALL)])
	var preview := run._plan_box(mono)
	check(preview.mono_kind == RUN.I.BALL and preview.combo_eligible, "mixed grades of one dish form a full platter")
	check(run._previous_mono_kind == -1 and not run._cache_ready, "preview does not spend or change state")
	run._serve(mono)
	close_enough(run._box_rule_bonus(mono), 0.1, "real platter submission freezes additive bonus")
	check(run._combo_n == 1, "platter advances chain at delivery time")
	run._note_served(mono)
	check(run._combo_n == 1, "same box cannot advance chain twice")
	var other := box(run, [RUN.I.BOWL, RUN.I.BOWL])
	run._serve(other)
	check(other.meal_rule.rotation, "successive full platters of different food earn rotation")
	close_enough(run._box_rule_bonus(other), 0.3, "rotation adds to mono bonus")
	close_enough(other.chain_multiplier, 1.1, "second delivered platter freezes chain multiplier")
	run._start_box(other)
	run._start_box(mono)
	check(run._combo_n == 2, "reverse eating order cannot rewrite delivery chain")
	var ghost_full := box(run, [RUN.I.BALL, RUN.make(RUN.I.BALL, 0, false, true), RUN.make(RUN.I.BALL, 0, false, true)])
	check(run._plan_box(ghost_full).mono_kind == -1, "ghost bites cannot fill or qualify a platter")
	var ghost_recipe := box(run, [RUN.make(RUN.KIND["carb"], 0, false, true)])
	check(not run._plan_box(ghost_recipe).cache_primed, "ghost recipes cannot charge cache")
	var mixed := box(run, [RUN.I.BALL, RUN.I.BALL, RUN.I.BALL, RUN.I.VEG])
	check(run._plan_box(mixed).mono_kind == -1, "mixed real dishes are not a mono platter")
	var recipe := -1
	for k in RUN.NAMES.size():
		if RUN.IS_SET[k] and RUN.SPACE[k] <= 2:
			recipe = k
			break
	check(recipe >= 0, "fixture has a real small recipe")
	var roomy := box(run, [RUN.make(recipe)])
	run.compress = 1
	check(run._box_profile(roomy).used_cells == run._cells(RUN.make(recipe)), "serving profile uses compressed real cell cost")
	run.compress = 0
	run._serve(roomy)
	check(roomy.meal_rule.cache_primed and run._cache_ready, "roomy recipe delivery stores one cache")
	check(roomy.meal_rule.cache_bridge and run._previous_mono_kind == RUN.I.BOWL and run._combo_n == 3,
		"actual cache submission bridges the preceding bowl platter and advances the chain")
	var prior_kind := run._previous_mono_kind
	var prior_chain := run._combo_n
	for origin in ["crew", "takeout"]:
		var npc := box(run, [RUN.I.BALL, RUN.I.BALL, RUN.I.BALL, RUN.I.BALL])
		npc[origin] = true
		run._serve(npc)
		check(run._cache_ready and run._previous_mono_kind == prior_kind and run._combo_n == prior_chain, origin + " cannot spend or interrupt player build state")
		close_enough(run._box_rule_bonus(npc), 0.0, origin + " receives no player build bonus")
	var cached := box(run, [RUN.I.BALL, RUN.I.BALL, RUN.I.BALL, RUN.I.BALL])
	run._serve(cached)
	check(cached.meal_rule.cache_consumed and not run._cache_ready, "next player full box consumes cache once")
	close_enough(run._box_rule_bonus(cached), 0.45, "real cached rotation stacks mono, cache and rotation bonuses")
	var empty := box(run, [])
	prior_kind = run._previous_mono_kind
	run._note_served(empty)
	check(run._previous_mono_kind == prior_kind, "empty box does not change delivery build state")
	# Large legitimate earnings survive checkout without hidden context deductions.
	run._queue.clear()
	run._hand = null
	run._eating = null
	run.earned = 100000.0
	Game.tokens = 100000.0
	Game.total_tokens = 100000.0
	var expected := run.earned * run.balance_mult() * run.review_mult()
	run._end("提前下班", false)
	close_enough(run.earned, expected, "checkout retains uncapped earnings")
	close_enough(Game.tokens, expected, "wallet has no hidden overflow deduction")
	check(not run._score.has("fuse"), "checkout emits no overflow penalty")
	run.queue_free()
	await get_tree().process_frame
	# These synchronous fixtures enqueue audio in one frame; let the mixer begin before stopping it.
	await get_tree().create_timer(0.12, true, false, true).timeout
	Audio._exit_tree()
	await get_tree().create_timer(0.12, true, false, true).timeout
	UiKit.clear_cache()
	print("CANTEEN_CONTROLS_RESULT ", JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures,
		"profile": Game.save_path, "scope": "deterministic state, trajectory, swept collision and serving fixtures; no GPU/audio listen"}))
	get_tree().quit(0 if failures.is_empty() else 1)
