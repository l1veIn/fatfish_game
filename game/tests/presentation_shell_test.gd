extends Node
## Isolated visual fixtures with actual GUI events. No player save or network service.
var _out := ""
var _failures: Array[String] = []
var _report := {}
var _current: Control
var _closed := 0
var _requested_size := Vector2i(1280, 720)


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_presentation_shell_"):
		push_error("Use --test-profile=presentation_shell_*")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--render-size="):
			var dimensions := arg.trim_prefix("--render-size=").split("x")
			_requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	Settings.window_size = _requested_size
	Settings.fullscreen = false
	Settings.apply()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(_requested_size)
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	_report = {"language": Settings.language, "source_sha256": {}, "scope": "Shell UI fixtures with GUI events; no full playthrough or physical gamepad"}
	for source in ["scripts/ui/title_screen.gd", "scripts/ui/settings_panel.gd", "scripts/ui/pause_menu.gd", "scripts/ui/ending_screen.gd", "scripts/run/checkout_receipt.gd", "scripts/ui/ui_kit.gd", "data/i18n/en.json", "assets/ui/premium/logo_zh.png", "assets/ui/premium/logo_en.png", "tests/presentation_shell_test.gd"]:
		_report.source_sha256[source] = FileAccess.get_sha256("res://" + source)
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Settings.reduced_motion = true
	Settings.pause_unfocused = false
	Game.version = Game.VERSIONS.size() - 1
	Game.runs = 123
	Game.tokens = 123456789
	Game.total_tokens = 9876543210
	var title := TitleScreen.new()
	_current = title
	add_child(title)
	await _wait()
	_check(title._logo is TextureRect and title._logo.texture != null, "title uses the generated wordmark texture")
	for button in title._buttons:
		_check(Rect2(0, 0, 1920, 998).encloses(button.get_global_rect()), "title action fits: " + button.text)
	await _shot("title_completed")
	title.open_settings.connect(func():
		var settings := SettingsPanel.new()
		title.add_child(settings))
	var settings_button: Button = title.find_child("Settings", true, false)
	settings_button.grab_focus()
	await _key(KEY_ENTER)
	var settings: SettingsPanel
	for child in title.get_children():
		if child is SettingsPanel:
			settings = child
	_check(settings != null, "focused title settings opens through Enter")
	for i in 4:
		settings._tabs[i].grab_focus()
		await _key(KEY_ENTER)
		_check(settings._active_tab == i, "settings category changes: %d" % i)
		await _shot("settings_%d" % i)
		await _key(KEY_DOWN)
		_check(settings._controls.has(get_viewport().gui_get_focus_owner()), "Down enters the active settings page")
	await _pad(JOY_BUTTON_B)
	_check(not is_instance_valid(settings), "B closes settings")
	_check(settings_button.has_focus(), "settings restores title focus")
	await _clear()
	Game.version = 0
	Game.runs = 0
	var fresh_title := TitleScreen.new()
	_current = fresh_title
	add_child(fresh_title)
	await _wait()
	_check(fresh_title._buttons[0].name == "Start", "fresh profile offers the start action")
	await _shot("title_fresh")
	await _clear()
	Game.version = Game.VERSIONS.size() - 1
	Game.runs = 123
	var pause := PauseMenu.new()
	_current = pause
	get_tree().paused = true
	add_child(pause)
	await _wait()
	await _shot("pause")
	pause._buttons[2].grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(is_instance_valid(pause._settings), "paused settings opens through A")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(pause._settings) and get_tree().paused, "settings cancel returns to paused parent")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused, "pause cancel resumes")
	await _clear()
	Game.best_run = 12345678
	Game.levels = {"start": 1, "stall_main": 3, "stall_wok": 3, "stall_dim": 3, "stall_fry": 3, "stall_sweet": 3, "moe": 3, "menu": 4, "grok": 1, "mtp": 4, "prompt": 3}
	Game.signatures = ["burger", "pork", "icecream"]
	Game.struck = ["ball", "potato", "soymilk", "fries"]
	Game._recompute()
	Game.recipes = {}
	CanteenRun.load_menu()
	for i in mini(18, CanteenRun.RECIPES.size()):
		Game.recipes[CanteenRun.RECIPES[i].id] = 1
	var ending := EndingScreen.new()
	_current = ending
	add_child(ending)
	await _wait()
	for page in 3:
		_check(ending._page == page, "epilogue page %d" % page)
		await _shot("ending_%d" % page)
		if page < 2:
			await _key(KEY_ENTER)
	_check(ending._summary.runs == Game.runs and ending._summary.best_run == Game.best_run and ending._summary.total_tokens == Game.total_tokens, "keepsake uses real current progress")
	_check(ending._summary.signatures == Game.active_signatures() and ending._summary.struck == Game.active_struck(), "keepsake reflects the effective current menu")
	for skill in ending._summary.skills:
		_check(Game.level(skill.id) == skill.level and skill.level > 0, "keepsake skill is actually owned: " + skill.id)
	var previous_bottom := 0.0
	for child in ending._content.get_children():
		if child is Label:
			_check(child.get_rect().end.y <= ending._content.size.y, "keepsake text stays on the paper: " + child.text.left(24))
			if child.name.begins_with("KeepsakeStat"):
				_check(child.get_rect().end.y <= 371, "keepsake statistic clears its caption: " + child.text)
			if child.position.x == 0 and child.position.y >= 426:
				_check(child.position.y >= previous_bottom, "keepsake build rows do not overlap")
				previous_bottom = child.get_rect().end.y
	var ending_marker_before := Game.ending_seen
	ending.export_directory = _out.path_join("keepsakes") if _out != "" else "user://qa_keepsakes"
	ending._save.grab_focus()
	await _pad(JOY_BUTTON_A)
	await _wait()
	if DisplayServer.get_name() != "headless":
		_check(ending._last_export_error == OK and FileAccess.file_exists(ending._last_export_path), "focused save action writes a local PNG")
		if ending._last_export_path != "":
			var keepsake := Image.load_from_file(ending._last_export_path)
			_check(keepsake != null and keepsake.get_size() == _requested_size, "keepsake PNG matches the actual viewport")
			_report["keepsake_png"] = ending._last_export_path
	else:
		_check(ending._last_export_error == ERR_UNAVAILABLE, "headless export reports unavailable instead of claiming a PNG")
	_check(ending._save.has_focus() and ending._next.visible and not ending._exporting, "export restores navigation and focused action")
	_check(Game.ending_seen == ending_marker_before and Game.runs == 123, "export leaves progress and ending marker unchanged")
	await _clear()
	var receipt := CheckoutReceipt.new()
	receipt.heading = tr("第 %d 顿 · 结账") % 123
	receipt.sub = tr("大肥鱼 AGI") + " · 18:00 · " + tr("食堂关门了")
	receipt.steps = [
		{"text": tr("这顿吃的：%d 份") % 1234, "add": 1256789.0},
		{"note": tr("其中招牌菜"), "add": 12345.0},
		{"note": tr("其中搭配加成：单品 / 缓存 / 换菜"), "add": 45678.0},
		{"text": tr("最差的几盒按平均算"), "add": 3000.0},
		{"text": tr("没吃完 %d 盒：浪费了约") % 12, "lost": 12345.0},
		{"text": tr("最后一口：%s") % tr("红烧肉"), "mark": "×8", "add": 87654.0},
	]
	receipt.subtotal = 1400000
	receipt.mults = [[tr("均衡"), 1.50], [tr("评鉴"), 2.40], [tr("招牌菜"), 1.20], [tr("新纪录"), 1.05], [tr("最后一口：%s") % "", 1.10]]
	receipt.total = 6985440
	receipt.target = 2000000
	receipt.passed = true
	receipt.record = true
	receipt.stuffed = true
	receipt.extra = tr("%s 发布！获得 %s") % [tr(Game.plate()), tr(Game.VERSIONS[Game.version].get("reward", ""))]
	receipt.closed.connect(func(): _closed += 1)
	_current = receipt
	add_child(receipt)
	for i in 120:
		if receipt._done:
			break
		await _wait(0.025)
	_check(receipt._done and not receipt._back.disabled, "reduced-motion receipt finishes and enables its action")
	_check(receipt._need_h + receipt.PAPER.position.y < receipt._back.position.y, "dense receipt paper clears its return action")
	_check(not receipt._extra_label.get_rect().intersects(receipt._back.get_rect()), "receipt explanation clears its return action")
	await _wait()
	_check(receipt._drawn_result_bounds.size() == receipt._results.size(), "every actually drawn result stamp reports its ink and paper bounds")
	_report["receipt_stamp_bounds"] = []
	for bounds in receipt._drawn_result_bounds:
		_check(bounds.position.x >= receipt.PAPER.end.x + 31.0 and Rect2(0, 0, 1920, 1080).encloses(bounds), "drawn result stamp clears the receipt and stays on screen")
		_report.receipt_stamp_bounds.append(str(bounds))
	for stamp_time in [0.0, 0.04, 0.08, 0.16, 1.0]:
		var animated: Rect2 = receipt._result_stamp_layout(140.0, tr("吃撑了"), stamp_time).bounds
		_check(animated.position.x >= receipt.PAPER.end.x + 31.0 and Rect2(0, 0, 1920, 1080).encloses(animated), "stamp animation respects the receipt edge at %.2fs" % stamp_time)
	await _shot("receipt_dense")
	receipt._back.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(_closed == 1, "receipt action emits exactly once")
	await _clear()
	Settings.reduced_motion = false
	var retry := CheckoutReceipt.new()
	retry.heading = tr("第 %d 顿 · 结账") % 124
	retry.sub = tr("大肥鱼 AGI") + " · 18:00 · " + tr("食堂关门了")
	retry.steps = [{"text": tr("这顿吃的：%d 份") % 123, "add": 87654.0}]
	retry.subtotal = 87654
	retry.mults = [[tr("均衡"), 1.0]]
	retry.total = 87654
	retry.target = 2000000
	retry.extra = tr("评测没过：差 %s token（门票已花掉，随时可以再来）") % Game.fmt(retry.target - retry.total)
	retry.closed.connect(func(): _closed += 1)
	_current = retry
	add_child(retry)
	await _key(KEY_ENTER)
	for i in 100:
		if retry._done:
			break
		await _wait(0.025)
	_check(retry._done, "Enter skips the normal receipt reveal")
	await _wait(0.3)
	await _shot("receipt_retry")
	await _pad(JOY_BUTTON_B)
	_check(_closed == 2, "B exits a completed receipt")
	await _clear()
	_report["passed"] = _failures.is_empty()
	_report["failures"] = _failures
	_report["window_size"] = str(DisplayServer.window_get_size())
	_report["requested_size"] = str(_requested_size)
	if DisplayServer.get_name() != "headless":
		_check(DisplayServer.window_get_size() == _requested_size, "actual window matches the requested resolution")
		_report["passed"] = _failures.is_empty()
		_report["failures"] = _failures
	if _out != "":
		var report := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		report.store_string(JSON.stringify(_report, "\t"))
	print("PRESENTATION_SHELL_TEST ", "PASS" if _failures.is_empty() else "FAIL")
	Audio.set_process(false)
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await _wait()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _clear() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null
	await _wait()


func _wait(seconds := 0.12) -> void:
	await get_tree().create_timer(seconds).timeout


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await _wait(0.045)


func _pad(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await _wait(0.045)


func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		_failures.append(description)


func _shot(stem: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == _requested_size, "native screenshot size: " + stem)
	image.save_png(_out.path_join(stem + ".png"))
