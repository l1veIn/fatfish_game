class_name TitleScreen
extends Control
## The title screen: the canteen at night with food drifting down, 大肥鱼 on the right, the logo
## and the menu on the left. Signals go to main.gd.
## Before V4 she is the early, 木讷 大肥鱼 (Game.emotion()): waist up, holding her iron basin,
## deadpan. Pat her head (the cursor turns into a hand): the first pats she just takes, then she
## side-eyes you, pouts, and at last puts the basin on her head; now the cursor is a spoon and a
## click knocks on the basin. Leave her alone and the basin comes off again.
## From V4 she is the standing, smiling drawing and a poke makes her cheer.

signal play
signal open_settings
signal open_credits
signal quit

const FOOD := ["ball", "bowl", "leg", "gold", "veg", "dump"]

var _food: Array = []          # {tex, pos, vel, rot, spin, scale}
var _fish: FishRig
var _logo: Control
var _t := 0.0
var _menu: VBoxContainer
var _poke_cd := 0.0
var _seated := false
var _pats := 0.0          # how fed up she is: +1 a pat, slowly forgiven
var _helmet_t := 0.0      # > 0: the basin is on her head (seconds left unless knocked)
var _knocks := 0
var _cursor := ""         # "", "hand", "spoon"
const HEAD := Rect2(230, 30, 570, 530)   # her head (and the basin on it) in the seated drawing, texture px
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
	_seated = _fish.emote < 2
	if _seated:
		_fish.seated = true
		_fish.idle_clip = "title_basin"
		_fish.height = 780.0                 # her head the same size as the standing drawing's (height 1000)
		_fish.position = Vector2(1400, 1050)
	else:
		_fish.idle_clip = "title_idle"
		_fish.height = 1000.0
		_fish.position = Vector2(1390, 1048)
	add_child(_fish)

	_logo = Control.new()
	_logo.position = Vector2(120, 90)
	add_child(_logo)
	var shadow := UiKit.label(tr("吃白饭的大肥鱼"), 128, Color(0.1, 0.05, 0.02, 0.6))
	shadow.position = Vector2(8, 10)
	_logo.add_child(shadow)
	var logo := UiKit.label(tr("吃白饭的大肥鱼"), 128, Color(1.0, 0.93, 0.72), 30)
	_logo.add_child(logo)
	var tag := UiKit.label(tr("接住梁阿姨抛来的饭，喂饱大肥鱼"), 34, Color(0.98, 0.84, 0.6), 10)
	tag.position = Vector2(10, 168)
	_logo.add_child(tag)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(150, 420)
	_menu.add_theme_constant_override("separation", 18)
	add_child(_menu)
	var start := UiKit.button(tr("开始上班") if Game.runs == 0 else tr("继续上班"), 40, Vector2(420, 96))
	start.pressed.connect(func(): play.emit())
	_menu.add_child(start)
	if Game.runs > 0:
		var info := UiKit.label(tr("第 %d 顿饭 · %s · %s token") % [Game.runs + 1, Game.plate(), Game.fmt(Game.tokens)], 24, Color(0.95, 0.88, 0.75), 8)
		_menu.add_child(info)
	var book := UiKit.button(tr("菜谱图鉴"), 34, Vector2(420, 80))
	book.pressed.connect(func():
		var b := RecipeBook.new()
		b.closed.connect(func(): start.grab_focus())
		add_child(b))
	_menu.add_child(book)
	var settings := UiKit.button(tr("设置"), 34, Vector2(420, 80))
	settings.pressed.connect(func(): open_settings.emit())
	_menu.add_child(settings)
	var credits := UiKit.button(tr("鸣谢"), 34, Vector2(420, 80))
	credits.pressed.connect(func(): open_credits.emit())
	_menu.add_child(credits)
	if not OS.has_feature("web"):
		var q := UiKit.button(tr("退出游戏"), 34, Vector2(420, 80))
		q.set_meta("ui_back", true)
		q.pressed.connect(func(): quit.emit())
		_menu.add_child(q)
	start.grab_focus.call_deferred()

	var credit := UiKit.label(tr("角色「蓝色大肥鱼」：原型「溟月」© 上善无形，女仆版 © ZipZipPipe，依 CC BY-NC-SA 4.0 二创。本作为免费粉丝作品，与 DeepSeek 官方无关。"), 20, Color(0.85, 0.78, 0.68), 6)
	credit.position = Vector2(0, 1036)
	credit.size = Vector2(1920, 30)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(credit)
	var ver := UiKit.label("Demo v" + str(ProjectSettings.get_setting("application/config/version", "")), 20, Color(0.8, 0.72, 0.62), 6)
	ver.position = Vector2(1700, 1000)
	ver.size = Vector2(190, 30)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	_intro()
	Audio.music("bgm_title")
	Audio.ambience("")


## The logo drops in with a bounce, the buttons slide in one after another.
func _intro() -> void:
	_logo.position.y = -260
	create_tween().tween_property(_logo, "position:y", 90.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	for f in _food:
		f.pos += f.vel * delta
		f.rot += f.spin * delta
		if f.pos.y > 1180:
			f.pos = Vector2(randf_range(0, 1920), -100)
	_logo.rotation = sin(_t * 1.3) * 0.012
	if _seated:
		_update_mood(delta)
	queue_redraw()


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
	draw_rect(Rect2(0, 1020, 1920, 60), Color(0.04, 0.02, 0.01, 0.55))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _seated:
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
