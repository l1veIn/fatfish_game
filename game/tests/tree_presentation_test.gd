extends Node
## Explicit late-game/lesson fixtures and real GUI events, not a progression playthrough.
var tree: TreeScreen
var output := ""
var requested := Vector2i(1280, 720)
var checks := 0
var failures: Array[String] = []
var report := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("TREE_PRESENTATION: " + label)


func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await frames(3)


func click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		get_viewport().push_input(e, true)
		await frames(3)


func shot(name: String) -> void:
	await frames(4)
	if DisplayServer.get_name() == "headless" or output == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	check(img.get_size() == requested, "native screenshot dimensions: " + name)
	var path := output.path_join(name + ".png")
	check(img.save_png(path) == OK, "saved " + name)
	report.shots.append({"name": name, "path": path, "sha256": FileAccess.get_sha256(path)})


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_tree_presentation_"):
		push_error("Use --test-profile=tree_presentation_<suffix>")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg == "--small":
			requested = Vector2i(960, 540)
	if output != "":
		DirAccess.make_dir_recursive_absolute(output)
	Settings.fullscreen = false
	Settings.window_size = requested
	Settings.pause_unfocused = false
	Settings.reduced_motion = true
	Settings.hit_pause = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	report = {"scope": "Injected late-game and first-lesson states plus real GUI key/click events; not a completed playthrough", "language": Settings.language,
		"window": str(requested), "engine": Engine.get_version_info().string, "renderer": DisplayServer.get_name(), "source_sha256": {}, "shots": []}
	for path in ["scripts/tree/tree_screen.gd", "scripts/ui/meal_planner.gd", "scripts/ui/run_coach.gd", "scripts/ui/ui_kit.gd", "data/i18n/en.json", "tests/tree_presentation_test.gd"]:
		report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	for path in ["cork_bg", "ticket", "stamp"]:
		report.source_sha256["assets/canteen/" + path + ".png"] = FileAccess.get_sha256("res://assets/canteen/" + path + ".png")
	Game.reset_save()
	Game.version = Game.VERSIONS.size() - 1
	Game.tokens = 1000000000
	Game.runs = 20
	for n in Game.nodes:
		if not n.get("locked", false):
			Game.levels[n.id] = int(n.max)
	Game.levels["menu"] = 2
	Game.levels["prompt"] = 1
	Game.seen_buttons = {"menu": true, "sigs": true, "menu_card": true, "sigs_card": true}
	Game._recompute()
	tree = TreeScreen.new()
	add_child(tree)
	await frames(5)
	check(tree._tex.has("cork_bg") and tree._tex.has("ui_chalkboard") and is_instance_valid(tree._fish), "original cork, chalkboard and character remain present")
	check(tree._header_rect().position == Vector2(24, 14) and tree._header_rect().size.x == 580, "original top-left chalkboard layout remains")
	var overlaps := 0
	for i in Game.nodes.size():
		for j in range(i + 1, Game.nodes.size()):
			var a := Rect2(tree._pos(Game.nodes[i]) - tree.TICKET * 0.5, tree.TICKET)
			var b := Rect2(tree._pos(Game.nodes[j]) - tree.TICKET * 0.5, tree.TICKET)
			if a.intersects(b):
				overlaps += 1
	check(overlaps == 0, "node cards do not overlap at any authored coordinate pair")
	tree._hover = "start"
	tree.grab_focus()
	await key(KEY_RIGHT)
	check(tree._hover != "start" and tree.has_focus(), "real arrows navigate nodes without escaping map focus")
	# Preserve the original click-to-buy interaction and explicit keyboard/controller accept.
	tree._pan = -tree._pos(Game.node("prompt")) * tree._zoom
	tree._hover = ""
	await frames(2)
	var before := Game.tokens
	var before_level := Game.level("prompt")
	await click(tree._at(Game.node("prompt")))
	check(Game.level("prompt") == before_level + 1 and Game.tokens < before, "original mouse click buys exactly one level")
	await key(KEY_ENTER)
	check(Game.level("prompt") == before_level + 2, "Enter on the map buys exactly one selected level")
	await frames(2)
	before = Game.tokens
	await click(tree._tooltip_bounds.get_center())
	check(Game.tokens == before, "floating explanation cannot purchase a ticket behind it")
	var longest := "start"
	var tallest := 0.0
	var saved_levels := Game.levels.duplicate()
	Game.levels = {"start": 1}
	Game._recompute()
	tree._trial.visible = true
	tree._trial.text = tr("提交评测 · 门票 %s") % "100K"
	for n in Game.nodes:
		var dimensions := Vector2.ZERO
		for level in [0, maxi(0, int(n.max) - 1), int(n.max)]:
			Game.levels[n.id] = level
			var measured := tree._tooltip_size(tree._tooltip_lines(n))
			dimensions.x = maxf(dimensions.x, measured.x)
			dimensions.y = maxf(dimensions.y, measured.y)
		Game.levels.erase(n.id)
		check(dimensions.y <= 700, "complete authored skill explanation fits without pagination: " + n.id)
		if dimensions.y > tallest:
			tallest = dimensions.y
			longest = n.id
		for target in [Vector2(1150, 540), Vector2(1780, 900), Vector2(120, 180), Vector2(700, 980), Vector2(1840, 180)]:
			tree._pan = target - Vector2(960, 540) - tree._pos(n) * tree._zoom
			var bounds := tree._tooltip_rect(n, dimensions)
			check(Rect2(0, 0, 1920, 1080).encloses(bounds), "tooltip stays onscreen: " + n.id + str(target))
			check(not bounds.intersects(tree._header_rect()) and not bounds.intersects(tree._bar.get_rect()), "tooltip avoids original header and tools: " + n.id + str(target))
			check(not bounds.intersects(tree._start.get_rect()) and not bounds.intersects(tree._trial.get_rect()), "tooltip avoids lunch and trial: " + n.id + str(target))
	report["maximum_tooltip_height"] = tallest
	report["maximum_tooltip_skill"] = longest
	Game.levels = saved_levels
	Game._recompute()
	tree._update_trial_button()
	tree._hover = longest
	tree._pan = -tree._pos(Game.node(longest)) * tree._zoom
	await shot("tree_longest_detail")
	tree._pan += Vector2(630, 360)
	await shot("tree_edge_tooltip")
	# Locked and unaffordable are separate review fixtures, restored before further UI actions.
	var lock_node: Dictionary = Game.node("menu")
	var was_locked: bool = lock_node.get("locked", false)
	lock_node["locked"] = true
	tree._hover = "menu"
	tree._pan = -tree._pos(lock_node) * tree._zoom
	check(tree._tooltip_lines(lock_node).any(func(line): return line[0] == tr("敬请期待")), "locked skill explains why purchase is unavailable")
	await shot("tree_locked")
	lock_node["locked"] = was_locked
	var funds := Game.tokens
	Game.tokens = 0
	check(not Game.can_buy("menu") and tree._tooltip_lines(lock_node).any(func(line): return line[0].contains("token")), "unaffordable skill keeps its price visible")
	await shot("tree_unaffordable")
	Game.tokens = funds
	tree._hover = "menu"
	tree._pan = -tree._pos(Game.node("menu")) * tree._zoom
	check(Game.level("menu") == 2 and not Game.is_maxed("menu"), "partial skill does not qualify for the max-level stamp")
	await shot("tree_partial")
	tree._hover = "start"
	tree._pan = Vector2.ZERO
	check(tree._tooltip_lines(Game.node("start")).any(func(line): return line[0] == tr("已满级")), "maxed root explains its completed state")
	await shot("tree_maxed")
	var opener: Button = tree.find_child("Tree_menu", true, false)
	opener.grab_focus()
	await key(KEY_ENTER)
	var planner: MealPlanner = tree._planner
	check(planner != null and planner._grid.columns == 3, "real toolbar event opens the original three-column menu")
	check(planner._portrait.size == Vector2(470, 326), "menu portrait stays at its intended layout dimensions")
	for card in planner._cards:
		var id: String = card.get_meta("dish_id")
		planner._show_detail(id)
		await frames(2)
		check(planner._detail_body.get_rect().end.y <= planner._done.position.y - 4, "dish detail does not cover confirmation: " + id)
		check(card.get_meta("status").get_rect().end.y < card.size.y, "selection status fits its row: " + id)
		check(card.get_meta("picture").size == Vector2(212, 126), "food texture stays within its intended card area: " + id)
		check(card.get_meta("status").get_rect().end.y <= card.get_meta("picture").position.y, "status does not cover the food picture: " + id)
	planner._by_id["ball"].grab_focus()
	await key(KEY_ENTER)
	await shot("planner_menu")
	planner._tabs[1].grab_focus()
	await key(KEY_ENTER)
	check(planner._portrait.size == Vector2(470, 326), "signature portrait swap preserves intended dimensions")
	await shot("planner_signatures")
	await key(KEY_ESCAPE)
	check(opener.has_focus(), "planner returns focus to its opener")
	tree.queue_free()
	await frames(3)
	# Actual canteen background at first-meal state, with gameplay frozen only for inspection.
	Game.reset_save()
	var run := CanteenRun.new()
	add_child(run)
	run.set_process(false)
	await frames(4)
	var coach: RunCoach = run._coach
	check(coach != null, "first-meal fixture exposes the real coach")
	if coach != null:
		check(not coach.get_rect().intersects(CanteenRun.TABLE), "coach leaves the real table area clear")
		await shot("coach_take")
		run._hand = run._new_basin(Vector2(850, 690))
		coach.took_box()
		run.queue_redraw()
		await key(KEY_LEFT)
		check(coach._device == "keyboard", "keyboard input changes tutorial key labels")
		for stage in [RunCoach.Step.TAKE, RunCoach.Step.CATCH, RunCoach.Step.SERVE]:
			coach.step = stage
			coach._refresh()
			await frames(2)
			check(coach._instruction.get_rect().end.y <= coach._footer.position.y, "tutorial instruction avoids footer: " + str(stage))
			check(coach._title.get_rect().end.x <= coach._skip.position.x, "tutorial title avoids skip: " + str(stage))
		await shot("coach_serve_keyboard")
		run._aim = Vector2(850, 880)
		run._update_hand(1.0 / 60.0)
		run.queue_redraw()
		await frames(4)
		check(coach.position == RunCoach.HOME, "coach stays fixed at bottom as the tray approaches")
		check(not coach.get_rect().intersects(Rect2(730, run._hand.pos.y - 75, 240, 140)), "reserved bottom dock leaves the held tray clear")
		await shot("coach_bottom_box")
		await click(coach.global_position + coach._skip.get_rect().get_center())
		check(not coach.active, "real skip button ends the lesson")
		check(coach.position == RunCoach.HOME and not coach.get_rect().intersects(Rect2(730, run._hand.pos.y - 75, 240, 140)), "completion message also leaves the held box clear")
		await shot("coach_done")
	run.queue_free()
	await frames(3)
	await get_tree().create_timer(0.12, true, false, true).timeout
	Audio._exit_tree()
	await get_tree().create_timer(0.12, true, false, true).timeout
	UiKit.clear_cache()
	report["checks"] = checks
	report["failures"] = failures
	report["ok"] = failures.is_empty()
	if output != "":
		var file := FileAccess.open(output.path_join("tree_presentation_report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("TREE_PRESENTATION_RESULT ", JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures, "language": Settings.language, "size": str(requested), "out": output}))
	get_tree().quit(0 if failures.is_empty() else 1)
