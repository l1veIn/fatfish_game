extends Node2D
## The cost + open-source video (2026-11-07). 大肥鱼 reads the bill, so every number has a voice line.
## Shot starts and captions come from promo/timeline.json (bill_timeline.py, from the voice lengths);
## real gameplay runs unchanged in a SubViewport. The music and voice are mixed in by bill_export.py.
const CREAM := Color("fff1cf")
const GOLD := Color("ffce73")
const INK := Color("3b2416")
const RED := Color("d23a2e")
const CHALK := Color(0.96, 0.96, 0.9)
const NAVY := Color("152735")

var data: Dictionary = {}
var shots: Array = []
var LENGTH := 60.0
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
var tex := {}
var art := {}
var out := ""
var log_lines: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	data = JSON.parse_string(FileAccess.get_file_as_string("res://promo/timeline.json"))
	shots = data.shots
	LENGTH = float(data.length)
	Settings.pause_unfocused = false
	Settings.mute_unfocused = false
	Settings.hit_pause = false
	Settings.screen_shake = false
	Settings.reduced_motion = false
	Settings.vsync = false
	Settings.language = "zh_CN"
	Settings.volume = {"Master": 1.0, "Music": 0.0, "SFX": 0.45, "Voice": 0.0}
	Settings.apply()
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_window().size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	big_font = load("res://promo/ZCOOLKuaiLe-full.ttf")
	body_font = load("res://promo/NotoSansSC-full.ttf")
	for k in ["ui_chalkboard", "ticket", "ticket_gold", "stamp", "cork_bg", "fx_burst", "pin", "ui_paper"]:
		tex[k] = load("res://assets/canteen/%s.png" % k)
	tex["logo"] = load("res://assets/ui/premium/logo_zh.png")
	tex["qr"] = load("res://promo/toy_qr.png")
	tex["github"] = load("res://promo/github.png")
	for name in data.art:
		art[name] = load("res://promo/art/%s.png" % name)
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


func base_state(version: int, levels: Dictionary) -> void:
	Game.reset_save()
	Game.version = version
	Game.runs = 58
	Game.tokens = 3.2e8
	Game.levels = levels.duplicate()
	Game._recompute()
	for k in ["canteen_complete", "stall_layout", "think", "warm", "grok"]:
		Game.seen_buttons["intro_" + k] = true
	for k in ["menu", "sigs", "crew", "vision"]:
		Game.seen_buttons[k] = true
		Game.seen_buttons[k + "_card"] = true
	seed(20261107 + version)


func _late_levels() -> Dictionary:
	return {"start":1,"conc":5,"api":5,"batch":3,"peak":2,"stall_main":3,"stall_wok":3,"stall_dim":3,"stall_fry":3,"stall_sweet":3,"vram":2,"mat":3,"eat":10,"hire":6,"orch":2,"skills":1,"sft":4,"dpo":2,"prompt":4,"fewshot":3,"agentwf":3,"cot":1,"rag":2,"agirec":2,"grok":1,"warmup":3,"stream":3,"mtp":3,"multiturn":3,"rlhf":4,"moe":2,"vision":1,"fetch":1,"fetchfast":3,"smallcup":2}


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
	if kind() == "game":
		base_state(7, _late_levels())
		if arg() == "vision":
			Game.set_vision_target("family")
		var run := CanteenRun.new()
		run.autotest = true
		screen = run
		vp.add_child(screen)
		run.can_think = false   # keeps the warm canteen colours (the bot's slow motion tints the frame)
		for i in (1500 if arg() == "hook" else 700): run._process(1.0 / 60.0)
	elif kind() == "tree":
		base_state(7, _late_levels())
		for id in ["ticket_v4", "ticket_flash", "ticket_1017", "ticket_pro", "fetchgold", "vmatch", "vfilter", "shorter"]:
			Game.levels[id] = 1
		Game._recompute()
		screen = TreeScreen.new()
		vp.add_child(screen)
		(screen as TreeScreen)._zoom = 1.0
		(screen as TreeScreen)._pan = Vector2(1120, 800)
	Audio.slowmo(false)
	if kind() in ["ill", "bill", "tokens", "redo", "github"]:
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
		if t >= float(shots[i][0]): wanted = i
	if wanted != shot: _enter(wanted)
	if kind() == "tree":
		var tree := screen as TreeScreen
		tree._pan = Vector2(1120 + local_t * 16.0, 800 + local_t * 10.0)
		tree.queue_redraw()
	# the receipt lines and stamps land with their voice lines
	for b in data.beats:
		if t >= float(b.t) and not events.has("b" + str(b.t)) and t < float(b.t) + 0.5:
			events["b" + str(b.t)] = true
			if b.get("sfx", "") != "":
				Audio.sfx(b.sfx, float(b.get("db", -4.0)))
	queue_redraw()
	overlay.queue_redraw()
	if t >= LENGTH:
		if out != "":
			var f := FileAccess.open(out.path_join("bill-report.json"), FileAccess.WRITE)
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


