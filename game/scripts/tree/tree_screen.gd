class_name TreeScreen
extends Control
## Authored node coordinates/prices stay unchanged. A fixed detail column separates inspection
## from purchase, while the clipped map never covers the toolbar or next-meal actions.

signal start_run
signal start_trial(trial: String)
signal open_settings
signal to_title

const TICKET := Vector2(172, 108)
const ZOOM := Vector2(0.55, 1.5)
const BOARD := Rect2(32, 178, 1264, 724)
const DETAIL := Rect2(1320, 178, 568, 724)
const PAPER := Color("f6efdf")
const NAVY := Color("193b49")
const INK := Color("233d46")
const SOFT := Color("65736e")
const BRASS := Color("b89758")
const MealPlannerPanel := preload("res://scripts/ui/meal_planner.gd")
const TICKET_ART := preload("res://assets/canteen/ticket.png")
const CORK_ART := preload("res://assets/canteen/cork_bg.png")
const STAMP_ART := preload("res://assets/canteen/stamp.png")
# Category art describes what the upgrade changes; individual skills keep their authored names.
const ART_GROUPS := {
	"food_bowl": ["start", "stall_main", "eat", "ttft", "stream", "mtp", "busy", "queue", "sleep"],
	"food_kungpao": ["stall_wok"], "food_dump": ["stall_dim"],
	"food_leg": ["stall_fry"], "food_icecream": ["stall_sweet"],
	"food_set_bento": ["menu", "moe", "prompt", "fewshot", "inject", "agentwf", "fuse3", "hodge", "agirec", "emerge"],
	"icon_box": ["vram", "ocr", "mat", "fill", "compress", "warm"],
	"icon_clock": ["think", "diverge", "converge", "cot", "rag"],
	"icon_leaf": ["canteen_std", "overfit", "rlhf", "constit", "grok", "warmup", "aftertaste", "nutri"],
	"icon_chain": ["multiturn", "memory"],
	"icon_flame": ["temp", "hot"],
	"icon_dice": ["lunch", "halluc", "regen", "spec", "bon"],
	"icon_bolt": ["api", "batch", "peak", "drift", "conc"],
	"icon_token": ["lora", "final", "eos"],
	"icon_crown": ["sft", "dpo", "fp32", "critic", "bench"],
	"icon_bell": ["skills", "hire", "orch", "fc", "clip", "async"],
}

var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _drag_moved := 0.0
var _hover := "start" # Persistent selection; name retained for the existing debug/test tools.
var _bar: HBoxContainer
var _bar_key := ""
var _board: Control
var _start: Button
var _trial: Button
var _buy: Button
var _refund: Button
var _planner: Control
var _book: Control
var _modal_focus: Array = []
var _tooltip_bounds := DETAIL
var _detail_name: Label
var _detail_status: Label
var _detail_icon: TextureRect
var _art_cache := {}
var _detail_body: Label
var _detail_path: Label
var _detail_price: Label
var _detail_scroll: ScrollContainer
var _budget: Label
var _version: Label
var _notice: Label
var _zoom_label: Label
var _last_detail := ""
var _respec_armed := 0.0
var _flash_text := ""
var _flash_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	CanteenRun.load_menu()
	_label(tr("下一顿，更进一步"), Rect2(48, 28, 700, 60), 44, PAPER)
	_budget = _label("", Rect2(48, 98, 570, 42), 32, Color("e3c78c"))
	_version = _label("", Rect2(630, 106, 1250, 38), 25, Color("d2ddd7"))
	_bar = HBoxContainer.new()
	_bar.position = Vector2(800, 30)
	_bar.add_theme_constant_override("separation", 10)
	add_child(_bar)
	_build_bar()
	_board = Control.new()
	_board.position = BOARD.position
	_board.size = BOARD.size
	_board.clip_contents = true
	_board.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.focus_mode = Control.FOCUS_ALL
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_map_input)
	add_child(_board)
	_label(tr("技能路线"), Rect2(54, 194, 650, 40), 27, INK)
	var recent := _button(tr("当前进度"), Vector2(254, 48), 24)
	recent.position = Vector2(772, 190)
	recent.pressed.connect(_show_newest_ring)
	add_child(recent)
	for spec in [["−", -1, 1050], ["+", 1, 1208]]:
		var b := _button(spec[0], Vector2(54, 48), 28)
		b.position = Vector2(spec[2], 190)
		b.pressed.connect(func(): _change_zoom(pow(1.15, spec[1]), BOARD.get_center()))
		add_child(b)
	_zoom_label = _label("100%", Rect2(1108, 198, 94, 34), 23, SOFT)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(tr("技能详情"), Rect2(1348, 194, 512, 30), 24, SOFT)
	_detail_name = _label("", Rect2(1348, 238, 512, 90), 34, INK)
	_detail_status = _label("", Rect2(1348, 340, 512, 44), 27, NAVY)
	_detail_icon = TextureRect.new()
	_detail_icon.position = Vector2(1796, 330)
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail_icon)
	_detail_icon.size = Vector2(64, 64)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.position = Vector2(1348, 398)
	_detail_scroll.size = Vector2(512, 282)
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.follow_focus = true
	add_child(_detail_scroll)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 26)
	_detail_scroll.add_child(copy)
	_detail_body = UiKit.label("", 27, INK)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(_detail_body)
	_detail_path = UiKit.label("", 24, SOFT)
	_detail_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_detail_path)
	_detail_price = _label("", Rect2(1348, 704, 512, 40), 29, INK)
	_buy = _button(tr("升级"), Vector2(322, 70), 29, true)
	_buy.position = Vector2(1348, 762)
	_buy.pressed.connect(func(): try_buy(_hover))
	add_child(_buy)
	_refund = _button(tr("退还"), Vector2(174, 70), 27)
	_refund.position = Vector2(1686, 762)
	_refund.pressed.connect(_refund_selected)
	add_child(_refund)
	_label(tr("选中节点后查看详情；购买会即时保存。"), Rect2(1348, 850, 512, 38), 21, SOFT)
	_notice = _label(tr("拖动查看路线 · 滚轮缩放\n方向键选节点 · Enter / A 升级 · G / Y 开饭"), Rect2(48, 950, 880, 96), 25, PAPER)
	_start = _button(tr("去打饭"), Vector2(368, 82), 36, true)
	_start.position = Vector2(1520, 950)
	_start.pressed.connect(func(): start_run.emit())
	add_child(_start)
	_trial = _button("", Vector2(520, 82), 28)
	_trial.position = Vector2(980, 950)
	_trial.pressed.connect(_on_trial)
	add_child(_trial)
	Game.changed.connect(_refresh)
	_show_newest_ring()
	_refresh()
	_board.grab_focus.call_deferred()
	Audio.music("bgm_tree")
	Audio.ambience("")


