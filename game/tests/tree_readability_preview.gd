extends Node
## Isolated presentation fixtures and real GUI input, not a progression playthrough.
var tree: TreeScreen
var output := ""
var requested := Vector2i(1280, 720)
var checks := 0
var failures: Array[String] = []
var report := {}
var player_before := {}
var before := false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("TREE_READABILITY: " + label)


func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func player_hashes() -> Dictionary:
	var hashes := {}
	for path in ["user://save.json", "user://save.json.bak", "user://settings.cfg"]:
		hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return hashes


func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await frames()


func pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)
	await frames()


func click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = down
		get_viewport().push_input(event, true)
		await frames()


func touch(at: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = at
		event.index = 0
		event.pressed = down
		get_viewport().push_input(event, true)
		await frames()


func fixture(late: bool) -> void:
	if is_instance_valid(tree):
		tree.queue_free()
		await frames()
	Game.reset_save()
	Game.tokens = 500000.0 if late else 1800.0
	Game.total_tokens = 2600000.0 if late else 2600.0
	Game.runs = 18 if late else 2
	Game.seen_buttons = {"menu": true, "sigs": true, "crew": true, "menu_card": true, "sigs_card": true, "crew_card": true}
	if late:
		Game.version = Game.VERSIONS.size() - 1
		for node in Game.nodes:
			if not node.get("locked", false):
				Game.levels[node.id] = 1 if node.get("kind", "") == "ticket" else maxi(1, int(node.max) / 2)
	else:
		Game.levels = {"start": 1, "stall_main": 1, "stall_wok": 1, "skills": 1, "eat": 2, "conc": 1, "hire": 1}
	Game._recompute()
	tree = TreeScreen.new()
	add_child(tree)
	tree.grab_focus()
	await frames(5)


func focus_node(id: String, zoom := 1.05, at := Vector2(1030, 530)) -> void:
	tree._zoom = zoom
	tree._pan = at - Vector2(960, 540) - tree._pos(Game.node(id)) * zoom
	tree._hover = ""
	tree._tooltip_bounds = Rect2()
	tree.grab_focus()
	await frames()
	await pointer(tree._at(Game.node(id)))
	check(tree._hover == id, "real mouse motion selects " + id)


func shot(name: String) -> void:
	await frames(4)
	if DisplayServer.get_name() == "headless" or output.is_empty():
		return
	# A native preview can be covered by the editor; still render the actual viewport.
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	check(image.get_size() == requested, "native screenshot dimensions: " + name)
	var path := output.path_join(name + ".png")
	check(image.save_png(path) == OK, "saved " + name)
	report.shots.append({"name": name, "path": path, "sha256": FileAccess.get_sha256(path), "zoom": tree._zoom, "selected": tree._hover})


func inspect_summaries() -> void:
	var font := ThemeDB.fallback_font
	var minimum_size := 100
	var widest := {"id": "", "width": 0.0}
	for node in Game.nodes:
		var layout: Dictionary = tree.call("_ticket_summary_layout", node)
		var text := str(layout.get("text", ""))
		check(not text.is_empty(), "revealed ticket has an effect summary: " + str(node.id))
		var font_size := int(layout.get("font_size", 0))
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		check(width <= float(layout.get("width", 0.0)) + 0.5, "complete summary fits ticket width: " + str(node.id))
		check(font_size >= 14, "summary remains at its minimum readable design size: " + str(node.id))
		minimum_size = mini(minimum_size, font_size)
		if width > float(widest.width):
			widest = {"id": node.id, "width": width}
	report.summary_layout = {"nodes": Game.nodes.size(), "minimum_font_size": minimum_size, "widest": widest}


func _glyph_rect(text: String, font_size: int, baseline: Vector2) -> Rect2:
	var font := ThemeDB.fallback_font
	return Rect2(baseline - Vector2(0, font.get_ascent(font_size)), Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, font.get_ascent(font_size) + font.get_descent(font_size)))