func outlined(ci: CanvasItem, s: String, size: int, fill: Color, line: Color, outline: int, f: Font = null) -> void:
	if f == null: f = big_font
	var w := text_w(f, s, size)
	var p := Vector2(-w * 0.5, size * 0.36)
	if outline > 0:
		ci.draw_string_outline(f, p + Vector2(0, outline * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.35 * fill.a))
		ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, line)
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


func caption(s: String, style: String, pos: Vector2, size: int, a: float, alpha: float) -> void:
	var o := overlay
	var sc := lerpf(1.35, 1.0, back_out(a / 0.28))
	match style:
		"big", "gold":
			o.draw_set_transform(pos, 0.0, Vector2(sc, sc))
			outlined(o, s, size, (GOLD if style == "gold" else CREAM) * Color(1, 1, 1, alpha), INK * Color(1, 1, 1, alpha), maxi(10, size / 7))
		"sub":
			var w := text_w(body_font, s, size) + 60.0
			o.draw_style_box(panel(Color(0.05, 0.03, 0.02, 0.66 * alpha), 10), Rect2(pos.x - w * 0.5, pos.y - size * 0.82, w, size * 1.6))
			o.draw_set_transform(pos, 0.0, Vector2.ONE)
			outlined(o, s, size, Color(1, 1, 1, alpha), INK, 0, body_font)
		"paper":
			var w := text_w(big_font, s, size) + size * 1.6
			o.draw_set_transform(pos, -0.02, Vector2(sc, sc))
			o.draw_style_box(panel(Color(0, 0, 0, 0.25 * alpha), 14), Rect2(-w * 0.5 + 6, -size * 0.9 + 9, w, size * 1.8))
			o.draw_style_box(panel(Color(1.0, 0.95, 0.84, alpha), 14, Color(0.55, 0.36, 0.22, alpha), 4), Rect2(-w * 0.5, -size * 0.9, w, size * 1.8))
			outlined(o, s, size, Color(INK, alpha), INK, 0)
		"stamp":
			var k := clampf(a / 0.14, 0, 1)
			var ssc := lerpf(2.2, 1.0, ease_out(k))
			var shake := Vector2(sin(a * 90.0), cos(a * 70.0)) * 6.0 * clampf(1.0 - (a - 0.14) / 0.2, 0, 1) if a > 0.14 else Vector2.ZERO
			var w := text_w(big_font, s, size) + size * 1.2
			o.draw_set_transform(pos + shake, -0.06, Vector2(ssc, ssc))
			var col := Color(RED, alpha * k)
			o.draw_style_box(panel(Color(1.0, 0.97, 0.9, 0.94 * alpha * k), 16, col, 8), Rect2(-w * 0.5, -size * 0.85, w, size * 1.7))
			o.draw_style_box(panel(Color.TRANSPARENT, 12, col, 3), Rect2(-w * 0.5 + 14, -size * 0.85 + 14, w - 28, size * 1.7 - 28))
			outlined(o, s, size, col, INK, 0)
	o.draw_set_transform(Vector2.ZERO)