func _button(text: String, dimensions: Vector2, fs: int, primary := false) -> Button:
	var b := UiKit.button(text, fs, dimensions)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, PAPER if primary else INK)
	b.add_theme_stylebox_override("normal", UiKit.box(NAVY if primary else PAPER, BRASS, 1, 12, 1))
	b.add_theme_stylebox_override("hover", UiKit.box(NAVY.lightened(0.12) if primary else Color("fff9ec"), BRASS, 2, 12, 1))
	b.add_theme_stylebox_override("pressed", UiKit.box(NAVY.darkened(0.12) if primary else Color("e6dcc7"), BRASS, 2, 12, 1))
	b.add_theme_stylebox_override("focus", UiKit.box(Color.TRANSPARENT, Color("daaa50"), 3, 12, 3))
	b.add_theme_stylebox_override("disabled", UiKit.box(Color("e3dfd3"), Color("c9c7bb"), 1, 12, 1))
	b.add_theme_color_override("font_disabled_color", SOFT)
	return b


func _label(text: String, rect: Rect2, fs: int, color: Color) -> Label:
	var l := UiKit.label(text, fs, color)
	l.position = rect.position
	l.size = rect.size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _build_bar() -> void:
	var specs: Array = [["book", tr("图鉴"), _open_book]]
	if Game.stat("menu_cut") > 0.0:
		specs.append(["menu", tr("今日菜单"), _open_menu])
	if Game.stat("sig_slots") > 0.0:
		specs.append(["sigs", tr("招牌菜"), _open_signatures])
	specs.append_array([["respec", tr("回滚"), _on_respec], ["settings", tr("设置"), func(): open_settings.emit()], ["title", tr("标题"), func(): to_title.emit()]])
	var key := ",".join(specs.map(func(s): return s[0]))
	if key == _bar_key:
		return
	_bar_key = key
	for child in _bar.get_children():
		_bar.remove_child(child)
		child.queue_free()
	for spec in specs:
		var b := _button(spec[1], Vector2(170, 56), 25)
		b.name = "Tree_" + spec[0]
		var id: String = spec[0]
		var action: Callable = spec[2]
		b.pressed.connect(func():
			if not Game.seen_buttons.has(id):
				Game.seen_buttons[id] = true
				Game.save_game()
			action.call())
		_bar.add_child(b)
	_bar.position.x = 1888 - _bar.get_combined_minimum_size().x


