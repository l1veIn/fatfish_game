extends Node
## Collection state fixtures + actual GUI events. Not a full playthrough or physical-pad test.
var _fails: Array[String] = []
var _shots := ""
var _host: Control
var _report := {}


class QuietRun extends CanteenRun:
	# The real run type/state without creating gameplay, consuming time or saving.
	func _ready() -> void:
		set_process(false)
		set_process_unhandled_input(false)

	func _draw() -> void:
		pass


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().has("--test-profile=collection_presentation") or not Game.save_path.begins_with("user://qa_"):
		push_error("Use --test-profile=collection_presentation; refusing player-save access")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_shots = arg.trim_prefix("--out=")
		elif arg.begins_with("--render-size=") and DisplayServer.get_name() != "headless":
			var dimensions := arg.trim_prefix("--render-size=").split("x")
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(dimensions[0]), int(dimensions[1])))
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	var player_before := FileAccess.get_file_as_bytes("user://save.json")
	Settings.reduced_motion = true
	_report = {"engine": Engine.get_version_info().string, "renderer": DisplayServer.get_name(), "command_line": OS.get_cmdline_args(), "scope": "State fixtures and GUI events; not a full playthrough or physical controller", "source_sha256": {}, "screenshots": []}
	for path in ["scripts/ui/recipe_book.gd", "scripts/ui/achievements_panel.gd", "scripts/ui/achievement_toast.gd", "scripts/ui/ui_kit.gd", "tests/collection_presentation_test.gd", "data/i18n/en.json", "assets/canteen/bg_wall.png", "assets/ui/premium/recipe_spread.png"]:
		if FileAccess.file_exists("res://" + path):
			_report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	for badge in ["meal", "growth", "recipe", "balance", "kitchen", "gold"]:
		var path := "assets/ui/premium/badge_%s.png" % badge
		if FileAccess.file_exists("res://" + path):
			_report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	_host = Control.new()
	_host.size = Vector2(1920, 1080)
	_host.theme = UiKit.build_theme()
	add_child(_host)
	Game.version = 4
	Game.runs = 25
	Game.achievements = {"first_meal": 1, "recipe_first": 1, "release_r1": 1, "balanced": 1, "gold_box": 1}
	Game.levels = {"start": 1, "stall_wok": 2, "stall_dim": 2, "stall_fry": 2, "stall_sweet": 2}
	Game.recipes_revealed = false
	Game._recompute()
	CanteenRun.load_menu()
	for locale in ["zh_CN", "en"]:
		Settings.language = locale
		TranslationServer.set_locale(locale)
		Game.recipes = {}
		for i in CanteenRun.RECIPES.size():
			if i % 3 != 0:
				Game.recipes[CanteenRun.RECIPES[i].id] = i + 1
		await _exercise_title(locale)
		await _exercise_pause(locale)
		await _exercise_recipe_reveal(locale)
	await _exercise_toast_timing()
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before, "player settings unchanged")
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_before, "player progress unchanged")
	_report["failures"] = _fails
	if not _shots.is_empty():
		var file := FileAccess.open(_shots.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_report, "\t"))
	print("COLLECTION_PRESENTATION_TEST: %d failures" % _fails.size())
	_finish.call_deferred()


