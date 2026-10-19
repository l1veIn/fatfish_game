extends Node
## State fixtures plus real GUI events; --test-profile=meal_planner_* is required.
const Planner := preload("res://scripts/ui/meal_planner.gd")
var _tree: TreeScreen
var _out := ""
var _failures: Array[String] = []
var _started := 0
var _report := {}


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_meal_planner_"):
		push_error("Refusing player save. Use --test-profile=meal_planner_*")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
		_report = {"language": Settings.language, "source_sha256": {}, "scope": "GUI event tests with late-game state fixtures; not a full playthrough or physical-controller test"}
		for source in ["scripts/ui/meal_planner.gd", "scripts/tree/tree_screen.gd", "scripts/autoload/game.gd", "data/i18n/en.json", "tests/meal_planner_test.gd"]:
			_report.source_sha256[source] = FileAccess.get_sha256("res://" + source)
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Settings.reduced_motion = true
	Game.version = Game.VERSIONS.size() - 1
	Game.runs = 35
	Game.tokens = 1000000000
	Game.levels = {}
	for node in Game.nodes:
		if not node.get("locked", false):
			Game.levels[node.id] = int(node.max)
	Game.levels["menu"] = 2   # the board contains a partial and a completed upgrade
	Game.signatures = []
	Game.struck = []
	Game.seen_buttons = {"book": true, "menu": true, "sigs": true, "menu_card": true, "sigs_card": true}
	Game._recompute()
	_tree = TreeScreen.new()
	_tree.start_run.connect(func(): _started += 1)
	add_child(_tree)
	await _wait(0.1)
	_tree._hover = "menu"
	_tree.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(Game.level("menu") == 3, "gamepad A on the map upgrades the selected skill once")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	_check(_tree._hover != "menu" and _tree.has_focus(), "gamepad direction navigates the map without leaving its focus")
	Game.levels["menu"] = 2
	Game._recompute()
	Game.changed.emit()
	_tree._zoom = 1.15
	_tree._pan = -_tree._pos(Game.node("menu")) * _tree._zoom
	await _wait(0.05)
	for button in _tree._bar.get_children():
		_check(Rect2(Vector2.ZERO, _tree.size).encloses(button.get_global_rect()), "toolbar fits inside the viewport: " + button.name)
	await _shot("tree_partial_full")
	for id in ["mtp", "prompt", "compress", "memory"]:
		_tree._hover = id
		_tree._pan = Vector2(500, 360) - _tree._pos(Game.node(id)) * _tree._zoom
		_tree._trial.visible = id != "mtp"
		_tree._trial.text = tr("评测「%s」 门票 %s") % ["AGI", "100K"]
		await _wait(0.05)
		await _shot("tooltip_" + id)
		if DisplayServer.get_name() != "headless":
			_check(not _tree._tooltip_bounds.intersects(_tree._start.get_rect()), "tooltip avoids the lunch action: " + id)
			_check(not _tree._trial.visible or not _tree._tooltip_bounds.intersects(_tree._trial.get_rect()), "tooltip avoids the trial action: " + id)
			_check(Rect2(Vector2.ZERO, _tree.size).encloses(_tree._tooltip_bounds), "complete tooltip remains on screen: " + id)
	_tree._trial.visible = false
	_tree._hover = ""
	_tree._pan = -_tree._pos(Game.node("menu")) * _tree._zoom
	var opener: Button = _tree.find_child("Tree_menu", true, false)
	opener.grab_focus()
	await _key(KEY_ENTER)
	var panel: Control = _tree._planner
	_check(is_instance_valid(panel), "Enter opens menu planning")
	for i in 8:
		_tree._open_menu()
	_check(_tree._planner == panel and _panel_count() == 1, "repeated menu requests reuse one modal")
	_tree._open_signatures()
	_check(_tree._planner == panel and _panel_count() == 1, "signature request switches the existing modal")
	_tree._open_menu()
	await _wait(0.1)
	var before_tokens := Game.tokens
	var before_pan := _tree._pan
	await _key(KEY_G)
	await _pad(JOY_BUTTON_Y)
	await _mouse(Vector2(20, 560), MOUSE_BUTTON_LEFT)
	await _mouse(Vector2(960, 540), MOUSE_BUTTON_RIGHT)
	_check(_started == 0 and Game.tokens == before_tokens and _tree._pan == before_pan, "modal blocks start, buy, refund and outside tree input")
	var card: Button = panel._by_id["ball"]
	card.grab_focus()
	await _key(KEY_ENTER)
	_check(Game.struck.has("ball"), "Enter strikes the focused dish")
	_check(panel._by_id["ball"] == card and card.has_focus(), "selection updates in place and retains focus")
	await _key(KEY_ENTER)
	_check(not Game.struck.has("ball"), "Enter restores a struck dish")
	await _mouse(card.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	_check(Game.struck.has("ball"), "mouse click selects the pictured dish")
	for id in ["bowl", "leg"]:
		panel._by_id[id].grab_focus()
		await _pad(JOY_BUTTON_A)
	_check(Game.struck.size() == 2 and not Game.struck.has("ball"), "full menu slots replace the oldest selection")
	await _shot("menu_selected")
	for i in 30:
		await _key(KEY_TAB)
		var focused := get_viewport().gui_get_focus_owner()
		_check(focused != null and panel.is_ancestor_of(focused), "Tab focus stays inside the modal")
	panel._tabs[1].grab_focus()
	await _key(KEY_ENTER)
	await _wait(0.1)
	var candidate := ""
	for candidate_card in panel._cards:
		var id: String = candidate_card.get_meta("dish_id")
		if Game.signature_available(id) and not Game.active_signatures().has(id):
			candidate = id
			break
	_check(candidate != "", "signature fixture has an alternate dish")
	var signature_card: Button = panel._by_id[candidate]
	signature_card.grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(Game.active_signatures().has(candidate), "gamepad A chooses a new signature")
	_check(signature_card.has_focus() and _panel_count() == 1, "signature mutation keeps one modal and original focus")
	await _shot("signatures_selected")
	await _pad(JOY_BUTTON_B)
	_check(not is_instance_valid(_tree._planner) and _panel_count() == 0, "B closes the single modal")
	_check(opener.has_focus(), "modal close restores its original toolbar focus")
	_tree._open_menu()
	await _wait(0.1)
	await _key(KEY_ESCAPE)
	_check(_panel_count() == 0, "Escape closes without opening another overlay")
	Game._stats["stall_sweet"] = 0
	_tree._open_signatures()
	await _wait(0.1)
	panel = _tree._planner
	var before := Game.active_signatures().duplicate()
	panel._by_id["icecream"].grab_focus()
	await _key(KEY_ENTER)
	_check(Game.active_signatures() == before, "locked dish cannot become a signature")
	_check(panel._detail_name.text == tr(CanteenRun.NAMES[CanteenRun.KIND["icecream"]]) and panel._detail_body.text.contains(str(CanteenRun.LEVEL[CanteenRun.KIND["icecream"]])), "locked signature explains its stall level requirement")
	await _shot("signatures_locked")
	await _key(KEY_ESCAPE)
	Game._stats["stall_main"] = 1
	Game.struck = []
	_tree._open_menu()
	await _wait(0.1)
	panel = _tree._planner
	panel._by_id["bowl"].grab_focus()
	await _key(KEY_ENTER)
	_check(Game.active_struck().has("bowl"), "first of two open staple dishes can be crossed off")
	panel._by_id["mantou"].grab_focus()
	await _key(KEY_ENTER)
	_check(not Game.active_struck().has("mantou"), "last dish at a stall remains on the menu")
	_check(panel._detail_body.text == tr(Game.struck_toggle_reason("mantou")), "last-dish refusal gives the actual reason")
	_check(panel._by_id["mantou"].get_meta("status").text == tr("档口最后一道 · 保留"), "last remaining dish has an explicit card label")
	await _shot("menu_last_dish")
	await _key(KEY_ESCAPE)
	_finish()


func _panel_count() -> int:
	return _tree.get_children().filter(func(child): return child is Planner).size()


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(0.025)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await _wait(0.035)


func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(0.025)
	event = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	await _wait(0.035)


func _mouse(at: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = true
	get_viewport().push_input(event, true)
	await _wait(0.025)
	event = InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = false
	get_viewport().push_input(event, true)
	await _wait(0.035)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		_failures.append(description)


func _shot(stem: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(stem + ".png"))


func _finish() -> void:
	print("MEAL_PLANNER_TEST ", "PASS" if _failures.is_empty() else "FAIL", " failures=", _failures.size())
	if _out != "":
		_report["passed"] = _failures.is_empty()
		_report["failures"] = _failures
		_report["window_size"] = str(DisplayServer.window_get_size())
		var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_report, "\t"))
	_tree.queue_free()
	Audio.set_process(false)
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await _wait(0.15)
	get_tree().quit(0 if _failures.is_empty() else 1)
