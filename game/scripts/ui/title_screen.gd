class_name TitleScreen
extends Control
## The title screen: a generated bilingual wordmark and restrained canteen menu on the left,
## the full character in warm light on the right. Signals go to main.gd.
## Before V4 she is the early, 木讷 大肥鱼 (Game.emotion()): standing, holding her iron basin,
## deadpan. Pat her head (the cursor turns into a hand): the first pats she just takes, then she
## side-eyes you, pouts, and at last puts the basin on her head; now the cursor is a spoon and a
## click knocks on the basin. Leave her alone and the basin comes off again.
## From V4 she is the standing, smiling drawing and a poke makes her cheer.

signal play
signal open_settings
signal open_credits
signal replay_ending
signal quit

const FOOD := ["ball", "bowl", "leg", "gold", "veg", "dump"]

var _food: Array = []          # {tex, pos, vel, rot, spin, scale}
var _fish: FishRig
var _logo: Control
var _t := 0.0
var _menu: VBoxContainer
var _poke_cd := 0.0
var _early := false
var _buttons: Array[Button] = []
var _pats := 0.0          # how fed up she is: +1 a pat, slowly forgiven
var _helmet_t := 0.0      # > 0: the basin is on her head (seconds left unless knocked)
var _knocks := 0
var _cursor := ""         # "", "hand", "spoon"
const HEAD := Rect2(250, 10, 530, 460)   # her head (and the basin on it) in the standing drawing, texture px
const ANNOYED_AT := 4.0
const POUT_AT := 7.0
const HELMET_AT := 9.0
const CURSORS := {"hand": ["res://assets/ui/cursor_hand.png", Vector2(36, 26)],
	"spoon": ["res://assets/ui/cursor_spoon.png", Vector2(14, 12)]}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_fish = FishRig.new()
	_fish.emote = Game.emotion()
	_early = _fish.emote < 2
	_fish.basin = _early
	_fish.idle_clip = "title_basin" if _early else "title_idle"
	_fish.height = 890.0
	_fish.position = Vector2(1460, 1005)
	add_child(_fish)
	_fish.set_process(not Settings.reduced_motion)
	Settings.changed.connect(_apply_motion)

	_logo = TextureRect.new()
	_logo.name = "GameWordmark"
	_logo.position = Vector2(46, 8)
	_logo.size = Vector2(1100, 430)
	var logo_view := _logo as TextureRect
	logo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_view.texture = load("res://assets/ui/premium/logo_en.png" if Settings.is_english() else "res://assets/ui/premium/logo_zh.png")
	logo_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	var tag := UiKit.label(tr("接住梁阿姨抛来的饭，喂饱大肥鱼"), 29, Color(0.88, 0.84, 0.74))
	tag.position = Vector2(146, 408)
	tag.size = Vector2(850, 62)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tag)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(146, 510)
	_menu.custom_minimum_size.x = 800
	_menu.add_theme_constant_override("separation", 14)
	add_child(_menu)
	var start := UiKit.button(tr("开始上班") if Game.runs == 0 else tr("继续上班"), 38, Vector2(800, 92))
	start.name = "Continue" if Game.runs > 0 else "Start"
	start.pressed.connect(func(): play.emit())
	_menu.add_child(start)
	_buttons.append(start)
	if Game.runs > 0:
		var info := UiKit.label(tr("第 %d 顿饭 · %s · %s token") % [Game.runs + 1, tr(Game.plate()), Game.fmt(Game.tokens)], 24, Color(0.85, 0.85, 0.78))
		info.custom_minimum_size = Vector2(800, 42)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_menu.add_child(grid)
	var book := UiKit.button(tr("菜谱图鉴"), 29, Vector2(393, 72))
	book.pressed.connect(func():
		var b := RecipeBook.new()
		b.closed.connect(func(): book.grab_focus())
		add_child(b))
	grid.add_child(book)
	_buttons.append(book)
	var achievements := UiKit.button(tr("食堂成就"), 29, Vector2(393, 72))
	achievements.name = "Achievements"
	achievements.pressed.connect(func():
		var panel := AchievementsPanel.new()
		panel.closed.connect(func(): achievements.grab_focus())
		add_child(panel))
	grid.add_child(achievements)
	_buttons.append(achievements)
	var settings := UiKit.button(tr("设置"), 29, Vector2(393, 72))
	settings.name = "Settings"
	settings.pressed.connect(func(): open_settings.emit())
	grid.add_child(settings)
	_buttons.append(settings)
	var credits := UiKit.button(tr("鸣谢"), 29, Vector2(393, 72))
	credits.pressed.connect(func(): open_credits.emit())
	grid.add_child(credits)
	_buttons.append(credits)
	if Game.version >= Game.VERSIONS.size() - 1:
		var ending := UiKit.button(tr("重看结局"), 29, Vector2(393, 72))
		ending.name = "ReplayEnding"
		ending.pressed.connect(func(): replay_ending.emit())
		grid.add_child(ending)
		_buttons.append(ending)
	if not OS.has_feature("web"):
		var q := UiKit.button(tr("退出游戏"), 29, Vector2(393, 72))
		q.set_meta("ui_back", true)
		q.pressed.connect(func(): quit.emit())
		grid.add_child(q)
		_buttons.append(q)
	for button in _buttons:
		_style_button(button, button == start)
	_wire_focus()
	start.grab_focus.call_deferred()

	var credit := UiKit.label(tr("角色「蓝色大肥鱼」：原型「溟月」© 上善无形，女仆版 © ZipZipPipe，依 CC BY-NC-SA 4.0 二创。本作为免费粉丝作品，与 DeepSeek 官方无关。"), 18, Color(0.76, 0.78, 0.76))
	credit.position = Vector2(86, 1016)
	credit.size = Vector2(1560, 60)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(credit)
	var ver := UiKit.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 20, Color(0.78, 0.8, 0.79))
	ver.position = Vector2(1638, 1024)
	ver.size = Vector2(190, 30)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	_intro()
	Audio.music("bgm_title")
	Audio.ambience("")