func _exercise_title(locale: String) -> void:
	var title := TitleScreen.new()
	_host.add_child(title)
	await _frames(5)
	title._buttons[1].grab_focus()
	await _key(KEY_ENTER)
	var book: RecipeBook = _find(title, "RecipeBook")
	_check(book != null, "title Enter opens cookbook: " + locale)
	if book == null:
		title.queue_free()
		return
	_check(_count_scrolls(book) == 0, "cookbook has no scrolling surface")
	_check(book._page == "index" and book._index_buttons.size() == 3, "cookbook starts at its navigable contents")
	_assert_layout(book, locale + " contents")
	await _shot(locale + "_book_contents")
	await _mouse(book._index_buttons[0].get_global_rect().get_center())
	_check(book._page == "sets", "mouse contents link opens recipe chapter")
	await _mouse(book._next.get_global_rect().get_center())
	_check(book._spread == 1, "mouse Next turns one spread")
	for chapter in [1, 2, 3]:
		book._tabs[chapter].grab_focus()
		await _pad(JOY_BUTTON_A)
		_check(book._page == RecipeBook.CHAPTERS[chapter], "pad A activates chapter bookmark")
		for spread in book._page_count:
			_check(book._spread == spread, "one input turns exactly one two-page spread")
			_assert_layout(book, locale + " " + book._page + " " + str(spread))
			_check(book._entry_controls.size() <= (4 if chapter == 1 else (6 if chapter == 2 else 2)), "spread uses bounded content capacity")
			if spread == 0 or spread == book._page_count - 1:
				await _shot(locale + "_book_" + book._page + "_" + str(spread))
			if spread < book._page_count - 1:
				await _key(KEY_PAGEDOWN)
		_check(book._next.disabled, "last spread disables Next")
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		_check(book._spread == maxi(0, book._page_count - 2), "LB turns back one spread")
	await _pad(JOY_BUTTON_B)
	_check(not is_instance_valid(book), "B closes cookbook")
	_check(title._buttons[1].has_focus(), "cookbook restores title opener focus")
	var opener: Button = title.find_child("Achievements", true, false)
	opener.grab_focus()
	await _key(KEY_ENTER)
	var panel: AchievementsPanel = _find(title, "AchievementsPanel")
	_check(panel != null, "title Enter opens medal collection")
	if panel != null:
		_check(_count_scrolls(panel) == 0, "medals are browsed by tray, not scroll")
		await _mouse(panel._medals[1].get_global_rect().get_center())
		_check(panel._selected_id == str(panel._medals[1].get_meta("achievement_id")), "mouse medal selection opens its detail")
		var ids: Array[String] = []
		for spread in panel._page_count:
			for medal in panel._medals:
				medal.grab_focus()
				await _frames(2)
				var id := str(medal.get_meta("achievement_id"))
				ids.append(id)
				_check(panel._selected_id == id, "focused medal shows corresponding detail")
				_assert_layout(panel, locale + " achievement " + id)
			if spread == 0 or spread == panel._page_count - 1:
				await _shot(locale + "_medals_" + str(spread))
			if spread < panel._page_count - 1:
				await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		_check(ids.size() == Game.achievement_catalog().size(), "every achievement has exactly one visible tray slot")
		panel._category_buttons[3].grab_focus()
		await _key(KEY_ENTER)
		_check(panel._filtered.size() == 4 and panel._group == "菜谱收藏", "category filters recipe medals")
		await _key(KEY_RIGHT)
		_check(panel._medals[0].has_focus(), "Right moves from categories into medals")
		await _shot(locale + "_medals_recipes")
		panel._medals[1].grab_focus()
		var selected_before := panel._selected_id
		TranslationServer.set_locale("en" if locale == "zh_CN" else "zh_CN")
		Settings.changed.emit()
		await _frames(3)
		_check(panel._selected_id == selected_before and get_viewport().gui_get_focus_owner().get_meta("achievement_id", "") == selected_before, "language rebuild preserves selected medal and focus")
		TranslationServer.set_locale(locale)
		Settings.changed.emit()
		await _frames(3)
		await _key(KEY_ESCAPE)
		_check(not is_instance_valid(panel) and opener.has_focus(), "Esc closes collection and restores title focus")
	var toast := AchievementToast.new()
	_host.add_child(toast)
	await _frames(2)
	var before := get_viewport().gui_get_focus_owner()
	toast._enqueue("gold_box")
	await _frames(2)
	_check(toast._card.visible and get_viewport().gui_get_focus_owner() == before, "medal toast never steals focus")
	_check(toast._badge.texture != null and toast._badge.size == Vector2(104, 104), "toast uses a legible dedicated small-icon area")
	await _shot(locale + "_medal_toast")
	toast.queue_free()
	title.queue_free()
	await _frames(3)


func _exercise_pause(locale: String) -> void:
	get_tree().paused = true
	var pause := PauseMenu.new()
	_host.add_child(pause)
	await _frames(3)
	pause._buttons[1].grab_focus()
	await _key(KEY_ENTER)
	_check(is_instance_valid(pause._book), "pause Enter opens cookbook")
	if is_instance_valid(pause._book):
		pause._book._tabs[3].grab_focus()
		await _key(KEY_ENTER)
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		await _shot(locale + "_paused_rules")
		await _key(KEY_ESCAPE)
	_check(get_tree().paused and not is_instance_valid(pause._book), "closing book preserves pause")
	_check(pause._buttons[1].has_focus(), "pause opener focus is restored")
	pause.queue_free()
	get_tree().paused = false
	Audio.duck(false)
	await _frames(3)