func _refresh() -> void:
	_build_bar()
	_budget.text = "%s  token" % Game.fmt(Game.tokens)
	_version.text = "%s   ·   %s" % [tr(Game.plate()), tr("第 %d 顿饭 · 累计吐出 %s token") % [Game.runs + 1, Game.fmt(Game.total_tokens)]]
	_update_trial_button()
	_last_detail = ""
	_refresh_detail()
	queue_redraw()


func _update_trial_button() -> void:
	var t := Game.open_trial()
	_trial.visible = t != ""
	if t != "":
		_trial.text = tr("提交评测 · 门票 %s") % Game.fmt(Game.trial_fee(t))


func _refresh_detail() -> void:
	if _hover == "" or Game.node(_hover).is_empty():
		_hover = "start"
	var n: Dictionary = Game.node(_hover)
	var key := _hover + ":" + str(Game.level(_hover)) + ":" + str(Game.tokens) + ":" + str(Game.version)
	if key == _last_detail:
		return
	_last_detail = key
	_detail_scroll.scroll_vertical = 0
	_detail_name.text = tr(n.name)
	_detail_icon.texture = _skill_art(n)
	_detail_body.text = tr(n.desc)
	var maxed := Game.is_maxed(_hover)
	var locked := bool(n.get("locked", false))
	var ticket: bool = n.get("kind", "") == "ticket"
	_detail_status.text = tr("敬请期待") if locked else tr("已发布") if ticket and maxed and Game.open_trial() == "" else tr("已解锁评测") if ticket and maxed else tr("已满级") if maxed else tr("等级 %d / %d") % [Game.level(_hover), int(n.max)]
	var path: Array[String] = []
	for parent in n.parents:
		path.append(("✓ " if Game.level(parent) > 0 else "○ ") + tr(Game.node(parent).name))
	_detail_path.text = tr("解锁路线") + "\n" + "\n".join(path) if not path.is_empty() else tr("这是你的第一步。")
	var need := int(n.get("need_levels", 0))
	var have := Game.ring_levels(int(n.get("ring", 0)))
	if need > have:
		_detail_path.text += "\n\n" + tr("要先在这一环升满 %d 级（现在 %d 级）") % [need, have]
	_detail_price.text = "" if maxed or locked else tr("花费 %s token") % Game.fmt(Game.cost(_hover))
	_buy.text = tr("已满级") if maxed and not ticket else tr("已提交") if maxed else tr("解锁评测") if ticket else tr("升级")
	_buy.disabled = not Game.can_buy(_hover)
	_refund.disabled = Game.level(_hover) <= 0 or _hover == "start" or ticket


func _skill_art(n: Dictionary) -> Texture2D:
	var key := "icon_crown" if n.get("kind", "") == "ticket" else "food_bowl"
	for category in ART_GROUPS:
		if n.id in ART_GROUPS[category]:
			key = category
			break
	if not _art_cache.has(key):
		_art_cache[key] = load("res://assets/canteen/" + key + ".png")
	return _art_cache[key]


func _on_trial() -> void:
	var t := Game.open_trial()
	if Game.pay_trial(t):
		Audio.sfx("ticket", -3.0)
		start_trial.emit(t)
	else:
		Audio.sfx("deny", -6.0)


func _on_respec() -> void:
	if _respec_armed <= 0.0:
		_respec_armed = 3.0
		_flash_text = tr("再点一次「回滚」：所有技能全额退款，重新加点")
	else:
		_respec_armed = 0.0
		_flash_text = tr("回滚完成：退回 %s token") % Game.fmt(Game.respec())
		Audio.sfx("buy", -3.0)
	_flash_time = 5.0


func _refund_selected() -> void:
	var back := Game.refund(_hover)
	if back > 0.0:
		_flash_text = tr("退掉「%s」：返还 %s token") % [tr(Game.node(_hover).name), Game.fmt(back)]
		_flash_time = 5.0
		Audio.sfx("buy", -6.0)


func _open_book() -> void:
	if is_instance_valid(_book):
		return
	_book = RecipeBook.new()
	var opener: WeakRef = weakref(get_viewport().gui_get_focus_owner())
	_book.tree_exited.connect(func():
		_book = null
		var old = opener.get_ref()
		if is_instance_valid(old):
			old.grab_focus.call_deferred())
	add_child(_book)


func _open_menu() -> void:
	_open_planner("menu")


func _open_signatures() -> void:
	_open_planner("signatures")


