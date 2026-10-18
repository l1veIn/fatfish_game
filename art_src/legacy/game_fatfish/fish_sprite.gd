class_name FishSprite
extends Node2D
## 大肥鱼 drawn from the packed animation sheets (res://data/fish_anims.json, built by
## pipeline/pack_fish_anims.py). Position this node at her feet.
##   play("slurp", true)   intro once, then repeat the clip's loop section until the next play()
##   play("happy")         play once (loop section included once), then back to `idle_clip`
## Clips without a loop section loop whole when held or when they are the idle clip.

signal clip_finished(clip: String)

static var _manifest := {}

var idle_clip := "idle"
var height := 256.0             # on-screen size of a 256 px tnd cell (character is ~200/256 of it)
var clip := ""

var _sprite: Sprite2D
var _spec := {}
var _hold := false
var _frame := 0
var _time := 0.0
var _squash := 0.0


func _ready() -> void:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_anims.json"))
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_sprite)
	if clip == "":
		play(idle_clip)


func has_clip(name: String) -> bool:
	return _manifest.has(name)


func play(name: String, hold := false) -> void:
	if not _manifest.has(name):
		push_warning("unknown fish clip " + name)
		return
	if name == clip and hold == _hold:
		return
	clip = name
	_hold = hold or name == idle_clip
	_spec = _manifest[name]
	_sprite.texture = load(_spec["sheet"])
	_sprite.hframes = int(_spec["cols"])
	_sprite.vframes = ceili(float(_spec["frames"]) / float(_spec["cols"]))
	_sprite.offset = -Vector2(float(_spec["pivot"][0]), float(_spec["pivot"][1]))
	# tnd clips are 256 px cells with a ~200 px tall character; the cropped dsh / yun clips are
	# scaled so the character comes out the same size
	var s := height / 256.0
	if not String(_spec["source"]).begins_with("tnd"):
		s = height * 200.0 / 256.0 / float(_spec["h"])
	_sprite.scale = Vector2.ONE * s
	_frame = 0
	_time = 0.0
	_sprite.frame = 0


## A quick squash-and-stretch on top of the current clip (eating bites, purchases).
func bounce() -> void:
	_squash = 0.15


func _process(delta: float) -> void:
	_squash = maxf(_squash - delta, 0.0)
	var k := _squash / 0.15
	scale = Vector2(1.0 + 0.08 * k, 1.0 - 0.06 * k)
	if _spec.is_empty():
		return
	_time += delta
	var step := 1.0 / float(_spec["fps"])
	while _time >= step:
		_time -= step
		_advance()


func _advance() -> void:
	var n := int(_spec["frames"])
	var has_section := _spec.has("loop_from")
	var last := n - 1
	if _hold and has_section and _frame >= int(_spec["loop_to"]):
		_frame = int(_spec["loop_from"])
	elif _frame >= last:
		if _hold:
			_frame = 0
		else:
			var done := clip
			play(idle_clip)
			clip_finished.emit(done)
			return
	else:
		_frame += 1
	_sprite.frame = _frame
