extends Node
var _fails: Array[String] = []
var _checks := 0
var _settings: SettingsPanel
var _remap: Control
var _leaks := 0
var _observing := false
var _out := ""
var _window := Vector2i(1280, 720)
var _screenshots: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Settings._testing or not Settings._config_path.begins_with("user://qa_input_remap") or not Game.save_path.begins_with("user://qa_input_remap"):
		push_error("Use --test-profile=input_remap_<suffix>")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg == "--small": _window = Vector2i(960, 540)
	if _out != "":
		if not _out.is_absolute_path(): _out = ProjectSettings.globalize_path("res://../" + _out)
		DirAccess.make_dir_recursive_absolute(_out)
	var player_settings := FileAccess.get_file_as_bytes(Settings.PATH)
	var player_save := FileAccess.get_file_as_bytes("user://save.json")
	Settings.reset_bindings()
	Settings.pause_unfocused = false
	Settings.reduced_motion = true
	Settings.window_size = _window
	Settings.fullscreen = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var opener := UiKit.button("Settings", 28, Vector2(300, 70))
	host.add_child(opener)
	opener.pressed.connect(func():
		_settings = SettingsPanel.new()
		host.add_child(_settings))
	opener.grab_focus()
	await _key(KEY_ENTER)
	_check(is_instance_valid(_settings), "keyboard opens real settings")
	_settings._tabs[3].grab_focus()
	await _key(KEY_ENTER)
	var entry: Button
	for control in _settings._controls:
		if control.get_meta("focus_key") == "input_remap": entry = control
	_check(is_instance_valid(entry), "settings includes a remap entry")
	entry.grab_focus()
	await _shot("01-settings-entry")
	await _pad(JOY_BUTTON_A)
	_remap = _settings._remap
	_check(is_instance_valid(_remap) and _remap._buttons.size() == 8, "controller opens all eight gameplay actions")
	_settings._open_remap()
	_check(_settings._remap == _remap, "remap is a single modal")
	_check_layout(_remap)
	_check_initial_row()
	await _shot("02-default-bindings")
	_observing = true
	await _begin("deliver", "keyboard")
	await _key(KEY_K)
	_check(Settings.binding_label("deliver") == "K" and _remap._capture_action == "", "keyboard captures K after opening Enter is released")
	_check(_event(KEY_K).is_action_pressed("deliver") and not _event(KEY_E).is_action_pressed("deliver"), "new key replaces old keyboard aliases")
	_check(_event(KEY_ENTER).is_action_pressed("ui_accept"), "menu Enter remains fixed after gameplay Enter is removed")
	_check(not Input.is_action_pressed("deliver") and _remap._buttons.deliver.keyboard.has_focus(), "capture consumes held gameplay input and restores edited focus")
	await _begin("think", "keyboard", true)
	await _key(KEY_K)
	_check(_remap._capture_action == "think" and _remap._status.text.contains(tr(Settings.BINDABLE_ACTIONS.deliver)), "conflicting key is rejected and identifies its existing action")
	_check_layout(_remap)
	await _shot("04-conflict-feedback")
	var fullscreen_before := Settings.fullscreen
	await _key(KEY_F11)
	_check(_remap._capture_action == "think" and Settings.fullscreen == fullscreen_before, "reserved fullscreen key is rejected without toggling fullscreen")
	await _key(KEY_ESCAPE)
	_check(is_instance_valid(_remap) and is_instance_valid(_settings) and _remap._capture_action == "", "Escape cancels capture without closing either panel")
	_check(Settings.binding_label("think").contains("Space"), "cancel preserves the old binding")
	await _begin("think", "keyboard")
	var config_before := FileAccess.get_file_as_bytes(Settings._config_path)
	Input.parse_input_event(_event(KEY_J))
	await _frames()
	_check(_remap._pending_event != null and Settings.binding_label("think").contains("Space") and FileAccess.get_file_as_bytes(Settings._config_path) == config_before, "key-down validates a candidate without saving or changing the live binding")
	_check_layout(_remap)
	await _shot("03-capture-candidate")
	await _key(KEY_ESCAPE)
	var released := _event(KEY_J)
	released.pressed = false
	Input.parse_input_event(released)
	await _frames()
	_check(Settings.binding_label("think").contains("Space") and _remap._pending_event == null, "Escape discards a held valid candidate and its later release cannot commit")
	await _begin("think", "gamepad", false, true)
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.95)
	await _pad(JOY_BUTTON_START)
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0)
	_check(Settings.binding_label("think", "gamepad") == "B / RB / RT", "Start discards an axis candidate before neutral")
	await _begin("think", "keyboard")
	Input.parse_input_event(_event(KEY_J))
	await _frames()
	Settings._set_focused(false)
	Settings._set_focused(true)
	Input.parse_input_event(released)
	await _frames()
	_check(_remap._capture_action == "" and Settings.binding_label("think").contains("Space") and FileAccess.get_file_as_bytes(Settings._config_path) == config_before, "window focus loss discards an uncommitted candidate and leaves settings bytes unchanged")
	await _begin("think", "keyboard")
	Input.parse_input_event(_event(KEY_J))
	await _frames()
	await _click(_remap._back.get_global_rect().get_center())
	Input.parse_input_event(released)
	await _frames()
	_check(is_instance_valid(_remap) and Settings.binding_label("think").contains("Space"), "visible cancel button discards the held candidate")
	await _begin("think", "keyboard")
	await _key(KEY_H)
	_check(Settings.binding_label("think") == "H", "a different key is accepted after cancellation")
	await _begin("think", "gamepad", false, true)
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.95)
	_check(_remap._pending_event != null and not Input.is_action_pressed("think"), "trigger is captured without starting Think while held")
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0)
	_check(Settings.binding_label("think", "gamepad") == "LT" and Settings.binding_label("think") == "H", "trigger release completes capture without changing keyboard binding")
	await _begin("think", "keyboard")
	for down in [true, false]:
		var modifier := _event(KEY_CTRL)
		modifier.pressed = down
		modifier.ctrl_pressed = down
		Input.parse_input_event(modifier)
		await _frames()
	_check(Settings.binding_label("think") == "Ctrl", "a modifier alone can be bound without allowing modifier chords")
	await _begin("move_left", "gamepad", false, true)
	await _axis(JOY_AXIS_RIGHT_X, -0.95)
	await _axis(JOY_AXIS_RIGHT_X, 0)
	_check(Settings.binding_label("move_left", "gamepad") == "RS ←", "stick direction can replace a movement binding")
	await _begin("start_shift", "gamepad", false, true)
	await _pad(JOY_BUTTON_START)
	_check(_remap._capture_action == "" and Settings.binding_label("start_shift", "gamepad") == "Y", "Start cancels gamepad capture and remains reserved")
	for discrete in ["deliver", "start_shift", "refund"]:
		await _begin(discrete, "gamepad", false, true)
		await _axis(JOY_AXIS_RIGHT_Y, 0.95)
		_check(_remap._capture_action == discrete and _remap._pending_event == null and _remap._status.text.begins_with(tr("摇杆和扳机仅用于移动或思考；这个操作请使用按键或手柄按钮。")), "axis input is rejected with an explanation for " + discrete)
		await _axis(JOY_AXIS_RIGHT_Y, 0)
		await _pad(JOY_BUTTON_START)
	await _begin("refund", "gamepad", false, true)
	await _pad(JOY_BUTTON_A)
	_check(_remap._capture_action == "refund" and _remap._pending_event == null and _remap._status.text.begins_with(tr("这个输入用于固定菜单导航、确认或返回，不能分配给开饭或退款。")), "tree actions reject fixed menu input with a clear reason")
	_check_layout(_remap)
	await _pad(JOY_BUTTON_START)
	for tree_action in ["start_shift", "refund"]:
		for key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			_check(not Settings.binding_error(tree_action, "keyboard", _event(key)).is_empty(), "fixed keyboard menu key stays available for " + tree_action + "/" + str(key))
		for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			_check(not Settings.binding_error(tree_action, "gamepad", _pad_event(button)).is_empty(), "fixed gamepad menu button stays available for " + tree_action + "/" + str(button))
	await _begin("refund", "gamepad", false, true)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _begin("deliver", "gamepad", false, true)
	await _pad(JOY_BUTTON_B)
	_check(is_instance_valid(_remap) and _remap._capture_action == "" and Settings.binding_label("deliver", "gamepad") == "B", "B is capturable for gameplay without cancelling the binding dialog")
	await _begin("deliver", "gamepad", false, true)
	await _pad(JOY_BUTTON_X)
	_check(Settings.binding_label("refund", "gamepad") == "LB" and Settings.binding_label("deliver", "gamepad") == "X", "controller buttons can be reassigned after freeing a conflict")
	var reconnected := InputEventJoypadButton.new()
	reconnected.button_index = JOY_BUTTON_X
	reconnected.device = 3
	reconnected.pressed = true
	_check(reconnected.is_action_pressed("deliver"), "binding applies after a controller reconnect changes its device index")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	cancel.pressed = true
	_check(accept.is_action_pressed("ui_accept") and cancel.is_action_pressed("ui_cancel"), "menu A and B remain fixed independently of gameplay")
	for action in ["move_left", "start_shift", "refund"]:
		await _begin(action, "keyboard")
		await _key({"move_left": KEY_J, "start_shift": KEY_L, "refund": KEY_Q}[action])
	_check(Settings.binding_label("refund") == "Q", "refund also supports a custom keyboard action")
	for action in Settings.BINDABLE_ACTIONS:
		_check(not Settings.binding_label(action).is_empty() and not Settings.binding_label(action, "gamepad").is_empty(), "both devices retain a binding for " + action)
	_check(_leaks == 0, "capture events do not reach underlying gameplay handlers")
	var saved := ConfigFile.new()
	_check(saved.load(Settings._config_path) == OK and saved.has_section_key("controls", "bindings"), "changes persist to the isolated settings.cfg")
	Settings._read_bindings({})
	_check(Settings.binding_label("deliver").contains("E"), "fixture clears the live mapping before a real reload")
	Settings.load_settings()
	_check(Settings.binding_label("deliver") == "K" and Settings.binding_label("deliver", "gamepad") == "X" and Settings.binding_label("refund") == "Q", "reload restores saved keyboard and controller mappings")
	_remap._refresh_labels()
	await _frames()
	_check_layout(_remap)
	_check(_remap._panel.get_global_rect().encloses(_remap._status.get_global_rect()), "status stays inside the warm paper panel")
	_check(_remap._status.get_line_count() * _remap._status.get_line_height() <= _remap._status.size.y + 1, "all status text lines fit")
	Settings._read_bindings({"deliver": {"keyboard": {"kind": "key", "code": KEY_K}}, "think": {"keyboard": {"kind": "key", "code": KEY_K}}})
	_check(Settings.binding_label("deliver").contains("E") and Settings.binding_label("think").contains("Space"), "conflicting saved configuration falls back safely to defaults")
	Settings._read_bindings({"deliver": {"keyboard": {"kind": "key", "code": KEY_ESCAPE}}})
	_check(not _event(KEY_ESCAPE).is_action_pressed("deliver") and _event(KEY_ESCAPE).is_action_pressed("pause"), "saved reserved bindings cannot steal the escape key")
	Settings._read_bindings({"refund": {"gamepad": {"kind": "axis", "code": JOY_AXIS_TRIGGER_LEFT, "sign": 1}}})
	_check(Settings.binding_label("refund", "gamepad") == "X", "a saved axis binding cannot bypass discrete-action validation")
	Settings._read_bindings({"start_shift": {"gamepad": {"kind": "button", "code": JOY_BUTTON_A}}})
	_check(Settings.binding_label("start_shift", "gamepad") == "Y", "a saved tree-action binding cannot steal fixed menu confirmation")
	await _click(_remap._reset.get_global_rect().get_center())
	_check(Settings.binding_label("deliver") == "E / Enter" and Settings.binding_label("refund") == "Backspace" and Settings.binding_label("think", "gamepad") == "B / RB / RT", "restore defaults reinstates all original aliases")
	_observing = false
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(_settings._remap) and entry.has_focus(), "closing remap restores the settings entry focus")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(_settings) and opener.has_focus(), "closing settings restores its opener")
	# Confirm the shared refund action is actually used by the live tree.
	Settings.set_binding("refund", "keyboard", _event(KEY_Q))
	Game.version = 0
	Game.levels = {"start": 1, "stall_wok": 1}
	Game.seen_buttons = {"menu": true, "sigs": true, "menu_card": true, "sigs_card": true}
	Game._recompute()
	var tree := TreeScreen.new()
	host.add_child(tree)
	await _frames()
	tree._hover = "stall_wok"
	tree.grab_focus()
	await _key(KEY_BACKSPACE)
	_check(Game.level("stall_wok") == 1, "old refund key no longer refunds in the actual tree")
	await _key(KEY_Q)
	_check(Game.level("stall_wok") == 0, "new refund key refunds in the actual tree")
	Settings.set_binding("refund", "gamepad", _pad_event(JOY_BUTTON_LEFT_SHOULDER))
	Game.levels["stall_wok"] = 1
	Game._recompute()
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(Game.level("stall_wok") == 0 and tree.has_focus(), "LB still refunds and is not stolen for tree tool navigation")
	await _pad(JOY_BUTTON_BACK)
	var tools := tree._tool_targets()
	_check(tools[0].has_focus(), "Back enters the tree toolbar from the map")
	for button in tools:
		_check(button.has_focus(), "D-pad reaches tree tool " + button.text)
		await _pad(JOY_BUTTON_DPAD_RIGHT)
	_check(tools[0].has_focus(), "tool directions wrap through every visible tool")
	await _pad(JOY_BUTTON_B)
	_check(tree.has_focus(), "B returns from tools to the skill map")
	await _key(KEY_TAB)
	_check(tools[0].has_focus(), "Tab also reaches the first tree tool")
	for i in tools.size(): await _key(KEY_TAB)
	_check(tree.has_focus(), "Tab cycles through all tools back to the map")
	await _pad(JOY_BUTTON_BACK)
	await _pad(JOY_BUTTON_BACK)
	_check(tree.has_focus(), "Back toggles tools back to the map")
	Settings.reset_bindings()
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == player_settings and FileAccess.get_file_as_bytes("user://save.json") == player_save, "player settings and save bytes are unchanged")
	if _out != "":
		var report := {"checks": _checks, "failures": _fails, "language": Settings.language, "renderer": DisplayServer.get_name(), "requested_window": [_window.x, _window.y], "screenshots": _screenshots, "scope": "GUI input and isolated config reload fixtures; no physical-controller hardware test. Screenshots require a GPU renderer and an output directory.", "source_sha256": {}}
		for path in ["scripts/autoload/settings.gd", "scripts/ui/settings_panel.gd", "scripts/ui/input_remap_panel.gd", "scripts/tree/tree_screen.gd", "tests/input_remap_test.gd", "data/i18n/en.json"]:
			report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
		FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("INPUT_REMAP_TEST %s failures=%d checks=%d" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size(), _checks])
	host.queue_free()
	await _frames()
	Audio._exit_tree()
	await get_tree().create_timer(0.15).timeout
	UiKit.clear_cache()
	get_tree().quit(_fails.size())


