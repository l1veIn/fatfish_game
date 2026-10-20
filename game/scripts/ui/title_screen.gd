class_name TitleScreen
extends Control
## The title screen: the canteen at night with food drifting down, 大肥鱼 on the right, the logo
## and the menu on the left. Signals go to main.gd.
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
	var textures := []
	for k in FOOD:
		textures.append(load("res://assets/canteen/food_%s.png" % k))
	for i in 16:
		var f := {"tex": textures[i % textures.size()], "pos": Vector2(randf_range(0, 1920), randf_range(-1080, 1080)),
			"vel": Vector2(randf_range(-20, 20), randf_range(40, 110)), "rot": randf() * TAU,
			"spin": randf_range(-0.8, 0.8), "scale": randf_range(0.35, 0.7)}
		f["vel"] *= f["scale"]   # far (small) food falls slower: a little depth
		_food.append(f)
	_food.sort_custom(func(a, b): return a.scale < b.scale)

	_fish = FishRig.new()
	_fish.emote = Game.emotion()
	_early = _fish.emote < 2
	_fish.basin = _early
	_fish.idle_clip = "title_basin" if _early else "title_idle"
	_fish.height = 1000.0
	_fish.position = Vector2(1390, 1048)
	add_child(_fish)
	_fish.set_process(not Settings.reduced_motion)
	Settings.changed.connect(_apply_motion)

	# Keep the warm canteen composition; only replace the placeholder type with the art wordmark.
	_logo = TextureRect.new()
	_logo.name = "GameWordmark"
	_logo.position = Vector2(80, 20)
	_logo.size = Vector2(900, 360)
	var wordmark := _logo as TextureRect
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.texture = load("res://assets/ui/premium/logo_en.png" if Settings.is_english() else "res://assets/ui/premium/logo_zh.png")
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	var tag := UiKit.label(tr("接住梁阿姨抛来的饭，喂饱大肥鱼"), 32, Color(0.98, 0.84, 0.6), 8)
	tag.position = Vector2(150, 390)
	tag.size = Vector2(850, 60)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tag)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(150, 472)
	_menu.custom_minimum_size.x = 620
	_menu.add_theme_constant_override("separation", 16)
	add_child(_menu)
	var start := UiKit.button(tr("开始上班") if Game.runs == 0 else tr("继续上班"), 38, Vector2(620, 92))
	start.name = "Continue" if Game.runs > 0 else "Start"
	start.pressed.connect(func(): play.emit())
	_menu.add_child(start)
	_buttons.append(start)
	if Game.runs > 0:
		var info := UiKit.label(tr("第 %d 顿饭 · %s · %s token") % [Game.runs + 1, tr(Game.plate()), Game.fmt(Game.tokens)], 24, Color(0.95, 0.88, 0.75), 8)
		info.custom_minimum_size = Vector2(620, 42)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_menu.add_child(grid)
	var book := UiKit.button(tr("菜谱图鉴"), 29, Vector2(302, 76))
	book.pressed.connect(func():
		var b := RecipeBook.new()
		b.closed.connect(func(): book.grab_focus())
		add_child(b))
	grid.add_child(book)
	_buttons.append(book)
	var achievements := UiKit.button(tr("食堂成就"), 29, Vector2(302, 76))
	achievements.name = "Achievements"
	achievements.pressed.connect(func():
		var panel := AchievementsPanel.new()
		panel.closed.connect(func(): achievements.grab_focus())
		add_child(panel))
	grid.add_child(achievements)
	_buttons.append(achievements)
	var settings := UiKit.button(tr("设置"), 29, Vector2(302, 76))
	settings.name = "Settings"
	settings.pressed.connect(func(): open_settings.emit())
	grid.add_child(settings)
	_buttons.append(settings)
	var credits := UiKit.button(tr("鸣谢"), 29, Vector2(302, 76))
	credits.pressed.connect(func(): open_credits.emit())
	grid.add_child(credits)
	_buttons.append(credits)
	if Game.version >= Game.VERSIONS.size() - 1:
		var ending := UiKit.button(tr("重看结局"), 29, Vector2(302, 76))
		ending.name = "ReplayEnding"
		ending.pressed.connect(func(): replay_ending.emit())
		grid.add_child(ending)
		_buttons.append(ending)
	if not OS.has_feature("web"):
		var q := UiKit.button(tr("退出游戏"), 29, Vector2(302, 76))
		q.set_meta("ui_back", true)
		q.pressed.connect(func(): quit.emit())
		grid.add_child(q)
		_buttons.append(q)
	_wire_focus()
	start.grab_focus.call_deferred()

	var author := LinkButton.new()
	author.name = "AuthorLink"
	author.text = tr("作者：%s") % "夸夸家族族长"
	author.uri = "https://space.bilibili.com/2501012"
	author.tooltip_text = author.uri
	if OS.has_feature("web"):
		author.uri = ""
		author.pressed.connect(ToyPlatform.open_author)
	author.focus_mode = Control.FOCUS_ALL
	author.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	author.position = Vector2(150, 1000)
	author.custom_minimum_size.y = 40
	author.add_theme_font_override("font", load("res://assets/ui/ui_font.tres"))
	author.add_theme_font_size_override("font_size", 22)
	author.add_theme_color_override("font_color", Color(0.85, 0.78, 0.68))
	author.add_theme_color_override("font_hover_color", UiKit.GOLD)
	author.add_theme_color_override("font_focus_color", UiKit.GOLD)
	author.add_theme_constant_override("outline_size", 6)
	author.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.03))
	add_child(author)
	author.focus_previous = author.get_path_to(_buttons.back())
	author.focus_next = author.get_path_to(start)
	author.focus_neighbor_top = author.focus_previous
	author.focus_neighbor_bottom = author.focus_next
	_buttons.back().focus_next = _buttons.back().get_path_to(author)
	_buttons.back().focus_neighbor_bottom = _buttons.back().focus_next
	start.focus_previous = start.get_path_to(author)
	start.focus_neighbor_top = start.focus_previous
	var ver := UiKit.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 20, Color(0.8, 0.72, 0.62), 6)
	ver.position = Vector2(1700, 1000)
	ver.size = Vector2(190, 30)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	_intro()
	Audio.music("bgm_title")
	Audio.ambience("")


