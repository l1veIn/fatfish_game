extends RefCounted
## One rigid painted arm in the tray's elevated perspective. Reach exposes more
## sleeve by clipping UVs; no frame can stretch, shear, rotate or flip the art.
const ART := preload("res://assets/canteen/player_hand.png")
const SOURCE_GRIP := Vector2(145, 90)
const AXIS := Vector2(0.707107, 0.707107)
const HAND_SCALE := 0.30
const THUMB := Rect2(95, 45, 190, 115)


static func grip(art: Rect2) -> Vector2:
	return art.end - Vector2(12, maxf(35, art.size.y * 0.17 + 10))


static func draw_arm(ci: CanvasItem, art: Rect2, touch: Vector2) -> void:
	var anchor := grip(art)
	# Keep the whole wrist/cuff and a short sleeve even at minimum reach.
	var length := maxf(160.0, (touch - anchor).dot(AXIS)) / HAND_SCALE
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(ART.get_width(), 0), ART.get_size(), Vector2(0, ART.get_height())])
	var source := _clip(corners, length)
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	for p in source:
		points.append(anchor + (p - SOURCE_GRIP) * HAND_SCALE)
		uv.append(p / ART.get_size())
	ci.draw_polygon(points, PackedColorArray([Color.WHITE]), uv, ART)


static func _clip(points: PackedVector2Array, length: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var da := (a - SOURCE_GRIP).dot(AXIS) - length
		var db := (b - SOURCE_GRIP).dot(AXIS) - length
		if da <= 0: result.append(a)
		if (da <= 0) != (db <= 0): result.append(a.lerp(b, da / (da - db)))
	return result


static func draw_fingers(ci: CanvasItem, art: Rect2) -> void:
	# The painted thumb overlaps the near-right lip. The tray occludes the
	# supporting palm/fingers, keeping the food compartments unobstructed.
	var destination := Rect2(grip(art) + (THUMB.position - SOURCE_GRIP) * HAND_SCALE, THUMB.size * HAND_SCALE)
	ci.draw_texture_rect_region(ART, destination, THUMB)
