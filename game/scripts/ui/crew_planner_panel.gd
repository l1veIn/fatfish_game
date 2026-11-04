extends Control
## Between-meal choices only. Game owns validation, persistence and the next-meal snapshot.
signal closed
const INK := Color("4a2914")
const SOFT := Color("79604b")
const RED := Color("a2422b")
const PAPER := preload("res://assets/canteen/ui_paper.png")
const RecipePicker := preload("res://scripts/ui/helper_recipe_picker.gd")
const ROLES := ["sweep", "recipe", "nutrition"]
const ROLE_NAMES := ["补漏", "配餐", "营养"]
const TRICKS := {
	"wen": ["宽口接菜", "问问：接菜范围更宽。"],
	"pu": ["吸近好菜", "谱谱：把附近有用的菜吸过来。"],
	"g": ["跳起来接", "小G：跳起来接更高的菜。"],
	"ke": ["捡起漏菜", "克劳：捡起地上有用的菜。"],
	"zi": ["跑得更快", "双子：跑得更快。"],
	"ge": ["首菜优质", "格格质检：每盒首份普通菜升为优质。"],
}
const AUTOMATION := {
	"auto_push": ["自动推空盒", "空手时自动拿起一个空饭盒。"],
	"auto_return": ["满盒回收", "装满后自动送到饭桌。"],
	"fuse3": ["模型融合", "三份相同散菜自动合成；暂停后可以保留单品拼盘。"],
	"temp": ["Temperature", "接菜时可能换成更高档菜，或提升品质。"],
	"regen": ["重新生成", "送饭时可能把散菜升级。"],
	"overfit": ["过拟合", "顿悟后，散菜可能变成青菜。"],
	"bon": ["Best-of-N", "自动留最贵整盒；暂停后可手动留盒。"],
}
var mode := "crew"
var _selected := "wen"
var _body: Control
var _tabs: Array[Button] = []
var _cards: Dictionary = {}
var _role_buttons: Dictionary = {}
var _recipe_buttons: Dictionary = {}
var _auto_buttons: Dictionary = {}
var _controls: Array[Control] = []
var _close: Button
var _activate: Button
var _count: Label
var _reason: Label
var _notice := ""
var _closed := false
var _recipe_picker: Control
var _recipe_open: Button
var _saved_focus: Array = []


func _ready() -> void:
	size = Vector2(1920, 1080)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	CanteenRun.load_menu()
	_label(self, tr("自动化"), Rect2(112, 80, 1200, 64), 48)
	_label(self, tr("开饭前安排好，所有改动下顿生效。"), Rect2(114, 156, 1280, 46), 27, SOFT)
	for i in 2:
		var button := _button(self, tr("助手排班") if i == 0 else tr("技能开关"), Rect2(112 + 300 * i, 218, 280, 66), "page_" + str(i))
		button.pressed.connect(show_mode.bind("crew" if i == 0 else "automation"))
		_tabs.append(button)
	_close = _button(self, tr("返回"), Rect2(1600, 88, 200, 64), "close")
	_close.set_meta("ui_back", true)
	_close.pressed.connect(close)
	_count = _label(self, "", Rect2(750, 218, 1040, 76), 26, SOFT)
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	Game.changed.connect(_refresh)
	_refresh()
	if not _closed:
		if mode == "crew":
			_cards[_selected].grab_focus.call_deferred()
		else:
			_tabs[1].grab_focus.call_deferred()


func _draw() -> void:
	draw_rect(ScreenLayout.full_rect(self), Color(0.06, 0.035, 0.015, 0.83))
	draw_style_box(UiKit.box(UiKit.CREAM, UiKit.WOOD, 2, 18, 3), Rect2(64, 48, 1792, 984))
	draw_texture_rect_region(PAPER, Rect2(76, 60, 1768, 960), Rect2(70, 70, 180, 110), Color(1, 1, 1, 0.18))
	if mode == "crew":
		draw_line(Vector2(1268, 310), Vector2(1268, 904), Color(0.53, 0.34, 0.18, 0.25), 2)


func show_mode(page: String) -> void:
	if not Game.automation_pages().has(page): return
	mode = page
	_notice = ""
	_refresh()
	_tabs[0 if mode == "crew" else 1].grab_focus.call_deferred()


