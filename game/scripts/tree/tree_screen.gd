class_name TreeScreen
extends Control
## The skill tree between shifts. Nodes come from res://data/skill_tree.json; a node appears
## once its version ring is released and a parent is owned. Click a node to buy a level, drag
## empty space to pan, then press 去打饭 for the next shift. Once the next version's ticket is
## bought, a red 提交评测 button starts its trial.
## Gamepad / keyboard: D-pad / stick / arrows inspect tickets, A / Enter buys revealed skills,
## X / Backspace refunds, Y / G goes to lunch, Start / Esc opens the settings.

signal start_run
signal start_trial(trial: String)
signal open_settings
signal to_title

const NODE_R := 44.0
const TICKET := Vector2(172, 108)     # avoids the four closest authored pairs without moving nodes
const ZOOM := Vector2(0.45, 1.3)
const MealPlannerPanel := preload("res://scripts/ui/meal_planner.gd")
const CrewPlannerPanel := preload("res://scripts/ui/crew_planner_panel.gd")

var _zoom := 0.75
var _bar: HBoxContainer
var _bar_key := ""
var _new_buttons := {}                # button -> its id, while it has never been clicked
var _tex := {}                        # board art: cork, ticket, ticket_gold, stamp, pin

var _pan := Vector2.ZERO
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_moved := 0.0
var _hover := ""
var _flash_at := Vector2.ZERO
var _flash_time := 0.0
var _fish: FishRig
var _start: Button
var _trial: Button
var _planner: Control
var _book: Control
var _crew_planner: Control
var _crew_button: Button
var _modal_focus: Array = []
var _tooltip_bounds := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fish = FishRig.new()
	_fish.emote = Game.emotion()
	_fish.basin = _fish.emote < 2   # before V4: deadpan, holding her basin
	if _fish.basin:
		_fish.idle_clip = "title_basin"
	_fish.position = Vector2(190, 1040)
	_fish.height = 420.0
	add_child(_fish)
	_start = Button.new()
	_start.text = tr("去打饭")
	_start.add_theme_font_size_override("font_size", 40)
	_start.position = Vector2(1580, 940)
	_start.size = Vector2(280, 90)
	_start.pressed.connect(func(): start_run.emit())
	add_child(_start)
	_trial = Button.new()
	_trial.add_theme_font_size_override("font_size", 30)
	_trial.add_theme_color_override("font_color", Color(1, 0.9, 0.8))
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.7, 0.15, 0.15)
	red.set_corner_radius_all(10)
	_trial.add_theme_stylebox_override("normal", red)
	_trial.position = Vector2(1460, 830)
	_trial.size = Vector2(400, 90)
	_trial.pressed.connect(_on_trial)
	add_child(_trial)
	_update_trial_button()
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 12)
	_bar.resized.connect(func(): _bar.position = Vector2(1860 - _bar.size.x, 30))
	add_child(_bar)
	_build_bar()
	var tools_hint := UiKit.label(tr("Tab / Back（Select）：切换工具区 · B：回技能树"), 22, Color("f2dfb7"))
	tools_hint.name = "TreeToolsHint"
	tools_hint.position = Vector2(630, 1024)
	tools_hint.size = Vector2(850, 44)
	tools_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tools_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tools_hint)
	Game.changed.connect(_build_bar)
	for n in ["cork_bg", "ticket", "ticket_gold", "stamp", "pin", "icon_lock", "fx_burst", "fx_star", "ui_chalkboard"]:
		var f := "res://assets/canteen/%s.png" % n
		if ResourceLoader.exists(f):
			_tex[n] = load(f)
	Game.changed.connect(queue_redraw)
	Game.changed.connect(_update_trial_button)
	_show_newest_ring()
	grab_focus.call_deferred()
	Audio.music("bgm_tree")
	Audio.ambience("")


