extends Node2D
## Promo v2 (2026-10-21) 《超可爱的大肥鱼增量小游戏，要实现AGI得先吃饱！》
## New illustrations (art_src/promo) carry the story; real PC gameplay runs unchanged in a viewport.
## Shot starts follow the sections of the promo BGM (gen_promo_audio.py); the music and 梁阿姨's
## lines are mixed in afterwards by export2.py, so in here the Music bus is silent.
const LENGTH := 59.0
const CREAM := Color("fff1cf")
const GOLD := Color("ffce73")
const INK := Color("3b2416")
const RED := Color("d23a2e")
const NAVY := Color("152735")
const BLUE := Color("87d8e4")

## The BGM (art_src/promo/audio/bgm_promo_a.mp3) is exactly 128 bpm from 0 s: one bar = 1.875 s.
## Its own shape: quiet intro 0-7.5, build 7.5-13.3, a beat of silence 13.3-15, the full band drops at
## 15, a final chord lands at 52.5 and rings out. Every cut below sits on one of those bar lines.
const BAR := 1.875
const BEAT := 0.46875
## [start, kind, arg]; a shot runs until the next one starts
var shots := [
	[0.0, "ill", "p1_hungry"],
	[7.5, "title", "title"],
	[13.3, "growl", "growl"],
	[15.0, "ill", "p2_auntie"],
	[18.75, "ill", "p3_catch"],
	[20.625, "game", "early"],
	[28.125, "tree", "tree"],
	[33.75, "ladder", "ladder"],
	[37.5, "ill", "p4_crew"],
	[41.25, "game", "late"],
	[48.75, "ill", "p5_full"],
	[52.5, "end", "p6_agi"],
]
## Ken Burns per illustration: [scale from, focus from, scale to, focus to] (focus: 0..1 of the image)
const KB := {
	"p1_hungry": [1.0, Vector2(0.5, 0.5), 1.14, Vector2(0.64, 0.5)],
	"p2_auntie": [1.16, Vector2(0.5, 0.62), 1.0, Vector2(0.5, 0.45)],
	"p3_catch": [1.05, Vector2(0.45, 0.5), 1.16, Vector2(0.52, 0.45)],
	"p4_crew": [1.18, Vector2(0.28, 0.5), 1.18, Vector2(0.72, 0.5)],
	"p5_full": [1.0, Vector2(0.5, 0.5), 1.1, Vector2(0.55, 0.55)],
	"p6_agi": [1.25, Vector2(0.62, 0.42), 1.0, Vector2(0.5, 0.5)],
}
## [shot arg, from, to, text, style, position, size]; times are seconds into that shot
var captions := [
	["p1_hungry", BAR, 7.4, "目标：实现 AGI", "chip", Vector2(330, 170), 40],
	["p1_hungry", 2 * BAR, 7.4, "当前进度——", "big", Vector2(420, 470), 92],
	["p1_hungry", 3 * BAR, 7.4, "饿了。", "gold", Vector2(420, 690), 200],
	["title", 0.25, 5.8, "超可爱的大肥鱼增量小游戏", "big", Vector2(960, 135), 76],
	["title", 2 * BEAT, 5.8, "要实现 AGI，得先吃饱！", "stamp", Vector2(960, 900), 84],
	["growl", 0.15, 1.7, "咕噜噜噜——", "big", Vector2(1260, 860), 110],
	["p2_auntie", 0.1, 3.75, "梁阿姨：开饭咯——！", "paper", Vector2(960, 950), 64],
	["p3_catch", 0.1, 1.875, "一口都不许掉！", "stamp", Vector2(560, 880), 96],
	["early", 0.2, 3.6, "接住饭菜，装满饭盒", "paper", Vector2(470, 975), 54],
	["early", 2 * BAR, 7.4, "端给大肥鱼，换成 Token", "paper", Vector2(510, 975), 54],
	["tree", 0.2, 5.5, "饭钱，点成技能树！", "paper", Vector2(470, 975), 54],
	["ladder", 0.1, 3.7, "一路进化……", "big", Vector2(960, 150), 80],
	["p4_crew", 0.1, 3.7, "招募六位外包小助手！", "big", Vector2(960, 150), 88],
	["late", 0.2, 3.6, "食堂越忙，越快乐！", "paper", Vector2(470, 975), 54],
	["late", 2 * BAR, 7.4, "暴食流 · 美食家流 · 吃菜邪修", "paper", Vector2(560, 975), 50],
	["p5_full", 0.2, 3.7, "吃饱了。", "big", Vector2(960, 170), 120],
	["p5_full", BAR, 3.7, "……明天还来。", "gold", Vector2(960, 310), 64],
]