func _refresh() -> void:
	if not is_instance_valid(_body) or _closed: return
	var pages := Game.automation_pages()
	if pages.is_empty():
		close()
		return
	if not pages.has(mode): mode = pages[0]
	var focus := get_viewport().gui_get_focus_owner()
	var focus_key: String = str(focus.get_meta("crew_key", "")) if focus != null else ""
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_cards.clear()
	_role_buttons.clear()
	_recipe_buttons.clear()
	_auto_buttons.clear()
	_controls.clear()
	var tab_position := 0
	for i in 2:
		var available := pages.has("crew" if i == 0 else "automation")
		_tabs[i].visible = available
		_tabs[i].disabled = not available
		if available:
			_tabs[i].position.x = 112 + 300 * tab_position
			tab_position += 1
			_controls.append(_tabs[i])
		_style(_tabs[i], (mode == "crew") == (i == 0))
	if mode == "crew":
		_build_crew()
	else:
		_build_automation()
	_controls.append(_close)
	_wire_focus()
	var restored := false
	for control in _controls:
		if not control.disabled and str(control.get_meta("crew_key", "")) == focus_key:
			control.grab_focus.call_deferred()
			restored = true
			break
	if not focus_key.is_empty() and not restored:
		_tabs[0 if mode == "crew" else 1].grab_focus.call_deferred()
	queue_redraw()


func _build_crew() -> void:
	var team := Game.active_helpers()
	var cap := Game.helper_capacity()
	_count.text = tr("出场 %d / %d · 剩余 %d 个名额") % [team.size(), cap, maxi(cap - team.size(), 0)]
	if cap == 0: _count.text += "\n" + tr("先在技能树学习招募，增加出场名额。")
	elif team.size() == cap: _count.text += "\n" + tr("名额已满：先让一位休息，再换人。")
	for i in Game.HELPER_IDS.size():
		var id: String = Game.HELPER_IDS[i]
		var config := Game.helper_config(id)
		var card := _button(_body, "", Rect2(112 + (i % 3) * 380, 320 + (i / 3) * 264, 358, 242), "member_" + id)
		_style(card, id == _selected)
		var picture := "res://assets/crew/%s%s.png" % [id, "" if config.active else "_sleep"]
		_picture(card, picture, Rect2(12, 18, 142, 192))
		_label(card, tr(CanteenRun.CREW[id].name), Rect2(164, 24, 180, 50), 31)
		_label(card, tr("出场") if config.active else tr("休息"), Rect2(164, 83, 180, 40), 26, SOFT)
		_role_mark(card, str(config.role), Rect2(164, 141, 26, 26))
		_label(card, tr(ROLE_NAMES[ROLES.find(config.role)]), Rect2(198, 133, 146, 42), 26)
		_label(card, tr(str(TRICKS[id][0])), Rect2(164, 182, 180, 54), 22, SOFT)
		card.pressed.connect(_select_member.bind(id))
		_cards[id] = card
		_controls.append(card)
	var current := Game.helper_config(_selected)
	_label(_body, tr(CanteenRun.CREW[_selected].name), Rect2(1300, 320, 470, 52), 37)
	_activate = _button(_body, tr("让这位休息") if current.active else tr("安排出场"), Rect2(1300, 386, 470, 62), "activate")
	_activate.disabled = cap == 0
	_activate.pressed.connect(_toggle_active)
	_controls.append(_activate)
	for i in ROLES.size():
		var role: String = ROLES[i]
		var button := _button(_body, "", Rect2(1300 + i * 160, 474, 150, 58), "role_" + role)
		_role_mark(button, role, Rect2(10, 16, 26, 26))
		_label(button, tr(ROLE_NAMES[i]), Rect2(44, 10, 100, 38), 22)
		button.disabled = cap == 0 or (role == "recipe" and (Game.stat("fc") <= 0 or Game.helper_recipe_options().is_empty())) or (role == "nutrition" and Game.stat("nutri") <= 0)
		_style(button, role == current.role)
		button.pressed.connect(_choose_role.bind(role))
		_role_buttons[role] = button
		_controls.append(button)
	var reason: String = _notice if _notice != "" else tr(str(current.reason))
	if reason.is_empty():
		if Game.stat("fc") <= 0 or Game.stat("nutri") <= 0:
			reason = tr("配餐需学会点单；营养需学会营养师。")
		elif Game.helper_recipe_options().is_empty(): reason = tr("当前菜单与饭盒没有可配的菜谱。")
	_reason = _label(_body, reason, Rect2(1300, 546, 470, 96), 23, RED if reason != "" else SOFT)
	_label(_body, tr(str(TRICKS[_selected][1])), Rect2(112, 858, 1130, 50), 26)
	if current.role == "recipe":
		var selected_recipe := ""
		var selected_kind := -1
		for option in Game.helper_recipe_options():
			if str(option.id) == str(current.recipe):
				selected_recipe = tr(str(option.name))
				selected_kind = int(option.kind)
		if selected_kind >= 0:
			_picture(_body, "res://assets/canteen/food_%s.png" % CanteenRun.FOOD_ART[selected_kind], Rect2(1300, 650, 100, 100))
		_label(_body, tr("目标：%s") % selected_recipe, Rect2(1414, 648, 356, 100), 25)
		_recipe_open = _button(_body, tr("选择套餐"), Rect2(1300, 766, 470, 62), "choose_recipe")
		_recipe_open.pressed.connect(_open_recipes)
		_controls.append(_recipe_open)
		_label(_body, tr("配齐才送；稀有原料等得更久。"), Rect2(1300, 840, 470, 68), 23, SOFT)
	else:
		var description := tr("接住有用的漏菜，帮你补上顾不到的地方。") if current.role == "sweep" else tr("按主食、荤菜、素菜 4:3:3 的缺口补餐，也会考虑正在收集和等待的饭盒。")
		_label(_body, description, Rect2(1300, 662, 470, 220), 27, SOFT)
	for i in 3:
		var state: String = ["catch", "return", "fetch"][i]
		var caption: String = [tr("圆点：接菜"), tr("箭头：送餐"), tr("沙漏：等盒")][i]
		var mark := Control.new()
		mark.position = Vector2(114 + i * 340, 911)
		mark.size = Vector2(20, 26)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(mark)
		mark.draw.connect(func(): CanteenRun.draw_helper_state(mark, Rect2(Vector2.ZERO, mark.size), state))
		_label(_body, caption, Rect2(145 + i * 340, 908, 300, 34), 22, SOFT)
	_label(_body, tr("接力：每种职责最多存一份，共三份。亲手送出下一只非空饭盒时消费，每份收益 +15% / +30%（按编排等级）。"), Rect2(112, 946, 1660, 76), 23, SOFT)


