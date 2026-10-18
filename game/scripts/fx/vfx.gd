class_name Vfx
extends Node2D
## Procedural one-shot effects (no textures): muzzle flash, sparks, hit flash, smoke, shell
## casing, explosion fire / shockwave. Spawned through the Fx helpers. Glowing kinds use
## additive blending; smoke and casings draw normally. Effects run on game time, so they
## freeze with hit-stop like everything else.

var kind := "spark"
var dir := Vector2.RIGHT
var color := Color(1.0, 0.85, 0.45)
var radius := 100.0
var count := 10
var life := 0.2

var _age := 0.0
var _parts: Array = []


static func make(k: String) -> Vfx:
	var v := Vfx.new()
	v.kind = k
	return v


func _ready() -> void:
	z_index = 38 if kind == "smoke" else 41
	if kind in ["muzzle", "spark", "flash", "fire", "ring"]:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	match kind:
		"muzzle":
			life = 0.07
			rotation = dir.angle() + randf_range(-0.08, 0.08)
			scale = Vector2.ONE * randf_range(1.4, 1.8)
		"spark":
			# streaks thrown in a cone around dir
			for i in count:
				var a := dir.angle() + randf_range(-0.9, 0.9)
				_parts.append({"p": Vector2.ZERO, "v": Vector2.from_angle(a) * randf_range(250.0, 900.0),
					"life": randf_range(0.08, 0.22), "w": randf_range(1.5, 3.0)})
			life = 0.25
		"flash":
			life = 0.09
			rotation = randf() * TAU
		"smoke":
			for i in count:
				_parts.append({"p": Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)) * radius,
					"v": Vector2(randf_range(-40.0, 40.0), randf_range(-90.0, -30.0)) + dir * randf_range(20.0, 90.0),
					"r": radius * randf_range(0.35, 0.6), "life": randf_range(0.5, 1.0) * life})
		"fire":
			for i in count:
				var a := randf() * TAU
				_parts.append({"p": Vector2.from_angle(a) * radius * 0.3, "v": Vector2.from_angle(a) * radius * randf_range(1.6, 3.2) + Vector2(0, -radius * 0.9),
					"r": radius * randf_range(0.55, 0.85), "life": randf_range(0.3, 0.5)})
			life = 0.5
		"ring":
			life = 0.22
		"rocks":
			# chunks of earth thrown up by a heavy impact
			for i in count:
				var a := -PI / 2.0 + randf_range(-1.1, 1.1)
				_parts.append({"p": Vector2(randf_range(-radius, radius) * 0.4, 0), "v": Vector2.from_angle(a) * randf_range(350.0, 900.0),
					"rot": randf() * TAU, "spin": randf_range(-14.0, 14.0), "r": randf_range(5.0, 12.0)})
			life = 0.9
		"shell":
			life = 1.1
			_parts.append({"p": Vector2.ZERO, "v": Vector2(-dir.x * randf_range(120.0, 220.0), randf_range(-420.0, -300.0)),
				"rot": randf() * TAU, "spin": randf_range(-25.0, 25.0), "bounced": false})


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	match kind:
		"spark", "fire", "smoke":
			for p in _parts:
				p.life -= delta
				p.v *= pow(0.08 if kind == "spark" else 0.25, delta)
				if kind == "spark":
					p.v.y += 1400.0 * delta
				p.p += p.v * delta
		"rocks":
			for p in _parts:
				p.v.y += 2200.0 * delta
				p.p += p.v * delta
				p.rot += p.spin * delta
		"shell":
			var s: Dictionary = _parts[0]
			s.v.y += 1800.0 * delta
			var from: Vector2 = global_position + s.p
			var to: Vector2 = from + s.v * delta
			var hit := {}   # no level geometry in this game, so debris never bounces
			if not hit.is_empty() and s.v.y > 0.0:
				s.p = hit["position"] - global_position
				s.v = Vector2(s.v.x * 0.45, -s.v.y * 0.32) if not s.bounced else Vector2.ZERO
				s.spin *= 0.4 if not s.bounced else 0.0
				s.bounced = true
			else:
				s.p += s.v * delta
			s.rot += s.spin * delta
	queue_redraw()


