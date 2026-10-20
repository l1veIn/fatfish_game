class_name FishRig
extends Node2D
## 大肥鱼 as a rig: one high-res drawing on a subdivided mesh, bent by rig.gdshader (breathing,
## head tilt, hair / tail / fin / ahoge sway), with expression patches on the face that follow
## the head. Everything moves every frame from smooth functions of time, so there are no frames
## to jitter. Two drawings (pipeline/prep_rig.py):
##   seated = false   standing (title from V4, result card): game/assets/fatfish/rig/
##   basin = true     standing, deadpan, holding her iron basin (title before V4), with the
##                    basin worn as a helmet as its one pose: game/assets/fatfish/rig_basin/
##   seated = true    from the waist up, holding her iron basin (the shift, behind the table):
##                    game/assets/fatfish/rig_seat/, plus POSE layers (arms, basin, props) for
##                    eating, banging the basin, sulking with it on her head, cheering, ...
##   play("happy")         a one-shot action, then back to `idle_clip`
##   play("slurp", true)   hold an action until the next play()
##   bounce()              a squash-and-stretch on top
## `beat` is emitted on every strike while banging the basin (the shift plays the clang).
## Position this node at her feet (seated: at her waist); `height` is the old 256 px-cell size
## (the character is 200/256 of it), so existing layouts keep their scale.

signal clip_finished(clip: String)
signal beat

const GRID := 40
## Actions: face patch ("" = the drawing's own face), length in seconds (0 = loops), pose layer
## (seated only; "eat" and "bang" alternate two poses).
## Seated, she is mostly deadpan (blank / jitome / stuffed cheeks): funnier than smiling.
const CLIPS := {
	"idle": ["", 0.0, ""], "title_idle": ["", 0.0, ""], "basin": ["blank", 0.0, ""],
	"happy": ["happy", 1.2, ""], "not_fat": ["jitome", 1.6, ""], "beg": ["tear", 0.0, ""],
	"slurp": ["chew", 0.0, "eat"], "nibble": ["chew", 0.0, "eat"], "eat_rice": ["chew", 0.0, "eat"],
	"full_belly": ["sleepy", 0.0, "full"], "broke": ["puppy", 2.0, ""], "think": ["think", 0.0, "think"],
	"outsource": ["sleepy", 0.0, ""], "surprised": ["o", 1.0, ""],
	# shift reactions (docs/fish_actions_design.md)
	"dig_in": ["o", 0.55, ""], "sulk": ["blank", 0.0, "sulk"], "spit": ["jitome", 0.8, ""],
	"yum": ["happy", 0.7, ""], "bang": ["blank", 0.0, "bang"],
	# 顿悟: forcing greens down, then getting it
	"grimace": ["grimace", 0.5, ""], "grok": ["grok", 2.2, ""],
	# the early, emotionally flat 大肥鱼 (emote 0): a nod instead of a cheer, droopy fins instead of tears
	"title_basin": ["blank", 0.0, ""], "nod": ["blank", 0.9, ""], "droop": ["blank", 1.8, ""],
	"smile": ["blink", 1.0, ""],
	# title screen: patted on the head, getting fed up, the basin goes on her head, knocked on
	"pat": ["blank", 0.5, ""], "annoyed": ["jitome", 0.0, ""], "pout": ["pout", 1.4, ""],
	"helmet": ["blank", 0.0, "sulk"], "knock": ["jitome", 0.3, "sulk"],
}
## How much she shows (Game.emotion(): her version). 0 木讷: deadpan, a nod at most; 1: now and
## then a small closed-eye smile; 2: the full range. Clips missing here play as they are.
const EMOTE_AS := {
	0: {"happy": "nod", "yum": "nod", "broke": "droop", "beg": "droop", "surprised": "nod", "title_idle": "title_basin"},
	1: {"happy": "smile", "broke": "droop"},
}
## Faces only the seated drawing has: the standing one shows its nearest.
const FACE_FALLBACK := {"blank": "", "jitome": "pout", "o": "surprised", "tear": "puppy", "stuffed": "chew", "star": "happy", "grimace": "pout", "grok": "happy"}
## Per drawing: folder, rig data, feet (texture px), her height (px), neck (px) and the shader
## regions (uv) that differ from the standing defaults in rig.gdshader.
const RIGS := {
	"stand": {"dir": "res://assets/fatfish/rig/", "data": "res://data/fish_rig.json",
		"feet": Vector2(517, 1011), "char": 998.0, "neck": Vector2(510, 440), "regions": {}},
	"seat": {"dir": "res://assets/fatfish/rig_seat/", "data": "res://data/fish_rig_seat.json",
		"feet": Vector2(512, 1024), "char": 1014.0, "neck": Vector2(512, 566), "regions": {
			"neck": Vector2(0.5, 0.553), "head_y": Vector2(0.53, 0.62),
			"ahoge_box": Vector4(0.25, 0.44, 0.08, 0.115), "ahoge_root": Vector2(0.455, 0.09),
			"fin_l": Vector4(0.2, 0.455, 0.085, 0.05), "fin_l_root": Vector2(0.275, 0.455),
			"fin_r": Vector4(0.81, 0.42, 0.09, 0.05), "fin_r_root": Vector2(0.73, 0.42),
			"arm_l": Vector4(-1, -1, 0.01, 0.01), "arm_r": Vector4(-1, -1, 0.01, 0.01),
			"belly_e": Vector4(0.5, 0.78, 0.2, 0.12), "breath_y": Vector2(0.72, 1.0),
			"hair_band": Vector4(0.29, 0.38, 0.45, 0.95), "tail_box": Vector4(2, 3, 2, 3)}},
	# redrawn on the standing master's canvas (prep_rig.build_basin): the standing regions, but
	# the arms hold the basin and don't sway
	"basin": {"dir": "res://assets/fatfish/rig_basin/", "data": "res://data/fish_rig_basin.json",
		"feet": Vector2(517, 1011), "char": 998.0, "neck": Vector2(510, 440), "regions": {
			"arm_l": Vector4(-1, -1, 0.01, 0.01), "arm_r": Vector4(-1, -1, 0.01, 0.01)}},
}