## These are the same shape primitives as the small in-shift badges, not substitutes.
func _role_mark(parent: Node, role: String, rect: Rect2) -> void:
	var mark := Control.new()
	mark.position = rect.position
	mark.size = rect.size
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_meta("helper_role", role)
	parent.add_child(mark)
	mark.draw.connect(func(): CanteenRun.draw_helper_role(mark, Rect2(Vector2.ZERO, mark.size), role))


func _open_recipes() -> void:
	if is_instance_valid(_recipe_picker): return
	_saved_focus.clear()
	for control in _controls:
		_saved_focus.append([weakref(control), control.focus_mode])
		control.focus_mode = Control.FOCUS_NONE
	var picker := RecipePicker.new()
	picker.selected = str(Game.helper_config(_selected).recipe)
	picker.member_name = tr(CanteenRun.CREW[_selected].name)
	_recipe_picker = picker
	picker.cancelled.connect(_close_recipes)
	picker.chosen.connect(func(id: String):
		_close_recipes(false)
		_choose_recipe(id)
		_recipe_open.grab_focus.call_deferred())
	add_child(picker)


func _close_recipes(restore_focus := true) -> void:
	if not is_instance_valid(_recipe_picker): return
	remove_child(_recipe_picker)
	_recipe_picker.queue_free()
	_recipe_picker = null
	for state in _saved_focus:
		var control = state[0].get_ref()
		if is_instance_valid(control): control.focus_mode = state[1]
	_saved_focus.clear()
	if restore_focus and is_instance_valid(_recipe_open): _recipe_open.grab_focus.call_deferred()


