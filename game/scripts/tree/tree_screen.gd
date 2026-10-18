class_name TreeScreen
extends Control
## The skill tree between shifts. Nodes come from res://data/skill_tree.json; a node appears
## once its version ring is released and a parent is owned. Click a node to buy a level, drag
## empty space to pan, then press 去打饭 for the next shift. Once the next version's ticket is
## bought, a red 提交评测 button starts its trial.
## Gamepad / keyboard: D-pad / stick / arrows move between nodes, A / Enter buys, Y / G goes to
## lunch, Start / Esc opens the settings.

signal start_run
signal start_trial(trial: String)
signal open_settings
signal to_title

const NODE_R := 44.0
const TICKET := Vector2(176, 116)     # a skill's meal ticket on the board, at zoom 1
const ZOOM := Vector2(0.45, 1.3)

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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	_bar.add_theme_constant_override("separation", 14)
	add_child(_bar)
	_build_bar()
	Game.changed.connect(_build_bar)
	for n in ["cork_bg", "ticket", "ticket_gold", "stamp", "pin", "icon_lock", "fx_burst", "fx_star", "ui_chalkboard"]:
		var f := "res://assets/canteen/%s.png" % n
		if ResourceLoader.exists(f):
			_tex[n] = load(f)
	Game.changed.connect(queue_redraw)
	Game.changed.connect(_update_trial_button)
	_show_newest_ring()
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


## The top bar. 今日菜单 and 招牌菜 show up once a skill unlocks them; a button the player has
## never pressed glows with a 「新！」 tag until they do.
func _build_bar() -> void:
	var specs: Array = [["book", tr("图鉴"), func(): add_child(RecipeBook.new())]]
	if Game.stat("menu_cut") > 0.0:
		specs.append(["menu", tr("今日菜单"), _open_menu])
	if Game.stat("sig_slots") > 0.0:
		specs.append(["sigs", tr("招牌菜"), _open_signatures])
	specs.append_array([["respec", tr("回滚"), _on_respec], ["settings", tr("设置"), func(): open_settings.emit()], ["title", tr("标题"), func(): to_title.emit()]])
	var key := ",".join(specs.map(func(x): return x[0]))
	if key == _bar_key:
		return
	_bar_key = key
	for c in _bar.get_children():
		c.queue_free()
	_new_buttons.clear()
	for spec in specs:
		var b := UiKit.button(spec[1], 26, Vector2(170, 64))
		var id: String = spec[0]
		var fn: Callable = spec[2]
		b.pressed.connect(func():
			if not Game.seen_buttons.has(id):
				Game.seen_buttons[id] = true
				_new_buttons.erase(b)
				Game.save_game()
			fn.call())
		_bar.add_child(b)
		if id in ["menu", "sigs"] and not Game.seen_buttons.has(id):
			_new_buttons[b] = id
			var dot := Control.new()   # the red dot sits on the button itself, above its art
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.position = Vector2(164, 6)
			dot.draw.connect(func():
				dot.draw_circle(Vector2.ZERO, 13.0, Color(1, 1, 1))
				dot.draw_circle(Vector2.ZERO, 10.0, Color(0.78, 0.22, 0.18)))
			b.add_child(dot)
			b.pressed.connect(dot.queue_free)
			if not Game.seen_buttons.has(id + "_card"):
				Game.seen_buttons[id + "_card"] = true
				_feature_card.call_deferred(id, fn)
	_bar.position = Vector2(1860 - specs.size() * 184 + 14, 30)


const FEATURES := {
	"menu": ["新功能：今日菜单", "开饭前划掉不想要的菜，想要的出得更多。"],
	"sigs": ["新功能：招牌菜", "选一道招牌菜，这顿它有特别加成。"],
}