## A quiet fade keeps the generated lettering legible throughout the entrance.
func _intro() -> void:
	if Settings.reduced_motion:
		return
	_logo.modulate.a = 0.0
	create_tween().tween_property(_logo, "modulate:a", 1.0, 0.55)
	_menu.modulate.a = 0.0
	create_tween().tween_property(_menu, "modulate:a", 1.0, 0.4).set_delay(0.12)


func _style_button(button: Button, primary: bool) -> void:
	var bg := Color(0.93, 0.79, 0.48) if primary else Color(0.97, 0.94, 0.86)
	var ink := Color(0.10, 0.23, 0.29)
	button.add_theme_stylebox_override("normal", UiKit.box(bg, Color(0.66, 0.53, 0.32), 2, 12, 3))
	button.add_theme_stylebox_override("hover", UiKit.box(bg.lightened(0.08), Color(0.94, 0.81, 0.54), 2, 12, 3))
	button.add_theme_stylebox_override("pressed", UiKit.box(bg.darkened(0.05), Color(0.66, 0.53, 0.32), 2, 12, 2))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)


func _process(delta: float) -> void:
	_t += delta
	_poke_cd = maxf(_poke_cd - delta, 0.0)
	if not Settings.reduced_motion:
		for f in _food:
			f.pos += f.vel * delta
			f.rot += f.spin * delta
			if f.pos.y > 1180:
				f.pos = Vector2(randf_range(0, 1920), -100)

	if _early:
		_update_mood(delta)
	queue_redraw()


func _apply_motion() -> void:
	_fish.set_process(not Settings.reduced_motion)
	if Settings.reduced_motion:
		_logo.rotation = 0.0


func _wire_focus() -> void:
	for i in _buttons.size():
		var b: Button = _buttons[i]
		b.focus_previous = b.get_path_to(_buttons[posmod(i - 1, _buttons.size())])
		b.focus_next = b.get_path_to(_buttons[(i + 1) % _buttons.size()])
		if i == 0:
			b.focus_neighbor_bottom = b.get_path_to(_buttons[1])
			b.focus_neighbor_top = b.get_path_to(_buttons.back())
			continue
		var j := i - 1
		b.focus_neighbor_top = b.get_path_to(_buttons[i - 2] if j >= 2 else _buttons[0])
		b.focus_neighbor_bottom = b.get_path_to(_buttons[i + 2] if i + 2 < _buttons.size() else _buttons[0])
		b.focus_neighbor_left = b.get_path_to(_buttons[i - 1] if j % 2 == 1 else b)
		b.focus_neighbor_right = b.get_path_to(_buttons[i + 1] if j % 2 == 0 and i + 1 < _buttons.size() else b)