func _draw() -> void:
	var k := _age / life   # 0 -> 1 over the effect's life
	match kind:
		"muzzle":
			var f := clampf((1.0 - k) * 2.0, 0.0, 1.0)   # full bright for the first half
			var hot := Color(1.0, 0.98, 0.85, f)
			var warm := Color(1.0, 0.62, 0.18, 0.85 * f)
			# long forward flame, two side tongues, a round core
			draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(58, 0), Vector2(0, 9), Vector2(-6, 0)]), warm)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -5), Vector2(40, 0), Vector2(0, 5)]), hot)
			for s in [-1.0, 1.0]:
				var tip := Vector2.from_angle(s * 0.75) * 26.0
				draw_colored_polygon(PackedVector2Array([Vector2(0, -4), tip, Vector2(0, 4)]), warm)
			draw_circle(Vector2(4, 0), 11.0 * f + 3.0, hot)
		"spark":
			for p in _parts:
				if p.life > 0.0:
					var a: float = clampf(p.life / 0.15, 0.0, 1.0)
					draw_line(p.p, p.p - p.v * 0.03, Color(color, a), p.w)
					draw_line(p.p, p.p - p.v * 0.012, Color(1, 1, 1, a), p.w * 0.6)
		"flash":
			var s := (1.0 - k) * radius
			var c := Color(color, 1.0 - k)
			var pts := PackedVector2Array()
			for i in 8:
				var r := s if i % 2 == 0 else s * 0.22
				pts.append(Vector2.from_angle(i * TAU / 8.0) * r)
			draw_colored_polygon(pts, c)
			draw_circle(Vector2.ZERO, s * 0.3, Color(1, 1, 1, 1.0 - k))
		"smoke":
			for p in _parts:
				if p.life > 0.0:
					var a: float = clampf(p.life / 0.4, 0.0, 1.0) * 0.4 * clampf((_age - 0.06) / 0.12, 0.0, 1.0)
					var grow: float = 1.0 + _age * 1.6
					draw_circle(p.p, p.r * grow, Color(color, a))
		"fire":
			for p in _parts:
				if p.life > 0.0:
					var t: float = clampf(p.life / 0.5, 0.0, 1.0)
					var c := Color(1.0, 0.7, 0.3).lerp(Color(0.95, 0.32, 0.06), 1.0 - t).lerp(Color(0.45, 0.08, 0.03), maxf(0.0, 0.5 - t))
					draw_circle(p.p, p.r * (0.55 + t * 0.6), Color(c, minf(0.55, t)))
			# white-hot core that collapses in the first fifth
			if k < 0.15:
				draw_circle(Vector2.ZERO, radius * 1.4 * (1.0 - k / 0.15), Color(1.0, 0.95, 0.75, 1.0 - k / 0.15))
		"ring":
			var r := radius * (0.25 + 0.85 * (1.0 - pow(1.0 - k, 3.0)))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(color, 0.7 * (1.0 - k)), 7.0 * (1.0 - k) + 1.5)
		"rocks":
			var fade := clampf((life - _age) / 0.25, 0.0, 1.0)
			for p in _parts:
				draw_set_transform(p.p, p.rot)
				var r: float = p.r
				draw_colored_polygon(PackedVector2Array([Vector2(-r, -r * 0.6), Vector2(r * 0.4, -r), Vector2(r, r * 0.2), Vector2(-r * 0.2, r)]), Color(color, fade))
				draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.6, -r * 0.4), Vector2(r * 0.2, -r * 0.7), Vector2(r * 0.3, -r * 0.1)]), Color(color.lightened(0.3), fade))
			draw_set_transform(Vector2.ZERO)
		"shell":
			var s: Dictionary = _parts[0]
			var a := clampf((life - _age) / 0.3, 0.0, 1.0)
			draw_set_transform(s.p, s.rot)
			draw_rect(Rect2(-5, -2, 10, 4), Color(0.86, 0.66, 0.28, a))
			draw_rect(Rect2(-5, -2, 3, 4), Color(0.6, 0.42, 0.16, a))
