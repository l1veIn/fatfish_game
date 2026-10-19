class_name CheckoutReceipt
extends Control
## 关门结账 (docs/settlement_design.md): a meal-ticket receipt prints out over the dimmed canteen
## (she lies flat on the table on the right) and plays the shift's closing back one step at a
## time: what she ate, the leftovers (eaten in her dreams with 我去睡了, or "wasted"), the 保温箱,
## the <EOS> last bite in a spotlight, 梯度裁剪, the subtotal, then the multipliers stamped into a
## row of five slots one by one (each stamp multiplies the total there and then, each one a step
## higher in pitch), and the result stamps. Earned tokens have no hidden overflow deduction.
## All the numbers were counted in CanteenRun._end() already: this is only the show. A click
## plays it 4x faster, Esc / Enter jumps to the end; the button goes back to the skill tree.

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
const PAPER := Rect2(500, 30, 740, 0)     # the receipt (its height follows what is on it)
const LINE_H := 46.0
const AMOUNT_COLUMN := 160.0
const INK := Color(0.29, 0.16, 0.08)
const GOLDEN := Color(0.62, 0.36, 0.06)
const RED := Color(0.78, 0.2, 0.16)
const GREY := Color(0.62, 0.55, 0.47)

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
var _extra_label: Label


func _ready() -> void:
	size = Vector2(1920, 1080)   # parent is the CanteenRun Node2D, so anchors have nothing to fill
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_dfont = load("res://assets/ui/ZCOOLKuaiLe.ttf") if ResourceLoader.exists("res://assets/ui/ZCOOLKuaiLe.ttf") else _font
	_nfont = UiKit.numerals()
	for n in ["ui_paper", "stamp_ring", "icon_token", "icon_box", "icon_clock", "icon_crown", "icon_shield", "icon_bolt", "fx_burst", "fx_star"]:
		var f := "res://assets/canteen/%s.png" % n
		if ResourceLoader.exists(f):
			_tex[n] = load(f)
	_stamp_t.resize(maxi(SLOTS, mults.size()))
	_stamp_t.fill(-1.0)
	_back = UiKit.button(tr("回技能树"), 32, Vector2(280, 80))
	_back.position = Vector2(PAPER.get_center().x - 140, 980)
	_back.modulate.a = 0.0
	_back.disabled = true
	_back.pressed.connect(_close)
	add_child(_back)
	# A release/retry explanation is longer than a receipt footer in English. Keep it
	# beside the result stamps, clear of the total and the return action.
	_extra_label = UiKit.label(extra, 24, Color(1.0, 0.9, 0.7), 5)
	_extra_label.position = Vector2(1300, 510)
	_extra_label.size = Vector2(520, 260)
	_extra_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_extra_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra_label.visible = false
	add_child(_extra_label)
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
	_extra_label.visible = extra != ""
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.02, 0.01, 0.5))
	var r := Rect2(PAPER.position, Vector2(PAPER.size.x, _paper_h))
	draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0, 0, 0, 0.35))   # its shadow
	UiKit.nine(self, _tex.get("ui_paper", null), r, 40.0, 0.8)
	var x0 := r.position.x + 48.0
	var x1 := r.end.x - 48.0
	var y := r.position.y + 70.0
	_text(_dfont, Vector2(r.get_center().x, y), heading, 34, RED, true)
	y += 34.0
	_text(_font, Vector2(r.get_center().x, y), sub, 18, GREY, true)
	y += 14.0
	_dashes(x0, x1, y)
	y += 12.0
	for i in mini(_shown, steps.size()):
		var st: Dictionary = steps[i]
		_line(st, x0, x1, y + 26.0)
		y += _line_height(st, x1 - x0)
	if _sub_on:
		y += 20.0
		_dashes(x0, x1, y)
		y += 44.0
		_text(_font, Vector2(x0, y), tr("小计"), 24, INK)
		_text(_nfont, Vector2(x1, y), Game.fmt(_sub_val), 38, Color(1.0, 0.96, 0.88), false, true)
	if _slots_on:
		y += 24.0
		_slots(x0, x1, y)
		y += 112.0
	# the total, once there is a subtotal to multiply
	_need_h = y - r.position.y + (130.0 if _sub_on else 30.0)
	if _sub_on:
		var ty := y + 96.0
		_dashes(x0, x1, ty - 58.0)
		_text(_font, Vector2(x0, ty - 6.0), tr("合计 token"), 24, INK)
		var k := 1.0 + 0.18 * _total_pop
		_text(_nfont, Vector2(x1, ty), Game.fmt(_total_val), int(64 * k), Color(1.0, 0.42, 0.32), false, true)
	# the result stamps, right of the receipt
	var sy := 140.0
	for res in _results:
		_result_stamp(Vector2(r.end.x + 150.0, sy), res[0], res[1], res[2])
		sy += 110.0
	if sleeping and _shown >= 2 and not _done:
		for j in 3:   # Zzz over her, while she eats the leftovers in her dreams
			var ph := fmod(_t * 0.6 + j / 3.0, 1.0)
			var at := Vector2(1640.0 + ph * 60.0, 760.0 - ph * 90.0)
			_text(_dfont, at, "Z" if j == 2 else "z", 26 + j * 8, Color(0.85, 0.92, 1.0, 1.0 - ph), false, false, Color(0.1, 0.15, 0.3, 1.0 - ph))
	if not _spot.is_empty():
		_spotlight()