func inspect_ticket_text() -> void:
	var old_levels := Game.levels.duplicate()
	var old_hover := tree._hover
	var old_zoom := tree._zoom
	# Exercise the completion stamp as well as the text at every supported scale.
	for node in Game.nodes:
		Game.levels[node.id] = int(node.max)
	tree.grab_focus()
	var combinations := 0
	for zoom in [0.45, 0.75, 1.05, 1.3]:
		tree._zoom = zoom
		for selected in [false, true]:
			for node in Game.nodes:
				tree._hover = str(node.id) if selected else ""
				var layout: Dictionary = tree.call("_ticket_text_layout", node, zoom)
				var label := "%s z=%.2f %s" % [node.id, zoom, "selected" if selected else "normal"]
				var title_rect: Rect2 = layout.title_rect
				var summary_rect: Rect2 = layout.summary_rect
				var content_rect: Rect2 = layout.content_rect
				var paper_rect: Rect2 = layout.paper_rect
				var marker_rect: Rect2 = layout.marker_rect
				var stamp_rect: Rect2 = layout.stamp_rect
				check(content_rect.grow(0.05).encloses(title_rect) and content_rect.grow(0.05).encloses(summary_rect), "title and effect stay inside the paper's content area: " + label)
				check(paper_rect.encloses(content_rect) and content_rect.position.x > paper_rect.position.x and content_rect.end.x < paper_rect.end.x, "content has real horizontal clearance from the paper edges: " + label)
				check(layout.title_lines.size() == layout.title_baselines.size(), "every rendered title line has a measured baseline: " + label)
				var glyphs: Array[Rect2] = []
				for i in layout.title_lines.size():
					var glyph := _glyph_rect(str(layout.title_lines[i]), int(layout.title_font_size), layout.title_baselines[i])
					check(title_rect.grow(0.05).encloses(glyph), "title glyph metrics fit their assigned row %d: %s" % [i, label])
					glyphs.append(glyph)
				var summary_glyph := _glyph_rect(str(layout.summary_text), int(layout.summary_font_size), layout.summary_baseline)
				check(str(layout.summary_text) == tree.call("_ticket_summary", node), "effect summary remains complete rather than clipped: " + label)
				check(summary_rect.grow(0.05).encloses(summary_glyph), "effect glyph metrics fit their assigned row: " + label)
				glyphs.append(summary_glyph)
				var level_glyph := _glyph_rect(str(layout.level_text), int(layout.level_font_size), layout.level_baseline)
				check(layout.level_rect.grow(0.05).encloses(level_glyph), "level glyph metrics fit their assigned row: " + label)
				glyphs.append(level_glyph)
				for i in glyphs.size():
					check(not glyphs[i].intersects(marker_rect) and not glyphs[i].intersects(stamp_rect), "rendered text clears the identity mark and completion stamp %d: %s" % [i, label])
					check(not glyphs[i].intersects(layout.progress_rect), "rendered text clears the progress track %d: %s" % [i, label])
					for j in range(i + 1, glyphs.size()):
						if glyphs[i].intersects(glyphs[j]):
							if not report.has("text_overlap_samples"):
								report.text_overlap_samples = []
							if report.text_overlap_samples.size() < 4:
								report.text_overlap_samples.append({"label": label, "first": str(glyphs[i]), "second": str(glyphs[j]), "intersection": str(glyphs[i].intersection(glyphs[j])), "title_font_size": layout.title_font_size})
						check(not glyphs[i].intersects(glyphs[j]), "rendered text rows do not overlap %d/%d: %s" % [i, j, label])
				combinations += 1
	Game.levels = old_levels
	tree._hover = old_hover
	tree._zoom = old_zoom
	report.ticket_text_layout = {"nodes": Game.nodes.size(), "zoom_levels": [0.45, 0.75, 1.05, 1.3], "states": ["normal", "selected"], "combinations": combinations, "completion_stamps": true, "metrics": "Actual production baselines, font ascent/descent and shaped text advances"}


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_tree_readability_") or not Settings._config_path.begins_with("user://qa_tree_readability_"):
		push_error("Use --test-profile=tree_readability_<suffix>")
		get_tree().quit(2)
		return
	player_before = player_hashes()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg == "--small":
			requested = Vector2i(960, 540)
		elif arg == "--before":
			before = true
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	Settings.fullscreen = false
	Settings.window_size = requested
	Settings.pause_unfocused = false
	Settings.reduced_motion = true
	Settings.hit_pause = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	report = {"scope": "Injected early/late-game states and real mouse, keyboard and touch GUI events; not a completed playthrough", "language": Settings.language,
		"window": str(requested), "renderer": DisplayServer.get_name(), "engine": Engine.get_version_info().string, "before": before, "source_sha256": {}, "shots": []}
	for path in ["scripts/tree/tree_screen.gd", "data/skill_tree.json", "data/i18n/en.json", "tests/tree_readability_preview.gd"]:
		report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	await fixture(false)
	if not before:
		check(tree.has_method("_ticket_summary_layout") and tree.has_method("_ticket_role") and tree.has_method("_edge_style") and tree.has_method("_ticket_text_layout"), "readability presentation API is available")
	check(tree._tex.has("cork_bg") and tree._tex.has("ticket") and tree._tex.has("pin") and is_instance_valid(tree._fish), "warm cork, paper tickets, pins and character stay present")
	tree._hover = ""
	await shot("early_overview")
	# An unlearned next layer remains a neutral, empty preview after adding labels.
	var previews := 0
	for node in Game.nodes:
		if not Game.is_preview(str(node.id)):
			continue
		previews += 1
		if not before:
			check(tree.call("_ticket_summary_layout", node).text == "", "blank preview reveals no summary: " + str(node.id))
			check(tree.call("_ticket_role", node) == "preview", "blank preview reveals no importance: " + str(node.id))
	check(previews > 0, "early fixture includes unrevealed preview tickets")
	# Spending and refunds go through the actual map GUI, with no direct buy calls.
	await focus_node("prompt", 1.05)
	var before_tokens := Game.tokens
	var before_level := Game.level("prompt")
	await click(tree._at(Game.node("prompt")))
	check(Game.level("prompt") == before_level + 1 and Game.tokens < before_tokens, "real mouse click buys exactly one level")
	var after_click := Game.tokens
	await click(tree._tooltip_bounds.get_center())
	check(Game.tokens == after_click and Game.level("prompt") == before_level + 1, "explanation click cannot buy through the tooltip")
	await key(KEY_BACKSPACE)
	check(Game.level("prompt") == before_level and is_equal_approx(Game.tokens, before_tokens), "real keyboard refund returns the bought level and full price")
	await key(KEY_ENTER)
	check(Game.level("prompt") == before_level + 1, "real keyboard confirm buys one selected level")
	await click(tree._at(Game.node("prompt")), MOUSE_BUTTON_RIGHT)
	check(Game.level("prompt") == before_level, "real right click refunds the selected ticket")
	var previous := tree._hover
	await key(KEY_RIGHT)
	check(tree._hover != previous and tree.has_focus(), "real directional key changes the map selection")
	await fixture(true)
	if not before:
		inspect_summaries()
		inspect_ticket_text()
	tree._hover = ""
	var normal_related: Dictionary = {} if before else tree.call("_edge_style", "ticket_r1", "think")
	await shot("late_overview")
	await focus_node("think", 1.05, Vector2(1030, 540))
	if not before:
		var selected_related: Dictionary = tree.call("_edge_style", "ticket_r1", "think")
		var selected_other: Dictionary = tree.call("_edge_style", "start", "stall_wok")
		check(bool(selected_related.focused) and not bool(selected_other.focused), "mouse selection emphasizes its prerequisite rather than unrelated branches")
		check(selected_related.color.a > normal_related.color.a and selected_related.color.a > selected_other.color.a, "selected connection becomes clearer while unrelated yarn recedes")
	await shot("key_unlock_focus")
	await focus_node("async", 1.05, Vector2(820, 560))
	if not before:
		check(tree.call("_edge_style", "hire", "async").focused and tree.call("_edge_style", "busy", "async").focused, "both prerequisites are highlighted for a require-all node")
	await shot("dual_parent_focus")
	# Native close-ups expose long two-line names and their neighboring ticket borders.
	for sample in ["skills", "menu", "busy", "constit"]:
		await focus_node(sample, 1.3, Vector2(1030, 540))
		await shot("ticket_closeup_" + sample)
	# A touch inspects first; only its dedicated purchase button spends tokens.
	await focus_node("prompt", 1.05, Vector2(1030, 530))
	tree._hover = ""
	tree._tooltip_bounds = Rect2()
	await frames()
	before_tokens = Game.tokens
	before_level = Game.level("prompt")
	await touch(tree._at(Game.node("prompt")))
	check(tree._hover == "prompt" and Game.level("prompt") == before_level and Game.tokens == before_tokens, "real touch selects and highlights a ticket without buying it")
	check(is_instance_valid(tree._touch_buy) and not tree._touch_buy.disabled, "touch selection exposes the existing purchase action")
	await shot("touch_inspect")
	check(player_hashes() == player_before, "player save, backup and settings hashes remain unchanged")
	report.player_files_unchanged = player_hashes() == player_before
	tree.queue_free()
	await frames()
	await get_tree().create_timer(0.12, true, false, true).timeout
	Audio._exit_tree()
	await get_tree().create_timer(0.12, true, false, true).timeout
	UiKit.clear_cache()
	report.checks = checks
	report.failures = failures
	report.ok = failures.is_empty()
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("tree_readability_report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("TREE_READABILITY_RESULT ", JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures, "language": Settings.language, "size": str(requested), "out": output}))
	get_tree().quit(0 if failures.is_empty() else 1)
