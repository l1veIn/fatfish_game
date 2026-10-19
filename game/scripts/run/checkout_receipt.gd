class_name CheckoutReceipt
extends Control
## A closing ledger: itemized income on cream paper, earned multipliers and the final
## total in a separate navy column. All amounts were calculated by CanteenRun._end().
## Click accelerates the reveal; Enter/A skips to the result. The final action reports
## completion to the main flow and retains its label override for the AGI ending.

signal closed

var title := "食堂关门了"
var heading := ""
var sub := ""
var steps: Array = []      # {icon, text, add, mark?, sfx?, sleep?} | {note, add} | {icon, text, lost} | + {dish, dish_name}
var subtotal := 0.0
var mults: Array = []      # [[name, x], ...] in stamping order
var total := 0.0
var target := 0.0
var passed := false
var record := false
var stuffed := false
var extra := ""
var sleeping := false      # Zzz over her while she eats the leftovers in her dreams
var fast := false          # (autotest) straight to the end

const SLOTS := 5
const PAPER := Rect2(170, 78, 1580, 922)
const LINE_H := 46.0
const INK := Color(0.11, 0.24, 0.29)
const GOLDEN := Color(0.62, 0.36, 0.06)
const RED := Color(0.78, 0.2, 0.16)
const GREY := Color(0.40, 0.43, 0.41)

var _font: Font
var _dfont: Font
var _nfont: Font           # 饭票数字 for the amounts
var _tex := {}
var _speed := 1.0
var _shown := 0                # steps on the paper so far
var _sub_on := false
var _sub_val := 0.0
var _slots_on := false
var _stamped := 0              # multipliers stamped so far
var _stamp_t: Array = []       # per slot: seconds since stamped (for the slam)
var _total_val := 0.0
var _total_pop := 0.0
var _results: Array = []       # [[text, colour, t]]
var _spot := {}                # the <EOS> dish in the spotlight: {tex, name, mark, t, stamp}
var _paper_h := 120.0
var _need_h := 120.0
var _t := 0.0
var _done := false
var _back: Button
var _closed := false
var _detail_font_size := 27


func _ready() -> void:
	size = Vector2(1920, 1080)   # parent is the CanteenRun Node2D, so anchors have nothing to fill
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_dfont = load("res://assets/ui/ZCOOLKuaiLe.ttf") if ResourceLoader.exists("res://assets/ui/ZCOOLKuaiLe.ttf") else _font
	_nfont = UiKit.bold(700)
	for n in ["ui_paper", "stamp_ring", "icon_token", "icon_box", "icon_clock", "icon_crown", "icon_shield", "icon_bolt", "fx_burst", "fx_star"]:
		var f := "res://assets/canteen/%s.png" % n
		if ResourceLoader.exists(f):
			_tex[n] = load(f)
	_stamp_t.resize(maxi(SLOTS, mults.size()))
	_stamp_t.fill(-1.0)
	_back = UiKit.button(tr("回技能树"), 32, Vector2(540, 74))
	_back.position = Vector2(1110, 900)
	_back.modulate.a = 0.0
	_back.disabled = true
	_back.pressed.connect(_close)
	_back.add_theme_stylebox_override("normal", UiKit.box(Color(0.09, 0.25, 0.32), Color(0.68, 0.57, 0.37), 2, 12, 3))
	_back.add_theme_stylebox_override("hover", UiKit.box(Color(0.15, 0.34, 0.40), Color(0.79, 0.67, 0.43), 2, 12, 3))
	_back.add_theme_stylebox_override("pressed", UiKit.box(Color(0.065, 0.20, 0.27), Color(0.79, 0.67, 0.43), 2, 12))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_back.add_theme_color_override(state, Color(0.97, 0.94, 0.84))
	add_child(_back)
	if fast or Settings.reduced_motion:
		_speed = 1000.0
	_play()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _done:
		_speed = maxf(_speed, 4.0)   # a click: hurry up
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not _done and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")):
		_speed = 1000.0
		get_viewport().set_input_as_handled()
	elif _done and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _closed or not _done:
		return
	_closed = true
	closed.emit()


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time() * _speed


func _sfx(name: String, db := -4.0, pitch := 1.0) -> void:
	if _speed < 100.0:
		Audio.sfx(name, db, 0.03, pitch)


## Counts `from` -> `to` on the subtotal or the total, ticking.
func _roll(which: String, from: float, to: float, seconds: float) -> void:
	var t := 0.0
	var ticks := 0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time() * _speed
		var v := lerpf(from, to, clampf(t / seconds, 0.0, 1.0))
		set(which, v)
		if int(t / 0.08) > ticks:
			ticks = int(t / 0.08)
			_sfx("token", -14.0, 1.5)
	set(which, to)


