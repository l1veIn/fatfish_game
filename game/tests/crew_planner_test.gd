extends Node
const Planner := preload("res://scripts/ui/crew_planner_panel.gd")
var _failures: Array[String] = []
var _checks := 0
var _out := ""
var _window := Vector2i(1920, 1080)
var _tree: TreeScreen
var _starts := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().has("--test-profile=crew_planner") or not Game.save_path.begins_with("user://qa_crew_planner") or not Settings._testing:
		push_error("Use --test-profile=crew_planner")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-shots="): _out = arg.trim_prefix("--qa-shots=")
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg in ["--qa-small", "--small"]: _window = Vector2i(960, 540)
	if _out != "": DirAccess.make_dir_recursive_absolute(_out)
	var player_before := FileAccess.get_file_as_bytes("user://save.json")
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	Settings.reduced_motion = true
	Settings.pause_unfocused = false
	Settings.window_size = _window
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Game.version = Game.VERSIONS.size() - 1
	Game.runs = 25
	Game.levels = {}
	for node in Game.nodes:
		if not node.get("locked", false): Game.levels[node.id] = int(node.max)
	Game.levels.hire = 1
	Game.struck = []
	Game.helper_plan = {}
	Game.automation = {}
	Game.seen_buttons = {"menu": true, "sigs": true, "menu_card": true, "sigs_card": true}
	Game._recompute()
	_tree = TreeScreen.new()
	_tree.start_run.connect(func(): _starts += 1)
	add_child(_tree)
	await _frames()
	_check(_tree._crew_button.get_parent() == _tree._bar and _tree._crew_button.text == tr("自动化"), "automation is a top toolbar entry")
	_check(not _tree._bar.get_rect().intersects(_tree._header_rect()), "toolbar clears the original chalkboard in this language")
	_check(_tree._tool_targets().size() == _tree._bar.get_child_count() + 1 + int(_tree._trial.visible), "toolbar focus contains no duplicate automation entry")
	await _click(_tree._crew_button.get_global_rect().get_center())
	var panel = _tree._crew_planner
	_check(is_instance_valid(panel), "mouse opens the helper planner")
	if not is_instance_valid(panel):
		get_tree().quit(1)
		return
	_tree._open_crew()
	_tree._open_menu()
	_tree._open_book()
	_check(_tree._crew_planner == panel and not is_instance_valid(_tree._planner) and not is_instance_valid(_tree._book), "helper modal is singleton and excludes the menu/book")
	var old_pan := _tree._pan
	await _key(KEY_G)
	await _pad(JOY_BUTTON_Y)
	await _click(Vector2(20, 500))
	_check(_starts == 0 and _tree._pan == old_pan, "helper modal blocks start and underlying map input")
	_check(panel._cards.size() == 6 and Game.active_helpers() == ["wen"], "six portraits shown with one inherited active slot")
	await _click(panel._cards.ge.get_global_rect().get_center())
	await _click(panel._activate.get_global_rect().get_center())
	_check(Game.active_helpers() == ["wen"] and panel._notice != "", "full team shows an explicit reason instead of silently replacing someone")
	await _shot("full_team_reason")
	await _click(panel._cards.wen.get_global_rect().get_center())
	await _click(panel._activate.get_global_rect().get_center())
	_check(Game.active_helpers().is_empty(), "mouse puts the current member at rest")
	await _click(panel._cards.ge.get_global_rect().get_center())
	panel._activate.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(Game.active_helpers() == ["ge"], "pad confirmation fills the freed slot with the chosen sixth member")
	_check(get_viewport().gui_get_focus_owner().get_meta("crew_key", "") == "activate", "state refresh restores the edited control's focus")
	panel._role_buttons.recipe.grab_focus()
	await _key(KEY_ENTER)
	_check(Game.helper_config("ge").role == "recipe" and is_instance_valid(panel._recipe_open), "Enter selects recipe work with a dedicated chooser")
	var options := Game.helper_recipe_options()
	var recipe_id: String = options.back().id
	var old_recipe: String = Game.helper_config("ge").recipe
	await _click(panel._recipe_open.get_global_rect().get_center())
	var picker = panel._recipe_picker
	_check(is_instance_valid(picker) and picker._scroll.size.y >= 500, "recipe chooser has a full-height illustrated grid")
	panel._open_recipes()
	_check(panel._recipe_picker == picker, "repeated requests reuse the same recipe chooser")
	picker._cards[recipe_id].grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(picker._pending == recipe_id and Game.helper_config("ge").recipe == old_recipe, "inspecting a recipe does not silently change the assignment")
	await _shot("recipe_picker")
	for i in 20:
		await _key(KEY_TAB)
		_check(picker.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Tab stays within the recipe chooser")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(panel._recipe_picker) and panel._recipe_open.has_focus() and Game.helper_config("ge").recipe == old_recipe, "cancel keeps assignment and returns focus to recipe card")
	await _click(panel._recipe_open.get_global_rect().get_center())
	picker = panel._recipe_picker
	picker._search.text = "no_such_meal_123"
	picker._search.text_changed.emit(picker._search.text)
	_check(picker._cards.is_empty(), "search filters unavailable text without changing the assignment")
	await _shot("recipe_no_matches")
	picker._search.text = ""
	picker._search.text_changed.emit("")
	picker._cards[recipe_id].grab_focus()
	await _pad(JOY_BUTTON_A)
	picker._confirm.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(Game.helper_config("ge").recipe == recipe_id and not is_instance_valid(panel._recipe_picker), "pad confirms the pictured recipe and returns to the roster")
	await _shot("recipe_work")
	Game.levels.fc = 0
	Game._recompute()
	Game.changed.emit()
	await _frames()
	_check(Game.helper_config("ge").role == "sweep" and panel._reason.text != "", "refunded prerequisite displays the effective fallback and reason")
	await _shot("invalid_recipe")
	Game.levels.fc = 1
	Game._recompute()
	Game.changed.emit()
	await _frames()
	panel._role_buttons.nutrition.grab_focus()
	await _key(KEY_ENTER)
	_check(Game.helper_config("ge").role == "nutrition", "nutrition work can be selected")
	await _shot("nutrition_work")
	for id in Game.HELPER_IDS:
		await _click(panel._cards[id].get_global_rect().get_center())
		_bounds(panel)
	panel._tabs[1].grab_focus()
	await _key(KEY_ENTER)
	_check(panel._auto_buttons.size() == 7, "automation includes independent warm-box selection on its own page")
	for id in Game.AUTOMATION_KEYS:
		var was_on: bool = Game.automation_enabled(id)
		await _click(panel._auto_buttons[id].get_global_rect().get_center())
		_check(Game.automation_enabled(id) != was_on, "mouse toggles purchased automation " + id)
		_check(Game.levels.size() > 0, "automation changes do not refund skills")
	await _shot("automation_off")
	panel._auto_buttons.bon.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(Game.automation_enabled("bon"), "controller can restore automatic warm-box selection")
	_check(get_viewport().gui_get_focus_owner().get_meta("crew_key", "") == "auto_bon", "warm-box toggle preserves controller focus after refresh")
	Game.levels.overfit = 0
	Game._recompute()
	Game.changed.emit()
	await _frames()
	_check(panel._auto_buttons.overfit.disabled, "unowned automation is unavailable")
	_bounds(panel)
	await _shot("automation_locked")
	for i in 18:
		await _key(KEY_TAB)
		var focus_owner := get_viewport().gui_get_focus_owner()
		_check(is_instance_valid(focus_owner) and panel.is_ancestor_of(focus_owner), "Tab remains within helper modal")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(_tree._crew_planner) and _tree._crew_button.has_focus(), "Esc closes and restores the tree entry focus")
	_tree._open_menu()
	await _frames()
	_tree._open_crew()
	_check(is_instance_valid(_tree._planner) and not is_instance_valid(_tree._crew_planner), "existing meal planner blocks helper opening")
	await _key(KEY_ESCAPE)
	_tree._crew_button.grab_focus()
	await _key(KEY_ENTER)
	await _pad(JOY_BUTTON_B)
	_check(not is_instance_valid(_tree._crew_planner) and _tree._crew_button.has_focus(), "keyboard open / gamepad B close restores entry")
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_before, "player progress bytes unchanged")
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before, "player settings bytes unchanged")
	if _out != "":
		var report := {"checks": _checks, "failures": _failures, "language": Settings.language, "window": str(_window), "scope": "State fixtures with real mouse/keyboard/simulated-pad GUI events", "source_sha256": {}}
		for path in ["scripts/tree/tree_screen.gd", "scripts/ui/crew_planner_panel.gd", "scripts/ui/helper_recipe_picker.gd", "scripts/autoload/game.gd", "tests/crew_planner_test.gd", "data/i18n/en.json"]:
			report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
		FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("CREW_PLANNER_TEST %s failures=%d checks=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size(), _checks])
	_tree.queue_free()
	await _frames()
	Audio._exit_tree()
	await get_tree().create_timer(0.15).timeout
	UiKit.clear_cache()
	get_tree().quit(_failures.size())


func _bounds(node: Node) -> void:
	if node is Button and node.has_meta("crew_rect"):
		_check(node.size.is_equal_approx(node.get_meta("crew_rect")), "button fits reserved bounds: " + node.text)
	if node is Label and node.has_meta("crew_rect"):
		if Settings.language == "en":
			var chinese := RegEx.create_from_string("[\u4e00-\u9fff]")
			_check(chinese.search(node.text) == null, "English UI uses shipped translations: " + node.text)
		_check(node.size.y <= node.get_meta("crew_rect").y + 1, "text fits reserved height: " + node.text)
		_check(node.get_line_count() * node.get_line_height() <= node.get_meta("crew_rect").y + 1, "all text lines fit: " + node.text)
		# Recipe rows deliberately live in a clipped, focus-following scroll.
		var scrolling := false
		var ancestor := node.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer: scrolling = true
			ancestor = ancestor.get_parent()
		if not scrolling:
			_check(Rect2(0, 0, 1920, 1080).encloses(node.get_global_rect()), "label within viewport: " + node.text)
		for sibling in node.get_parent().get_children():
			if sibling is Label and sibling != node:
				_check(not node.get_rect().intersects(sibling.get_rect()), "adjacent label regions do not overlap: " + node.text)
	if node is TextureRect and node.has_meta("crew_rect"):
		_check(node.size.is_equal_approx(node.get_meta("crew_rect")), "portrait/icon keeps its intended size")
	for child in node.get_children(): _bounds(child)


func _shot(name: String) -> void:
	_bounds(_tree._crew_planner)
	if _out == "" or DisplayServer.get_name() == "headless": return
	await _frames()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == _window, "screenshot uses declared window dimensions")
	image.save_png(_out.path_join(name + ".png"))


func _frames() -> void:
	for i in 3: await get_tree().process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await _frames()


func _pad(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await _frames()


func _click(at: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await _frames()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
		push_error(label)