## ---------------------------------------------------------------- frames
func _draw() -> void:
	var lt := local_t
	var dur: float = shot_end() - float(shots[shot][0])
	match kind():
		"ill", "bill", "redo", "end":
			var k: Array = data.kb[arg()]
			var p: float = ease_out(lt / dur) * 0.6 + (lt / dur) * 0.4
			var s := lerpf(k[0], k[3], p) * (1.0 + 0.06 * exp(-lt * 9.0))
			var f := Vector2(k[1], k[2]).lerp(Vector2(k[4], k[5]), p)
			draw_art(self, art[arg()], s, f, Color(0.62, 0.58, 0.55) if kind() == "bill" else Color.WHITE)
		"tokens":
			draw_texture_rect(tex["cork_bg"], Rect2(0, 0, 1920, 1080), false, Color(0.55, 0.5, 0.45))
		"github":
			draw_texture_rect(tex["cork_bg"], Rect2(0, 0, 1920, 1080), false)
		_:
			pass


func _draw_overlay() -> void:
	var lt := local_t
	if arg() == "hook" or arg() == "vision":
		for i in 9:
			overlay.draw_rect(Rect2(0, i * 40, 1920, 40), Color(0.04, 0.03, 0.02, 0.62 * (1.0 - i / 9.0)))
	match kind():
		"bill": _draw_bill()
		"tokens": _draw_tokens(lt)
		"redo": _draw_redo()
		"github": _draw_github(lt)
		"end": _draw_end(lt)
	for c in data.captions:
		var from: float = c.from
		var to: float = c.to
		if t < from or t > to: continue
		var a: float = t - from
		caption(c.text, c.style, Vector2(c.x, c.y), int(c.size), a, clampf(a / 0.12, 0, 1) * clampf((to - t) / 0.12, 0, 1))
	if t > LENGTH - 0.8: overlay.draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, (t - (LENGTH - 0.8)) / 0.8))
	if t > 1.0 and lt < 0.1:
		overlay.draw_rect(Rect2(0, 0, 1920, 1080), Color(1, 1, 1, 0.3 * (1.0 - lt / 0.1)))


## The receipt: lines appear with the voice, the total gets a stamp, then Steam's fee lands.
func _draw_bill() -> void:
	var o := overlay
	var bill: Dictionary = data.bill
	var x := 300.0
	var w := 1320.0
	var lines: Array = bill.lines
	var shown := 0
	for l in lines:
		if t >= float(l.t): shown += 1
	var h := 180.0 + 158.0 * shown
	o.draw_style_box(panel(Color(0, 0, 0, 0.35), 10), Rect2(x + 12, 34, w, h))
	o.draw_style_box(panel(Color(1.0, 0.96, 0.86), 10, Color(0.55, 0.36, 0.22), 3), Rect2(x, 20, w, h))
	o.draw_string(big_font, Vector2(x + 44, 104), "食堂结算小票", HORIZONTAL_ALIGNMENT_LEFT, -1, 70, INK)
	o.draw_string(body_font, Vector2(x + 500, 100), "《吃白饭的大肥鱼》首发版账单", HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(INK, 0.72))
	o.draw_dashed_line(Vector2(x + 30, 150), Vector2(x + w - 30, 150), Color(INK, 0.5), 3.0, 14.0)
	var y := 150.0
	for i in shown:
		var l: Dictionary = lines[i]
		var a: float = t - float(l.t)
		var bounce := lerpf(1.25, 1.0, back_out(a / 0.2))
		var total: bool = l.get("total", false)
		if total:
			o.draw_line(Vector2(x + 30, y + 6), Vector2(x + w - 30, y + 6), Color(INK, 0.7), 5.0)
		o.draw_set_transform(Vector2(x + 44, y + 86), 0.0, Vector2(bounce, bounce))
		o.draw_string(big_font, Vector2.ZERO, l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 80 if total else 66, RED if total else INK)
		if l.get("note", "") != "":
			o.draw_string(body_font, Vector2(2, 50), l.note, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(INK, 0.72))
		o.draw_set_transform(Vector2(x + w - 44, y + 96), 0.0, Vector2(bounce, bounce))
		var amount: String = l.amount
		var amount_size := 116 if total else 92
		o.draw_string(big_font, Vector2(-text_w(big_font, amount, amount_size), 0), amount, HORIZONTAL_ALIGNMENT_LEFT, -1, amount_size, RED if total else INK)
		o.draw_set_transform(Vector2.ZERO)
		y += 158.0