func _begin(action: String, device: String, mouse := false, pad := false) -> void:
	var button: Button = _remap._buttons[action][device]
	button.grab_focus()
	await _frames()
	if mouse: await _click(button.get_global_rect().get_center())
	elif pad: await _pad(JOY_BUTTON_A)
	else: await _key(KEY_ENTER)
	_check(_remap._capture_action == action and _remap._pending_event == null, "opening input is not captured for " + action + "/" + device)
	_check_layout(_remap)


func _check_layout(node: Node) -> void:
	if node == _remap:
		_check(_remap.get_global_rect().encloses(_remap._panel.get_global_rect()), "remap panel stays in the viewport")
	if node is Label:
		_check(node.get_line_count() * node.get_line_height() <= node.size.y + 1, "all label lines fit: " + node.text)
	if Settings.language == "en" and (node is Label or node is Button):
		var chinese := RegEx.create_from_string("[\u4e00-\u9fff]")
		_check(chinese.search(node.text) == null, "UI uses shipped English: " + node.text)
	for child in node.get_children(): _check_layout(child)


func _check_initial_row() -> void:
	var first: Button = _remap._buttons.move_left.keyboard
	var visible: Rect2 = _remap._scroll.get_global_rect()
	_check(first.has_focus(), "initial remap focus is the first keyboard binding")
	_check(_remap._scroll.scroll_vertical == 0, "initial remap scroll stays at the top")
	for control in first.get_parent().get_children():
		_check(visible.encloses(control.get_global_rect()), "first row is fully visible at initial open: " + str(control.text))


func _unhandled_input(event: InputEvent) -> void:
	if _observing:
		for action in ["deliver", "think", "start_shift", "refund"]:
			if event.is_action_pressed(action):
				_leaks += 1
				print("REMAP_LEAK ", action, " ", event.as_text())


func _event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := _event(code)
		event.pressed = down
		Input.parse_input_event(event)
		await _frames()


func _pad(code: JoyButton) -> void:
	for down in [true, false]:
		var event := _pad_event(code)
		event.pressed = down
		Input.parse_input_event(event)
		await _frames()


func _pad_event(code: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = true
	return event


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
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


func _frames() -> void:
	for i in 3: await get_tree().process_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless": return
	await _frames()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == _window, "screenshot uses requested dimensions: " + name)
	var path := _out.path_join(name + ".png")
	_check(image.save_png(path) == OK, "screenshot is saved: " + name)
	_screenshots.append({"file": path, "width": image.get_width(), "height": image.get_height()})


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(message)
		push_error(message)
