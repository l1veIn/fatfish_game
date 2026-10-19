extends Node
## No mouse events or replacement production methods. Progress and falling-food placement
## are fixtures; navigation, movement, pickup, delivery and thinking use the real viewport.
## --headless --path game res://tests/input_access_test.tscn -- --test-profile=input_access --out=...

var _main: Node
var _checks: Array = []
var _fails: Array[String] = []
var _out := ""
var _source := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.save_path != "user://qa_input_access.json" or Settings._config_path != "user://qa_input_access_settings.cfg":
		push_error("Use --test-profile=input_access; refusing player files")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	if _out != "": DirAccess.make_dir_recursive_absolute(_out)
	var player_save := FileAccess.get_file_as_bytes("user://save.json")
	var player_settings := FileAccess.get_file_as_bytes(Settings.PATH)
	for path in ["scripts/main.gd", "scripts/autoload/settings.gd", "scripts/tree/tree_screen.gd", "scripts/run/canteen_run.gd", "scripts/ui/run_coach.gd", "scripts/ui/recipe_book.gd", "scripts/ui/pause_menu.gd", "scripts/ui/settings_panel.gd", "scripts/ui/meal_planner.gd", "scripts/ui/crew_planner_panel.gd", "scripts/ui/canteen_overlay.gd", "tests/input_access_test.gd", "data/i18n/en.json"]:
		_source[path] = FileAccess.get_sha256("res://" + path)
	Settings.reset_bindings()
	Settings.reduced_motion = true
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	await _dynamic_hints()
	await _tree_tools()
	for pad in [false, true]:
		await _route(pad)
	Settings.reset_bindings()
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_save, "player save bytes unchanged")
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == player_settings, "player settings bytes unchanged")
	var report := {"passed": _fails.is_empty(), "checks": _checks, "failures": _fails, "source_sha256": _source,
		"scope": "Headless real keyboard and simulated-controller viewport events; no mouse events, no method stubs. Progress, disabled random spoons, and nearby falling food are fixtures. Not a human full playthrough or hardware/controller/Steam Deck validation.",
		"english_copy": "shipped data/i18n/en.json only; no injected translation", "renderer": DisplayServer.get_name()}
	if _out != "": FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("INPUT_ACCESS_TEST %s checks=%d failures=%d" % ["PASS" if _fails.is_empty() else "FAIL", _checks.size(), _fails.size()])
	Audio._exit_tree()
	await _wait(0.15)
	UiKit.clear_cache()
	get_tree().quit(0 if _fails.is_empty() else 1)


func _dynamic_hints() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var coach := RunCoach.new()
	host.add_child(coach)
	await _key(KEY_UP)
	_check(coach._device == "keyboard" and coach._instruction.text.contains(Settings.binding_label("deliver")), "coach selects keyboard labels from real input")
	_bind("deliver", "keyboard", _key_event(KEY_F))
	_check(coach._instruction.text.contains("F") and not coach._instruction.text.contains("E / Enter"), "open coach refreshes immediately after binding changes")
	_bind("deliver", "gamepad", _pad_event(JOY_BUTTON_RIGHT_STICK))
	await _pad(JOY_BUTTON_A)
	_check(coach._device == "pad" and coach._instruction.text.contains("R3"), "coach shows remapped controller action")
	for language in ["zh_CN", "en"]:
		Settings.language = language
		Settings.apply()
		for device in ["keyboard", "pad"]:
			coach._device = device
			for step in [RunCoach.Step.TAKE, RunCoach.Step.CATCH, RunCoach.Step.SERVE]:
				coach.step = step
				coach._refresh()
				await _wait()
				_check(coach._instruction.get_line_count() * coach._instruction.get_line_height() <= 74 + 1, "%s %s coach step %d fits two-line ticket" % [language, device, step])
				_check(coach._instruction.get_rect().end.y <= coach._footer.position.y, "%s %s coach instruction clears footer" % [language, device])
				if language == "en": _check(_english(coach._instruction.text), "shipped English coach prompt is translated")
	coach.queue_free()
	await _wait()
	var book := RecipeBook.new()
	host.add_child(book)
	await _wait()
	for i in 3: await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_check(book._page == "rules", "book rules reachable through only keyboard focus")
	_bind("think", "keyboard", _key_event(KEY_Q))
	_check(book._tabs[3].has_focus(), "book binding refresh preserves its focused chapter")
	_check(str(book._rules()[0][1]).contains("F") and str(book._rules()[4][1]).contains("Q"), "book pickup and thinking instructions reflect custom bindings")
	for language in ["zh_CN", "en"]:
		Settings.language = language
		Settings.apply()
		await _wait()
		for spread in book._page_count:
			await _wait()
			for entry in book._entry_controls:
				for child in entry.get_children():
					if child is Label:
						var intended: Vector2 = child.get_meta("collection_rect_size")
						_check(child.get_line_count() * child.get_line_height() <= intended.y + 1, "%s book text fits assigned height: %s" % [language, child.text.left(38)])
						if language == "en": _check(_english(child.text), "shipped English book text is translated: " + child.text.left(32))
			if spread < book._page_count - 1: await _key(KEY_PAGEDOWN)
		for i in book._page_count - 1: await _key(KEY_PAGEUP)
	await _pad(JOY_BUTTON_B)
	_check(not is_instance_valid(book), "controller B closes book while deliver is remapped")
	host.queue_free()
	await _wait()
	Settings.language = "zh_CN"
	Settings.apply()