## The first time a feature unlocks: a ticket-paper card slides in from the right with one plain
## sentence and a 「去看看」 button, and slides away by itself after a while.
func _feature_card(id: String, open: Callable) -> void:
	var card := Control.new()
	card.size = Vector2(440, 250)
	card.position = Vector2(1940, 150)
	card.z_index = 40
	add_child(card)
	var bg := TextureRect.new()
	if ResourceLoader.exists("res://assets/canteen/ui_paper.png"):
		bg.texture = load("res://assets/canteen/ui_paper.png")
	bg.size = card.size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	card.add_child(bg)
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
	var hide := func():
		if is_instance_valid(card):
			var tw2 := create_tween()
			tw2.tween_property(card, "position:x", 1940.0, 0.25)
			tw2.tween_callback(card.queue_free)
	go.pressed.connect(func():
		Game.seen_buttons[id] = true
		Game.save_game()
		_bar_key = ""
		_build_bar()
		hide.call()
		open.call())
	var tw := create_tween()
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
	var panel := PanelContainer.new()
	panel.position = Vector2(460, 140)
	panel.custom_minimum_size = Vector2(1000, 760)
	panel.z_index = 50
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiKit.label(tr("招牌菜（最多 %d 道）：选中的菜这一顿有特别加成") % int(Game.stat("sig_slots")), 32, UiKit.GOLD))
	CanteenRun.load_menu()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var any := false
	for id in CanteenRun.KIND:
		var k: int = CanteenRun.KIND[id]
		if CanteenRun.SIG[k] == null:
			continue
		var b := CheckButton.new()
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(470, 0)
		if Game.signature_available(id):
			any = true
			b.text = "%s：%s" % [tr(CanteenRun.NAMES[k]), _sig_text(CanteenRun.SIG[k])]
			b.button_pressed = Game.active_signatures().has(id)
			b.toggled.connect(func(_on):
				Game.toggle_signature(id)
				panel.queue_free()
				_open_signatures.call_deferred())
		else:
			b.text = tr("（%s：开档口或升级后解锁）") % tr(CanteenRun.NAMES[k])
			b.disabled = true
		grid.add_child(b)
	if not any:
		col.add_child(UiKit.label(tr("还没有能选的招牌菜：先在技能树上开档口、升级档口"), 24))
	var close := UiKit.button(tr("好了"), 30, Vector2(220, 70))
	close.set_meta("ui_back", true)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(panel.queue_free)
	col.add_child(close)


## 今日菜单 (System Prompt): strike up to menu_cut dishes of the open stalls off the menu.
func _open_menu() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(360, 120)
	panel.custom_minimum_size = Vector2(1200, 800)
	panel.z_index = 50
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var cut := int(Game.stat("menu_cut"))
	col.add_child(UiKit.label(tr("今日菜单：划掉的菜这一顿不出（可以划 %d 道，已划 %d 道）") % [cut, mini(Game.struck.size(), cut)], 30, UiKit.GOLD))
	if cut == 0:
		col.add_child(UiKit.label(tr("先在技能树上点「System Prompt：今日菜单」才能划菜"), 24))
	CanteenRun.load_menu()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for id in CanteenRun.KIND:
		var k: int = CanteenRun.KIND[id]
		var st: String = CanteenRun.STALL[k]
		if CanteenRun.IS_SET[k] or st == "" or Game.stat("stall_" + st) < CanteenRun.LEVEL[k]:
			continue
		var b := CheckButton.new()
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(280, 0)
		b.text = tr("划掉%s") % tr(CanteenRun.NAMES[k])
		b.button_pressed = Game.struck.has(id) and Game.struck.find(id) < cut
		b.disabled = cut == 0
		b.toggled.connect(func(_on):
			Game.toggle_struck(id)
			panel.queue_free()
			_open_menu.call_deferred())
		grid.add_child(b)
	var close := UiKit.button(tr("好了"), 30, Vector2(220, 70))
	close.set_meta("ui_back", true)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(panel.queue_free)
	col.add_child(close)


func _sig_text(e: Dictionary) -> String:
	if e.has("stack"):
		return tr("每吃一份，本顿它的价值 +%d%%（叠加）") % int(float(e.stack) * 100)
	if e.has("mult"):
		return tr("价值 ×%.1f，但它的档口出餐慢 %d%%") % [float(e.mult), int(float(e.slow) * 100)]
	return tr("每吃一份，均衡倍率 +%.2f") % float(e.balance)


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
	for n in Game.nodes:
		if Game.is_visible(n["id"]) and Rect2(_at(n) - TICKET * _zoom * 0.5, TICKET * _zoom).has_point(p):
			return n["id"]
	return ""