## She asks how much the AI ate: a counter rolls up, then one bar shows how little was written.
func _draw_tokens(_lt: float) -> void:
	var o := overlay
	var d: Dictionary = data.tokens
	var board := Rect2(170, 60, 1580, 960)
	o.draw_texture_rect(tex["ui_chalkboard"], board, false)
	var roll := ease_out((t - float(d.t_roll)) / 1.1)
	if t >= float(d.t_roll):
		var value: float = float(d.total_yi) * roll
		o.draw_set_transform(Vector2(960, 268), 0.0, Vector2.ONE)
		outlined(o, "%.1f 亿 token" % value, 170, CHALK, NAVY, 0)
		o.draw_set_transform(Vector2.ZERO)
		var scope: String = d.scope
		o.draw_string(body_font, Vector2(960 - text_w(body_font, scope, 36) * 0.5, 382), scope, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(CHALK, 0.88))
	if t >= float(d.t_bar):
		var a := ease_out((t - float(d.t_bar)) / 0.7)
		var bar := Rect2(290, 420, 1340, 136)
		o.draw_style_box(panel(Color(0.12, 0.2, 0.2), 8, Color(CHALK, 0.8), 3), bar)
		var read_w := (bar.size.x - 6.0) * float(d.read_share) * a
		o.draw_rect(Rect2(bar.position.x + 3, bar.position.y + 3, read_w, bar.size.y - 6), Color(0.55, 0.72, 0.78))
		var write_w := maxf((bar.size.x - 6.0) * float(d.write_share) * a, 3.0)
		o.draw_rect(Rect2(bar.position.x + 3 + read_w, bar.position.y + 3, write_w, bar.size.y - 6), Color(0.95, 0.75, 0.35))
		var out_w := maxf((bar.size.x - 6.0) * float(d.output_share), 7.0)
		o.draw_rect(Rect2(bar.end.x - 3 - out_w, bar.position.y + 3, out_w, bar.size.y - 6), RED)
		o.draw_string(big_font, Vector2(320, 512), "翻来覆去读上下文 %s" % d.read_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 74, NAVY)
	if t >= float(d.t_output):
		var a := back_out((t - float(d.t_output)) / 0.25)
		o.draw_line(Vector2(1622, 562), Vector2(1622, 610), Color(1.0, 0.55, 0.45), 8.0)
		var s2: String = d.output_label
		o.draw_set_transform(Vector2(1622, 680), 0.0, Vector2(a, a))
		o.draw_string(big_font, Vector2(-text_w(big_font, s2, 92), 20), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 92, Color(1.0, 0.72, 0.6))
		o.draw_set_transform(Vector2.ZERO)
	if t >= float(d.t_api):
		var a := clampf((t - float(d.t_api)) / 0.15, 0, 1)
		var label: String = d.api_label
		o.draw_string(big_font, Vector2(960 - text_w(big_font, label, 72) * 0.5, 830), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 72, Color(GOLD, a))