func _open_planner(page: String) -> void:
	if is_instance_valid(_planner):
		_planner.show_mode(page)
		return
	var opener: WeakRef = weakref(get_viewport().gui_get_focus_owner())
	_dragging = false
	_modal_focus.clear()
	for control in find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
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
			var c = state.node.get_ref()
			if is_instance_valid(c):
				c.focus_mode = state.mode
		_modal_focus.clear()
		var old = opener.get_ref()
		if is_instance_valid(old) and old.is_inside_tree():
			old.grab_focus.call_deferred()
		else:
			_board.grab_focus.call_deferred())
	add_child(panel)


func _show_newest_ring() -> void:
	_hover = "start"
	for n in Game.nodes:
		if int(n.get("ring", 0)) == Game.version and Game.is_visible(n.id) and not Game.is_maxed(n.id):
			_hover = n.id
			break
	_pan = -_pos(Game.node(_hover)) * _zoom


func center() -> Vector2:
	return BOARD.get_center() + _pan + Vector2(0, 28)


func _pos(n: Dictionary) -> Vector2:
	return Vector2(n.pos[0], n.pos[1])


func _at(n: Dictionary) -> Vector2:
	return center() + _pos(n) * _zoom


func node_at(p: Vector2) -> String:
	if not BOARD.grow(-10).has_point(p) or p.y < 248:
		return ""
	for n in Game.nodes:
		if Game.is_visible(n.id) and Rect2(_at(n) - TICKET * _zoom * 0.5, TICKET * _zoom).has_point(p):
			return n.id
	return ""


func try_buy(id: String) -> bool:
	_hover = id
	if Game.buy(id):
		Audio.sfx("buy")
		_refresh_detail()
		return true
	Audio.sfx("deny", -6.0)
	return false


func _process(delta: float) -> void:
	_respec_armed = maxf(0, _respec_armed - delta)
	_flash_time = maxf(0, _flash_time - delta)
	_notice.text = _flash_text if _flash_time > 0 else tr("拖动查看路线 · 滚轮缩放\n方向键选节点 · Enter / A 升级 · G / Y 开饭")
	_refresh_detail()
	_board.queue_redraw()


func _blocked() -> bool:
	return is_instance_valid(_planner) or is_instance_valid(_book) or get_children().any(func(c): return c is SettingsPanel)


func _input(event: InputEvent) -> void:
	# Releasing over a toolbar/button still ends a map drag even when that control consumes it.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_settings.emit()
	elif event.is_action_pressed("start_shift"):
		get_viewport().set_input_as_handled()
		start_run.emit()
	elif event.is_action_pressed("deliver") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A):
		if get_viewport().gui_get_focus_owner() == _board:
			get_viewport().set_input_as_handled()
			try_buy(_hover)
	else:
		for d in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
			if event.is_action_pressed(d[0]) and get_viewport().gui_get_focus_owner() == _board:
				get_viewport().set_input_as_handled()
				_step(d[1])
				return


func _map_input(event: InputEvent) -> void:
	if _blocked():
		return
	for d in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
		if event.is_action_pressed(d[0]):
			_board.accept_event()
			_step(d[1])
			return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("deliver"):
		_board.accept_event()
		try_buy(_hover)


func _step(dir: Vector2) -> void:
	if _hover == "":
		_hover = "start"
	var origin := _pos(Game.node(_hover))
	var best := ""
	var score := INF
	for n in Game.nodes:
		if not Game.is_visible(n.id) or n.id == _hover:
			continue
		var delta := _pos(n) - origin
		var facing := delta.normalized().dot(dir)
		if facing < 0.5:
			continue
		var distance := delta.length() * (2.0 - facing)
		if distance < score:
			score = distance
			best = n.id
	if best != "":
		_hover = best
		Audio.sfx("ui_hover", -10)
	var at := _at(Game.node(_hover))
	if not BOARD.grow(-140).has_point(at):
		_pan += BOARD.get_center() - at
	_refresh_detail()


func _change_zoom(factor: float, at: Vector2) -> void:
	var nz := clampf(_zoom * factor, ZOOM.x, ZOOM.y)
	_pan += (at - center()) * (1.0 - nz / _zoom)
	_zoom = nz
	_zoom_label.text = "%d%%" % roundi(_zoom * 100)


func _gui_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event is InputEventMouseButton:
		if not BOARD.has_point(event.position):
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_change_zoom(1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = 0
				_board.grab_focus()
			else:
				_dragging = false
				if _drag_moved < 8.0:
					var id := node_at(event.position)
					if id != "":
						_hover = id
						_refresh_detail()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var id := node_at(event.position)
			if id != "":
				_hover = id
				_refund_selected()
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.relative
		_drag_moved += event.relative.length()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), NAVY)
	draw_line(Vector2(32, 157), Vector2(1888, 157), BRASS, 2)
	draw_style_box(UiKit.box(Color("eee7d5"), BRASS, 1, 16, 1), BOARD)
	draw_style_box(UiKit.box(PAPER, BRASS, 1, 16, 1), DETAIL)
	draw_line(Vector2(32, 924), Vector2(1888, 924), Color("47606a"), 1)