## Buys one level; returns true on success (also used by the autotest).
func try_buy(id: String) -> bool:
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


func _process(delta: float) -> void:
	_respec_armed = maxf(_respec_armed - delta, 0.0)
	_flash_time = maxf(_flash_time - delta, 0.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if get_children().any(func(c): return c is SettingsPanel):
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_settings.emit()
	elif event.is_action_pressed("start_shift"):
		get_viewport().set_input_as_handled()
		start_run.emit()
	elif event.is_action_pressed("deliver") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A):
		if _hover != "":
			get_viewport().set_input_as_handled()
			try_buy(_hover)
	else:
		for d in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
			if event.is_action_pressed(d[0]):
				get_viewport().set_input_as_handled()
				_step(d[1])
				return


## Gamepad cursor: the nearest visible node roughly in direction `dir` from the current one,
## and pan so it stays on screen.
func _step(dir: Vector2) -> void:
	if _hover == "":
		_hover = "start"
	else:
		var from := _pos(Game.node(_hover))
		var best := ""
		var best_d := INF
		for n in Game.nodes:
			if not Game.is_visible(n["id"]) or n["id"] == _hover:
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
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var nz := clampf(_zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), ZOOM.x, ZOOM.y)
		_pan = (_pan + Vector2(960, 540) - event.position) * (nz / _zoom) + event.position - Vector2(960, 540)   # zoom around the cursor
		_zoom = nz
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var rid := node_at(event.position)   # right click: refund this node
		if rid != "" and Game.level(rid) > 0:
			var back := Game.refund(rid)
			if back > 0.0:
				_flash_text = tr("退掉「%s」：返还 %s token") % [tr(Game.node(rid)["name"]), Game.fmt(back)]
				Audio.sfx("buy", -6.0)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_from = event.position
			_drag_moved = 0.0
		else:
			_dragging = false
			if _drag_moved < 8.0:
				var id := node_at(event.position)
				if id != "":
					try_buy(id)
	elif event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			_drag_moved += event.relative.length()
		_hover = node_at(event.position)


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
		if not Game.is_visible(n["id"]):
			continue
		for p in n["parents"]:
			if not Game.is_visible(p):
				continue
			var a := _at(Game.node(p))
			var b := _at(n)
			var owned := Game.level(n["id"]) > 0
			# red yarn pinned at both tickets, hanging slack: it sags more the longer it runs
			var sag := 14.0 * z + a.distance_to(b) * 0.18
			var mid := (a + b) * 0.5 + Vector2(0, sag * 2.0)
			var pts := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
			draw_polyline(pts, Color(0.78, 0.1, 0.1, 0.95) if owned else Color(0.6, 0.15, 0.12, 0.45), (4.0 if owned else 2.5) * z, true)
	for n in Game.nodes:
		var id: String = n["id"]
		if not Game.is_visible(id):
			continue
		var c := _at(n)
		var lv := Game.level(id)
		var ticket: bool = n.get("kind", "") == "ticket"
		var sz := TICKET * z
		var r := Rect2(c - sz * 0.5, sz)
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
		# the name on the ticket (two lines at most), the level on the tear-off stub
		var fs := int(21 * z)
		var label := _name_lines(font, tr(n["name"]), fs, sz.x * 0.74)
		var y := c.y - (label.size() - 1) * fs * 0.6 + fs * 0.1
		for line in label:
			var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(c.x - sz.x * 0.08 - tw * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.3, 0.17, 0.08))
			y += fs * 1.2
		var lvtext: String = tr("门票") if ticket else "%d/%d" % [lv, int(n["max"])]
		var ls := int(16 * z)
		var lw := font.get_string_size(lvtext, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
		draw_string(font, Vector2(r.end.x - sz.x * 0.11 - lw * 0.5, c.y + ls * 0.35), lvtext, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Color(0.45, 0.25, 0.12))
		if lv > 0 and _tex.has("stamp"):   # 已兑: a stamp, bigger once maxed
			var ss := sz.y * (0.62 if Game.is_maxed(id) else 0.42)
			var sc := r.position + Vector2(sz.x * 0.86, sz.y * 0.86)   # on the corner, clear of the name
			draw_set_transform(sc, -0.25, Vector2.ONE)
			draw_texture_rect(_tex.stamp, Rect2(-Vector2(ss, ss) * 0.5, Vector2(ss, ss)), false, Color(1, 1, 1, 0.8))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _tex.has("pin"):
			var ps := 30.0 * z
			draw_texture_rect(_tex.pin, Rect2(Vector2(c.x - ps * 0.5, r.position.y - ps * 0.55), Vector2(ps, ps)), false)
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
	UiKit.nine(self, _tex.get("ui_chalkboard", null), Rect2(24, 14, 580, 290 if Game.open_trial() == "" else 350), 60.0, 0.7)
	draw_string_outline(font, Vector2(60, 80), "token %s" % Game.fmt(Game.tokens), HORIZONTAL_ALIGNMENT_LEFT, -1, 52, 10, Color(0.1, 0.05, 0.02))
	draw_string(font, Vector2(60, 80), "token %s" % Game.fmt(Game.tokens), HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1.0, 0.93, 0.72))
	draw_string(font, Vector2(60, 125), tr("第 %d 顿饭 · 累计吐出 %s token") % [Game.runs + 1, Game.fmt(Game.total_tokens)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.85, 0.7))
	if _flash_text != "":
		draw_string(font, Vector2(60, 300), _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.5))
	var sigs: Array = []
	for id in Game.active_signatures():
		sigs.append(tr(CanteenRun.NAMES[CanteenRun.KIND[id]]))
	if Game.stat("sig_slots") > 0.0:
		draw_string(font, Vector2(60, 255), tr("招牌菜：%s") % ("、".join(sigs) if not sigs.is_empty() else tr("（无）")), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.9, 0.7))
	var bt := Game.open_trial()
	if bt != "":
		draw_string(font, Vector2(60, 340), tr("最好的一顿 %s / 评测目标 %s") % [Game.fmt(Game.best_run), Game.fmt(Game.trial_target(bt))], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.8, 0.6))
	CanteenRun.load_menu()
	draw_string(font, Vector2(60, 215), tr("菜谱图鉴 %d / %d") % [Game.recipes.size(), CanteenRun.RECIPES.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.88, 0.55))
	draw_string(font, Vector2(60, 175), tr(Game.plate()), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1.0, 0.8, 0.45))
	if _hover != "":
		_draw_tooltip(font, Game.node(_hover))


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