func _update_trial_button() -> void:
	var t := Game.open_trial()
	_trial.visible = t != ""
	if t != "":
		_trial.text = tr("评测「%s」 门票 %s") % [tr(Game.trial_name(t)).get_slice("·", 0).strip_edges(), Game.fmt(Game.trial_fee(t))]
		var fs := 30   # long (English) names: smaller text rather than spilling out of the button
		while fs > 16 and ThemeDB.fallback_font.get_string_size(_trial.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _trial.size.x - 30:
			fs -= 2
		_trial.add_theme_font_size_override("font_size", fs)
	_link_tool_focus()


## The top bar. 今日菜单 and 招牌菜 show up once a skill unlocks them; a button the player has
## never pressed glows with a 「新！」 tag until they do.
func _build_bar() -> void:
	var specs: Array = [["book", tr("图鉴"), _open_book]]
	if Game.stat("menu_cut") > 0.0:
		specs.append(["menu", tr("今日菜单"), _open_menu])
	if Game.stat("sig_slots") > 0.0:
		specs.append(["sigs", tr("招牌菜"), _open_signatures])
	if not Game.automation_pages().is_empty():
		specs.append(["crew", tr("自动化"), _open_crew])
	specs.append_array([["respec", tr("回滚"), _on_respec], ["settings", tr("设置"), func(): open_settings.emit()], ["title", tr("标题"), func(): to_title.emit()]])
	var key := ",".join(specs.map(func(x): return x[0]))
	if key == _bar_key:
		return
	_bar_key = key
	_crew_button = null
	for c in _bar.get_children():
		_bar.remove_child(c)
		c.queue_free()
	_new_buttons.clear()
	for spec in specs:
		var fs := 21 if Settings.is_english() else 26
		var width := maxf(100.0, get_theme_font("font", "Button").get_string_size(spec[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 44.0)
		var b := UiKit.button(spec[1], fs, Vector2(width, 64))
		var id: String = spec[0]
		b.name = "Tree_" + id
		var fn: Callable = spec[2]
		b.pressed.connect(func():
			if not Game.seen_buttons.has(id):
				Game.seen_buttons[id] = true
				_new_buttons.erase(b)
				Game.save_game()
			fn.call())
		_bar.add_child(b)
		if id == "crew": _crew_button = b
		if id in ["menu", "sigs", "crew"] and not Game.seen_buttons.has(id):
			_new_buttons[b] = id
			var dot := Control.new()   # the red dot sits on the button itself, above its art
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.position = Vector2(width - 6, 6)
			dot.draw.connect(func():
				dot.draw_circle(Vector2.ZERO, 13.0, Color(1, 1, 1))
				dot.draw_circle(Vector2.ZERO, 10.0, Color(0.78, 0.22, 0.18)))
			b.add_child(dot)
			b.pressed.connect(dot.queue_free)
			if not Game.seen_buttons.has(id + "_card"):
				Game.seen_buttons[id + "_card"] = true
				_feature_card.call_deferred(id, fn)
	_bar.size = _bar.get_combined_minimum_size()
	_bar.position = Vector2(1860 - _bar.size.x, 30)
	_link_tool_focus()


func _tool_targets() -> Array[Control]:
	var targets: Array[Control] = []
	if is_instance_valid(_bar):
		for button in _bar.get_children():
			if button is Button and button.visible and not button.disabled: targets.append(button)
	for button in [_trial, _start]:
		if is_instance_valid(button) and button.visible and not button.disabled: targets.append(button)
	return targets


func _link_tool_focus() -> void:
	var tools := _tool_targets()
	if tools.is_empty(): return
	# Tab includes the map; tool directions cycle through every visible button.
	focus_next = get_path_to(tools[0])
	focus_previous = get_path_to(tools[-1])
	for i in tools.size():
		var button := tools[i]
		button.focus_next = button.get_path_to(tools[i + 1] if i + 1 < tools.size() else self)
		button.focus_previous = button.get_path_to(tools[i - 1] if i > 0 else self)
		button.focus_neighbor_right = button.get_path_to(tools[(i + 1) % tools.size()])
		button.focus_neighbor_bottom = button.focus_neighbor_right
		button.focus_neighbor_left = button.get_path_to(tools[posmod(i - 1, tools.size())])
		button.focus_neighbor_top = button.focus_neighbor_left


func _tools_have_focus() -> bool:
	return _tool_targets().has(get_viewport().gui_get_focus_owner())


func _has_input_modal() -> bool:
	return is_instance_valid(_planner) or is_instance_valid(_crew_planner) or is_instance_valid(_book) or get_children().any(func(c): return c is SettingsPanel or c is RecipeBook)


const FEATURES := {
	"menu": ["新功能：今日菜单", "开饭前划掉不想要的菜，想要的出得更多。"],
	"sigs": ["新功能：招牌菜", "选一道招牌菜，这顿它有特别加成。"],
	"crew": ["自动化", "开饭前安排好，所有改动下顿生效。"],
}


## The first time a feature unlocks: a ticket-paper card slides in from the right with one plain
## sentence and a 「去看看」 button, and slides away by itself after a while.
func _feature_card(id: String, open: Callable) -> void:
	if is_instance_valid(_planner) or is_instance_valid(_crew_planner):
		return
	var card := Control.new()
	card.set_meta("feature_card", true)
	card.size = Vector2(440, 250)
	card.position = Vector2(1940, 150)
	card.z_index = 40
	add_child(card)
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if ResourceLoader.exists("res://assets/canteen/ui_paper.png"):
		bg.texture = load("res://assets/canteen/ui_paper.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	card.add_child(bg)
	bg.size = card.size
	var title := UiKit.label(tr(FEATURES[id][0]), 30, Color(0.78, 0.22, 0.18))
	title.position = Vector2(34, 34)
	card.add_child(title)
	var body := UiKit.label(tr(FEATURES[id][1]), 22, Color(0.29, 0.16, 0.08))
	body.position = Vector2(34, 86)
	body.size = Vector2(372, 70)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(body)
	var go := UiKit.button(tr("去看看"), 24, Vector2(160, 54))
	go.position = Vector2(246, 170)
	card.add_child(go)
	var card_ref: WeakRef = weakref(card)
	var hide := func():
		var target = card_ref.get_ref()
		if is_instance_valid(target) and not target.is_queued_for_deletion():
			var tw2 := create_tween().bind_node(target)
			tw2.tween_property(target, "position:x", 1940.0, 0.25)
			tw2.tween_callback(target.queue_free)
	go.pressed.connect(func():
		Game.seen_buttons[id] = true
		Game.save_game()
		_bar_key = ""
		_build_bar()
		hide.call()
		open.call())
	var tw := create_tween().bind_node(card)
	tw.tween_property(card, "position:x", 1460.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(7.0)
	tw.tween_callback(hide)
	Audio.sfx("ticket", -6.0)


## 评测: pay the ticket (10% of the target) and go.
func _on_trial() -> void:
	var t := Game.open_trial()
	if Game.pay_trial(t):
		Audio.sfx("ticket", -3.0)
		start_trial.emit(t)
	else:
		Audio.sfx("deny", -6.0)
		_fish.play("broke")


## 回滚到 checkpoint: refund every skill (two clicks).
var _respec_armed := 0.0


func _on_respec() -> void:
	if _respec_armed <= 0.0:
		_respec_armed = 3.0
		_flash_text = tr("再点一次「回滚」：所有技能全额退款，重新加点")
		return
	_respec_armed = 0.0
	var back := Game.respec()
	_flash_text = tr("回滚完成：退回 %s token") % Game.fmt(back)
	Audio.sfx("buy", -3.0)


var _flash_text := ""


## 招牌菜: pick up to sig_slots of the dishes the open stalls serve.
func _open_signatures() -> void:
	_open_planner("signatures")


## 今日菜单 (System Prompt): strike up to menu_cut dishes of the open stalls off the menu.
func _open_menu() -> void:
	_open_planner("menu")


func _open_book() -> void:
	if is_instance_valid(_book) or is_instance_valid(_planner) or is_instance_valid(_crew_planner):
		return
	_book = RecipeBook.new()
	var opener: WeakRef = weakref(get_viewport().gui_get_focus_owner())
	_book.tree_exited.connect(func():
		_book = null
		var old = opener.get_ref()
		if is_instance_valid(old):
			old.grab_focus.call_deferred())
	add_child(_book)


func _open_planner(page: String) -> void:
	if is_instance_valid(_crew_planner) or is_instance_valid(_book):
		return
	if is_instance_valid(_planner):
		_planner.show_mode(page)
		return
	var opener: WeakRef = weakref(get_viewport().gui_get_focus_owner())
	_dragging = false
	_hover = ""
	for child in get_children():
		if child.has_meta("feature_card"):
			child.queue_free()
	_modal_focus.clear()
	_modal_focus.append({"node": weakref(self), "mode": focus_mode})
	focus_mode = Control.FOCUS_NONE
	# Disable every underlying focus target before adding the modal. Tab cannot escape it.
	for control in find_children("*", "Control", true, false):
		_modal_focus.append({"node": weakref(control), "mode": control.focus_mode})
		control.focus_mode = Control.FOCUS_NONE
	var panel := MealPlannerPanel.new()
	panel.mode = page
	_planner = panel
	panel.closed.connect(func():
		if panel.get_parent() == self:
			remove_child(panel)
		_planner = null
		for state in _modal_focus:
			var control = state.node.get_ref()
			if is_instance_valid(control):
				control.focus_mode = state.mode
		_modal_focus.clear()
		var focus = opener.get_ref()
		if is_instance_valid(focus) and focus is Control and focus.is_inside_tree():
			focus.grab_focus.call_deferred()
		else:
			_start.grab_focus.call_deferred())
	add_child(panel)


func _open_crew() -> void:
	if Game.automation_pages().is_empty() or is_instance_valid(_crew_planner) or is_instance_valid(_planner) or is_instance_valid(_book) or get_children().any(func(c): return c is SettingsPanel):
		return
	var opener := get_viewport().gui_get_focus_owner()
	var previous: WeakRef = weakref(opener) if opener != null else null
	_dragging = false
	_hover = ""
	for child in get_children():
		if child.has_meta("feature_card"):
			child.queue_free()
	_modal_focus.clear()
	_modal_focus.append({"node": weakref(self), "mode": focus_mode})
	focus_mode = Control.FOCUS_NONE
	for control in find_children("*", "Control", true, false):
		_modal_focus.append({"node": weakref(control), "mode": control.focus_mode})
		control.focus_mode = Control.FOCUS_NONE
	var panel := CrewPlannerPanel.new()
	_crew_planner = panel
	panel.closed.connect(func():
		if panel.get_parent() == self:
			remove_child(panel)
		_crew_planner = null
		for state in _modal_focus:
			var control = state.node.get_ref()
			if is_instance_valid(control):
				control.focus_mode = state.mode
		_modal_focus.clear()
		var target = previous.get_ref() if previous != null else null
		if is_instance_valid(target) and target.is_inside_tree():
			target.grab_focus.call_deferred()
		elif is_instance_valid(_crew_button):
			_crew_button.grab_focus.call_deferred()
		else:
			grab_focus.call_deferred())
	add_child(panel)


## Later version rings grow off to the left: pan so the newest ring is on screen.
## The tree grows out from the middle in every direction: start centred, a little to the right
## of the side texts.
func _show_newest_ring() -> void:
	_pan = Vector2(180, 70)


func center() -> Vector2:
	return Vector2(960, 540) + _pan


## Where a node sits on screen (the board pans and zooms).
func _at(n: Dictionary) -> Vector2:
	return center() + _pos(n) * _zoom


func node_at(p: Vector2) -> String:
	if _header_rect().has_point(p) or _bar.get_rect().grow(10).has_point(p):
		return ""
	for n in Game.nodes:
		if _is_displayed(n["id"]) and Rect2(_at(n) - TICKET * _zoom * 0.5, TICKET * _zoom).has_point(p):
			return n["id"]
	return ""


func _is_displayed(id: String) -> bool:
	return Game.is_visible(id) or Game.is_preview(id)


## Buys one level; returns true on success (also used by the autotest).
func try_buy(id: String) -> bool:
	if not Game.is_visible(id):
		_flash_text = tr("满足前置技能与版本条件后，空白便签才会揭晓。")
		Audio.sfx("ui_hover", -10.0)
		return false
	if Game.buy(id):
		var p := _at(Game.node(id))
		Audio.sfx("buy")
		_fish.bounce()
		# every fifth level she protests that she is NOT fat
		var fat := Game.total_levels() % 5 == 0
		_fish.play("not_fat" if fat else "happy")
		Audio.vo("fish_not_fat" if fat else "fish_happy", 1, 1.0 if fat else [0.0, 0.25, 0.5][Game.emotion()])   # 嘿嘿 only once she has feelings
		_flash_at = p
		_flash_time = 0.3
		return true
	Audio.sfx("deny", -6.0)
	if _fish.clip != "broke":
		_fish.play("broke")
		Audio.vo("fish_broke", 1)
	return false


## Mouse and keyboard use the same explanation for a partial or refused refund.
func _refund_node(id: String) -> void:
	var n := Game.node(id)
	if n.is_empty(): return
	if not Game.is_visible(id):
		_flash_text = tr("满足前置技能与版本条件后，空白便签才会揭晓。")
	elif Game.level(id) <= 0:
		_flash_text = tr("尚未购买，无需退款。")
	elif id == "start" or n.get("kind", "") == "ticket":
		_flash_text = tr("起点与版本门票不能单独退款。")
	else:
		var floor_level := Game.refund_floor(id)
		var back := Game.refund(id)
		if back > 0.0:
			_flash_text = (tr("退回 %s token；下游仍依赖它，保留 1 级。") if floor_level > 0 else tr("已退回 %s token，这项技能已清空。")) % Game.fmt(back)
			Audio.sfx("buy", -6.0)
			return
		_flash_text = tr("不能再退：已购买的下游技能需要保留这 1 级。") if floor_level > 0 else tr("尚未购买，无需退款。")
	Audio.sfx("deny", -6.0)


func _is_refund_input(event: InputEvent) -> bool:
	return event.is_action_pressed("refund") and not event.is_echo()


func _process(delta: float) -> void:
	_respec_armed = maxf(_respec_armed - delta, 0.0)
	_flash_time = maxf(_flash_time - delta, 0.0)
	if _hover != "" and not _is_displayed(_hover):
		_hover = ""
	if _hover != "" and not Game.node(_hover).is_empty() and not _tools_have_focus():
		_tooltip_bounds = _tooltip_rect(Game.node(_hover), _tooltip_size(_tooltip_lines(Game.node(_hover))))
	else:
		_tooltip_bounds = Rect2()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	if _has_input_modal(): return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_BACK:
			get_viewport().set_input_as_handled()
			if _tools_have_focus(): grab_focus()
			else:
				var tools := _tool_targets()
				if not tools.is_empty(): tools[0].grab_focus()
		elif event.button_index == JOY_BUTTON_B and _tools_have_focus():
			get_viewport().set_input_as_handled()
			grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _has_input_modal():
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_settings.emit()
	elif event.is_action_pressed("start_shift"):
		get_viewport().set_input_as_handled()
		start_run.emit()
	elif has_focus() and _hover != "" and _is_refund_input(event):
		get_viewport().set_input_as_handled()
		_refund_node(_hover)
	elif event.is_action_pressed("deliver") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A):
		if has_focus() and _hover != "":
			get_viewport().set_input_as_handled()
			try_buy(_hover)
	else:
		if not has_focus():
			return
		for d in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
			if event.is_action_pressed(d[0]):
				get_viewport().set_input_as_handled()
				_step(d[1])
				return


## Gamepad cursor: the nearest revealed or preview ticket in direction `dir`,
## and pan so it stays on screen.
func _step(dir: Vector2) -> void:
	if _hover == "":
		_hover = "start"
	else:
		var from := _pos(Game.node(_hover))
		var best := ""
		var best_d := INF
		for n in Game.nodes:
			if not _is_displayed(n["id"]) or n["id"] == _hover:
				continue
			var v := _pos(n) - from
			if v.normalized().dot(dir) < 0.5:
				continue
			var d := v.length() * (2.0 - v.normalized().dot(dir))
			if d < best_d:
				best_d = d
				best = n["id"]
		if best != "":
			_hover = best
			Audio.sfx("ui_hover", -10.0)
	var at := _at(Game.node(_hover))
	if not Rect2(300, 200, 1320, 640).has_point(at):
		_pan += (Vector2(960, 520) - at) * 0.6


func _gui_input(event: InputEvent) -> void:
	if _has_input_modal():
		return
	if has_focus():
		if _hover != "" and _is_refund_input(event):
			accept_event()
			_refund_node(_hover)
			return
		for direction in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
			if event.is_action_pressed(direction[0]):
				accept_event()
				_step(direction[1])
				return
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("deliver"):
			if _hover != "":
				accept_event()
				try_buy(_hover)
			return
	# The explanation is informational; clicking through it must not buy a hidden ticket.
	if event is InputEventMouseButton and _tooltip_bounds.has_point(event.position):
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var nz := clampf(_zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), ZOOM.x, ZOOM.y)
		_pan = (_pan + Vector2(960, 540) - event.position) * (nz / _zoom) + event.position - Vector2(960, 540)   # zoom around the cursor
		_zoom = nz
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var rid := node_at(event.position)   # right click: refund this node
		if rid != "":
			grab_focus()
			_hover = rid
			_refund_node(rid)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			_dragging = true
			_drag_from = event.position
			_drag_moved = 0.0
		else:
			_dragging = false
			if _drag_moved < 8.0:
				var id := node_at(event.position)
				if id != "":
					_hover = id
					try_buy(id)
				else:
					_hover = ""
	elif event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			_drag_moved += event.relative.length()
		elif _tooltip_bounds.has_point(event.position):
			return
		var pointed := node_at(event.position)
		if pointed != "":
			_hover = pointed


func _pos(n: Dictionary) -> Vector2:
	return Vector2(float(n["pos"][0]), float(n["pos"][1]))


func _draw() -> void:
	# the 饭票软木板: cork, red yarn between the tickets, a pin on each, a red stamp once bought
	if _tex.has("cork_bg"):
		draw_texture_rect(_tex.cork_bg, Rect2(Vector2.ZERO, size), false)
	else:
		draw_texture(preload("res://assets/canteen/bg_wall.png"), Vector2.ZERO, Color(0.55, 0.5, 0.46))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.04, 0.02, 0.18))
	var font := ThemeDB.fallback_font
	var z := _zoom
	for n in Game.nodes:
		if not _is_displayed(n["id"]):
			continue
		for p in n["parents"]:
			if not Game.is_visible(p):
				continue
			var a := _at(Game.node(p))
			var b := _at(n)
			var preview := Game.is_preview(n["id"])
			var owned := Game.level(n["id"]) > 0
			# red yarn pinned at both tickets, hanging slack: it sags more the longer it runs
			var sag := 14.0 * z + a.distance_to(b) * 0.18
			var mid := (a + b) * 0.5 + Vector2(0, sag * 2.0)
			var pts := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
			draw_polyline(pts, Color(0.6, 0.15, 0.12, 0.26) if preview else (Color(0.78, 0.1, 0.1, 0.95) if owned else Color(0.6, 0.15, 0.12, 0.45)), (1.5 if preview else (4.0 if owned else 2.5)) * z, true)
	for n in Game.nodes:
		var id: String = n["id"]
		if not _is_displayed(id):
			continue
		var c := _at(n)
		var lv := Game.level(id)
		var ticket: bool = n.get("kind", "") == "ticket"
		var sz := TICKET * z
		var r := Rect2(c - sz * 0.5, sz)
		# An unrevealed successor uses only the ordinary paper and pin. No key colour,
		# name, progress, price, stamp or lock art leaks the skill behind this preview.
		if Game.is_preview(id):
			if id == _hover: r = r.grow(4.0 * z)
			if _tex.has("ticket"):
				draw_texture_rect(_tex.ticket, r, false, Color(0.88, 0.83, 0.74, 0.8))
			else:
				draw_rect(r, Color(0.82, 0.76, 0.64, 0.8))
			_draw_pin(c, r, z)
			continue
		var tex: Texture2D = _tex.get("ticket_gold" if n.get("key", false) else "ticket", null)
		var tint := Color.WHITE
		if ticket:
			tint = Color(1.0, 0.62, 0.55)   # a release ticket: pink paper
		if not Game.can_buy(id) and lv == 0:
			tint = tint * Color(0.8, 0.76, 0.7)   # can't buy yet: a little faded
		if n.get("locked", false):
			tint = tint * Color(0.72, 0.7, 0.68)   # locked: greyer still, and a padlock (below)
		if id == _hover:
			r = r.grow(4.0 * z)
		if Game.can_buy(id):   # affordable: a warm glow behind the ticket
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
			var gs := r.size * (1.45 + 0.05 * pulse)
			draw_texture_rect(UiKit.glow(), Rect2(r.get_center() - gs * 0.5, gs), false, Color(1.0, 0.85, 0.4, 0.45 + 0.2 * pulse))
		if tex != null:
			draw_texture_rect(tex, r, false, tint)
		else:
			draw_rect(r, Color(0.95, 0.9, 0.78) * tint)
		# Keep names and progress inside the paper's safe area. The stub is reserved for
		# a small completion stamp; a partly purchased skill must never look completed.
		var fs := int(21 * z)
		var label := _name_lines(font, tr(n["name"]), fs, sz.x * 0.70)
		var y := r.position.y + sz.y * 0.34
		for line in label:
			var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(r.position.x + sz.x * 0.44 - tw * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.3, 0.17, 0.08))
			y += fs * 1.2
		var lvtext: String = tr("门票") if ticket else "%d/%d" % [lv, int(n["max"])]
		var ls := int(16 * z)
		draw_string(font, r.position + Vector2(16 * z, sz.y - 24 * z), lvtext, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Color(0.45, 0.25, 0.12))
		var track := Rect2(r.position + Vector2(16 * z, sz.y - 16 * z), Vector2(sz.x - 64 * z, 5 * z))
		draw_rect(track, Color(0.48, 0.3, 0.16, 0.22))
		var fraction := clampf(float(lv) / maxf(1.0, float(n["max"])), 0.0, 1.0)
		if fraction > 0.0:
			draw_rect(Rect2(track.position, Vector2(track.size.x * fraction, track.size.y)), Color(0.6, 0.31, 0.1))
		if Game.is_maxed(id) and _tex.has("stamp"):
			var ss := 28.0 * z
			var sc := r.position + Vector2(sz.x - 21 * z, sz.y - 20 * z)
			draw_set_transform(sc, -0.25, Vector2.ONE)
			draw_texture_rect(_tex.stamp, Rect2(-Vector2(ss, ss) * 0.5, Vector2(ss, ss)), false, Color(1, 1, 1, 0.8))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_pin(c, r, z)
		if n.get("locked", false):   # not yet: a padlock hung on the ticket
			var ls2 := sz.y * 0.62
			if _tex.has("icon_lock"):
				draw_texture_rect(_tex.icon_lock, Rect2(r.get_center() + Vector2(sz.x * 0.28, -sz.y * 0.05) - Vector2(ls2, ls2) * 0.5, Vector2(ls2, ls2)), false)
	if _flash_time > 0.0 and _tex.has("fx_burst"):   # bought: a burst and stars
		var q := 1.0 - _flash_time / 0.3
		var bs := NODE_R * 2.0 * (1.0 + 1.2 * q) * _zoom
		draw_set_transform(_flash_at, q * 0.6, Vector2.ONE)
		draw_texture_rect(_tex.fx_burst, Rect2(-Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false, Color(1, 1, 1, 1.0 - q * q))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _tex.has("fx_star"):
			for j in 5:
				var at := _flash_at + Vector2.from_angle(j * TAU / 5.0 + 0.3) * bs * (0.35 + 0.3 * q)
				var ss := 34.0 * (1.0 - 0.5 * q)
				draw_texture_rect(_tex.fx_star, Rect2(at - Vector2(ss, ss) * 0.5, Vector2(ss, ss)), false, Color(1, 1, 1, 1.0 - q))
	# header, on a small chalkboard so it reads on the cork
	UiKit.nine(self, _tex.get("ui_chalkboard", null), _header_rect(), 60.0, 0.7)
	draw_string_outline(font, Vector2(60, 80), "token %s" % Game.fmt(Game.tokens), HORIZONTAL_ALIGNMENT_LEFT, -1, 52, 10, Color(0.1, 0.05, 0.02))
	draw_string(font, Vector2(60, 80), "token %s" % Game.fmt(Game.tokens), HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1.0, 0.93, 0.72))
	draw_string(font, Vector2(60, 125), _fit_line(tr("第 %d 顿饭 · 累计吐出 %s token") % [Game.runs + 1, Game.fmt(Game.total_tokens)], 26, 500), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.85, 0.7))
	if _flash_text != "":
		draw_multiline_string(font, Vector2(60, 296), _flash_text, HORIZONTAL_ALIGNMENT_LEFT, 500, 22, -1, Color(1.0, 0.85, 0.5))
	var sigs: Array = []
	for id in Game.active_signatures():
		sigs.append(tr(CanteenRun.NAMES[CanteenRun.KIND[id]]))
	if Game.stat("sig_slots") > 0.0:
		draw_string(font, Vector2(60, 255), _fit_line(tr("招牌菜：%s") % ("、".join(sigs) if not sigs.is_empty() else tr("（无）")), 24, 500), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.9, 0.7))
	var bt := Game.open_trial()
	if bt != "":
		draw_string(font, Vector2(60, _trial_status_y()), _fit_line(tr("最好的一顿 %s / 评测目标 %s") % [Game.fmt(Game.best_run), Game.fmt(Game.trial_target(bt))], 24, 500), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.8, 0.6))
	CanteenRun.load_menu()
	draw_string(font, Vector2(60, 215), tr("菜谱图鉴 %d / %d") % [Game.recipes.size(), CanteenRun.RECIPES.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.88, 0.55))
	draw_string(font, Vector2(60, 175), tr(Game.plate()), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1.0, 0.8, 0.45))
	if _hover != "" and not Game.node(_hover).is_empty() and not _has_input_modal() and not _tools_have_focus():
		_draw_tooltip(font, Game.node(_hover))