func _tree_tools() -> void:
	Settings.reset_bindings()
	Game.reset_save()
	Game.version = 4
	Game.runs = 10
	Game.tokens = 10000000
	Game.levels = {"start": 1, "stall_main": 2, "stall_wok": 1, "menu": 1, "moe": 1, "hire": 2, "ticket_agi": 1}
	Game.seen_buttons = {"menu": true, "sigs": true, "menu_card": true, "sigs_card": true}
	Game._recompute()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.15)
	await _pad(JOY_BUTTON_A)
	var tree: TreeScreen = _main._screen
	await _pad(JOY_BUTTON_BACK)
	var targets: Array = tree._tool_targets()
	_check(targets.size() == 9, "late-game fixture exposes six toolbar items, helper, trial and meal actions")
	for target in targets:
		_check(target.has_focus(), "D-pad reaches visible tree tool: " + str(target.name))
		await _pad(JOY_BUTTON_DPAD_RIGHT)
	_check(targets[0].has_focus(), "controller tool direction chain wraps without losing focus")
	for name in ["Tree_book", "Tree_menu", "Tree_sigs", "Tree_crew", "Tree_settings"]:
		var target: Control = tree.find_child(name, true, false)
		for i in targets.size():
			if target.has_focus(): break
			await _pad(JOY_BUTTON_DPAD_RIGHT)
		_check(target.has_focus(), "controller reaches named tree tool: " + name)
		await _pad(JOY_BUTTON_A)
		var modal: Control
		match name:
			"Tree_book": modal = tree._book
			"Tree_menu", "Tree_sigs": modal = tree._planner
			"Tree_crew": modal = tree._crew_planner
			"Tree_settings":
				for child in tree.get_children():
					if child is SettingsPanel: modal = child
		_check(is_instance_valid(modal), "controller activates actual tree tool: " + name)
		if not is_instance_valid(modal): continue
		await _pad(JOY_BUTTON_BACK)
		var focus := get_viewport().gui_get_focus_owner()
		_check(is_instance_valid(focus) and modal.is_ancestor_of(focus), "Back cannot steal focus through open tree modal: " + name)
		await _pad(JOY_BUTTON_B)
		_check(not is_instance_valid(modal) and target.has_focus(), "controller closes modal and restores its tree tool: " + name)
	await _pad(JOY_BUTTON_BACK)
	_check(tree.has_focus(), "Back toggles tools back to map")
	await _pad(JOY_BUTTON_BACK)
	await _pad(JOY_BUTTON_B)
	_check(tree.has_focus(), "B independently returns tools to map")
	_main.queue_free()
	await _wait(0.15)


func _english(text: String) -> bool:
	return RegEx.create_from_string("[\u4e00-\u9fff]").search(text) == null