func _select_member(id: String) -> void:
	_selected = id
	_notice = ""
	_refresh()
	_cards[id].grab_focus.call_deferred()


func _toggle_active() -> void:
	var current := Game.helper_config(_selected)
	if not current.active and Game.active_helpers().size() >= Game.helper_capacity():
		_notice = tr("名额已满：先让一位休息，再换人。")
		_refresh()
		return
	_apply(not current.active, str(current.role), str(current.recipe))


func _choose_role(role: String) -> void:
	var config := Game.helper_config(_selected)
	var recipe: String = str(config.recipe)
	if role == "recipe" and recipe.is_empty():
		var options := Game.helper_recipe_options()
		if options.is_empty(): return
		recipe = str(options[0].id)
	_apply(bool(config.active), role, recipe)


func _choose_recipe(id: String) -> void:
	_apply(bool(Game.helper_config(_selected).active), "recipe", id)


func _apply(active: bool, role: String, recipe: String) -> void:
	_notice = ""
	if not Game.set_helper_config(_selected, active, role, recipe):
		_notice = tr("配置未保存，请检查名额、技能和当前菜单。")
		_refresh()


func _build_automation() -> void:
	_count.text = tr("已购买的技能才可切换；暂停不退款，下顿生效。")
	for i in Game.AUTOMATION_KEYS.size():
		var key: String = Game.AUTOMATION_KEYS[i]
		var spec: Array = AUTOMATION[key]
		var reserve := key == "bon"
		var origin := Vector2(112 + (i % 2) * 850, 326 + (i / 2) * 210)
		if reserve:
			origin = Vector2(112, 952)
		var card := Panel.new()
		card.position = origin
		card.size = Vector2(1662, 64) if reserve else Vector2(812, 186)
		card.add_theme_stylebox_override("panel", UiKit.box(Color("f6e6c2"), UiKit.WOOD, 1, 12))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(card)
		_label(card, tr(str(spec[0])), Rect2(22, 10, 250, 44) if reserve else Rect2(22, 16, 555, 50), 27 if reserve else 31)
		_label(card, tr(str(spec[1])), Rect2(285, 10, 1100, 44) if reserve else Rect2(22, 81, 765, 88), 22 if reserve else 25, SOFT)
		var owned := Game.stat(key) > 0
		var button := _button(card, tr("开启") if Game.automation_enabled(key) else (tr("暂停") if owned else tr("未学会")), Rect2(1453, 8, 187, 48) if reserve else Rect2(601, 16, 187, 55), "auto_" + key)
		button.disabled = not owned
		_style(button, Game.automation_enabled(key))
		button.pressed.connect(func(): Game.set_automation(key, not Game.automation_enabled(key)))
		_auto_buttons[key] = button
		_controls.append(button)


func _wire_focus() -> void:
	var active := _controls.filter(func(c): return not c.disabled)
	for i in active.size():
		var control: Control = active[i]
		control.focus_next = control.get_path_to(active[(i + 1) % active.size()])
		control.focus_previous = control.get_path_to(active[posmod(i - 1, active.size())])
		control.focus_neighbor_bottom = control.focus_next
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_right = control.focus_next
		control.focus_neighbor_left = control.focus_previous


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_recipe_picker): return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closed: return
	_closed = true
	closed.emit()
	queue_free()


func _label(parent: Node, text: String, rect: Rect2, font_size: int, color := INK) -> Label:
	var label := UiKit.label("", font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("crew_rect", rect.size)
	parent.add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	return label


func _picture(parent: Node, path: String, rect: Rect2) -> void:
	var picture := TextureRect.new()
	picture.texture = load(path)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	picture.position = rect.position
	picture.size = rect.size
	picture.set_meta("crew_rect", rect.size)


func _button(parent: Node, text: String, rect: Rect2, key: String) -> Button:
	var button := UiKit.button(text, 27, rect.size)
	button.set_meta("crew_key", key)
	parent.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button


func _style(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", UiKit.box(UiKit.CREAM_HI if selected else UiKit.CREAM, UiKit.WOOD, 2, 12, 4))