func _draw_pin(center_at: Vector2, paper: Rect2, zoom: float) -> void:
	if _tex.has("pin"):
		var ps := Vector2(16, 30) * zoom
		draw_texture_rect(_tex.pin, Rect2(Vector2(center_at.x - ps.x * 0.5, paper.position.y - ps.y * 0.55), ps), false)


func _feedback_height() -> float:
	return 0.0 if _flash_text.is_empty() else ThemeDB.fallback_font.get_multiline_string_size(_flash_text, HORIZONTAL_ALIGNMENT_LEFT, 500, 22).y


func _trial_status_y() -> float:
	return maxf(340.0, 300.0 + _feedback_height() + 16.0) if not _flash_text.is_empty() else 340.0


func _header_rect() -> Rect2:
	var bottom := 304.0
	if not _flash_text.is_empty(): bottom = 300.0 + _feedback_height() + 12.0
	if Game.open_trial() != "": bottom = _trial_status_y() + 24.0
	return Rect2(24, 14, 580, bottom - 14.0)


func _fit_line(text: String, fs: int, width: float) -> String:
	while text.length() > 1 and ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		text = text.left(text.length() - 2) + "…"
	return text


## A node's name in at most two lines of max_w px (English names are long): split at spaces,
## or anywhere for Chinese, and cut the rest with "…".
func _name_lines(font: Font, text: String, fs: int, max_w: float) -> Array:
	var fits := func(t: String) -> bool: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w
	if fits.call(text):
		return [text]
	if text.contains("："):   # 「System Prompt：今日菜单」: the meme on top, the plain name below
		var parts := text.split("：", true, 1)
		return [_name_lines(font, parts[0], fs, max_w)[0], _name_lines(font, parts[1], fs, max_w)[0]]
	var words: Array = Array(text.split(" ")) if text.contains(" ") else Array(text.split(""))
	var sep := " " if text.contains(" ") else ""
	var first := ""
	var i := 0
	while i < words.size() and fits.call((first + sep + words[i]) if first != "" else words[i]):
		first = (first + sep + words[i]) if first != "" else words[i]
		i += 1
	var rest := sep.join(words.slice(i))
	while rest.length() > 1 and not fits.call(rest):
		rest = rest.left(rest.length() - 2) + "…"
	return [first, rest] if first != "" else [rest]