var seated := false
var basin := false                     # standing with the basin (rig_basin); ignored when seated
var idle_clip := "idle"
var height := 256.0
var clip := ""
var belly := 0.0                       # tummy roundness, set by the shift as she eats
var emote := 2                         # how much she shows (EMOTE_AS); the shift keeps 2

var _cfg: Dictionary
var _root: Node2D
var _body: MeshInstance2D
var _pose_fade: MeshInstance2D
var _pose_fade_left := 0.0
var _base: Texture2D
var _poses := {}
var _mat: ShaderMaterial
var _pivot: Node2D
var _face: Sprite2D
var _faces := {}
var _face_rect := Rect2()
var _t := 0.0
var _ct := 0.0                 # time in the current clip
var _hold := false
var _squash := 0.0
var _blink_in := 2.5
var _blink := 0.0
var _down := false             # banging: the spoon is down
# smoothed values (eased toward their targets every frame)
var _head := 0.0
var _hop := 0.0
var _lean := 0.0
## Presentation clock comes from real bites; it never drives score or eating speed.
var meal_active := false
var meal_phase := 0.0
var meal_style := "gobble"
var meal_fast := false
var meal_chain := false
var meal_continuing := false
var meal_variant := 0
var _meal_pose := ""
var _meal_breath := 0.0
var _meal_faces := {}
var _cosmetic_rng := RandomNumberGenerator.new()
const MEAL_MOUTH_RECT := Rect2(115, 100, 110, 80)


func _ready() -> void:
	_cosmetic_rng.randomize()
	_cfg = RIGS["seat" if seated else ("basin" if basin else "stand")]
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root = Node2D.new()
	add_child(_root)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/fatfish/rig/rig.gdshader")
	for k in _cfg.regions:
		_mat.set_shader_parameter(k, _cfg.regions[k])
	var mesh := _grid_mesh()
	_body = MeshInstance2D.new()
	_body.mesh = mesh
	_base = load(_cfg.dir + "body.png")
	_body.texture = _base
	_body.material = _mat
	_body.position = -_cfg.feet
	_root.add_child(_body)
	_pose_fade = MeshInstance2D.new()
	_pose_fade.mesh = mesh
	_pose_fade.material = _mat
	_pose_fade.position = -_cfg.feet
	_pose_fade.visible = false
	_root.add_child(_pose_fade)
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_cfg.data))
	for name in info.get("poses", {}):
		_poses[name] = load(_cfg.dir + "pose_%s.png" % name)
	if seated:
		for name in ["take", "comic"]:
			_poses["meal_" + name] = load(_cfg.dir + "pose_meal_%s.png" % name)
	var r: Array = info["face_rect"]
	_face_rect = Rect2(r[0], r[1], r[2], r[3])
	for name in info["faces"]:
		_faces[name] = load(_cfg.dir + "face_%s.png" % name)
	if seated:
		for name in ["stuffed"]:
			var mouth := AtlasTexture.new()
			mouth.atlas = _faces[name]
			mouth.region = MEAL_MOUTH_RECT
			_meal_faces[name] = mouth
	_pivot = Node2D.new()
	_root.add_child(_pivot)
	_face = Sprite2D.new()
	_face.centered = false
	_face.position = _face_rect.position - _cfg.neck
	_pivot.add_child(_face)
	_t = _cosmetic_rng.randf() * 10.0
	if clip == "":
		play(idle_clip)
	_apply(0.0)