var t := 0.0
var shot := -1
var local_t := 0.0
var events := {}
var vp: SubViewport
var screen: CanvasItem
var display: TextureRect
var overlay: Node2D
var big_font: Font
var body_font: Font
var art := {}
var tex := {}
var foods: Array[Texture2D] = []
var out := ""
var log_lines: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	Settings.pause_unfocused = false
	Settings.mute_unfocused = false
	Settings.hit_pause = false
	Settings.screen_shake = false
	Settings.reduced_motion = false
	Settings.vsync = false
	Settings.language = "zh_CN"
	Settings.volume = {"Master": 1.0, "Music": 0.0, "SFX": 0.6, "Voice": 0.9}
	Settings.apply()
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_window().size = Vector2i(1920, 1080)
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	big_font = load("res://promo/ZCOOLKuaiLe-full.ttf")
	body_font = load("res://promo/NotoSansSC-full.ttf")
	for k in KB:
		art[k] = load("res://promo/art/%s.png" % k)
	for k in ["ticket", "ticket_gold", "stamp", "stamp_ring", "cork_bg", "fx_burst", "fx_star", "pin"]:
		tex[k] = load("res://assets/canteen/%s.png" % k)
	tex["logo"] = load("res://assets/ui/premium/logo_zh.png")
	tex["qr"] = load("res://promo/toy_qr.png")
	for id in ["ball", "leg", "dump", "gold", "bowl", "bun", "egg", "pudding", "fries", "kungpao"]:
		foods.append(load("res://assets/canteen/food_%s.png" % id))
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.audio_listener_enable_2d = true
	add_child(vp)
	display = TextureRect.new()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture = vp.get_texture()
	display.size = Vector2(1920, 1080)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	overlay = Node2D.new()
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

## ---------------------------------------------------------------- game fixtures (as trailer.gd)
func base_state(version: int, levels: Dictionary) -> void:
	Game.reset_save()
	Game.version = version
	Game.runs = 8 if version == 0 else 42
	Game.tokens = 12000.0 if version == 0 else 240000.0
	Game.levels = levels.duplicate()
	Game._recompute()
	for k in ["canteen_complete", "stall_layout", "think", "warm", "grok"]:
		Game.seen_buttons["intro_" + k] = true
	for k in ["menu", "sigs", "crew"]:
		Game.seen_buttons[k] = true
		Game.seen_buttons[k + "_card"] = true
	seed(20261021 + version)

func kind() -> String:
	return shots[shot][1]

func arg() -> String:
	return shots[shot][2]

func shot_end() -> float:
	return shots[shot + 1][0] if shot + 1 < shots.size() else LENGTH

func _enter(index: int) -> void:
	shot = index
	local_t = 0.0
	events.clear()
	if is_instance_valid(screen):
		Fx.world = null
		vp.remove_child(screen)
		screen.queue_free()
		screen = null
	display.visible = kind() in ["game", "tree"]
	log_lines.append({"t": t, "shot": shots[index]})
	if kind() == "game" and arg() == "early":
		base_state(0, {"start": 1, "conc": 1, "vram": 1, "api": 2, "eat": 1})
		var run := CanteenRun.new()
		run.autotest = true
		screen = run
		vp.add_child(screen)
		for i in 180: run._process(1.0 / 60.0)
	elif kind() == "game":
		var lv := {"start":1,"conc":5,"api":5,"batch":3,"peak":2,"stall_main":3,"stall_wok":3,"stall_dim":3,"stall_fry":3,"stall_sweet":3,"vram":2,"mat":3,"eat":8,"hire":6,"orch":2,"skills":1,"sft":4,"dpo":2,"prompt":4,"fewshot":3,"agentwf":3,"cot":1,"rag":2,"agirec":2,"grok":1,"warmup":3,"stream":3,"mtp":3,"multiturn":3,"rlhf":4,"moe":2}
		base_state(4, lv)
		var run := CanteenRun.new()
		run.autotest = true
		screen = run
		vp.add_child(screen)
		for i in 480: run._process(1.0 / 60.0)
	elif kind() == "tree":
		base_state(1, {"start": 1, "conc": 1, "vram": 1, "api": 2, "eat": 1, "ticket_r1": 1})
		Game.tokens = 240000.0
		screen = TreeScreen.new()
		vp.add_child(screen)
		(screen as TreeScreen)._zoom = 0.85
		(screen as TreeScreen)._pan = Vector2(160, 70)
	Audio.slowmo(false)
	# every cut lands on a beat: one short accent
	if kind() == "ill":
		Audio.sfx("fling", -8.0)