func _tooltip_lines(n: Dictionary) -> Array:
	var id: String = n["id"]
	if not Game.is_visible(id):
		return [[tr("空白便签"), 34, Color.WHITE], [tr("满足前置技能与版本条件后，空白便签才会揭晓。"), 24, Color(0.95, 0.88, 0.75)], [tr("这里只预告下一层，暂时不能购买。"), 22, Color(0.8, 0.75, 0.7)]]
	var lines := [[tr(n["name"]), 34, Color.WHITE], [tr(n["desc"]), 24, Color(0.95, 0.88, 0.75)]]
	var need := int(n.get("need_levels", 0))
	var have := Game.ring_levels(int(n.get("ring", 0)))
	if n.get("locked", false):
		lines.append([tr("敬请期待"), 26, Color(0.6, 0.6, 0.65)])
	elif n.get("kind", "") == "ticket" and Game.is_maxed(id):
		lines.append([tr("已提交：点右下角红色按钮开始评测") if Game.open_trial() != "" else tr("已发布"), 26, Color(0.95, 0.82, 0.45)])
	elif Game.is_maxed(id):
		lines.append([tr("已满级"), 26, Color(0.95, 0.82, 0.45)])
	else:
		if n.get("key", false):
			lines.append([tr("新的赚钱方式"), 24, Color(1.0, 0.75, 0.3)])
		if need > have:
			lines.append([tr("要先在这一环升满 %d 级（现在 %d 级）") % [need, have], 26, Color(1.0, 0.7, 0.5)])
		var afford := Game.tokens >= Game.cost(id)
		lines.append([tr("花费 %s token") % Game.fmt(Game.cost(id)), 26, Color(0.75, 1.0, 0.8) if afford else Color(1.0, 0.55, 0.5)])
	if Game.level(id) > 0 and id != "start" and n.get("kind", "") != "ticket":
		lines.append([tr("退款：右键 / %s / 手柄 %s") % [Settings.binding_label("refund"), Settings.binding_label("refund", "gamepad")], 22, Color(0.8, 0.75, 0.7)])
		if Game.refund_floor(id) > 0:
			lines.append([tr("已有下游技能：只能退多余等级，最低保留 1 级。"), 22, Color(1.0, 0.75, 0.5)])
		else:
			lines.append([tr("可全额退还这项技能的全部等级。"), 22, Color(0.8, 0.75, 0.7)])
	return lines