func _step_text(st: Dictionary) -> String:
	return str(st.get("note", st.get("text", "")))


func _description_width(st: Dictionary, width: float) -> float:
	var available := width - 44.0 - AMOUNT_COLUMN
	if st.has("mark"):
		available -= _dfont.get_string_size(str(st.mark), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
	return available


func _line_height(st: Dictionary, width: float) -> float:
	var fs := 18 if st.has("note") else 22
	var measured := _font.get_multiline_string_size(_step_text(st), HORIZONTAL_ALIGNMENT_LEFT, _description_width(st, width), fs)
	return maxf(LINE_H, measured.y + 12.0)


func _line(st: Dictionary, x0: float, x1: float, y: float) -> void:
	var note := st.has("note")
	var lost := st.has("lost")
	var fs := 18 if note else 22
	var tx := x0 + 44.0
	var copy := _step_text(st)
	var description_width := _description_width(st, x1 - x0)
	# Reserve the amount column before wrapping. A long explanation must never run
	# through the outlined receipt numerals or force the amount off the paper.
	draw_multiline_string(_font, Vector2(tx, y - (4.0 if note else 0.0)), copy,
		HORIZONTAL_ALIGNMENT_LEFT, description_width, fs, -1, GREY if note or lost else INK)
	if st.has("mark"):
		var badge_width := _dfont.get_string_size(str(st.mark), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 14.0
		var badge := Rect2(tx + description_width + 10.0, y - 22.0, badge_width, 26.0)
		draw_set_transform(badge.get_center(), -0.08, Vector2.ONE)
		draw_style_box(UiKit.box(RED, Color.TRANSPARENT, 0, 5), Rect2(-badge.size * 0.5, badge.size))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(_dfont, Vector2(badge.get_center().x, y - 2.0), str(st.mark), 20, Color(1.0, 0.96, 0.88), true)
	if not note:
		var icon: Texture2D = _tex.get("icon_" + str(st.get("icon", "")), null)
		if icon != null:
			var scale_factor := 32.0 / maxf(icon.get_width(), icon.get_height())
			draw_texture_rect(icon, Rect2(Vector2(x0, y - 26.0), icon.get_size() * scale_factor), false, Color(1, 1, 1, 0.5 if lost else 1.0))
	var amount := Game.fmt(float(st.get("lost", st.get("add", 0.0))))
	if note:
		_text(_nfont, Vector2(x1, y - 4.0), amount, 22, GREY, false, true)
	elif lost:
		_text(_nfont, Vector2(x1, y), amount, 28, GREY, false, true)
		var amount_width := _nfont.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_line(Vector2(x1 - amount_width - 2.0, y - 9.0), Vector2(x1 + 2.0, y - 9.0), GREY, 2.0)
	else:
		_text(_nfont, Vector2(x1, y), "+" + amount, 30, Color(0.95, 0.72, 0.25), false, true)


## Five stamp slots: the multipliers stamped in so far, dashed rings for the ones still to unlock.
func _slots(x0: float, x1: float, y: float) -> void:
	var d := 96.0
	var step := (x1 - x0 - d) / float(SLOTS - 1)
	for i in SLOTS:
		var c := Vector2(x0 + d * 0.5 + step * i, y + d * 0.5)
		if i < mults.size() and i < _stamped:
			var t: float = _stamp_t[i]
			var k := 1.0 + 1.3 * maxf(0.0, 1.0 - t / 0.14)   # slams down from big
			var a := clampf(t / 0.06, 0.0, 1.0)
			draw_set_transform(c, -0.22, Vector2(k, k))
			var ring: Texture2D = _tex.get("stamp_ring", null)
			if ring != null:
				draw_texture_rect(ring, Rect2(-Vector2(d, d) * 0.55, Vector2(d, d) * 1.1), false, Color(1, 1, 1, a))
			draw_multiline_string(_font, Vector2(-56, -18), str(mults[i][0]), HORIZONTAL_ALIGNMENT_CENTER, 112, 17, 2, Color(RED, a))
			_text(_nfont, Vector2(0, 22), "×%.2f" % float(mults[i][1]), 23, Color(1.0, 0.42, 0.32, a), true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			for j in 16:   # a dashed ring and a question mark: more to unlock in the skill tree
				var a0 := j * TAU / 16.0
				draw_arc(c, d * 0.45, a0, a0 + TAU / 32.0, 4, Color(0.78, 0.66, 0.5), 2.0, true)
			_text(_dfont, c + Vector2(0, 12), "?", 34, Color(0.78, 0.66, 0.5), true)


func _result_stamp(c: Vector2, text: String, col: Color, t: float) -> void:
	var k := 1.0 + 1.4 * maxf(0.0, 1.0 - t / 0.16)
	var a := clampf(t / 0.06, 0.0, 1.0)
	var w := _dfont.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x + 40.0
	draw_set_transform(c, -0.16, Vector2(k, k))
	draw_style_box(UiKit.box(Color(1.0, 0.96, 0.87, 0.92 * a), Color(col, a), 5, 10), Rect2(-w * 0.5, -36, w, 66))
	_text(_dfont, Vector2(0, 12), text, 40, Color(col, a), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The <EOS> last bite: the dish big in the middle under a warm light, then its stamp.
func _spotlight() -> void:
	var c := Vector2(870, 470)
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
