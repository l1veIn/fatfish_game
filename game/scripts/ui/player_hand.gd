extends RefCounted
## Shared grip art. The forearm sits behind the tray; fingers wrap over its outer rim.
const INK := Color("372a35")
const SKIN := Color("f0c9aa")


static func grip(art: Rect2) -> Vector2:
	return art.end - Vector2(25, 28)


static func draw_arm(ci: CanvasItem, art: Rect2, touch: Vector2) -> void:
	var palm := grip(art)
	var direction := (touch - palm).normalized()
	if direction.length_squared() < 0.1: direction = Vector2(1, 1).normalized()
	var side := direction.orthogonal()
	var cuff := palm.lerp(touch, 0.42)
	var wrist := palm + direction * 24
	var arm := PackedVector2Array([wrist - side * 18, touch - side * 34, touch + side * 34, wrist + side * 18])
	ci.draw_colored_polygon(arm, SKIN)
	ci.draw_polyline(PackedVector2Array([arm[0], arm[1], arm[2], arm[3], arm[0]]), INK, 5, true)
	var sleeve := PackedVector2Array([cuff - side * 25, touch - side * 35, touch + side * 35, cuff + side * 25])
	ci.draw_colored_polygon(sleeve, Color("647ca6"))
	ci.draw_polyline(PackedVector2Array([sleeve[0], sleeve[1], sleeve[2], sleeve[3], sleeve[0]]), INK, 5, true)
	ci.draw_line(cuff - side * 25, cuff + side * 25, Color("fff0d5"), 16, true)
	ci.draw_line(cuff - side * 25, cuff + side * 25, INK, 2, true)
	ci.draw_circle(palm, 29, INK, true, -1, true)
	ci.draw_circle(palm, 25, SKIN, true, -1, true)
	ci.draw_line(wrist, cuff - direction * 11, Color("ffdfc1"), 13, true)


static func draw_fingers(ci: CanvasItem, art: Rect2) -> void:
	var palm := grip(art)
	# Curled fingers remain on the outside rim, below the food compartments.
	for i in 3:
		var from := palm + Vector2(-22 + i * 12, -5 + i * 3)
		var to := from + Vector2(3, 18)
		ci.draw_line(from, to, INK, 12, true)
		ci.draw_circle(from, 6, INK, true, -1, true)
		ci.draw_line(from, to, SKIN, 8, true)
		ci.draw_circle(from, 4, SKIN, true, -1, true)
	ci.draw_line(palm + Vector2(17, -13), palm + Vector2(25, 4), INK, 16, true)
	ci.draw_line(palm + Vector2(17, -13), palm + Vector2(25, 4), SKIN, 11, true)