func _tooltip_size(lines: Array) -> Vector2:
	var font := ThemeDB.fallback_font
	var w := 0.0
	var h := 72.0
	for l in lines:
		var sz := font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, 640.0, l[1])
		w = maxf(w, sz.x)
		h += sz.y + 10.0
	return Vector2(maxf(360, w + 80), h)


func _tooltip_rect(n: Dictionary, dimensions: Vector2) -> Rect2:
	var at := _at(n)
	var preferred := at + Vector2(TICKET.x * _zoom * 0.5 + 18, -60)
	var blocked := [_header_rect().grow(12), _bar.get_rect().grow(12)]
	for action in [_start, _trial]:
		if action.visible:
			blocked.append(action.get_rect().grow(18))
	for child in get_children():
		if child.has_meta("feature_card"):
			blocked.append(child.get_rect().grow(12))
	var selected := Rect2(at - TICKET * _zoom * 0.5, TICKET * _zoom).grow(8)
	var best := Rect2(preferred, dimensions)
	var best_score := INF
	# Try either side of the inspected ticket and the clear area beside the header.
	for x in [preferred.x, at.x - TICKET.x * _zoom * 0.5 - dimensions.x - 18, 630.0, 20.0, size.x - dimensions.x - 20]:
		for y in [preferred.y, 114.0, _header_rect().end.y + 18, size.y - dimensions.y - 20]:
			var rect := Rect2(Vector2(clampf(x, 20, size.x - dimensions.x - 20), clampf(y, 114, size.y - dimensions.y - 20)), dimensions)
			var score := rect.position.distance_to(preferred)
			for obstacle in blocked:
				score += rect.intersection(obstacle).get_area() * 1000.0
			score += rect.intersection(selected).get_area() * 10.0
			if score < best_score:
				best_score = score
				best = rect
	return best


func _draw_tooltip(font: Font, n: Dictionary) -> void:
	var lines := _tooltip_lines(n)
	_tooltip_bounds = _tooltip_rect(n, _tooltip_size(lines))
	UiKit.nine(self, _tex.get("ui_chalkboard", null), _tooltip_bounds, 60.0, 0.6)
	var y := _tooltip_bounds.position.y + 34
	for l in lines:
		draw_multiline_string(font, Vector2(_tooltip_bounds.position.x + 40, y + l[1]), l[0], HORIZONTAL_ALIGNMENT_LEFT, 640.0, l[1], -1, l[2])
		y += font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, 640.0, l[1]).y + 10.0