func _exercise_recipe_reveal(locale: String) -> void:
	var old_levels := Game.levels.duplicate(true)
	var old_recipes := Game.recipes.duplicate(true)
	var old_revealed := Game.recipes_revealed
	Game.recipes = {}
	Game.recipes_revealed = false
	Game.levels.erase("agirec")
	# Open every ingredient so unchanged helper options cannot pass merely because
	# an undiscovered hidden recipe lacks its ingredients or a large enough box.
	for node in Game.nodes:
		if str(node.id).begins_with("stall_"):
			Game.levels[node.id] = int(node.max)
	Game.levels["vram"] = 2
	Game.levels["compress"] = 1
	Game._recompute()
	var hidden_options := Game.helper_recipe_options()
	_check(CanteenRun.RECIPES.size() == 20, "twenty collectible recipes are covered: " + locale)
	for state in ["hidden", "revealed", "made"]:
		if state == "revealed":
			Game.levels["agirec"] = 1
			Game._recompute()
			_check(Game.all_recipes_revealed(), "AGI level one reveals formulas: " + locale)
			_check(Game.recipes.is_empty(), "revealing formulas does not discover recipes: " + locale)
			_check(Game.helper_recipe_options() == hidden_options, "formula reveal does not unlock hidden helper orders: " + locale)
		elif state == "made":
			# A recorded production remains distinct from merely reading its formula.
			Game.recipes = {"deep": 3, "full": 7}
		var recipes_before := Game.recipes.duplicate(true)
		var achievements_before := Game.achievements.duplicate(true)
		var helpers_before := Game.helper_recipe_options()
		var book := RecipeBook.new()
		_host.add_child(book)
		await _frames(3)
		_check(_label_texts(book).has(tr("已发现 %d / %d 道套餐") % [Game.recipes.size(), CanteenRun.RECIPES.size()]), "contents counts actual discoveries: " + locale + " " + state)
		await _mouse(book._index_buttons[0].get_global_rect().get_center())
		var seen: Array[String] = []
		for spread in book._page_count:
			_check(book._spread == spread, "revealed chapter turns exactly one spread: " + locale + " " + state)
			var entries: Array = []
			for side in 2:
				var leaf := spread * 2 + side
				if leaf < book._leaves.size():
					entries.append_array(book._leaves[leaf])
			_check(entries.size() == book._entry_controls.size(), "every recipe on the spread has a visible entry")
			for i in mini(entries.size(), book._entry_controls.size()):
				var recipe: Dictionary = entries[i]
				var entry: Control = book._entry_controls[i]
				var texts := _label_texts(entry)
				var context: String = locale + " " + state + " " + str(recipe.id)
				_check(not seen.has(str(recipe.id)), "recipe appears once: " + context)
				seen.append(str(recipe.id))
				if state == "hidden":
					_check(texts.has(tr("未发现的套餐")), "unrevealed recipe keeps its concealed title: " + context)
					_check(texts.has(tr(recipe.hint) if recipe.hint != "" else tr("还没吃到过")), "unrevealed recipe keeps its hint: " + context)
				else:
					_check(texts.has(tr(recipe.name)), "revealed recipe shows its actual title: " + context)
					var ingredients: Array[String] = []
					for need in recipe.needs:
						ingredients.append(tr(CanteenRun.NAMES[need]))
					_check(texts.has(" + ".join(ingredients)), "revealed recipe shows all direct ingredients: " + context)
					var status := tr("已制作 %d 次") % int(Game.recipes[recipe.id]) if Game.recipes.has(recipe.id) else tr("尚未制作")
					_check(texts.has(status), "reading and actual production have distinct statuses: " + context)
					if recipe.id == "full":
						_check(texts.has(tr("子套餐配方")), "full recipe displays its nested-formula heading: " + context)
						var body := "\n".join(texts)
						for parts in [["egg_veg", "egg", "veg"], ["homestyle", "bowl", "egg_veg"], ["happy", "burger", "fries", "cola"], ["breakfast", "soymilk", "youtiao"], ["tea", "pudding", "milktea"]]:
							var names: Array[String] = []
							for id in parts.slice(1):
								names.append(tr(CanteenRun.NAMES[CanteenRun.KIND[id]]))
							var formula := "%s = %s" % [tr(CanteenRun.NAMES[CanteenRun.KIND[parts[0]]]), " + ".join(names)]
							_check(body.contains(formula), "full recipe expands subrecipe through raw ingredients: " + context + " " + str(parts[0]))
				for child in entry.get_children():
					if child is TextureRect:
						_check(child.modulate.is_equal_approx(Color.WHITE) == Game.recipes.has(recipe.id), "only produced dishes have bright artwork: " + context)
			_assert_layout(book, locale + " " + state + " sets " + str(spread))
			if state == "revealed":
				await _shot(locale + "_revealed_sets_" + str(spread))
			if spread < book._page_count - 1:
				await _key(KEY_PAGEDOWN)
		_check(seen.size() == CanteenRun.RECIPES.size(), "every recipe is browsable in this state: " + locale + " " + state)
		await _key(KEY_ESCAPE)
		_check(not is_instance_valid(book), "revealed cookbook closes normally: " + locale + " " + state)
		_check(Game.recipes == recipes_before, "browsing leaves recipe discovery and production counts unchanged: " + locale + " " + state)
		_check(Game.achievements == achievements_before, "browsing leaves achievements unchanged: " + locale + " " + state)
		_check(Game.helper_recipe_options() == helpers_before, "browsing leaves helper recipe choices unchanged: " + locale + " " + state)
	Game.levels = old_levels
	Game.recipes = old_recipes
	Game.recipes_revealed = old_revealed
	Game._recompute()


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label and node.is_visible_in_tree():
		texts.append(node.text)
	for child in node.get_children():
		texts.append_array(_label_texts(child))
	return texts