## A flat grid over the body texture; the shader bends it.
func _grid_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for y in GRID + 1:
		for x in GRID + 1:
			var uv := Vector2(float(x) / GRID, float(y) / GRID)
			uvs.append(uv)
			verts.append(uv * 1024.0)
	for y in GRID:
		for x in GRID:
			var i := y * (GRID + 1) + x
			idx.append_array([i, i + 1, i + GRID + 1, i + 1, i + GRID + 2, i + GRID + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A rectangle in the drawing's texture pixels -> the same area in the parent's coordinates
## (ignores the small hops and tilts), e.g. her head for clicks.
func tex_rect(r: Rect2) -> Rect2:
	var s := height * (200.0 / 256.0) / float(_cfg.char)
	return Rect2(position + (r.position - Vector2(_cfg.feet)) * s * scale, r.size * s * scale)


func has_clip(name: String) -> bool:
	return CLIPS.has(name)


func play(name: String, hold := false) -> void:
	name = EMOTE_AS.get(emote, {}).get(name, name)
	if not CLIPS.has(name):
		name = "idle"
	if name == clip and hold == _hold:
		return
	clip = name
	_hold = hold or float(CLIPS[name][1]) <= 0.0
	_ct = 0.0


func bounce() -> void:
	_squash = 0.15


func _process(delta: float) -> void:
	_t += delta
	_ct += delta
	_squash = maxf(_squash - delta, 0.0)
	var length: float = CLIPS[clip][1]
	if not _hold and length > 0.0 and _ct >= length:
		var done := clip
		play(idle_clip)
		clip_finished.emit(done)
	_apply(delta)


func _apply(delta: float) -> void:
	var s := height * (200.0 / 256.0) / float(_cfg.char)
	var face: String = CLIPS[clip][0]
	var pose: String = CLIPS[clip][2] if not _poses.is_empty() else ""
	var head := sin(_t * 0.7) * 0.025          # idle: a slow, slight tilt
	var hop := 0.0
	var lean := 0.0
	var head_shift := Vector2.ZERO
	var breath := sin(_t * TAU / 3.4) * 0.0035
	var fin := sin(_t * 2.3) * 0.06
	var arm := sin(_t * TAU / 3.4 + 0.6) * 0.012
	var tail := sin(_t * 1.4) * 0.08
	var hair := 0.004
	var comic_hand := Vector2.ZERO
	match clip:
		"happy":
			hop = absf(sin(_ct * TAU / 1.1)) * 34.0 * maxf(1.0 - _ct / 1.2, 0.0)
			fin = sin(_t * 9.0) * 0.16
			arm = 0.05 + sin(_t * 9.0) * 0.03
			tail = sin(_t * 6.0) * 0.18
		"not_fat":
			head = sin(_ct * 15.0) * 0.07 * maxf(1.0 - _ct / 1.6, 0.0)
			fin = -0.08
			arm = -0.02
		"beg", "broke":
			head = 0.09 + sin(_t * 1.3) * 0.02
			fin = -0.1 + sin(_t * 1.3) * 0.03   # ears droop
			hair = 0.002
			if clip == "broke":
				lean = sin(_ct * 12.0) * 0.012 * maxf(1.0 - _ct / 2.0, 0.0)
		"slurp", "nibble", "eat_rice":
			# Waiting for a real bite: never conjure a basin of rice from a loop timer.
			face = "blank"
			pose = ""
		"full_belly", "outsource":
			lean = -0.03
			breath *= 2.2
			head = -0.04 + sin(_t * 0.6) * 0.02
			fin = -0.05
		"think":
			head = 0.07 + sin(_t * 0.9) * 0.015
		"basin":
			hop = absf(sin(_t * 4.0)) * 8.0
			fin = sin(_t * 6.0) * 0.1
			head = sin(_t * 2.2) * 0.05   # looking about, hopeful
		"dig_in":
			hop = sin(minf(_ct / 0.55, 1.0) * PI) * 26.0
			fin = 0.18
			tail = sin(_t * 8.0) * 0.2
		"sulk":
			# head turned away, now and then a huffy shake
			head = -0.08 + (sin(_t * 18.0) * 0.04 if fmod(_t, 3.0) < 0.4 else 0.0)
			fin = -0.12
			hair = 0.002
			tail = sin(_t * 3.0) * 0.12
		"spit":
			head = sin(_ct * 20.0) * 0.08 * maxf(1.0 - _ct / 0.8, 0.0)
			fin = -0.06
		"grimace":
			head = sin(_ct * 30.0) * 0.03   # a shudder
			fin = -0.1
		"grok":
			hop = sin(minf(_ct / 0.4, 1.0) * PI) * 20.0
			fin = sin(_t * 12.0) * 0.18
		"yum":
			hop = sin(minf(_ct / 0.35, 1.0) * PI) * 14.0
			fin = sin(_t * 10.0) * 0.14
			head = sin(_ct * 9.0) * 0.04
			face = "star" if seated else "happy"
		"title_basin":
			head = sin(_t * 0.5) * 0.015   # just standing there with the basin, waiting
			breath *= 0.8
		"nod":
			# one small dip of the head, the ahoge flicks: that's all the joy you get
			var k := sin(minf(_ct / 0.6, 1.0) * PI)
			head_shift = Vector2(0.0, 0.012 * k)
			fin = 0.08 * k
			hair = 0.003
		"droop":
			head = 0.05
			head_shift = Vector2(0.0, 0.008)
			fin = -0.12   # ears down; the face doesn't move
			hair = 0.002
		"smile":
			hop = sin(minf(_ct / 0.5, 1.0) * PI) * 10.0
			fin = sin(_t * 7.0) * 0.08
		"pat":
			# the hand pushes her head down a little; eyes stay as they are
			var k := sin(minf(_ct / 0.45, 1.0) * PI)
			head_shift = Vector2(0.0, 0.016 * k)
			fin = -0.1 * k
			hair = 0.003
		"annoyed":
			head = -0.05 + sin(_t * 0.8) * 0.01   # face turned a little away
			fin = -0.06
		"pout":
			head = -0.07 + sin(_ct * 16.0) * 0.03 * maxf(1.0 - _ct / 0.6, 0.0)
			fin = -0.1
		"helmet":
			head = sin(_t * 0.6) * 0.01
			fin = -0.12
			hair = 0.002
		"knock":
			head_shift = Vector2(0.0, 0.01 * maxf(1.0 - _ct / 0.3, 0.0))
			fin = -0.14
		"bang":
			# the longer she waits the faster she bangs: 2.5 -> 5 strikes a second
			var rate := lerpf(2.5, 5.0, clampf(_ct / 6.0, 0.0, 1.0))
			var down := fmod(_ct * rate, 1.0) > 0.55
			if down and not _down:
				beat.emit()
				_squash = 0.08
			_down = down
			pose = "bang_down" if down else "bang_up"
			head = 0.03 if down else -0.02
			fin = 0.1 if down else -0.05
	_meal_pose = ""
	if seated and meal_active and clip not in ["spit", "grimace", "grok", "full_belly", "think"]:
		var preparing := meal_phase < 0.16 and not meal_continuing
		var settling := meal_phase >= 0.70 and not meal_chain
		_meal_pose = "take" if preparing or settling else "comic"
		pose = "meal_" + _meal_pose
		face = "stuffed" if settling and meal_phase < 0.93 else ""
		# Deadpan eyes, a short hold for chewing, then one little swallowing nod.
		head = (sin(meal_phase * PI) * 0.012) * (1 if meal_variant == 0 else -1)
		head_shift = Vector2(0, sin(clampf((meal_phase - 0.86) / 0.14, 0.0, 1.0) * PI) * 0.007) if settling else Vector2.ZERO
		if _meal_pose == "comic":
			var beat := meal_phase * TAU * (4.0 if meal_fast else 2.0)
			comic_hand = Vector2(cos(beat) * 0.006, sin(beat) * 0.014) * (0.4 if meal_style == "sip" else 1.0)
		hop = 0.0
		if Settings.reduced_motion:
			head = 0.0
			head_shift = Vector2.ZERO
			breath = 0.0
			comic_hand = Vector2.ZERO
	_meal_breath = breath
	# ease the big moves so switching actions never snaps
	var k := 1.0 - exp(-12.0 * delta) if delta > 0.0 else 1.0
	_head = lerpf(_head, head, k)
	_hop = lerpf(_hop, hop, k * 1.5 if hop > _hop else k)
	_lean = lerpf(_lean, lean, k)
	# a pose is a whole replacement drawing (same as the body except arms, basin and face);
	# the face patch only for pose-less clips
	var pose_tex: Texture2D = _poses.get(pose, null)
	var next_body: Texture2D = pose_tex if pose_tex != null else _base
	if next_body != _body.texture:
		if seated and meal_active and not Settings.reduced_motion:
			_pose_fade.texture = _body.texture
			_pose_fade_left = 0.065
		_body.texture = next_body
	_pose_fade_left = maxf(0.0, _pose_fade_left - delta)
	_pose_fade.visible = _pose_fade_left > 0.0 and not Settings.reduced_motion
	_pose_fade.modulate.a = _pose_fade_left / 0.065
	if pose_tex != null and not pose.begins_with("bang") and not pose.begins_with("meal_"):
		face = ""
	# blink now and then, only with the calm faces (other faces have their own eyes); the
	# deadpan one blinks without the smile (blink_flat: seated and basin)
	if (face == "" or face == "blank") and pose_tex == null:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink = 0.13
			_blink_in = _cosmetic_rng.randf_range(2.2, 5.0) * (0.35 if _cosmetic_rng.randf() < 0.2 else 1.0)
		if _blink > 0.0:
			_blink -= delta
			face = "blink_flat" if face == "blank" and _faces.has("blink_flat") else "blink"
	if not _faces.has(face) and FACE_FALLBACK.has(face):
		face = FACE_FALLBACK[face]
	# Only the mouth changes during a bite: keep the new pose's deadpan eyes and identity.
	var meal_mouth: bool = pose.begins_with("meal_") and _meal_faces.has(face)
	_face.texture = _meal_faces[face] if meal_mouth else _faces.get(face, null)
	_face.position = _face_rect.position - _cfg.neck + (MEAL_MOUTH_RECT.position if meal_mouth else Vector2.ZERO)
	_face.visible = face != "" and _face.texture != null
	# shader and the face pivot get the same head motion
	_mat.set_shader_parameter("t", _t)
	_mat.set_shader_parameter("head_angle", _head)
	_mat.set_shader_parameter("head_shift", head_shift)
	_mat.set_shader_parameter("breath", breath)
	_mat.set_shader_parameter("hair_amp", hair)
	_mat.set_shader_parameter("fin_angle", fin)
	_mat.set_shader_parameter("ahoge_angle", 0.0 if pose == "sulk" else sin(_t * 3.1) * 0.09 + _head * 1.5)   # (under the basin)
	_mat.set_shader_parameter("tail_angle", 0.0 if seated else tail)
	_mat.set_shader_parameter("arm_angle", 0.0 if seated or basin else arm)
	_mat.set_shader_parameter("belly", belly)
	_mat.set_shader_parameter("comic_hand", comic_hand)
	_pivot.position = -_cfg.feet + _cfg.neck + head_shift * 1024.0 - Vector2(0.0, breath * 1024.0)
	_pivot.rotation = _head
	var q := _squash / 0.15
	_root.scale = Vector2(1.0 + 0.06 * q, 1.0 - 0.05 * q) * s
	_root.position = Vector2(0.0, -_hop)
	_root.rotation = _lean


## Authored comic accent points in the 1024 px rig canvas; no food is rendered here.
func meal_anchor(which: String) -> Vector2:
	var point := Vector2(500, 746)
	if which == "basin" and _meal_pose == "comic": point = Vector2(506, 610)
	elif which == "utensil":
		point = Vector2(325, 570)
	elif which == "mouth": point = Vector2(511, 519)
	# Match the shader's head rotation and breathing at the contact point.
	var wh := 1.0 - smoothstep(0.53, 0.62, point.y / 1024.0)
	point = point.lerp(_cfg.neck + (point - Vector2(_cfg.neck)).rotated(_head), wh)
	point.y -= _meal_breath * 1024.0 * (1.0 - smoothstep(0.72, 1.0, point.y / 1024.0))
	return _root.to_global(point - Vector2(_cfg.feet))
