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
	Game.seen_buttons = {"menu": true, "sigs": true}
	Game._recompute()
	tree = TreeScreen.new()
	add_child(tree)
	await frames(5)
	check(tree._board.clip_contents, "node map is clipped before fixed UI")
	check(not tree.BOARD.intersects(tree.DETAIL), "map and long-detail column have independent areas")
	check(not tree.DETAIL.intersects(tree._start.get_rect()), "details cannot cover the lunch action")
	check(not tree.DETAIL.intersects(tree._trial.get_rect()), "details cannot cover the review action")
	check(tree._detail_icon.size == Vector2(64, 64), "detail art remains at its intended small-icon scale")
	check(not tree._detail_icon.get_rect().intersects(tree._detail_name.get_rect()), "category art leaves the full title area clear")
	check(not tree._detail_icon.get_rect().intersects(tree._detail_scroll.get_rect()), "category art leaves the full scrolling text area clear")
	var overlaps := 0
	for i in Game.nodes.size():
		for j in range(i + 1, Game.nodes.size()):
			var a := Rect2(tree._pos(Game.nodes[i]) - tree.TICKET * 0.5, tree.TICKET)
			var b := Rect2(tree._pos(Game.nodes[j]) - tree.TICKET * 0.5, tree.TICKET)
			if a.intersects(b):
				overlaps += 1
	check(overlaps == 0, "node cards do not overlap at any authored coordinate pair")
	tree._hover = "start"
	tree._board.grab_focus()
	await key(KEY_RIGHT)
	check(tree._hover != "start" and tree._board.has_focus(), "real arrows navigate nodes without escaping map focus")
	# A click selects, then an explicit accept purchases exactly one level.
	tree._pan = -tree._pos(Game.node("prompt")) * tree._zoom
	var before := Game.tokens
	var before_level := Game.level("prompt")
	await click(tree._at(Game.node("prompt")))
	check(tree._hover == "prompt" and Game.tokens == before, "mouse click inspects without spending")
	await key(KEY_ENTER)
	check(Game.level("prompt") == before_level + 1, "Enter on the map buys exactly one selected level")
	check(tree._detail_name.text == tr(Game.node("prompt").name), "purchased skill remains selected in the detail column")
	var longest := "start"
	var longest_count := 0
	for n in Game.nodes:
		tree._hover = n.id
		tree._last_detail = ""
		tree._refresh_detail()
		await frames(2)
		check(tree._detail_name.get_rect().end.y <= tree._detail_status.position.y - 4, "full skill title fits its own area: " + n.id)
		check(tree._detail_scroll.get_rect().end.y < tree._detail_price.position.y, "scrolling detail avoids the purchase row: " + n.id)
		check(tree._detail_icon.texture != null, "category art is available for " + n.id)
		check(tree._detail_icon.size == Vector2(64, 64), "texture swap preserves category icon dimensions: " + n.id)
		var status_width := tree._detail_status.get_theme_font("font").get_string_size(tree._detail_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
		check(tree._detail_status.position.x + status_width + 16 < tree._detail_icon.position.x, "category art avoids the actual level/status text: " + n.id)
		var art_path := tree._detail_icon.texture.resource_path
		report.source_sha256[art_path.trim_prefix("res://")] = FileAccess.get_sha256(art_path)
		if tr(n.desc).length() > longest_count:
			longest_count = tr(n.desc).length()
			longest = n.id
	tree._hover = longest
	tree._pan = -tree._pos(Game.node(longest)) * tree._zoom
	tree._last_detail = ""
	tree._refresh_detail()
	await shot("tree_longest_detail")
	tree._detail_scroll.scroll_vertical = 10000
	await shot("tree_detail_path")
	# Locked and unaffordable are separate review fixtures, restored before further UI actions.
	var lock_node: Dictionary = Game.node("menu")
	var was_locked: bool = lock_node.get("locked", false)
	lock_node["locked"] = true
	tree._hover = "menu"
	tree._pan = -tree._pos(lock_node) * tree._zoom
	tree._last_detail = ""
	tree._refresh_detail()
	check(tree._buy.disabled and tree._detail_status.text == tr("敬请期待"), "locked skill explains why purchase is unavailable")
	await shot("tree_locked")
	lock_node["locked"] = was_locked
	var funds := Game.tokens
	Game.tokens = 0
	tree._refresh()
	check(tree._buy.disabled and tree._detail_price.text != "", "unaffordable skill keeps its price visible")
	await shot("tree_unaffordable")
	Game.tokens = funds
	tree._refresh()
	tree._hover = "menu"
	tree._pan = -tree._pos(Game.node("menu")) * tree._zoom
	tree._last_detail = ""
	tree._refresh_detail()
	check(tree._detail_status.text == tr("等级 %d / %d") % [2, Game.node("menu").max], "partial skill is labelled by actual level")
	await shot("tree_partial")
	tree._hover = "start"
	tree._pan = Vector2.ZERO
	tree._last_detail = ""
	tree._refresh_detail()
	check(tree._buy.disabled and tree._detail_status.text == tr("已满级"), "maxed root cannot invite a purchase")
	await shot("tree_maxed")
	var opener: Button = tree.find_child("Tree_menu", true, false)
	opener.grab_focus()
	await key(KEY_ENTER)
	var planner: MealPlanner = tree._planner
	check(planner != null and planner._grid.columns == 2, "real toolbar event opens the wide-row menu")
	check(planner._portrait.size == Vector2(470, 338), "menu portrait stays at its intended layout dimensions")
	for card in planner._cards:
		var id: String = card.get_meta("dish_id")
		planner._show_detail(id)
		await frames(2)
		check(planner._detail_body.get_rect().end.y <= planner._done.position.y - 4, "dish detail does not cover confirmation: " + id)
		check(card.get_meta("status").get_rect().end.y < card.size.y, "selection status fits its row: " + id)
		check(card.get_meta("picture").size == Vector2(118, 126), "food texture stays within its intended card area: " + id)
	planner._by_id["ball"].grab_focus()
	await key(KEY_ENTER)
	await shot("planner_menu")
	planner._tabs[1].grab_focus()
	await key(KEY_ENTER)
	check(planner._portrait.size == Vector2(470, 338), "signature portrait swap preserves intended dimensions")
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
		run._hand.pos = Vector2(850, 880)
		run.queue_redraw()
		await frames(4)
		check(coach._raised and coach.position.y < RunCoach.HOME.y, "coach yields its lower-left area to the actual held box")
		check(not coach.get_rect().intersects(Rect2(730, 805, 240, 160)), "raised coach leaves the bottom-edge box clear")
		await shot("coach_bottom_box")
		await click(coach.global_position + coach._skip.get_rect().get_center())
		check(not coach.active, "real skip button ends the lesson")
		check(coach._raised and not coach.get_rect().intersects(Rect2(730, 805, 240, 160)), "completion message also leaves the held box clear")
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