func _play() -> void:
	await _wait(0.3)
	# the lines, one by one
	for st in steps:
		if st.has("dish"):   # <EOS>: the last bite in the spotlight first
			_spot = {"tex": st.dish, "name": st.dish_name, "mark": st.mark, "t": 0.0, "stamp": -1.0}
			Audio.vo("fish_savor", 3)
			await _wait(0.7)
			_spot.stamp = 0.0
			_sfx("ticket", -2.0)
			_sfx("catch_gold", -4.0)
			await _wait(0.7)
			_spot = {}
		_shown += 1
		_sfx("deny" if st.has("lost") else ("version_up" if st.get("sfx", "") == "version_up" else "token"), -6.0 if st.has("lost") else -4.0)
		await _wait(0.45 if not st.has("note") else 0.25)
	# subtotal
	_sub_on = true
	await _roll("_sub_val", 0.0, subtotal, 0.6)
	_total_val = subtotal
	await _wait(0.25)
	# the multiplier stamps
	_slots_on = true
	await _wait(0.35)
	var running := subtotal
	for i in mults.size():
		_stamped = i + 1
		_stamp_t[i] = 0.0
		_sfx("ticket", -2.0)
		_sfx("catch_gold", -5.0, pow(2.0, i * 4.0 / 12.0))   # do, mi, so...
		_total_pop = 1.0
		var to: float = running * float(mults[i][1])
		await _roll("_total_val", running, to, 0.45)
		running = to
		await _wait(0.3)
	_total_val = total
	await _wait(0.25)
	# results
	if target > 0.0:
		_results.append([tr("评测通过") if passed else tr("还差 %s") % Game.fmt(maxf(target - total, 0.0)), RED if passed else Color(0.18, 0.36, 0.62), 0.0])
		_sfx("trial_pass" if passed else "trial_fail", -3.0)
		await _wait(0.4)
	if record:
		_results.append([tr("新纪录"), RED, 0.0])
		_sfx("ticket", -2.0)
		await _wait(0.3)
	if stuffed:
		_results.append([tr("吃撑了"), RED, 0.0])
		_sfx("ticket", -2.0)
		await _wait(0.3)
	if _results.is_empty() or target <= 0.0:
		_sfx("result", -4.0)
	_done = true
	_speed = 1.0
	_back.disabled = false
	if Settings.reduced_motion:
		_back.modulate.a = 1.0
	else:
		create_tween().tween_property(_back, "modulate:a", 1.0, 0.25)
	_back.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	_total_pop = maxf(_total_pop - delta * 6.0, 0.0)
	for i in _stamp_t.size():
		if _stamp_t[i] >= 0.0:
			_stamp_t[i] += delta * maxf(_speed, 1.0)
	for r in _results:
		r[2] += delta * maxf(_speed, 1.0)
	if not _spot.is_empty():
		_spot.t += delta * _speed
		if _spot.stamp >= 0.0:
			_spot.stamp += delta * _speed
	_paper_h = lerpf(_paper_h, _goal_height(), 1.0 - exp(-delta * 18.0 * maxf(_speed, 1.0)))
	queue_redraw()


## How tall the receipt is with what is on it now (measured by the last _draw()).
func _goal_height() -> float:
	return _need_h


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.075, 0.10, 0.83))
	draw_style_box(UiKit.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, 18), Rect2(PAPER.position + Vector2(10, 16), PAPER.size))
	draw_style_box(UiKit.box(Color(0.97, 0.95, 0.89), Color(0.65, 0.55, 0.35), 2, 18), PAPER)
	# A bound ledger: separate numeric columns, a narrow brass rule and a navy total block.
	draw_line(Vector2(1050, 136), Vector2(1050, 942), Color(0.66, 0.58, 0.41, 0.44), 2)
	draw_style_box(UiKit.box(Color(0.07, 0.20, 0.27), Color(0.65, 0.55, 0.35), 1, 14), Rect2(1092, 138, 576, 728))
	_text(_font, Vector2(236, 168), heading, 38, INK)
	_paragraph(sub, Rect2(238, 186, 780, 64), 24, GREY)
	_dashes(238, 1006, 264)
	_detail_font_size = 27
	var heights: Array[float] = []
	for st in steps:
		var copy: String = str(st.get("note", st.get("text", "")))
		if st.has("mark"):
			copy += "  " + str(st.mark)
		var measured := _font.get_multiline_string_size(copy, HORIZONTAL_ALIGNMENT_LEFT, 540, _detail_font_size).y
		heights.append(maxf(62.0, measured + 20.0))
	var total_height := 0.0
	for height in heights:
		total_height += height
	var row_scale := minf(1.0, 530.0 / maxf(total_height, 1.0))
	if row_scale < 0.9:
		_detail_font_size = 24
	var y := 286.0
	for i in mini(_shown, steps.size()):
		var h: float = heights[i] * row_scale
		_ledger_line(steps[i], Rect2(238, y, 768, h))
		y += h
	if _sub_on:
		_text(_font, Vector2(1132, 196), tr("小计"), 25, Color(0.74, 0.82, 0.82))
		_text(_nfont, Vector2(1628, 250), Game.fmt(_sub_val), 45, Color(0.97, 0.94, 0.82), false, true)
		if _slots_on:
			_text(_font, Vector2(1132, 322), tr("本顿加成"), 25, Color(0.74, 0.82, 0.82))
			for i in mini(_stamped, mults.size()):
				var my := 372.0 + i * 50.0
				_text(_font, Vector2(1132, my), str(mults[i][0]), 26, Color(0.93, 0.91, 0.80))
				_text(_nfont, Vector2(1628, my), "×%.2f" % float(mults[i][1]), 28, Color(0.93, 0.78, 0.48), false, true)
		draw_line(Vector2(1132, 625), Vector2(1628, 625), Color(0.70, 0.64, 0.46, 0.55), 2)
		_text(_font, Vector2(1132, 674), tr("合计 token"), 27, Color(0.84, 0.87, 0.80))
		_text(_nfont, Vector2(1628, 751), Game.fmt(_total_val), 72, Color(0.98, 0.82, 0.51), false, true)
		var results: PackedStringArray = []
		for result in _results:
			results.append(str(result[0]))
		_paragraph(" · ".join(results), Rect2(1132, 785, 496, 65), 24, Color(0.98, 0.77, 0.62))
	else:
		_paragraph(tr("正在结账…"), Rect2(1132, 196, 496, 80), 32, Color(0.95, 0.91, 0.79))
	if extra != "" and _done:
		_paragraph(extra, Rect2(238, 847, 768, 110), 25, INK)
	elif not _done:
		_paragraph(tr("点击加速 · Enter / A 查看结果"), Rect2(238, 912, 768, 52), 24, GREY)
	if not _spot.is_empty():
		_spotlight()