## Three rejected things, each stamped 重来 as she says it.
func _draw_redo() -> void:
	var o := overlay
	var i := 0
	for r in data.redo:
		if t < float(r.t):
			i += 1
			continue
		var a: float = t - float(r.t)
		var pos := Vector2(370 + i * 590, 860 - i * 30)
		var sc := lerpf(1.6, 1.0, back_out(a / 0.22))
		var w := 500.0
		o.draw_set_transform(pos, -0.04 + i * 0.03, Vector2(sc, sc))
		o.draw_style_box(panel(Color(0, 0, 0, 0.3), 12), Rect2(-w * 0.5 + 8, -82, w, 170))
		o.draw_style_box(panel(Color(1.0, 0.96, 0.86), 12, Color(0.55, 0.36, 0.22), 4), Rect2(-w * 0.5, -90, w, 170))
		outlined(o, r.text, 54, INK, INK, 0)
		var sa := clampf((a - 0.16) / 0.1, 0, 1)
		if sa > 0.0:
			var ssc := lerpf(1.6, 1.0, ease_out(sa))
			o.draw_set_transform(pos + Vector2(145, -54), 0.25 - i * 0.05, Vector2(ssc, ssc))
			o.draw_style_box(panel(Color(1, 1, 1, 0.0), 10, Color(RED, sa), 6), Rect2(-92, -42, 184, 84))
			outlined(o, "重来", 58, Color(RED, sa), INK, 0)
		o.draw_set_transform(Vector2.ZERO)
		i += 1


## The real repository page in a browser frame, stamped 开源.
func _draw_github(lt: float) -> void:
	var o := overlay
	var img: Texture2D = tex["github"]
	var a := back_out(lt / 0.3)
	var rect := Rect2(190, 70, 1540, 866)
	o.draw_set_transform(Vector2(960, 500), 0.0, Vector2(a, a))
	var r := Rect2(rect.position - Vector2(960, 500), rect.size)
	o.draw_style_box(panel(Color(0, 0, 0, 0.35), 12), Rect2(r.position + Vector2(10, 14), r.size))
	var src_h := img.get_width() * rect.size.y / rect.size.x
	o.draw_texture_rect_region(img, r, Rect2(0, 0, img.get_width(), minf(src_h, img.get_height())))
	o.draw_set_transform(Vector2.ZERO)


func _draw_end(lt: float) -> void:
	var o := overlay
	var band := ease_out((lt - float(data.end_cta)) / 0.4)
	if band > 0:
		o.draw_rect(Rect2(0, 850, 1920, 230), Color(0.05, 0.08, 0.1, 0.84 * band))
	var logo: Texture2D = tex["logo"]
	var ls := back_out(lt / 0.35) * 0.36
	var lsz := logo.get_size() * ls
	o.draw_set_transform(Vector2(400, 210), sin(lt * 2.0) * 0.015, Vector2.ONE)
	o.draw_texture_rect(logo, Rect2(-lsz * 0.5, lsz), false)
	o.draw_set_transform(Vector2.ZERO)
	if lt > float(data.end_cta):
		var al := ease_out((lt - float(data.end_cta)) / 0.4)
		o.draw_style_box(panel(Color(1, 0.96, 0.87, al), 14), Rect2(70, 870, 180, 180))
		o.draw_texture_rect(tex["qr"], Rect2(78, 878, 164, 164), false, Color(1, 1, 1, al))
		o.draw_string(big_font, Vector2(285, 930), "B站 Toy 免费玩 · GitHub 搜 fatfish_game", HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color(GOLD, al))
		o.draw_string(body_font, Vector2(287, 985), "你觉得她下个版本该吃什么？评论区告诉我", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(CREAM, al))
		o.draw_string(body_font, Vector2(287, 1035), "角色原型「溟月」：上善无形 · 女仆版设计：ZipZipPipe · 素材 CC BY-NC-SA 4.0 · 免费同人作品，与 DeepSeek 官方无关", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.78, 0.82, 0.82, al))