func cue(at: float, key: String) -> bool:
	if local_t >= at and not events.has(key):
		events[key] = true
		return true
	return false

func _process(delta: float) -> void:
	t += delta
	local_t += delta
	var wanted := 0
	for i in shots.size():
		if t >= shots[i][0]: wanted = i
	if wanted != shot: _enter(wanted)
	match kind():
		"ill":
			if arg() == "p1_hungry" and cue(3 * BAR + 0.5, "hungry"): Audio.vo("fish_wait", 2)
			if arg() == "p3_catch" and cue(0.1, "stamp"): Audio.sfx("crit", -4.0)
			if arg() == "p4_crew":
				for i in 7:
					if cue(i * BEAT, "hop%d" % i): Audio.sfx("crew_hop", -6.0)
			if arg() == "p5_full" and cue(0.15, "full"): Audio.vo("fish_full", 2)
		"title":
			if cue(2 * BEAT, "stamp"): Audio.sfx("ticket", 0.0)
		"growl":
			# the BGM is silent here; export2.py lays the growl in
			pass
		"tree":
			var tree := screen as TreeScreen
			for b in [[BEAT, "skills"], [3 * BEAT, "hire"], [5 * BEAT, "think"], [7 * BEAT, "vram"], [9 * BEAT, "eat"]]:
				if cue(b[0], b[1]):
					tree._hover = b[1]
					tree.try_buy(b[1])
			tree._pan = Vector2(180 + local_t * 8.0, 80 + local_t * 2.0)
			tree.queue_redraw()
		"ladder":
			for i in 5:
				if cue(LADDER_AT[i], "v%d" % i): Audio.sfx("ticket", -2.0)
			if cue(LADDER_AGI, "agi"): Audio.sfx("version_up", 0.0)
		"end":
			if cue(0.4, "smile"): Audio.vo("fish_happy", 2)
			if cue(2 * BEAT, "stamp"): Audio.sfx("ticket", 0.0)
	queue_redraw()
	overlay.queue_redraw()
	if t >= LENGTH:
		if out != "":
			var f := FileAccess.open(out.path_join("promo2-report.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify({"duration": LENGTH, "fps": 30, "shots": log_lines, "save_path": Game.save_path}, "\t"))
		get_tree().quit()

## ---------------------------------------------------------------- drawing helpers
static func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

static func back_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

## Draw a 16:9 window of an illustration: zoom s (1 = whole frame), centred on focus (0..1).
func draw_art(ci: CanvasItem, img: Texture2D, s: float, focus: Vector2, tint := Color.WHITE) -> void:
	var size := img.get_size()
	var base := Vector2(size.x, size.x * 9.0 / 16.0)
	if base.y > size.y: base = Vector2(size.y * 16.0 / 9.0, size.y)
	var reg := base / s
	var c := focus * size
	c.x = clampf(c.x, reg.x * 0.5, size.x - reg.x * 0.5)
	c.y = clampf(c.y, reg.y * 0.5, size.y - reg.y * 0.5)
	ci.draw_texture_rect_region(img, Rect2(0, 0, 1920, 1080), Rect2(c - reg * 0.5, reg), tint)

func panel(color: Color, radius := 18, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
	var p := StyleBoxFlat.new()
	p.bg_color = color
	p.set_corner_radius_all(radius)
	p.border_color = border
	p.set_border_width_all(width)
	return p

func text_w(f: Font, s: String, size: int) -> float:
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Centred text at the current transform origin, with a thick outline.
func outlined(ci: CanvasItem, s: String, size: int, fill: Color, line: Color, outline: int, f: Font = null) -> void:
	if f == null: f = big_font
	var w := text_w(f, s, size)
	var p := Vector2(-w * 0.5, size * 0.36)
	if outline > 0:
		ci.draw_string_outline(f, p + Vector2(0, outline * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.35 * fill.a))
		ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, line)
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)

func _draw_caption(s: String, style: String, pos: Vector2, size: int, a: float, alpha: float) -> void:
	var o := overlay
	var sc := lerpf(1.35, 1.0, back_out(a / 0.28))
	match style:
		"big", "gold":
			o.draw_set_transform(pos, 0.0, Vector2(sc, sc))
			outlined(o, s, size, (GOLD if style == "gold" else CREAM) * Color(1, 1, 1, alpha), INK * Color(1, 1, 1, alpha), maxi(10, size / 7))
		"chip":
			var w := text_w(body_font, s, size) + size * 1.4
			o.draw_set_transform(pos, 0.0, Vector2(sc, sc))
			o.draw_style_box(panel(Color(0.08, 0.16, 0.22, 0.86 * alpha), int(size * 0.7), Color(BLUE, 0.6 * alpha), 2), Rect2(-w * 0.5, -size * 0.85, w, size * 1.7))
			outlined(o, s, size, Color(CREAM, alpha), INK, 0, body_font)
		"paper":
			var w := text_w(big_font, s, size) + size * 1.6
			o.draw_set_transform(pos, -0.025, Vector2(sc, sc))
			o.draw_style_box(panel(Color(0, 0, 0, 0.25 * alpha), 14), Rect2(-w * 0.5 + 6, -size * 0.9 + 9, w, size * 1.8))
			o.draw_style_box(panel(Color(1.0, 0.95, 0.84, alpha), 14, Color(0.55, 0.36, 0.22, alpha), 4), Rect2(-w * 0.5, -size * 0.9, w, size * 1.8))
			o.draw_texture_rect(tex["pin"], Rect2(-w * 0.5 + 10, -size * 0.9 - 34, 28, 56), false, Color(1, 1, 1, alpha))
			outlined(o, s, size, Color(INK, alpha), INK, 0)
		"stamp":
			var k := clampf(a / 0.14, 0, 1)
			var ssc := lerpf(2.2, 1.0, ease_out(k))
			var shake := Vector2(sin(a * 90.0), cos(a * 70.0)) * 6.0 * clampf(1.0 - (a - 0.14) / 0.2, 0, 1) if a > 0.14 else Vector2.ZERO
			var w := text_w(big_font, s, size) + size * 1.2
			o.draw_set_transform(pos + shake, -0.06, Vector2(ssc, ssc))
			var col := Color(RED, alpha * k)
			o.draw_style_box(panel(Color(1.0, 0.97, 0.9, 0.92 * alpha * k), 16, col, 8), Rect2(-w * 0.5, -size * 0.85, w, size * 1.7))
			o.draw_style_box(panel(Color.TRANSPARENT, 12, col, 3), Rect2(-w * 0.5 + 14, -size * 0.85 + 14, w - 28, size * 1.7 - 28))
			outlined(o, s, size, col, INK, 0)
	o.draw_set_transform(Vector2.ZERO)

## ---------------------------------------------------------------- frames
func _draw() -> void:
	var lt := local_t
	var dur: float = shot_end() - float(shots[shot][0])
	match kind():
		"ill", "end":
			var k: Array = KB[arg()]
			var p: float = ease_out(lt / dur) * 0.6 + (lt / dur) * 0.4
			var s := lerpf(k[0], k[2], p) * (1.0 + 0.06 * exp(-lt * 9.0))
			var f: Vector2 = (k[1] as Vector2).lerp(k[3], p)
			if arg() == "p3_catch" and lt > 0.1 and lt < 0.4:
				f += Vector2(sin(lt * 80.0), cos(lt * 60.0)) * 0.004
			draw_art(self, art[arg()], s, f)
		"growl":
			# silence in the music: a dim close-up on her tummy, trembling with each rumble
			var shake := Vector2(sin(lt * 70.0), cos(lt * 53.0)) * 0.0025 * clampf(1.0 - absf(lt - 0.5) * 1.5, 0, 1)
			draw_art(self, art["p1_hungry"], 2.1, Vector2(0.69, 0.62) + shake, Color(0.75, 0.78, 0.9))
		"title":
			_draw_title(lt)
		"ladder":
			_draw_ladder(lt)
		_:
			pass

func _draw_title(lt: float) -> void:
	# warm sunburst with food flying out from the logo
	draw_rect(Rect2(0, 0, 1920, 1080), Color("ffe4a6"))
	var c := Vector2(960, 500)
	for i in 24:
		var ang := lt * 0.25 + i * TAU / 24.0
		if i % 2 == 0:
			var pts := PackedVector2Array([c, c + Vector2.from_angle(ang) * 1600, c + Vector2.from_angle(ang + TAU / 24.0) * 1600])
			draw_colored_polygon(pts, Color("ffd27d"))
	for i in 18:
		var ang := i * TAU / 18.0 + 0.3
		var d := 220.0 + fmod(lt * 420.0 + i * 97.0, 900.0)
		var img: Texture2D = foods[i % foods.size()]
		var sz := 120.0 * (0.6 + 0.4 * sin(i * 1.7) * sin(i * 1.7))
		draw_set_transform(c + Vector2.from_angle(ang) * d, lt * (1.5 if i % 2 else -1.2) + i, Vector2.ONE)
		draw_texture_rect(img, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false)
	draw_set_transform(Vector2.ZERO)
	var burst: Texture2D = tex["fx_burst"]
	draw_set_transform(c, lt * 0.6, Vector2.ONE * 3.4)
	draw_texture_rect(burst, Rect2(-burst.get_size() * 0.5, burst.get_size()), false, Color(1, 1, 1, 0.55))
	draw_set_transform(Vector2.ZERO)
	var logo: Texture2D = tex["logo"]
	var ls := back_out(lt / 0.35) * 0.62 + sin(lt * 3.0) * 0.008
	var lsz := logo.get_size() * ls
	draw_set_transform(c, sin(lt * 2.2) * 0.02, Vector2.ONE)
	draw_texture_rect(logo, Rect2(-lsz * 0.5, lsz), false)
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(0, 0, 1920, 1080), Color(1, 1, 1, clampf(1.0 - lt / 0.25, 0, 1)))

