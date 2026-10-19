extends Node
## Fixtures cover presentation and real GUI events, not a progression playthrough.
var _tree: TreeScreen
var _failures: Array[String] = []
var _checks := 0
var _out := ""
var _window := Vector2i(1280, 720)
var _shots: Array = []


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_tree_dependency") or not Settings._testing:
		push_error("Use --test-profile=tree_dependency_<suffix>")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg == "--small": _window = Vector2i(960, 540)
	if _out != "": DirAccess.make_dir_recursive_absolute(_out)
	var player_before := FileAccess.get_file_as_bytes("user://save.json")
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	Settings.window_size = _window
	Settings.fullscreen = false
	Settings.pause_unfocused = false
	Settings.reduced_motion = true
	Settings.apply()
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Game.version = 0
	Game.tokens = 100000
	Game.levels = {"start": 1}
	Game.helper_plan = {}
	Game.automation = {}
	Game.struck = []
	Game.seen_buttons = {"menu": true, "sigs": true, "menu_card": true, "sigs_card": true}
	Game._recompute()
	_tree = TreeScreen.new()
	add_child(_tree)
	await _frames()
	_check(_tree._tex.has("ticket") and _tree._tex.has("pin") and _tree._tex.has("cork_bg"), "original paper, pin and cork art remain")
	_check(Game.is_preview("stall_dim") and _tree._is_displayed("stall_dim"), "a direct successor of a visible skill is a preview")
	_check(not Game.is_preview("stall_fry") and not _tree._is_displayed("stall_fry"), "preview does not recursively reveal another layer")
	var before := Game.tokens
	var levels_before := Game.levels.duplicate()
	_center("stall_dim")
	await _frames()
	_check(_tree.node_at(_tree._at(Game.node("stall_dim"))) == "stall_dim", "blank preview is mouse-inspectable")
	await _click(_tree._at(Game.node("stall_dim")))
	_check(_tree._hover == "stall_dim" and Game.tokens == before and Game.levels == levels_before, "mouse click inspects a preview without buying it")
	_check(_tree._flash_text == tr("满足前置技能与版本条件后，空白便签才会揭晓。"), "preview click explains prerequisite and version gates")
	var preview_lines := _tree._tooltip_lines(Game.node("stall_dim"))
	_check(preview_lines[0][0] == tr("空白便签"), "preview title is generic")
	for n in Game.nodes:
		if Game.is_preview(n.id):
			var lines := _tree._tooltip_lines(n)
			_check(lines == preview_lines, "all previews hide skill identity, description and cost: " + str(n.id))
			_check(not Game.can_buy(n.id), "preview remains unpurchasable: " + str(n.id))
	await _shot("blank_successor")
	# Start from a known parent, then use real directional/accept events to inspect its successor.
	_tree._hover = "stall_wok"
	_tree.grab_focus()
	await _key(KEY_UP)
	_check(_tree._hover == "stall_dim", "keyboard navigation reaches the blank successor")
	await _key(KEY_ENTER)
	await _pad(JOY_BUTTON_A)
	_check(Game.tokens == before and Game.levels == levels_before, "Enter and controller A cannot buy a preview")
	await _key(KEY_BACKSPACE)
	_check(Game.tokens == before and _tree._flash_text == tr("满足前置技能与版本条件后，空白便签才会揭晓。"), "refund on a preview gives the generic explanation without disclosing details")
	# Buying the prerequisite reveals the original skill at the same authored coordinate.
	var authored := _tree._pos(Game.node("stall_dim"))
	_center("stall_wok")
	await _click(_tree._at(Game.node("stall_wok")))
	_check(Game.level("stall_wok") == 1 and Game.is_visible("stall_dim") and not Game.is_preview("stall_dim"), "real purchase reveals its direct successor")
	_check(_tree._pos(Game.node("stall_dim")) == authored, "reveal preserves the authored ticket coordinates")
	_check(_tree._tooltip_lines(Game.node("stall_dim"))[0][0] == tr(Game.node("stall_dim").name), "revealed skill uses its ordinary title")
	_check(Game.is_preview("stall_fry"), "newly visible parent exposes one next preview across a version gate")
	_center("stall_fry")
	await _click(_tree._at(Game.node("stall_fry")))
	_check(_tree._tooltip_lines(Game.node("stall_fry")) == preview_lines and Game.level("stall_fry") == 0, "future-version preview still reveals no skill details")
	await _shot("version_preview")
	# Purchased downstream skill protects one parent level, but extra levels refund at full cost.
	Game.levels = {"start": 1, "stall_wok": 3, "stall_dim": 1}
	Game._recompute()
	Game.changed.emit()
	_center("stall_wok")
	await _frames()
	var lines := _tree._tooltip_lines(Game.node("stall_wok"))
	_check(lines.any(func(line): return line[0] == tr("退款：右键 / Backspace / 手柄 X")), "maxed skills expose mouse and keyboard refund controls")
	_check(lines.any(func(line): return line[0] == tr("已有下游技能：只能退多余等级，最低保留 1 级。")), "protected skill tooltip explains its minimum level")
	before = Game.tokens
	var n := Game.node("stall_wok")
	var expected := floorf(float(n.cost) * float(n.growth)) + floorf(float(n.cost) * pow(float(n.growth), 2))
	await _click(_tree._at(n), MOUSE_BUTTON_RIGHT)
	_check(Game.level("stall_wok") == 1 and Game.level("stall_dim") == 1 and is_equal_approx(Game.tokens - before, expected), "right-click refunds extra parent levels while retaining the dependency")
	_check(_tree._flash_text == tr("退回 %s token；下游仍依赖它，保留 1 级。") % Game.fmt(expected), "partial refund explicitly reports retained level 1")
	await _shot("partial_refund")
	before = Game.tokens
	await _key(KEY_BACKSPACE)
	_check(Game.level("stall_wok") == 1 and Game.tokens == before, "Backspace cannot refund the protected final level")
	_check(_tree._flash_text == tr("不能再退：已购买的下游技能需要保留这 1 级。"), "refused refund explains the purchased dependency")
	await _pad(JOY_BUTTON_X)
	_check(Game.tokens == before, "repeated controller refund cannot create money")
	await _shot("refund_floor")
	# Clear the child via real key input, then refund the now-unprotected parent via controller X.
	_center("stall_dim")
	_tree._hover = "stall_dim"
	_tree.grab_focus()
	await _key(KEY_BACKSPACE)
	_check(Game.level("stall_dim") == 0 and Game.refund_floor("stall_wok") == 0, "keyboard refund removes a leaf and releases the parent floor")
	_tree._hover = "stall_wok"
	await _pad(JOY_BUTTON_X)
	_check(Game.level("stall_wok") == 0, "controller X can fully refund the released parent")
	_check(_tree._flash_text == tr("已退回 %s token，这项技能已清空。") % Game.fmt(float(n.cost)), "full refund clearly reports the skill was cleared")
	before = Game.tokens
	await _key(KEY_BACKSPACE)
	_check(Game.tokens == before and _tree._flash_text == tr("尚未购买，无需退款。"), "refund of an unowned skill is explained and does not pay again")
	_center("start")
	await _click(_tree._at(Game.node("start")), MOUSE_BUTTON_RIGHT)
	_check(Game.level("start") == 1 and _tree._flash_text == tr("起点与版本门票不能单独退款。"), "root refund refusal has a reason")
	# Existing modal focus continues to block tree shortcuts.
	_tree._crew_button.grab_focus()
	await _key(KEY_ENTER)
	before = Game.tokens
	await _key(KEY_BACKSPACE)
	await _pad(JOY_BUTTON_X)
	_check(is_instance_valid(_tree._crew_planner) and Game.tokens == before, "refund shortcuts do not leak through a modal")
	await _key(KEY_ESCAPE)
	_check(_tree._crew_button.has_focus(), "modal close preserves its original focus recovery")
	# Inspect real late-game text with all dependencies purchased, including partial levels.
	Game.version = Game.VERSIONS.size() - 1
	for skill in Game.nodes:
		if not skill.get("locked", false): Game.levels[skill.id] = int(skill.max)
	Game._recompute()
	for skill in Game.nodes:
		if not Game.is_visible(skill.id): continue
		var owned := Game.level(skill.id)
		for level in [owned, maxi(0, owned - 1)]:
			Game.levels[skill.id] = level
			var dimensions := _tree._tooltip_size(_tree._tooltip_lines(skill))
			_check(dimensions.y <= 700, "full skill and refund explanation fits: " + str(skill.id))
		Game.levels[skill.id] = owned
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_before, "player save bytes unchanged")
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before, "player settings bytes unchanged")
	var report := {"checks": _checks, "failures": _failures, "scope": "State fixtures and real mouse, keyboard and simulated-controller GUI events", "language": Settings.language, "window": str(_window), "renderer": DisplayServer.get_name(), "shots": _shots, "source_sha256": {}}
	for path in ["scripts/tree/tree_screen.gd", "scripts/autoload/game.gd", "data/skill_tree.json", "data/i18n/en.json", "tests/tree_dependency_test.gd"]:
		report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	if _out != "": FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("TREE_DEPENDENCY_TEST %s failures=%d checks=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size(), _checks])
	_tree.queue_free()
	await _frames()
	Audio._exit_tree()
	await get_tree().create_timer(0.15).timeout
	UiKit.clear_cache()
	get_tree().quit(_failures.size())


func _center(id: String) -> void:
	_tree._hover = ""
	_tree._tooltip_bounds = Rect2()
	_tree._pan = -_tree._pos(Game.node(id)) * _tree._zoom


func _shot(name: String) -> void:
	await _frames()
	_check(Rect2(0, 0, 1920, 1080).encloses(_tree._tooltip_bounds), "tooltip stays in viewport: " + name)
	_check(not _tree._tooltip_bounds.intersects(_tree._header_rect()), "tooltip avoids the feedback chalkboard: " + name)
	_check(300 + _tree._feedback_height() + 10 < _tree._header_rect().end.y, "complete feedback fits inside chalkboard: " + name)
	if Settings.language == "en":
		var chinese := RegEx.create_from_string("[\u4e00-\u9fff]")
		_check(chinese.search(_tree._flash_text) == null, "feedback uses shipped English: " + name)
		for line in _tree._tooltip_lines(Game.node(_tree._hover)):
			_check(chinese.search(line[0]) == null, "tooltip uses shipped English: " + name)
	if _out == "" or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == _window, "screenshot uses declared size: " + name)
	var path := _out.path_join(name + ".png")
	_check(image.save_png(path) == OK, "saved screenshot: " + name)
	_shots.append({"path": path, "sha256": FileAccess.get_sha256(path)})


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


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = down
		get_viewport().push_input(event, true)
		await _frames()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
		push_error(label)