func _ledger_line(st: Dictionary, row: Rect2) -> void:
	var note := st.has("note")
	var lost := st.has("lost")
	var copy: String = str(st.get("note", st.get("text", "")))
	if st.has("mark"):
		copy += "  " + str(st.mark)
	var left := row.position.x + (24.0 if note else 0.0)
	_paragraph(copy, Rect2(left, row.position.y, 540 - (24 if note else 0), row.size.y), _detail_font_size - (2 if note else 0), GREY if note or lost else INK)
	var amount := Game.fmt(float(st.get("lost", st.get("add", 0.0))))
	var color := GREY if lost or note else Color(0.11, 0.34, 0.37)
	_text(_nfont, Vector2(row.end.x, row.position.y + 30), amount if lost or note else "+" + amount, 27 if note else 31, color, false, true)
	if lost:
		var w := _nfont.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 31).x
		draw_line(Vector2(row.end.x - w, row.position.y + 18), Vector2(row.end.x, row.position.y + 18), GREY, 2)
	draw_line(Vector2(row.position.x, row.end.y - 10), Vector2(row.end.x, row.end.y - 10), Color(0.65, 0.62, 0.49, 0.16), 1)


func _paragraph(copy: String, rect: Rect2, font_size: int, color: Color) -> void:
	draw_multiline_string(_font, rect.position + Vector2(0, font_size), copy, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, font_size, -1, color)


## The <EOS> last bite: the dish big in the middle under a warm light, then its stamp.
func _spotlight() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.06, 0.09, 0.86))
	var c := Vector2(960, 470)
	var k := minf(_spot.t / 0.3, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	draw_texture_rect(UiKit.glow(), Rect2(c - Vector2(260, 260) * e, Vector2(520, 520) * e), false, Color(1.0, 0.82, 0.4, 0.8))
	var tex: Texture2D = _spot.tex
	var s := 230.0 * e / maxf(tex.get_width(), tex.get_height())
	draw_texture_rect(tex, Rect2(c - tex.get_size() * s * 0.5, tex.get_size() * s), false)
	_text(_dfont, c + Vector2(0, 170), tr("最后一口：%s") % _spot.name, 34, Color(1.0, 0.95, 0.8), true, false, Color(0.3, 0.15, 0.04))
	if _spot.stamp >= 0.0:
		var t: float = _spot.stamp
		var sk := 1.0 + 1.4 * maxf(0.0, 1.0 - t / 0.14)
		draw_set_transform(c + Vector2(120, -110), -0.22, Vector2(sk, sk))
		var ring: Texture2D = _tex.get("stamp_ring", null)
		if ring != null:
			draw_texture_rect(ring, Rect2(-60, -60, 120, 120), false)
		_text(_nfont, Vector2(0, 16), _spot.mark, 46, Color(1.0, 0.42, 0.32), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dashes(x0: float, x1: float, y: float) -> void:
	var x := x0
	while x < x1:
		draw_line(Vector2(x, y), Vector2(minf(x + 10.0, x1), y), Color(0.8, 0.7, 0.55), 2.0)
		x += 18.0


func _text(f: Font, pos: Vector2, text: String, fs: int, col: Color, centred := false, right := false, outline := Color(0, 0, 0, 0)) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if centred:
		pos.x -= w * 0.5
	elif right:
		pos.x -= w
	if outline.a > 0.0:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 5), outline)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