const LADDER := ["V3", "R1", "V3.1", "V3.2", "V4"]
const LADDER_AT := [0.1, 0.1 + BEAT, 0.1 + 2 * BEAT, 0.1 + 3 * BEAT, 0.1 + 4 * BEAT]
const LADDER_AGI := 6 * BEAT

func _draw_ladder(lt: float) -> void:
	draw_texture_rect(tex["cork_bg"], Rect2(0, 0, 1920, 1080), false)
	var tk: Texture2D = tex["ticket"]
	for i in 5:
		var at: float = LADDER_AT[i]
		if lt < at: continue
		var a := lt - at
		var p := Vector2(250 + i * 275, 860 - i * 118)
		var sc := lerpf(1.5, 1.0, back_out(a / 0.22))
		draw_set_transform(p, -0.05 + i * 0.02, Vector2(sc, sc) * 1.35)
		draw_texture_rect(tk, Rect2(-tk.get_size() * 0.5, tk.get_size()), false)
		outlined(self, LADDER[i], 44, INK, INK, 0)
		var stamp_a := clampf((a - 0.18) / 0.1, 0, 1)
		if stamp_a > 0:
			var st: Texture2D = tex["stamp"]
			var ssc := lerpf(1.8, 0.62, ease_out(stamp_a))
			draw_set_transform(p + Vector2(70, -26) * 1.35, 0.3, Vector2(ssc, ssc))
			draw_texture_rect(st, Rect2(-st.get_size() * 0.5, st.get_size()), false, Color(1, 1, 1, 0.9 * stamp_a))
		draw_set_transform(Vector2.ZERO)
		draw_texture_rect(tex["pin"], Rect2(p + Vector2(-20, -100), Vector2(30, 60)), false)
	# the last ticket: gold, shaking, still unknown
	if lt > LADDER_AGI:
		var a := lt - LADDER_AGI
		var tg: Texture2D = tex["ticket_gold"]
		var p := Vector2(1665, 235) + Vector2(sin(a * 40.0), cos(a * 33.0)) * 5.0 * clampf(1.2 - a, 0, 1)
		var sc := lerpf(2.4, 1.0, back_out(a / 0.3)) * 1.7
		var burst: Texture2D = tex["fx_burst"]
		draw_set_transform(p, a * 0.8, Vector2.ONE * 1.6)
		draw_texture_rect(burst, Rect2(-burst.get_size() * 0.5, burst.get_size()), false, Color(1, 1, 1, 0.8))
		draw_set_transform(p, 0.06, Vector2(sc, sc))
		draw_texture_rect(tg, Rect2(-tg.get_size() * 0.5, tg.get_size()), false)
		outlined(self, "AGI？", 46, RED, INK, 0)
		draw_set_transform(Vector2.ZERO)