func _exercise_toast_timing() -> void:
	var run := QuietRun.new()
	_host.add_child(run)
	var toast := AchievementToast.new()
	_host.add_child(toast)
	toast._enqueue("first_meal")
	toast._enqueue("gold_box")
	await _frames(5)
	_check(not toast._card.visible and toast._pending == ["first_meal", "gold_box"], "live shift defers every medal and preserves queue order")
	_check(toast._run != null and toast._run.get_ref() == run, "deferred toast caches the existing run")
	run._ended = true
	await _frames(3)
	_check(toast._card.visible and toast._current_id == "first_meal" and toast._pending == ["gold_box"], "settlement shows the oldest queued medal")
	run.queue_free()
	await _frames(2)
	var next_run := QuietRun.new()
	_host.add_child(next_run)
	await _frames(3)
	_check(not toast._card.visible and toast._pending == ["first_meal", "gold_box"], "starting another shift requeues the visible medal without losing later medals")
	next_run.queue_free()
	await _frames(3)
	_check(toast._card.visible and toast._current_id == "first_meal", "leaving a shift releases the queue even without settlement")
	toast._remaining = 0.01
	toast._process(0.02)
	await _frames(3)
	_check(toast._card.visible and toast._current_id == "gold_box" and toast._pending.is_empty(), "deferred medals eventually display once in their original order")
	toast.queue_free()
	await _frames(3)


func _assert_layout(node: Node, context: String) -> void:
	if node is TextureRect and node.has_meta("collection_rect_size"):
		_check(node.size.is_equal_approx(node.get_meta("collection_rect_size")), context + " image keeps its designed display size")
	if node is Label and node.has_meta("collection_rect_size"):
		var reserved: Vector2 = node.get_meta("collection_rect_size")
		if node.size.y > reserved.y + 1.0:
			_check(false, context + " text exceeds its reserved height: " + node.text)
		if not Rect2(0, 0, 1920, 1080).encloses(node.get_global_rect()):
			_check(false, context + " text leaves viewport: " + node.text)
	for child in node.get_children():
		_assert_layout(child, context)


func _count_scrolls(node: Node) -> int:
	var count := 1 if node is ScrollContainer else 0
	for child in node.get_children():
		count += _count_scrolls(child)
	return count


func _find(node: Node, type_name: String):
	if node.get_script() != null and node.get_script().get_global_name() == type_name:
		return node
	for child in node.get_children():
		var found = _find(child, type_name)
		if found != null:
			return found
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails.append(label)
		push_error(label)


func _frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _mouse(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await _frames(2)


func _shot(name: String) -> void:
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(6)
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(_shots.path_join(name + ".png"))
	_report.screenshots.append({"file": name + ".png", "width": shot.get_width(), "height": shot.get_height()})


func _finish() -> void:
	_host.queue_free()
	await _frames(3)
	Audio._exit_tree()
	await get_tree().create_timer(0.15, true, false, true).timeout
	UiKit.clear_cache()
	await _frames(2)
	get_tree().quit(_fails.size())