func _draw_tooltip(font: Font, n: Dictionary) -> void:
	var id: String = n["id"]
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
		if Game.level(id) > 0:
			lines.append([tr("右键退掉这个技能（全额退款）"), 22, Color(0.8, 0.75, 0.7)])
		if need > have:
			lines.append([tr("要先在这一环升满 %d 级（现在 %d 级）") % [need, have], 26, Color(1.0, 0.7, 0.5)])
		var afford := Game.tokens >= Game.cost(id)
		lines.append([tr("花费 %s token") % Game.fmt(Game.cost(id)), 26, Color(0.75, 1.0, 0.8) if afford else Color(1.0, 0.55, 0.5)])
	const WRAP := 640.0
	var w := 0.0
	var h := 40.0
	for l in lines:
		var sz := font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, WRAP, l[1])
		w = maxf(w, sz.x)
		h += sz.y + 10.0
	var pos := _at(n) + Vector2(TICKET.x * _zoom * 0.5 + 16, -60)
	pos.x = minf(pos.x, size.x - w - 60)
	pos.y = clampf(pos.y, 10.0, size.y - h - 10.0)
	UiKit.nine(self, _tex.get("ui_chalkboard", null), Rect2(pos, Vector2(w + 40, h)).grow(10.0), 60.0, 0.6)
	var y := pos.y + 20
	for l in lines:
		draw_multiline_string(font, Vector2(pos.x + 20, y + l[1]), l[0], HORIZONTAL_ALIGNMENT_LEFT, WRAP, l[1], -1, l[2])
		y += font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, WRAP, l[1]).y + 10.0