func _draw_overlay() -> void:
	var lt := local_t
	var until: float = shot_end() - float(shots[shot][0]) - 0.05
	for c in captions:
		if c[0] != arg(): continue
		var to: float = minf(c[2], until)
		if lt < c[1] or lt > to: continue
		var a: float = lt - c[1]
		_draw_caption(c[3], c[4], c[5], c[6], a, clampf(a / 0.12, 0, 1) * clampf((to - lt) / 0.15, 0, 1))
	if kind() == "end": _draw_end(lt)
	# opening fade from black, closing fade to black
	if t < 0.8: overlay.draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, 1.0 - t / 0.8))
	if t > LENGTH - 1.2: overlay.draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, (t - (LENGTH - 1.2)) / 1.2))
	# a quick white flash on every cut (on the beat)
	if t > 1.0 and lt < 0.12 and kind() not in ["title", "growl"]:
		overlay.draw_rect(Rect2(0, 0, 1920, 1080), Color(1, 1, 1, 0.35 * (1.0 - lt / 0.12)))

func _draw_end(lt: float) -> void:
	var o := overlay
	# darken the lower band a little so the call to action reads
	var band := ease_out((lt - 2.8) / 0.5)
	if band > 0:
		o.draw_rect(Rect2(0, 860, 1920, 220), Color(0.05, 0.1, 0.14, 0.82 * band))
	var logo: Texture2D = tex["logo"]
	var a := lt - 0.05
	if a > 0:
		var ls := back_out(a / 0.35) * 0.4
		var lsz := logo.get_size() * ls
		o.draw_set_transform(Vector2(470, 250), sin(lt * 2.0) * 0.015, Vector2.ONE)
		o.draw_texture_rect(logo, Rect2(-lsz * 0.5, lsz), false)
		o.draw_set_transform(Vector2.ZERO)
	if lt > 2 * BEAT:
		_draw_caption("要实现 AGI，得先吃饱！", "stamp", Vector2(470, 520), 64, lt - 2 * BEAT, 1.0)
	if lt > 2.8:
		var al := ease_out((lt - 2.8) / 0.4)
		o.draw_style_box(panel(Color(1, 0.96, 0.87, al), 14), Rect2(80, 885, 170, 170))
		o.draw_texture_rect(tex["qr"], Rect2(88, 893, 154, 154), false, Color(1, 1, 1, al))
		o.draw_string(big_font, Vector2(290, 950), "B站 Toy 免费开玩 · 手机电脑都能玩", HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color(GOLD, al))
		o.draw_string(body_font, Vector2(292, 1005), "免费 · 开源 · 非商用同人作品   作者：夸夸家族族长", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(CREAM, al))
		o.draw_string(body_font, Vector2(292, 1046), "角色原型「溟月」：上善无形 · 女仆版设计：ZipZipPipe · 素材 CC BY-NC-SA 4.0 · 与 DeepSeek 官方无关", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(0.75, 0.83, 0.85, al))
