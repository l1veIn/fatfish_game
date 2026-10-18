class_name Burst
extends Node2D
## A one-shot spray of droplet particles (hit splashes, dust, death puffs).

var _color := Color.WHITE
var _parts: Array = []


func setup(color: Color, count: int, speed: float, size: float) -> void:
	_color = color
	z_index = 30
	for i in count:
		var dir := Vector2.from_angle(randf() * TAU)
		_parts.append({
			"pos": Vector2.ZERO,
			"vel": dir * speed * randf_range(0.3, 1.0),
			"life": randf_range(0.18, 0.45),
			"size": randf_range(size * 0.5, size),
		})


func _process(delta: float) -> void:
	var alive := false
	for p in _parts:
		p.life -= delta
		if p.life <= 0.0:
			continue
		alive = true
		p.vel *= pow(0.02, delta)
		p.vel.y += 900.0 * delta
		p.pos += p.vel * delta
	if not alive:
		queue_free()
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		if p.life > 0.0:
			# a droplet: streak along its velocity with a round head, shrinking as it dies
			var s: float = p.size * clampf(p.life / 0.3, 0.3, 1.0)
			draw_line(p.pos, p.pos - p.vel * 0.035, Color(_color, 0.7), s * 0.7)
			draw_circle(p.pos, s * 0.5, _color)
