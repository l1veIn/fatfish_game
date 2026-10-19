extends Node
## Isolated real mouse / keyboard / pad events; GPU screenshots are optional and serialized.
## --headless --path game res://tests/stall_layout_ui_test.tscn -- --test-profile=stall_layout_ui
## Optional: --out=<absolute path> --small --render-size=1280x720 --lang=en
var _run: CanteenRun
var _hud: Control
var _failures: Array[String] = []
var _checks: Array = []
var _out := ""
var _window := Vector2i(1920, 1080)
var _shots := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().has("--test-profile=stall_layout_ui") or Game.save_path != "user://qa_stall_layout_ui.json" or not Settings._testing:
		push_error("Use isolated --test-profile=stall_layout_ui")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg == "--small":
			_window = Vector2i(960, 540)
		if arg.begins_with("--render-size="):
			var dimensions := arg.trim_prefix("--render-size=").split("x")
			if dimensions.size() == 2:
				var requested := Vector2i(int(dimensions[0]), int(dimensions[1]))
				if requested in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
					_window = requested
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://../build/qa/stall-layout-ui-" + Settings.language)
	DirAccess.make_dir_recursive_absolute(_out)
	var player_before := FileAccess.get_file_as_bytes("user://save.json")
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	Settings.pause_unfocused = false
	Settings.hit_pause = false
	Settings.reduced_motion = true
	Settings.fullscreen = false
	Settings.window_size = _window
	Settings.apply()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(_window)
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Game.reset_save()
	Game.version = 4
	Game.levels = {"start": 1, "stall_main": 1, "stall_wok": 3, "stall_dim": 2, "conc": 2}
	Game.seen_buttons["intro_canteen_complete"] = true
	Game.seen_buttons["intro_think"] = true
	Game._recompute()
	seed(2026101905)
	_run = CanteenRun.new()
	_run.autotest = true
	add_child(_run)
	_hud = _run._service_ui
	await _frames()
	await _key(KEY_ESCAPE)
	_check(get_tree().paused and is_instance_valid(_run._pause), "Escape opens the existing pause menu")
	var pause_menu: PauseMenu = _run._pause
	for i in 3:
		await _key(KEY_DOWN)
	_check(pause_menu._stall_button.has_focus(), "keyboard reaches the guide from resume")
	await _key(KEY_ENTER)
	_check(is_instance_valid(_hud._modal), "Enter opens the stall guide")
	_check(_hud._selected_id == "main" and _hud._selected == 2, "initial selection is the main-food identity")
	var modal: Control = _hud._modal
	_hud.open_guide(2, pause_menu)
	_check(_hud._modal == modal, "guide remains a singleton")
	var time_before := _run._t
	var arms_before: Array = _run._arms.duplicate(true)
	await _shot("guide_default")
	await _click(_hud._tabs[1].get_global_rect().get_center())
	_check(_hud._selected_id == "wok", "mouse selects wok by its pictured sign")
	await _click(_hud._move_right.get_global_rect().get_center())
	_check(_run.stall_order == ["dim", "main", "wok", "fry", "sweet"], "mouse move-right applies the physical order immediately")
	_check(_hud._selected_id == "wok" and _hud._selected == 2, "selection follows moved identity")
	_check(_hud._move_right.has_focus(), "move refresh preserves the clicked action focus")
	_check(Game.active_stall_order() == _run.stall_order, "active saved order matches the paused shift")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(saved.get("stall_order", []) == _run.stall_order, "reorder is persisted to the isolated save immediately")
	_check_arms(arms_before)
	await _shot("wok_moved")
	# Expose the real counter as well as the editor: this capture can show that signs and
	# future food sources actually moved, instead of covering the world with a modal.
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	await _shot("counter_moved")
	await _key(KEY_ESCAPE)
	pause_menu = _run._pause
	pause_menu._stall_button.grab_focus()
	await _key(KEY_ENTER)
	_check(_hud._selected_id == "wok" and _hud._selected == 2, "resumed shift reopens the same moved identity")
	time_before = _run._t
	arms_before = _run._arms.duplicate(true)
	_hud._move_right.grab_focus()
	await _pad(JOY_BUTTON_DPAD_UP)
	_check(_hud._tabs[2].has_focus(), "pad up returns to the selected sign")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	_check(_hud._selected_id == "main" and _hud._selected == 1, "pad selects the neighboring identity")
	await _key(KEY_DOWN)
	_check(_hud._move_left.has_focus(), "keyboard down enters the move actions")
	await _key(KEY_ENTER)
	_check(_run.stall_order[0] == "main" and _hud._selected == 0, "keyboard moves the selected stall to the left edge")
	_check(_hud._move_left.disabled and _hud._tabs[0].has_focus(), "disabled edge action restores focus to selected sign")
	await _pad(JOY_BUTTON_B)
	_check(get_tree().paused and not is_instance_valid(_hud._modal), "pad cancel closes only the guide")
	_check(pause_menu._stall_button.has_focus(), "cancel restores the guide entry focus")
	await _key(KEY_ENTER)
	_check(_hud._selected_id == "main" and _hud._selected == 0, "reopening remembers identity after movement")
	await _click(_hud._tabs[4].get_global_rect().get_center())
	_check(_hud._selected_id == "sweet" and int(_run.stall_lv.sweet) == 0, "closed stall remains selectable")
	_hud._move_left.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(_run.stall_order[3] == "sweet" and _hud._selected_id == "sweet", "pad moves a closed stall without opening it")
	_check(int(_run.stall_lv.sweet) == 0, "moving a closed stall does not grant a level")
	_check(_hud._tabs[3].get_node("Sign").modulate.r < 0.9, "closed sign remains visibly muted after movement")
	await _shot("closed_stall_moved")
	_hud._reset_order.grab_focus()
	await _key(KEY_ENTER)
	_check(_run.stall_order == Game.DEFAULT_STALL_ORDER, "Enter restores the default layout")
	_check(_hud._selected_id == "sweet" and _hud._selected == 4, "default restore preserves selected identity")
	_check(_hud._reset_order.disabled and _hud._tabs[4].has_focus(), "default action disables and restores usable focus")
	for i in 5:
		await _click(_hud._tabs[i].get_global_rect().get_center())
		_check(_hud._selected == i, "legacy tab index remains compatible: %d" % i)
		_bounds(_hud._modal)
		await _shot("guide_stall_%d" % i)
	_check(is_equal_approx(_run._t, time_before), "guide editing never advances meal time")
	_check_arms(arms_before)
	_hud._close_button.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(get_tree().paused and not is_instance_valid(_hud._modal), "explicit back returns to paused menu")
	_check(pause_menu._stall_button.has_focus(), "explicit back restores pause focus")
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	_check(get_tree().paused and not is_instance_valid(_hud._modal), "Escape closes guide without resuming")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused and not is_instance_valid(_run._pause), "second Escape resumes the original shift")
	await _shot("counter_default")
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_before, "player save remains byte-identical")
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before, "player settings remain byte-identical")
	var report := {"checks": _checks, "failures": _failures, "passed": _failures.is_empty(), "language": Settings.language,
		"requested_size": str(_window), "window_size": str(DisplayServer.window_get_size()), "screenshots": _shots,
		"scope": "Isolated real GUI events for pause/layout/selection/persistence; no human play or visual quality claim", "source_sha256": {}}
	for path in ["scripts/ui/canteen_overlay.gd", "scripts/ui/pause_menu.gd", "scripts/run/canteen_run.gd", "scripts/autoload/game.gd", "tests/stall_layout_ui_test.gd", "data/i18n/en.json"]:
		report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	Fx.world = null
	_run.queue_free()
	await _frames()
	Audio.set_process(false)
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.15, true, false, true).timeout
	print("STALL_LAYOUT_UI_TEST %s checks=%d failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _checks.size(), _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_arms(before: Array) -> void:
	_check(_run._arms.size() == before.size(), "layout keeps the existing spoon count")
	for i in before.size():
		for field in ["stall", "dish", "t", "t0", "raise"]:
			_check(_run._arms[i][field] == before[i][field], "layout preserves spoon %d %s" % [i, field])


func _bounds(node: Node) -> void:
	if node is Label and node.has_meta("stall_rect"):
		var intended: Vector2 = node.get_meta("stall_rect")
		_check(node.get_line_count() * node.get_line_height() <= intended.y + 1.0, "label lines fit: " + node.text)
		_check(node.size.y <= intended.y + 1.0, "label keeps assigned height (%.0f / %.0f): %s" % [node.size.y, intended.y, node.text])
		_check(Rect2(160, 80, 1600, 920).encloses(node.get_global_rect()), "label stays on guide paper: " + node.text)
		if Settings.language == "en":
			_check(RegEx.create_from_string("[\u4e00-\u9fff]").search(node.text) == null, "English guide has translated copy: " + node.text)
	for child in node.get_children():
		_bounds(child)


func _shot(name: String) -> void:
	if is_instance_valid(_hud._modal):
		_check(_hud._layout_hint.get_global_rect().end.y <= 446.0, "layout instruction stays above the 452px details row")
		for i in _hud._tabs.size():
			var id: String = _run.stall_order[i]
			_check(_hud._tabs[i].get_meta("stall_id") == id, "sign identity follows slot: " + id)
			var texture: Texture2D = _hud._tabs[i].get_node("Sign").texture
			_check(texture.resource_path.get_file().begins_with(id + "_"), "sign texture follows identity: " + id)
			if i > 0:
				_check(not _hud.stall_rect(i).intersects(_hud.stall_rect(i - 1)), "physical sign bounds do not overlap")
		_bounds(_hud._modal)
	if DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == _window, "native screenshot dimensions: " + name)
	var path := _out.path_join(name + ".png")
	_check(image.save_png(path) == OK, "screenshot saved: " + name)
	_shots[name] = path


func _check(ok: bool, description: String) -> void:
	_checks.append({"ok": ok, "description": description})
	if not ok:
		_failures.append(description)
		push_error("STALL_LAYOUT_UI: " + description)


func _frames() -> void:
	for i in 3:
		await get_tree().process_frame


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