func _route(pad: bool) -> void:
	Settings.reset_bindings()
	_bind("move_left", "keyboard", _key_event(KEY_J))
	_bind("move_right", "keyboard", _key_event(KEY_L))
	_bind("move_up", "keyboard", _key_event(KEY_I))
	_bind("move_down", "keyboard", _key_event(KEY_K))
	_bind("deliver", "keyboard", _key_event(KEY_F))
	_bind("think", "keyboard", _key_event(KEY_Q))
	_bind("start_shift", "keyboard", _key_event(KEY_H))
	_bind("refund", "keyboard", _key_event(KEY_R))
	_bind("deliver", "gamepad", _pad_event(JOY_BUTTON_RIGHT_STICK))
	_bind("think", "gamepad", _pad_event(JOY_BUTTON_LEFT_SHOULDER))
	Game.reset_save()
	Game.version = 1
	Game.runs = 1
	Game.tokens = 50000
	Game.levels = {"start": 1, "stall_main": 1}
	Game.seen_buttons = {"menu": true, "sigs": true, "menu_card": true, "sigs_card": true, "intro_think": true, "intro_canteen_started": true}
	Game._recompute()
	seed(2026102007)
	var name := "pad" if pad else "keyboard"
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.15)
	_check(_main._screen is TitleScreen and _main._screen._buttons[0].has_focus(), name + " title begins with usable focus")
	await _accept(pad)
	_check(_main._screen is TreeScreen and _main._screen.has_focus(), name + " confirm enters focused skill tree")
	var tree: TreeScreen = _main._screen
	if pad:
		await _pad(JOY_BUTTON_BACK)
		_check(not tree.has_focus() and get_viewport().gui_get_focus_owner() != null, "pad Back reaches skill-tree tools from map")
		await _pad(JOY_BUTTON_B)
		_check(tree.has_focus(), "pad cancel returns from skill-tree tools to map")
	else:
		for tool in [tree.find_child("Tree_book", true, false), tree._crew_button]:
			for i in 20:
				if tool.has_focus(): break
				await _key(KEY_TAB)
			_check(tool.has_focus(), "keyboard Tab reaches tree tool: " + tool.name)
			await _accept(false)
			_check(is_instance_valid(tree._book) or is_instance_valid(tree._crew_planner), "keyboard activates tree tool: " + tool.name)
			await _cancel(false)
			_check(tool.has_focus(), "keyboard child modal restores tree tool: " + tool.name)
		for i in 20:
			if tree.has_focus(): break
			await _key(KEY_TAB)
		_check(tree.has_focus(), "keyboard Tab returns from tree tools to map")
	await _direction(pad, "left") # first direction selects start
	await _direction(pad, "left") # authored next visible ticket is wok
	_check(tree._hover != "" and tree._hover != "start", name + " directions select a skill without mouse")
	var id: String = tree._hover
	var before: int = Game.level(id)
	await _accept(pad)
	_check(Game.level(id) == before + 1, name + " fixed menu confirm buys selected skill after deliver rebind")
	await _pad(JOY_BUTTON_X) if pad else await _key(KEY_R)
	_check(Game.level(id) == 0, name + " refund action reaches selected skill")
	await _pad(JOY_BUTTON_Y) if pad else await _key(KEY_H)
	_check(_main._screen is CanteenRun, name + " start action enters meal")
	var run: CanteenRun = _main._screen
	run._arms.clear() # deterministic food source fixture, never a replacement input/physics method
	_check(run._learning(), name + " lesson starts without timing pressure")
	await _deliver(pad)
	_check(run._hand != null and run._coach.step == RunCoach.Step.CATCH, name + " remapped deliver takes a box at table")
	if run._hand == null:
		_main.queue_free()
		await _wait()
		return
	var before_pos: Vector2 = run._hand.pos
	await _move(pad, -1.0, 0.35)
	_check(run._hand.pos.x < before_pos.x - 100, name + " movement steers the actual box")
	await _wait(0.2)
	var caught_before: int = run.caught
	run._add_item(run._hand.pos + Vector2(0, -8), Vector2(0, 140), CanteenRun.I.BALL)
	await _wait(0.2)
	_check(run.caught == caught_before + 1 and run._coach.step == RunCoach.Step.SERVE, name + " real falling collision advances lesson")
	await _move(pad, 1.0, 0.35)
	await _wait(0.2)
	await _deliver(pad)
	_check(run._hand == null and not run._learning(), name + " return movement and remapped deliver finish first service")
	var think: InputEvent = _pad_event(JOY_BUTTON_LEFT_SHOULDER) if pad else _key_event(KEY_Q)
	Input.parse_input_event(think)
	await _wait(0.08)
	_check(run._thinking, name + " remapped think action enters slow motion")
	think = think.duplicate()
	think.pressed = false
	Input.parse_input_event(think)
	await _wait(0.06)
	_check(not run._thinking and run._think_cooldown > 0, name + " release exits thought with cooldown")
	await _pause(pad)
	_check(get_tree().paused and is_instance_valid(run._pause), name + " fixed pause works after rebind")
	var pause_menu: PauseMenu = run._pause
	await _direction(pad, "down")
	await _accept(pad)
	_check(is_instance_valid(pause_menu._book), name + " pause book is reachable by navigation")
	await _cancel(pad)
	_check(get_tree().paused and pause_menu._buttons[1].has_focus(), name + " closing book restores pause opener focus")
	await _direction(pad, "down")
	await _accept(pad)
	_check(is_instance_valid(pause_menu._settings), name + " pause settings is reachable by navigation")
	await _cancel(pad)
	_check(get_tree().paused and pause_menu._buttons[2].has_focus(), name + " closing settings restores pause opener focus")
	await _direction(pad, "down")
	await _accept(pad)
	var hud: Control = run._service_ui
	_check(is_instance_valid(hud._modal), name + " pause stall guide is reachable by navigation")
	var old_order: Array = run.stall_order.duplicate()
	await _direction(pad, "down")
	await _accept(pad)
	_check(run.stall_order != old_order, name + " move action rearranges a real stall without mouse")
	await _cancel(pad)
	_check(get_tree().paused and pause_menu._stall_button.has_focus(), name + " closing guide returns focus and keeps pause")
	await _direction(pad, "down")
	await _accept(pad)
	_check(not get_tree().paused and run._ended, name + " early-end action closes paused world normally")
	await _wait(1.25)
	await _accept(pad)
	await _wait(0.65)
	await _accept(pad)
	_check(_main._screen is TreeScreen and _main._screen.has_focus(), name + " settlement confirm returns to playable skill tree")
	_main.queue_free()
	await _wait(0.15)


