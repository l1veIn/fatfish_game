extends Node
## Isolated state fixtures + real Godot GUI key/gamepad events, not a full AGI playthrough.
## Godot --path game --resolution 1280x720 res://tests/ending_flow_test.tscn -- 
##   --test-profile=ending_flow --lang=zh_CN --out=<absolute screenshot directory>

var _main
var _out := ""
var _failures: Array[String] = []
var _report := {}


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_ending_"):
		push_error("Use a dedicated --test-profile=ending_*; refusing to touch player progress")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		_report = {"scope": "State fixtures plus real Godot GUI keyboard/gamepad events; not a full playthrough or physical-controller test", "language": Settings.language, "engine": Engine.get_version_info().string, "command_line": OS.get_cmdline_args(), "source_sha256": {}}
		for source in ["project.godot", "scripts/main.gd", "scripts/ui/title_screen.gd", "scripts/ui/ending_screen.gd", "scripts/ui/achievements_panel.gd", "scripts/ui/achievement_toast.gd", "scripts/ui/settings_panel.gd", "scripts/autoload/game.gd", "scripts/autoload/settings.gd", "scripts/run/canteen_run.gd", "scripts/run/checkout_receipt.gd", "tests/ending_flow_test.gd", "data/achievements.json", "data/i18n/en.json", "assets/ui/NotoSansSC-VF.ttf"]:
			_report.source_sha256[source] = FileAccess.get_sha256("res://" + source)
	Settings.reduced_motion = true
	Settings.fullscreen = false
	get_tree().root.gui_embed_subwindows = true   # route injected keys through popup GUI too
	Game.version = Game.VERSIONS.size() - 1
	Game.runs = 35
	Game.tokens = 34567
	Game.total_tokens = 2345678
	Game.ending_seen = false
	Game.achievements = {"first_meal": 1, "release_agi": 1, "resident": 1, "recipe_ten": 1}
	Game.recipes = {}
	CanteenRun.load_menu()
	for i in mini(18, CanteenRun.RECIPES.size()):
		Game.recipes[CanteenRun.RECIPES[i].id] = 1
	Game.seen_buttons = {"book": true, "signatures": true, "menu_cut": true, "checkpoint": true}
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.3)
	_check(_main._screen is TitleScreen, "AGI fixture starts on title")
	var title: TitleScreen = _main._screen
	_check(title._buttons.size() == 7, "completed title exposes replay and achievements")
	for button in title._buttons:
		_check(Rect2(0, 0, 1920, 1000).encloses(button.get_global_rect()), "menu button stays above footer: " + button.text)
	await _shot("title_agi")
	var achievement_button: Button = title.find_child("Achievements", true, false)
	achievement_button.grab_focus()
	await _key(KEY_ENTER)
	var panel: AchievementsPanel = _find_type(title, "AchievementsPanel")
	_check(panel != null, "Enter opens the focused achievements button")
	if panel == null:
		_finish()
		return
	var achievement_ids := {}
	panel._back.grab_focus()
	await _key(KEY_DOWN)
	_check(panel._medals[0].has_focus(), "Down enters the first achievement tray")
	await _key(KEY_DOWN)
	_check(panel._medals[2].has_focus(), "Down follows medal grid columns")
	await _key(KEY_UP)
	_check(panel._medals[0].has_focus(), "Up returns to the first medal")
	for page in panel._page_count:
		_check(panel._spread == page and panel._medals.size() <= 6, "achievement tray advances one page with bounded capacity")
		for i in panel._medals.size():
			var medal: Button = panel._medals[i]
			var id := str(medal.get_meta("achievement_id"))
			_check(medal.has_focus() and panel._selected_id == id, "keyboard navigation exposes detail for " + id)
			_check(not achievement_ids.has(id), "achievement appears on exactly one tray: " + id)
			achievement_ids[id] = true
			for child in medal.get_children():
				if child is TextureRect:
					_check(Rect2(Vector2.ZERO, medal.size).encloses(child.get_rect()), "small medal art stays in its slot: " + id)
					_check(child.size == Vector2(112, 112) and not child.texture.resource_path.contains("portraits"), "small art uses a dedicated simple icon: " + id)
			for child in panel._detail.get_children():
				if child is TextureRect:
					_check(child.size.x >= 350 and child.size.y >= 280, "complex character art has a large detail display")
			if i + 1 < panel._medals.size():
				await _key(KEY_TAB)
		if page == 0:
			await _shot("achievements_first_tray")
		if page + 1 < panel._page_count:
			await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(achievement_ids.size() == Game.achievement_catalog().size(), "every catalog achievement is reachable through real paged navigation")
	_check(panel._medals.back().has_focus() and panel._next.disabled, "final achievement is focused and final tray cannot advance")
	await _shot("achievements_last_tray")
	await _pad(JOY_BUTTON_B)
	_check(not is_instance_valid(panel), "gamepad B closes achievements")
	_check(achievement_button.has_focus(), "closing achievements restores menu focus")
	title._buttons[0].grab_focus()
	await _key(KEY_ENTER)
	_check(_main._screen is EndingScreen, "Continue on an unseen AGI save opens the epilogue")
	var ending: EndingScreen = _main._screen
	_check(ending._page == 0 and not Game.ending_seen, "opening the ending does not consume its save marker")
	var frozen_time: float = ending._t
	await _wait(0.15)
	_check(is_equal_approx(ending._t, frozen_time), "reduced motion holds decorative animation still")
	await _shot("ending_1")
	await _key(KEY_ENTER)
	_check(ending._page == 1, "Enter advances to the character epilogue")
	await _shot("ending_2")
	await _key(KEY_ENTER)
	_check(ending._page == 2 and ending._save.visible, "Enter advances to the shareable keepsake")
	_check(ending._next.text == tr("继续开饭"), "keepsake clearly offers continued play")
	_check(ending._summary.runs == 35 and ending._summary.total_tokens == 2345678, "keepsake contains real progress from the isolated profile")
	ending.share_capture_changed.emit(true)
	_check(not _main._notices.visible, "share capture hides overlays above the ending")
	ending.share_capture_changed.emit(false)
	_check(_main._notices.visible, "share capture restores notification layer")
	await _shot("ending_3")
	await _key(KEY_ENTER)
	_check(_main._screen is TreeScreen, "finishing returns to the playable skill tree")
	_check(Game.ending_seen and not Game.ending_pending(), "completion persists the ending marker")
	_check(Game.version == Game.VERSIONS.size() - 1 and Game.runs == 35 and Game.tokens == 34567, "ending leaves earned progress intact")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(saved is Dictionary and saved.get("ending_seen", false), "isolated save contains ending completion")
	_main._show_title()
	await _wait(0.1)
	title = _main._screen
	var replay: Button = title.find_child("ReplayEnding", true, false)
	replay.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(_main._screen is EndingScreen, "gamepad A can replay a completed ending")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	_check(_main._screen._page == 2 and _main._screen._save.visible, "title replay can reach the shareable keepsake again")
	await _pad(JOY_BUTTON_B)
	_check(_main._screen is TreeScreen, "gamepad B skips a replay and returns to the tree")
	Game.ending_seen = false
	_main._show_title()
	await _wait(0.1)
	title = _main._screen
	title._buttons[0].grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	_check(_main._screen is TreeScreen and Game.ending_seen, "Escape skips first viewing without trapping progress")
	_main._show_title()
	await _wait(0.1)
	var notice: AchievementToast
	for child in _main.get_children():
		for nested in child.get_children():
			if nested is AchievementToast:
				notice = nested
	Game.save_status = "ending test fixture"
	Game.save_failed.emit(Game.save_status)
	await _wait(0.1)
	_check(notice != null and notice._warning.visible, "save failure produces a persistent visible warning")
	await _shot("save_warning")
	Game.save_status = ""
	await _wait(0.1)
	_check(not notice._warning.visible, "successful subsequent save clears the warning")
	var original_language := Settings.language
	title = _main._screen
	var settings_button: Button = title.find_child("Settings", true, false)
	settings_button.grab_focus()
	await _key(KEY_ENTER)
	var settings_panel: SettingsPanel = _find_type(title, "SettingsPanel")
	_check(settings_panel != null, "title opens settings through focused button")
	settings_panel._tabs[3].grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	_check(get_viewport().gui_get_focus_owner().get_meta("focus_key", "") == "language", "game settings tab focuses language option")
	await _key(KEY_ENTER)
	await _key(KEY_DOWN if original_language == "zh_CN" else KEY_UP)
	await _key(KEY_ENTER)
	await _wait(0.2)
	_check(Settings.language != original_language, "language selection changes through popup input")
	_check(is_instance_valid(settings_panel) and settings_panel._active_tab == 3, "changing language preserves the settings panel and page")
	_check(get_viewport().gui_get_focus_owner().get_meta("focus_key", "") == "language", "changing language preserves focused setting")
	await _key(KEY_ESCAPE)
	_check(_main._screen is TitleScreen and not is_instance_valid(title), "translated title rebuilds only after settings closes")
	_check(get_viewport().gui_get_focus_owner().name == "Settings", "rebuilt title restores focus to settings")
	Settings.language = original_language
	Settings.apply()
	await _wait(0.1)
	Settings.reduced_motion = false
	_main._show_title()
	await _wait(0.6)
	title = _main._screen
	replay = title.find_child("ReplayEnding", true, false)
	replay.grab_focus()
	await _pad(JOY_BUTTON_A)
	await _key(KEY_ESCAPE)
	await _wait(0.5)
	_check(_main._screen is EndingScreen and not _main._screen._closed, "input during screen fade cannot strand a closed ending")
	await _key(KEY_ESCAPE)
	await _wait(0.5)
	_check(_main._screen is TreeScreen, "normal-motion ending exits after fade finishes")
	Settings.reduced_motion = true
	Game.version = Game.VERSIONS.size() - 2
	Game.ending_seen = false
	Game.runs = 34
	Game._recompute()
	_main._show_run("agi")
	await _wait(0.15)
	var run: CanteenRun = _main._screen
	run.earned = run.target
	run._end("食堂关门了")
	await _wait(1.2)
	_check(run.passed and Game.ending_pending(), "AGI trial settlement creates a pending ending")
	var receipt: CheckoutReceipt = _find_type(run, "CheckoutReceipt")
	_check(receipt != null and receipt._back.text == tr("查看结局"), "final settlement labels its next action as View ending")
	await _key(KEY_ENTER)
	await _wait(0.7)
	await _key(KEY_ENTER)
	_check(_main._screen is EndingScreen, "confirming the real settlement receipt enters the ending")
	await _key(KEY_ESCAPE)
	_check(_main._screen is TreeScreen and Game.ending_seen, "settlement ending exits back to playable upgrades")
	_finish()


func _find_type(parent: Node, script_class: String):
	for child in parent.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == script_class:
			return child
	return null


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(0.04)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await _wait(0.05)


func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(0.04)
	event = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	await _wait(0.05)


func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		_failures.append(description)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(stem: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(stem + ".png"))


func _finish() -> void:
	print("ENDING_FLOW_TEST ", "PASS" if _failures.is_empty() else "FAIL", " failures=", _failures.size())
	if not _out.is_empty():
		_report["passed"] = _failures.is_empty()
		_report["failures"] = _failures
		_report["window_size"] = str(DisplayServer.window_get_size())
		_report["completed_at_unix"] = Time.get_unix_time_from_system()
		var report_file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		if report_file != null:
			report_file.store_string(JSON.stringify(_report, "\t"))
	_main.queue_free()
	Audio.set_process(false)
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await _wait(0.2)
	get_tree().quit(0 if _failures.is_empty() else 1)