## Patience comes back slowly; the basin comes off when nobody knocks for a while.
func _update_mood(delta: float) -> void:
	if _helmet_t > 0.0:
		_helmet_t -= delta
		if _helmet_t <= 0.0:
			_pats = ANNOYED_AT   # still a bit cross
			_fish.idle_clip = "annoyed"
			_fish.play("annoyed")
	else:
		_pats = maxf(_pats - 0.3 * delta, 0.0)
		_fish.idle_clip = "annoyed" if _pats >= ANNOYED_AT else "title_basin"
		if _fish.clip == "annoyed" and _pats < ANNOYED_AT:
			_fish.play("title_basin")
	var over := _fish.tex_rect(HEAD).has_point(get_local_mouse_position())
	_set_cursor(("spoon" if _helmet_t > 0.0 else "hand") if over else "")


func _set_cursor(kind: String) -> void:
	if kind == _cursor:
		return
	_cursor = kind
	if kind == "":
		Input.set_custom_mouse_cursor(null)
	else:
		Input.set_custom_mouse_cursor(load(CURSORS[kind][0]), Input.CURSOR_ARROW, CURSORS[kind][1])


func _exit_tree() -> void:
	if _cursor != "":
		Input.set_custom_mouse_cursor(null)


func _draw() -> void:
	draw_texture_rect(preload("res://assets/canteen/bg_wall.png"), Rect2(0, 0, 1920, 1080), false, Color(0.78, 0.76, 0.68))
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.06, 0.15, 0.2, 0.22))
	draw_texture_rect(UiKit.glow(), Rect2(1030, 65, 920, 980), false, Color(1.0, 0.83, 0.52, 0.48))
	draw_rect(Rect2(0, 0, 1000, 1080), Color(0.045, 0.13, 0.19, 0.94))
	draw_polygon(PackedVector2Array([Vector2(1000, 0), Vector2(1440, 0), Vector2(1440, 1080), Vector2(1000, 1080)]),
		PackedColorArray([Color(0.045, 0.13, 0.19, 0.94), Color(0.045, 0.13, 0.19, 0.0), Color(0.045, 0.13, 0.19, 0.0), Color(0.045, 0.13, 0.19, 0.94)]))
	draw_line(Vector2(146, 478), Vector2(946, 478), Color(0.76, 0.64, 0.4, 0.55), 2)
	draw_circle(Vector2(146, 478), 4, Color(0.86, 0.72, 0.44))
	draw_rect(Rect2(0, 998, 1920, 82), Color(0.035, 0.09, 0.13, 0.92))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _early:
		if _fish.tex_rect(HEAD).has_point(event.position):
			_pat()
		return
	# poke 大肥鱼 (V4 on: she has feelings now)
	if Rect2(1080, 280, 620, 760).has_point(event.position) and _poke_cd <= 0.0:
		_poke_cd = 0.8
		Audio.vo("fish_happy", 2)
		_fish.bounce()
		_fish.play(["happy", "not_fat", "surprised"].pick_random())


## A pat on the head (or, with the basin on, a knock on it).
func _pat() -> void:
	if _helmet_t > 0.0:
		_knocks += 1
		_helmet_t = 5.0
		Audio.sfx("clang", -4.0)
		_fish.play("knock")
		_fish.bounce()
		if _knocks % 4 == 0:
			Audio.vo("fish_hmph", 1, 0.6)
		return
	_pats += 1.0
	if _pats >= HELMET_AT:
		_helmet_t = 6.0
		_knocks = 0
		_fish.idle_clip = "helmet"
		_fish.play("helmet", true)
		Audio.sfx("helmet", -6.0)
		Audio.vo("fish_hmph", 2)
	elif _pats >= POUT_AT:
		_fish.play("pout")
		if _pats < POUT_AT + 1.0:
			Audio.vo("fish_hmph", 1)
	elif _pats >= ANNOYED_AT:
		_fish.play("annoyed")
		_fish.bounce()
	else:
		_fish.play("pat")
		if _pats >= 3.0:
			Audio.vo("fish_wait", 1)   # 「嗯？」