func _bind(action: String, device: String, event: InputEvent) -> void:
	_check(Settings.set_binding(action, device, event).is_empty(), "bind " + action + " " + device)


func _check(ok: bool, message: String) -> void:
	_checks.append({"ok": ok, "description": message})
	if not ok:
		_fails.append(message)
		push_error("INPUT_ACCESS: " + message)


func _wait(seconds := 0.06) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	return event


func _pad_event(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _tap(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await _wait(0.04)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _wait()


func _key(code: Key) -> void:
	await _tap(_key_event(code))


func _pad(button: JoyButton) -> void:
	await _tap(_pad_event(button))


func _direction(pad: bool, direction: String) -> void:
	if pad:
		await _pad({"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "down": JOY_BUTTON_DPAD_DOWN}[direction])
	else:
		await _key({"left": KEY_LEFT, "right": KEY_RIGHT, "down": KEY_DOWN}[direction])


func _accept(pad: bool) -> void:
	if pad: await _pad(JOY_BUTTON_A)
	else: await _key(KEY_ENTER)


func _cancel(pad: bool) -> void:
	if pad: await _pad(JOY_BUTTON_B)
	else: await _key(KEY_ESCAPE)


func _pause(pad: bool) -> void:
	if pad: await _pad(JOY_BUTTON_START)
	else: await _key(KEY_ESCAPE)


func _deliver(pad: bool) -> void:
	if pad: await _pad(JOY_BUTTON_RIGHT_STICK)
	else: await _key(KEY_F)


func _move(pad: bool, direction: float, duration: float) -> void:
	if pad:
		var event := InputEventJoypadMotion.new()
		event.axis = JOY_AXIS_LEFT_X
		event.axis_value = direction
		Input.parse_input_event(event)
		await _wait(duration)
		event = event.duplicate()
		event.axis_value = 0
		Input.parse_input_event(event)
	else:
		var event := _key_event(KEY_J if direction < 0 else KEY_L)
		Input.parse_input_event(event)
		await _wait(duration)
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
	await _wait()
