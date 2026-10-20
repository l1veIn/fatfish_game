extends Node2D
## A comic performance driven by real consumption. Food remains identifiable in the box;
## nothing is pasted into the basin or onto the face. No gameplay RNG, inventory or audio.
const MARK_TIME := 0.22
const MAX_MARKS := 4
const SIP_FOODS := ["congee", "soymilk", "cola", "milktea"]
const INK := Color("71503c")
const PAPER := Color("fff3d7")
var run: CanteenRun
var fish: FishRig
var _marks: Array = []
var _current := {}
var _pending := {}
var _elapsed := 0.0
var _duration := 0.76
var _continuing := false
var observed_bites := 0
var represented_bites := 0
var completed_gestures := 0
var peak_marks := 0


func _ready() -> void:
	z_index = 2
	set_process(false)  # The production eating clock also handles pause and deep thinking.


func consume(it: int, origin: Vector2, rejected := false) -> void:
	observed_bites += 1
	var k := CanteenRun.K(it)
	var id: String = CanteenRun.KIND.find_key(k)
	var style := "sip" if id in SIP_FOODS else "gobble"
	# At high throughput, coalesce the same cell's ink cue instead of flashing per bite.
	if _marks.size() < MAX_MARKS and not _marks.any(func(m): return m.from.distance_to(origin) < 16.0):
		_marks.append({"from": origin, "age": 0.0, "reject": rejected})
	peak_marks = maxi(peak_marks, _marks.size())
	if rejected:
		represented_bites += 1
		return  # The production spit / grok reactions retain priority over eating.
	if _current.is_empty():
		_current = {"count": 1, "style": style}
		_elapsed = 0.0
		_continuing = false
	elif _elapsed < 0.20:
		_add_bite(_current, style)
	else:
		if _pending.is_empty(): _pending = {"count": 0, "style": style}
		_add_bite(_pending, style)
	_sync_rig()
	queue_redraw()


func _add_bite(packet: Dictionary, style: String) -> void:
	packet.count += 1
	if packet.style != style: packet.style = "gobble"


func advance(delta: float) -> void:
	for mark in _marks: mark.age += delta
	_marks = _marks.filter(func(m): return m.age < MARK_TIME)
	if not _current.is_empty():
		_elapsed += delta
		if _elapsed >= _duration:
			represented_bites += int(_current.count)
			completed_gestures += 1
			_current = _pending
			_pending = {}
			_elapsed = 0.0
			_continuing = not _current.is_empty()
	_sync_rig()
	queue_redraw()


func clear() -> void:
	_marks.clear()
	_current.clear()
	_pending.clear()
	_continuing = false
	fish.meal_active = false
	fish.meal_chain = false
	queue_redraw()


func _sync_rig() -> void:
	fish.meal_active = not _current.is_empty()
	if fish.meal_active:
		fish.meal_phase = clampf(_elapsed / _duration, 0.0, 1.0)
		fish.meal_style = str(_current.style)
		fish.meal_fast = int(_current.count) > 2
		fish.meal_chain = not _pending.is_empty()
		fish.meal_continuing = _continuing
		fish.meal_variant = completed_gestures % 2


func _draw() -> void:
	if not is_instance_valid(fish) or run._ended or Settings.reduced_motion: return
	# A tiny stationary pick-up mark belongs to the actual consumed cell. No icon flights.
	for mark in _marks:
		var t := float(mark.age) / MARK_TIME
		var fade := (1.0 - t) * 0.65
		for i in 3:
			var dir := Vector2.from_angle(-PI * 0.85 + i * 0.35)
			var a: Vector2 = mark.from + dir * (10.0 + t * 4.0)
			var b: Vector2 = a + dir * (7.0 - t * 3.0)
			_stroke(PackedVector2Array([a, b]), fade)
	if _current.is_empty() or fish._meal_pose != "comic": return
	var ph := fish.meal_phase
	var fast := fish.meal_fast
	var sip := fish.meal_style == "sip"
	var beat := fmod(ph * (4.0 if fast else 2.0), 1.0)
	var alpha := (0.5 if sip else 0.76) * sin(beat * PI)
	# Two small impact ticks at the basin edge; never a screen flash or a text bubble.
	if fast:
		var edge := to_local(fish.meal_anchor("basin")) + Vector2(56, 0)
		_stroke(PackedVector2Array([edge + Vector2(0, -8), edge + Vector2(7, -13), edge + Vector2(10, -21)]), alpha * 0.65)


func _stroke(points: PackedVector2Array, alpha: float) -> void:
	if alpha < 0.02: return
	draw_polyline(points, Color(INK, alpha), 3.6, true)
	draw_polyline(points, Color(PAPER, alpha), 1.5, true)
