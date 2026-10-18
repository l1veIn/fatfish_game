extends Node
## Game-feel helpers used everywhere: hit-stop, screen shake, damage numbers, popups and
## particle bursts. Also installs the global CJK font for custom drawing.

var camera: Camera2D = null   # set by SharedCamera
var world: Node2D = null      # transient effects and projectiles are spawned here

var _hitstop_end := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Noto Sans SC (SIL OFL, assets/ui/OFL.txt) at a semi-bold weight, system CJK fonts as
	# backup. The same resource is the project's gui/theme/custom_font, so Labels and Buttons
	# use it too (the web build has no system fonts to fall back on).
	ThemeDB.fallback_font = load("res://assets/ui/ui_font.tres")


func _process(_delta: float) -> void:
	if Engine.time_scale < 1.0 and _now() >= _hitstop_end:
		Engine.time_scale = 1.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Freezes the game for a few hundredths of a second so hits feel heavy.
func hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	_hitstop_end = maxf(_hitstop_end, _now() + duration)
	Engine.time_scale = 0.05


func shake(power: float, duration: float) -> void:
	if is_instance_valid(camera) and camera.has_method("add_shake"):
		camera.add_shake(power, duration)


func spawn(node: Node2D, pos: Vector2) -> void:
	if not is_instance_valid(world):
		node.free()
		return
	world.add_child(node)
	node.global_position = pos


func damage_number(pos: Vector2, value: int, color: Color) -> void:
	_float_label(pos + Vector2(randf_range(-16.0, 16.0), 0.0), str(value), color, 30, 0.6)


func popup_text(pos: Vector2, text: String, color: Color) -> void:
	_float_label(pos, text, color, 28, 1.2)


func burst(pos: Vector2, color: Color, count: int, speed: float, size: float) -> void:
	var b := Burst.new()
	b.setup(color, count, speed, size)
	spawn(b, pos)


## --- procedural effects (see Vfx) -----------------------------------------------------

func muzzle_flash(pos: Vector2, dir: Vector2) -> void:
	var v := Vfx.make("muzzle"); v.dir = dir
	spawn(v, pos)
	var sm := Vfx.make("smoke"); sm.dir = dir; sm.radius = 14.0; sm.count = 3; sm.life = 0.45
	sm.color = Color(0.85, 0.85, 0.85)
	spawn(sm, pos + dir * 10.0)


## Sparks flying along dir (e.g. the reflection off a wall), plus a small flash.
func sparks(pos: Vector2, dir: Vector2, color := Color(1.0, 0.8, 0.4), n := 8) -> void:
	var v := Vfx.make("spark"); v.dir = dir; v.color = color; v.count = n
	spawn(v, pos)


## Star-shaped hit flash at a contact point.
func hit_flash(pos: Vector2, color := Color(1.0, 0.95, 0.75), size := 46.0) -> void:
	var v := Vfx.make("flash"); v.color = color; v.radius = size
	spawn(v, pos)


func shell(pos: Vector2, facing: int) -> void:
	var v := Vfx.make("shell"); v.dir = Vector2(facing, 0)
	spawn(v, pos)


## Fireball, shockwave ring, smoke and debris; radius in world px.
func explosion(pos: Vector2, radius: float) -> void:
	var ring := Vfx.make("ring"); ring.radius = radius; ring.color = Color(1.0, 0.85, 0.55)
	spawn(ring, pos)
	var fire := Vfx.make("fire"); fire.radius = radius * 0.3; fire.count = 14
	spawn(fire, pos)
	var sm := Vfx.make("smoke"); sm.radius = radius * 0.4; sm.count = 9; sm.life = 1.3
	sm.color = Color(0.36, 0.32, 0.3); sm.dir = Vector2.UP
	spawn(sm, pos + Vector2(0, -10))
	for i in 2:
		var sp := Vfx.make("spark"); sp.dir = Vector2.from_angle(-PI / 2.0 + (i - 0.5) * 1.6); sp.count = 12
		sp.color = Color(1.0, 0.7, 0.3)
		spawn(sp, pos)
	shake(16.0, 0.35)


## Heavy ground impact (boss slam / landing): dust shockwave ring, flying rocks, dust clouds.
func ground_slam(pos: Vector2, radius: float) -> void:
	var ring := Vfx.make("ring"); ring.radius = radius; ring.color = Color(0.9, 0.82, 0.62)
	spawn(ring, pos + Vector2(0, -8))
	var rocks := Vfx.make("rocks"); rocks.radius = radius; rocks.count = 14; rocks.color = Color(0.36, 0.29, 0.22)
	spawn(rocks, pos)
	var sm := Vfx.make("smoke"); sm.radius = radius * 0.35; sm.count = 10; sm.life = 1.1
	sm.color = Color(0.55, 0.48, 0.38); sm.dir = Vector2.UP
	spawn(sm, pos + Vector2(0, -20))
	for s in [-1.0, 1.0]:
		var d := Vfx.make("smoke"); d.radius = radius * 0.25; d.count = 5; d.life = 0.8
		d.color = Color(0.6, 0.53, 0.42); d.dir = Vector2(s * 3.0, -0.3).normalized()
		spawn(d, pos + Vector2(s * radius * 0.3, -10))


func _float_label(pos: Vector2, text: String, color: Color, font_size: int, duration: float) -> void:
	if not is_instance_valid(world):
		return
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.size = Vector2(400, 40)
	label.position = pos - Vector2(200, 30)
	label.z_index = 60
	world.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 70.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.tween_callback(label.queue_free)