func _draw_board() -> void:
	var font := ThemeDB.fallback_font
	# Use only the cork interior. The source's wooden frame is never stretched into this map.
	_board.draw_texture_rect_region(CORK_ART, Rect2(2, 74, BOARD.size.x - 4, BOARD.size.y - 76),
		Rect2(80, 80, 1760, 920), Color(1, 1, 1, 0.20))
	for n in Game.nodes:
		if not Game.is_visible(n.id):
			continue
		for parent in n.parents:
			if not Game.is_visible(parent):
				continue
			var a := _at(Game.node(parent)) - BOARD.position
			var b := _at(n) - BOARD.position
			var highlight: bool = n.id == _hover or parent == _hover
			_board.draw_line(a, b, BRASS if highlight else Color("8b9c92"), 4.0 if highlight else 2.0, true)
	for n in Game.nodes:
		if not Game.is_visible(n.id):
			continue
		var id: String = n.id
		var rect := Rect2(_at(n) - BOARD.position - TICKET * _zoom * 0.5, TICKET * _zoom)
		var owned := Game.level(id) > 0
		var selected := id == _hover
		var maxed := Game.is_maxed(id)
		var tint := Color(0.92, 1.0, 0.95) if maxed else Color.WHITE if owned or Game.can_buy(id) else Color(0.88, 0.90, 0.88)
		var border := NAVY if selected else BRASS if Game.can_buy(id) else Color("a7b0a1")
		_board.draw_style_box(UiKit.box(Color(0.15, 0.20, 0.18, 0.13), Color.TRANSPARENT, 0, 5), Rect2(rect.position + Vector2(0, 2), rect.size))
		# A real paper ticket with an intact perforated stub. Only its blank centre stretches.
		UiKit.nine(_board, TICKET_ART, rect, 24, minf(0.5 * _zoom, 0.5), tint)
		if selected or Game.can_buy(id):
			_board.draw_style_box(UiKit.box(Color.TRANSPARENT, border, 3 if selected else 1, 5, 3 if selected else 1), rect)
		if maxed and _zoom >= 0.85:
			var seal := 24 * _zoom
			_board.draw_texture_rect(STAMP_ART, Rect2(rect.end - Vector2(seal + 12, seal + 8), Vector2.ONE * seal), false, Color(0.80, 0.88, 0.87, 0.80))
		if selected:
			_board.draw_rect(Rect2(rect.position + Vector2(12, 10), Vector2(5, rect.size.y - 20)), BRASS)
		var fs := maxi(19, roundi(23 * _zoom))
		var lines := _name_lines(font, tr(n.name), fs, rect.size.x - 34)
		if _zoom < 0.85 and lines.size() > 1:
			lines = [lines[0]]
		var y := rect.position.y + maxf(24, 29 * _zoom)
		for line in lines:
			_board.draw_string(font, Vector2(rect.position.x + 18, y), line, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, fs, INK)
			y += fs * 1.16
		var lv := "%d / %d" % [Game.level(id), int(n.max)]
		if maxed:
			lv = "✓ " + lv
		elif n.get("locked", false):
			lv = "○ " + lv
		_board.draw_string(font, rect.position + Vector2(18, rect.size.y - 13), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(17, roundi(19 * _zoom)), SOFT)
	_board.draw_rect(Rect2(0, 0, BOARD.size.x, 72), Color("eee7d5"))
	_board.draw_line(Vector2(18, 72), Vector2(BOARD.size.x - 18, 72), Color("cec7b4"), 1)


func _name_lines(font: Font, text: String, fs: int, max_w: float) -> Array:
	var lines: Array[String] = []
	var current := ""
	var words := text.split(" ") if text.contains(" ") else text.split("")
	var separator := " " if text.contains(" ") else ""
	for word in words:
		var candidate := current + (separator if current != "" else "") + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w and current != "":
			lines.append(current)
			current = word
		else:
			current = candidate
	if current != "":
		lines.append(current)
	if Settings.is_english() and not text.contains(" ") and lines.size() > 1:
		lines = [text]  # Truncate a long English word instead of leaving a one-letter second line.
	if lines.size() > 2:
		lines = [lines[0], lines[1] + "…"]
	for i in lines.size():
		while lines[i].length() > 1 and font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			lines[i] = lines[i].left(lines[i].length() - 2) + "…"
	return lines