## The logo drops in with a bounce, the buttons slide in one after another.
func _intro() -> void:
	if Settings.reduced_motion:
		return
	_logo.position.y = -260
	create_tween().tween_property(_logo, "position:y", 20.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var i := 0
	for c in _menu.get_children():
		var item := c as Control
		item.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.25 + 0.08 * i)
		tw.tween_property(item, "modulate:a", 1.0, 0.25)
		i += 1


func _process(delta: float) -> void:
	_t += delta
	_poke_cd = maxf(_poke_cd - delta, 0.0)
	if not Settings.reduced_motion:
		for f in _food:
			f.pos += f.vel * delta
			f.rot += f.spin * delta
			if f.pos.y > 1180:
				f.pos = Vector2(randf_range(0, 1920), -100)
		_logo.rotation = sin(_t * 1.3) * 0.012
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
	draw_texture(preload("res://assets/canteen/bg_wall.png"), Vector2.ZERO, Color(1.25, 1.18, 1.1))
	# warm light from the right, darker on the left where the menu is
	var grad := PackedColorArray([Color(0.05, 0.02, 0.0, 0.55), Color(0.05, 0.02, 0.0, 0.0)])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1100, 0), Vector2(1100, 1080), Vector2(0, 1080)]),
		PackedColorArray([grad[0], grad[1], grad[1], grad[0]]))
	for f in _food:
		var tex: Texture2D = f.tex
		var s: float = f.scale
		draw_set_transform(f.pos, f.rot, Vector2(s, s))
		draw_texture(tex, -tex.get_size() * 0.5, Color(1, 1, 1, 0.35 + s * 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
