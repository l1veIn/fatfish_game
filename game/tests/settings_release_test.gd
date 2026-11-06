extends Node
## Run with --test-profile=settings-release. Does not launch the shared balance bot.
## Keyboard and joypad events travel through the real GUI dispatch path.

class ShakeCamera extends Camera2D:
	var calls := 0
	func add_shake(_power: float, _duration: float) -> void:
		calls += 1

var _fails := 0
var _root: Control
var _panel: SettingsPanel
var _shots := ""


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
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


func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
	# process_frame resumes before the nodes' _process calls. Let Fx process the
	# frame that crossed the deadline before reading its restored time scale.
	await get_tree().process_frame


func _shot(name: String) -> void:
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(8)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == Vector2i(1280, 720), "captured actual 1280 x 720 viewport")
	image.save_png(_shots.path_join(name + ".png"))


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=settings-release"):
		push_error("Use --test-profile=settings-release; refusing to test with player progress")
		get_tree().quit(1)
		return
	_check(Settings._testing, "test profile protects player settings before startup apply")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-shots="):
			_shots = arg.trim_prefix("--settings-shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	# Parent merges this supplementary translation file into en.json for the release.
	var extra_path := ProjectSettings.globalize_path("res://../docs/settings-translations.json")
	if FileAccess.file_exists(extra_path):
		var extra = JSON.parse_string(FileAccess.get_file_as_string(extra_path))
		var translation := Translation.new()
		translation.locale = "en"
		for source in extra:
			translation.add_message(source, extra[source])
		TranslationServer.add_translation(translation)
	var player_before := FileAccess.get_file_as_bytes(Settings.PATH)
	var original := Settings._create_config()
	Settings.reduced_motion = true
	Settings.screen_shake = false
	Settings.hit_pause = false
	Settings.window_size = Vector2i(1600, 900)
	var encoded: String = Settings._create_config().encode_to_text()
	var decoded := ConfigFile.new()
	_check(decoded.parse(encoded) == OK, "settings serialize as valid ConfigFile")
	Settings.reduced_motion = false
	Settings.screen_shake = true
	Settings.hit_pause = true
	Settings.window_size = Vector2i(1280, 720)
	Settings._read_config(decoded)
	_check(Settings.reduced_motion and not Settings.screen_shake and not Settings.hit_pause and Settings.window_size == Vector2i(1600, 900), "all accessibility flags and window size round-trip")
	Settings.vsync = false # capture fixture; apply() can override the engine's startup flag
	Settings.apply()
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == player_before, "applying a test profile leaves player settings byte-identical")
	for screen in [Rect2i(0, 0, 1280, 680), Rect2i(-1920, 0, 1920, 1040), Rect2i(1920, 120, 2560, 1400)]:
		for requested in Settings.WINDOW_SIZES:
			var rect: Rect2i = Settings.safe_window_rect(requested, screen)
			_check(screen.encloses(rect) and rect.position == screen.position + (screen.size - rect.size) / 2, "window fits and centers on monitor %s at %s" % [screen, requested])
	Settings.hit_pause = true
	for speed in [0.35, 1.0, 4.0]:
		Engine.time_scale = speed
		Fx.hitstop(0.03)
		Fx.hitstop(0.05)
		await _wait_real(0.09)
		_check(is_equal_approx(Engine.time_scale, speed), "overlapping hit pause restores original speed %.2f" % speed)
	Engine.time_scale = 0.35
	await _frames()
	_check(is_equal_approx(Engine.time_scale, 0.35), "idle Fx leaves unrelated slow motion unchanged")
	Fx.hitstop(0.05)
	Engine.time_scale = 2.0
	await _wait_real(0.08)
	_check(is_equal_approx(Engine.time_scale, 2.0), "external speed change during hit pause wins")
	Fx.hitstop(0.5)
	Settings.hit_pause = false
	Settings.apply()
	_check(is_equal_approx(Engine.time_scale, 2.0), "turning hit pause off restores its held speed immediately")
	Fx.hitstop(0.1)
	_check(is_equal_approx(Engine.time_scale, 2.0), "disabled hit pause cannot slow the game")
	Engine.time_scale = 1.0
	var camera := ShakeCamera.new()
	add_child(camera)
	Fx.camera = camera
	Settings.reduced_motion = false
	Settings.screen_shake = true
	Fx.shake(4.0, 0.1)
	Settings.screen_shake = false
	Fx.shake(4.0, 0.1)
	Settings.screen_shake = true
	Settings.reduced_motion = true
	Fx.shake(4.0, 0.1)
	_check(camera.calls == 1, "screen shake and reduce motion both suppress camera shake")
	Fx.camera = null
	camera.queue_free()
	var world := Node2D.new()
	add_child(world)
	Fx.world = world
	Fx.burst(Vector2.ZERO, Color.WHITE, 8, 20.0, 5.0)
	_check(world.get_child_count() == 0, "reduce motion suppresses decorative particles")
	Fx.popup_text(Vector2(500, 300), "Readable result", Color.WHITE)
	var label := world.get_child(0) as Label
	var origin := label.position
	await _wait_real(0.12)
	_check(label.position == origin, "reduce motion retains result text without floating it")
	Fx.world = null
	world.queue_free()
	Settings._read_config(original)
	Settings.fullscreen = false
	Settings.window_size = Vector2i(1280, 720)
	Settings.language = "zh_CN"
	Settings.vsync = false
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	_root = Control.new()
	add_child(_root)
	_root.size = get_viewport().get_visible_rect().size
	var opener := UiKit.button("Open settings", 28, Vector2(300, 70))
	_root.add_child(opener)
	Settings.reduced_motion = false
	UiKit._bounce(opener, 1.04)
	Settings.reduced_motion = true
	UiKit._bounce(opener, 1.04)
	await _wait_real(0.12)
	_check(opener.scale == Vector2.ONE, "reduce motion cancels button bounce and keeps its scale stable")
	opener.grab_focus()
	_panel = SettingsPanel.new()
	_root.add_child(_panel)
	await _frames(6)
	_check(_panel.get_rect().encloses(_panel._panel.get_rect()), "settings panel stays inside the logical viewport")
	_check(get_viewport().gui_get_focus_owner() == _panel._tabs[0], "initial focus lands on sound tab")
	for page in 4:
		_panel._tabs[page].grab_focus()
		await _key(KEY_ENTER)
		_check(_panel._active_tab == page, "keyboard activates tab %d" % page)
		await _shot("zh_%d" % page)
		await _key(KEY_DOWN)
		for control in _panel._controls:
			_check(get_viewport().gui_get_focus_owner() == control, "keyboard reaches %s" % control.get_meta("focus_key"))
			await _key(KEY_DOWN)
		_check(get_viewport().gui_get_focus_owner() == _panel._back, "keyboard reaches return from page %d" % page)
		await _key(KEY_DOWN)
		_check(get_viewport().gui_get_focus_owner() == _panel._tabs[page], "keyboard focus loops inside page %d" % page)
	for control in _panel._controls:
		if control.get_meta("focus_key", "") == "language":
			control.grab_focus()
	Settings.language = "en"
	Settings.apply()
	await _frames(8)
	_check(_panel._active_tab == 3 and get_viewport().gui_get_focus_owner().get_meta("focus_key", "") == "language", "language rebuild preserves current page and focus")
	for page in 4:
		_panel._tabs[page].grab_focus()
		await _pad(JOY_BUTTON_A)
		await _shot("en_%d" % page)
		await _pad(JOY_BUTTON_DPAD_DOWN)
		for control in _panel._controls:
			_check(get_viewport().gui_get_focus_owner() == control, "gamepad reaches %s" % control.get_meta("focus_key"))
			await _pad(JOY_BUTTON_DPAD_DOWN)
		_check(get_viewport().gui_get_focus_owner() == _panel._back, "gamepad reaches return from page %d" % page)
		_check(_panel.get_rect().encloses(_panel._panel.get_rect()), "English page %d remains inside viewport" % page)
	_panel._tabs[2].grab_focus()
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var previous_motion: bool = Settings.reduced_motion
	await _pad(JOY_BUTTON_A)
	_check(Settings.reduced_motion != previous_motion, "gamepad A changes the focused reduce-motion switch")
	await _pad(JOY_BUTTON_B)
	await _frames()
	_check(not is_instance_valid(_panel), "gamepad B closes settings")
	_check(get_viewport().gui_get_focus_owner() == opener, "closing settings restores opener focus")
	get_tree().paused = true
	_panel = SettingsPanel.new()
	_root.add_child(_panel)
	await _frames()
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(_panel) and get_tree().paused, "Esc closes nested settings while keeping its parent game paused")
	_check(get_viewport().gui_get_focus_owner() == opener, "paused settings returns focus to its opener")
	get_tree().paused = false
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == player_before, "complete GUI and FX test preserves player settings")
	Settings._read_config(original)
	UiKit.clear_cache()
	print("SETTINGS_RELEASE_TEST failures=%d" % _fails)
	get_tree().quit(_fails)
