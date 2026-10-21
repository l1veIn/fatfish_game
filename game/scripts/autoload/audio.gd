extends Node
## Global audio: one-shot sound effects (pooled players, random pitch, per-sound throttling),
## crossfading music with adaptive layers, an ambience loop and the characters' voices.
## Sounds are referenced by file name without extension, e.g. Audio.sfx("parry"). Files live in
## res://assets/audio/{sfx,music,loops,voice}.
## Variants: name_v1.wav, name_v2.wav ... are one sound "name" picked at random (no repeats
## twice in a row), so rapid eating doesn't sound like a loop.
##
## The mix (buses: Settings creates Music / SFX / Voice for the volume sliders, the rest is here):
##   Master   a hard limiter, so a pile of catches at once never clips
##   Music    menu / end-of-shift ducking, a low-pass while time is slowed (深度思考), and a
##            compressor keyed from Voice: the music steps back a little while someone speaks
##   SFX      the slider; the KEY stingers (新菜谱, 顿悟, banners, results) play here directly...
##   SFXBed   ...while every other sound effect and the ambience go through this bus into SFX,
##            and it dips DUCK_DB while a stinger plays, so the big moments cut through
##   Voice    大肥鱼 and 梁阿姨: one line at a time across both (see vo()); her chomps share her
##            mouth with her lines (MOUTH)
## Music layers: a shift's track can come with <track>_peak.ogg and <track>_final.ogg
## (pipeline/make_music_layers.py, exactly as long as the track), played locked to it in an
## AudioStreamSynchronized and faded in and out by music_layer().

const SFX_DIR := "res://assets/audio/sfx"
const POOL_SIZE := 16
## Minimum seconds between two plays of the same sound (rapid fire would otherwise stack).
## Her mouth: these are her own eating noises (her voice), so they never overlap each other or a
## line of hers. One plays only when the last one has finished and she is not speaking; a voice
## line of hers cuts it off. (Overlapping chomps sounded like a whole table eating.)
const MOUTH := ["chomp", "crit"]
const MOUTH_GAP := 0.08        # seconds of quiet between two chomps
const THROTTLE := {"chomp": 0.18, "catch": 0.05, "catch_crisp": 0.05, "catch_slosh": 0.05, "catch_saucy": 0.05,
	"catch_wobble": 0.05, "catch_gold": 0.05, "floor": 0.08, "token": 0.06, "fling": 0.06, "ui_hover": 0.05, "bounce": 0.08}
## Stingers: everything else in SFXBed (and the music) ducks under them.
const KEY := ["version_up", "ticket", "trial_pass", "trial_fail", "shift_closed", "peak_start"]
const DUCK_DB := -4.0          # other sound effects under a stinger
const DUCK_MUSIC_DB := -4.0    # the music under a stinger
const MENU_DB := -9.0          # music while a menu is open (duck())
const SETTLE_DB := -7.0        # music after a shift closed (settle())
const LAYERS := ["peak", "final"]
const LAYER_DB := {"peak": 0.0, "final": -1.0}   # a layer at full volume (they are mixed under the track already)
const LAYER_IN := 0.6          # seconds to fade a layer in...
const LAYER_OUT := 1.6         # ...and out
const SLOW_CUTOFF := 1400.0    # music low-pass while time is slowed (Hz)

var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _key_pool: Array[AudioStreamPlayer] = []
var _next := 0
var _next_key := 0
var _last_played := {}
var _last_variant := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name := ""
var _music_cur: AudioStreamPlayer       # the player of _music_name
var _amb: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _music_amp: AudioEffectAmplify
var _bed_amp: AudioEffectAmplify
var _music_lp: AudioEffectLowPassFilter
var _lp_index := -1
## mix state, eased toward its target every frame in _process
var _menu := false
var _settled := false
var _key_until := 0.0                   # a stinger plays until then (seconds, ticks clock)
var _key_db := 0.0
var _music_db := 0.0
var _layer_on := {}                     # layer -> wanted
var _layer_level := {}                  # layer -> 0..1 now
var _tempo := 1.0                       # wanted music speed (the last seconds of a shift)
var _slow := false
var _pitch := 1.0
var _cutoff := 20000.0
## Character voices (pipeline/gen_voice.py): res://assets/audio/voice/<role>_<cue>_v<n>.ogg, one
## designed voice per character, one player per character.
const VO_DIR := "res://assets/audio/voice"
## Eating reactions share a real-time budget, even when meals or tests run faster.
## Purchase/pat feedback (happy / not_fat) and key story/gameplay cues stay immediate.
const FISH_NORMAL_CUES := ["fish_dig_in", "fish_bang", "fish_hmph", "fish_wait", "fish_grimace",
	"fish_bliss", "fish_savor", "fish_munch", "fish_crit"]
const FISH_VOICE_COOLDOWN := 4.0       # minimum seconds between ordinary line starts
const FISH_VOICE_GAP := 0.65           # quiet after her last line finishes or is interrupted
var _mouth: AudioStreamPlayer
var _mouth_free := 0.0                 # ticks clock (s) when her mouth can chomp again
var _vo := {}                          # "fish_spit" -> [streams]
var _vo_player := {}                   # role -> AudioStreamPlayer
var _vo_prio := {}                     # role -> priority of what it is saying
var _fish_last_normal := -100.0        # ticks clock; a rejected request never extends it
var _fish_quiet_until := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for file in ResourceLoader.list_directory(SFX_DIR):
		if file.ends_with(".wav"):
			var key := file.get_basename()
			var m := key.rfind("_v")
			if m > 0 and key.substr(m + 2).is_valid_int():
				key = key.substr(0, m)
			if not _sfx.has(key):
				_sfx[key] = []
			_sfx[key].append(load(SFX_DIR.path_join(file)))
	print("Audio: %d sound effects" % _sfx.size())
	for file in ResourceLoader.list_directory(VO_DIR):
		if file.ends_with(".ogg"):
			var key := file.get_basename()
			key = key.substr(0, key.rfind("_v"))
			if not _vo.has(key):
				_vo[key] = []
			_vo[key].append(load(VO_DIR.path_join(file)))
	print("Audio: %d voice cues" % _vo.size())
	_make_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFXBed"
		add_child(p)
		_pool.append(p)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_key_pool.append(p)
	_mouth = AudioStreamPlayer.new()
	_mouth.bus = "SFXBed"
	add_child(_mouth)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_amb = AudioStreamPlayer.new()
	_voice = AudioStreamPlayer.new()
	for p in [_music_a, _music_b, _amb, _voice]:
		add_child(p)
	_music_a.bus = "Music"
	_music_b.bus = "Music"
	_amb.bus = "SFXBed"
	_voice.bus = "Voice"
	for l in LAYERS:
		_layer_on[l] = false
		_layer_level[l] = 0.0


## The buses and effects of the mix (see the top). Settings has made Music / SFX / Voice.
func _make_buses() -> void:
	var master := AudioServer.get_bus_index("Master")
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(master, lim)
	if AudioServer.get_bus_index("SFXBed") < 0:
		var i := AudioServer.bus_count
		# Match Settings' Web-safe append; add_bus() breaks sample bus routing.
		AudioServer.bus_count = i + 1
		AudioServer.set_bus_name(i, "SFXBed")
		AudioServer.set_bus_send(i, "SFX")
	_bed_amp = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFXBed"), _bed_amp)
	var music := AudioServer.get_bus_index("Music")
	if music < 0:
		return
	_music_amp = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(music, _music_amp)
	_music_lp = AudioEffectLowPassFilter.new()
	_music_lp.cutoff_hz = 20000.0
	_music_lp.resonance = 0.6
	AudioServer.add_bus_effect(music, _music_lp)
	_lp_index = AudioServer.get_bus_effect_count(music) - 1
	AudioServer.set_bus_effect_enabled(music, _lp_index, false)
	var comp := AudioEffectCompressor.new()   # a voice line pulls the music down ~2-3 dB
	comp.sidechain = &"Voice"
	comp.threshold = -26.0
	comp.ratio = 3.0
	comp.attack_us = 8000.0
	comp.release_ms = 280.0
	AudioServer.add_bus_effect(music, comp)


## Stop everything on quit, so no playback outlives the audio server (leak warnings).
func _exit_tree() -> void:
	for p in _pool + _key_pool + [_mouth, _music_a, _music_b, _amb, _voice] + _vo_player.values():
		p.stop()
		p.stream = null
	_sfx.clear()
	_vo.clear()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var key_on := now < _key_until
	_key_db = _ease(_key_db, DUCK_DB if key_on else 0.0, 0.03 if key_on else 0.35, delta)
	if _bed_amp != null:
		_bed_amp.volume_db = _key_db
	var music_target := (MENU_DB if _menu else 0.0) + (SETTLE_DB if _settled else 0.0) + (DUCK_MUSIC_DB if key_on else 0.0)
	_music_db = _ease(_music_db, music_target, 0.05 if music_target < _music_db else 0.4, delta)
	if _music_amp != null:
		_music_amp.volume_db = _music_db
	# layers: linear fades, so a rush hour swells in on the beat rather than snapping on
	var sync := _music_cur.stream as AudioStreamSynchronized if _music_cur != null else null
	for i in LAYERS.size():
		var l: String = LAYERS[i]
		var lv: float = _layer_level[l]
		lv = move_toward(lv, 1.0 if _layer_on[l] else 0.0, delta / (LAYER_IN if _layer_on[l] else LAYER_OUT))
		_layer_level[l] = lv
		if sync != null and sync.stream_count > i + 1:
			sync.set_sync_stream_volume(i + 1, linear_to_db(maxf(lv, 0.0001)) + float(LAYER_DB[l]) if lv > 0.0 else -80.0)
	# speed and filter: 深度思考 slows and muffles the music, the last seconds speed it up
	_pitch = _ease(_pitch, _tempo * (0.94 if _slow else 1.0), 0.25, delta)
	if _music_cur != null:
		_music_cur.pitch_scale = _pitch
	if _music_lp != null:
		_cutoff = exp(_ease(log(_cutoff), log(SLOW_CUTOFF if _slow else 20000.0), 0.12 if _slow else 0.3, delta))
		_music_lp.cutoff_hz = _cutoff
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), _lp_index, _cutoff < 18000.0)


## Exponential approach of `value` to `target`, `tau` seconds to get ~63% of the way.
static func _ease(value: float, target: float, tau: float, delta: float) -> float:
	return lerpf(value, target, 1.0 - exp(-delta / maxf(tau, 0.001)))


## Music a little quieter while a menu (pause, settings) is open.
func duck(on: bool) -> void:
	_menu = on


## The shift is over: the layers and the speed-up stop, the music steps back under the result
## card. The next music() with another track brings it back up.
func settle() -> void:
	_settled = true
	for l in LAYERS:
		_layer_on[l] = false
	_tempo = 1.0
	_slow = false


## Turns a music layer ("peak", "final") of the current track on or off; cheap, call it every frame.
func music_layer(layer: String, on: bool) -> void:
	if not _settled:
		_layer_on[layer] = on


## The music's speed (1 = normal): the last seconds of a shift run it a touch faster.
func music_tempo(scale: float) -> void:
	if not _settled:
		_tempo = scale


## Time is slowed (深度思考): the music sinks and muffles.
func slowmo(on: bool) -> void:
	_slow = on and not _settled


## `pitch`: 1 = as recorded (the checkout's stamps climb a scale with it).
func sfx(sound: String, volume_db := 0.0, pitch_variance := 0.08, pitch := 1.0) -> void:
	var variants: Array = _sfx.get(sound, [])
	if variants.is_empty():
		return
	var pick := randi() % variants.size()
	if variants.size() > 1 and pick == int(_last_variant.get(sound, -1)):
		pick = (pick + 1) % variants.size()
	_last_variant[sound] = pick
	var stream: AudioStream = variants[pick]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -10.0)) < float(THROTTLE.get(sound, 0.0)):
		return
	var p: AudioStreamPlayer
	if sound in MOUTH:
		var fish: AudioStreamPlayer = _vo_player.get("fish")
		if now < _mouth_free or (fish != null and fish.playing):
			return
		p = _mouth
		_mouth_free = now + stream.get_length() + MOUTH_GAP
	elif sound in KEY:
		p = _key_pool[_next_key]
		_next_key = (_next_key + 1) % _key_pool.size()
		_key_until = maxf(_key_until, now + minf(stream.get_length(), 2.5))
	else:
		p = _pool[_next]
		_next = (_next + 1) % POOL_SIZE
	_last_played[sound] = now
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_variance, pitch_variance))
	p.play()


## Crossfades to a looping music track (file name in assets/audio/music); "" fades out.
## A track with layer files plays as one synchronized stream: the track, then each layer, silent.
func music(track: String, fade := 1.2, volume_db := -6.0, loop := true) -> void:
	if track == _music_name:
		return
	_music_name = track
	_settled = false
	_tempo = 1.0
	_slow = false
	for l in LAYERS:
		_layer_on[l] = false
		_layer_level[l] = 0.0
	var old := _music_a if _music_a.playing else _music_b
	var new := _music_b if old == _music_a else _music_a
	if old != null:
		old.pitch_scale = 1.0
	_music_cur = null
	var path := "res://assets/audio/music/%s.ogg" % track
	if track != "" and ResourceLoader.exists(path):   # missing tracks (not generated yet) are silent
		var stream: AudioStream = _loop(load(path), loop)
		var layers: Array = []
		for l in LAYERS:
			var lp := "res://assets/audio/music/%s_%s.ogg" % [track, l]
			if ResourceLoader.exists(lp) and not OS.has_feature("web"):   # web plays samples: no synced streams
				layers.append(_loop(load(lp), loop))
		if layers.size() == LAYERS.size():
			var sync := AudioStreamSynchronized.new()
			sync.stream_count = 1 + layers.size()
			sync.set_sync_stream(0, stream)
			sync.set_sync_stream_volume(0, 0.0)
			for i in layers.size():
				sync.set_sync_stream(i + 1, layers[i])
				sync.set_sync_stream_volume(i + 1, -80.0)
			stream = sync
		new.stream = stream
		new.volume_db = -40.0
		new.pitch_scale = 1.0
		new.play()
		_music_cur = new
		create_tween().tween_property(new, "volume_db", volume_db, fade)
	if old.playing:
		var t := create_tween()
		t.tween_property(old, "volume_db", -40.0, fade)
		t.tween_callback(old.stop)


static func _loop(stream: AudioStream, loop: bool) -> AudioStream:
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
	return stream


func ambience(loop_name: String, volume_db := -14.0) -> void:
	var path := "res://assets/audio/loops/%s.ogg" % loop_name
	if loop_name == "" or not ResourceLoader.exists(path):
		_amb.stop()
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_amb.stream = stream
	_amb.volume_db = volume_db
	_amb.play()


## Plays a voice line (res:// path to an .ogg); "" stops the current line.
func voice(path: String, volume_db := 2.0) -> void:
	_voice.stop()
	if path == "" or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.play()


func voice_playing() -> bool:
	return _voice.playing


## A character noise: "fish_savor", "auntie_care" ... A random variant, the pitch a little off.
## One line at a time across all characters. Ordinary eating reactions never interrupt a line,
## and share a 4s start cooldown plus a 0.65s breathing gap after her voice ends. Other cues keep
## the existing priority rule: equal/higher may interrupt, 0 never interrupts. Priority 3+
## explicitly marks an important event (including the receipt's fish_savor), bypassing the CD.
## `chance` remains the caller's probability; skipped requests are discarded, never queued.
func vo(cue: String, priority := 1, chance := 1.0, volume_db := 0.0) -> void:
	var variants: Array = _vo.get(cue, [])
	if variants.is_empty() or chance <= 0.0 or randf() > chance:
		return
	var normal := cue in FISH_NORMAL_CUES and priority < 3
	var now := Time.get_ticks_msec() / 1000.0
	if normal and (now < _fish_last_normal + FISH_VOICE_COOLDOWN or now < _fish_quiet_until):
		return
	for r in _vo_player:
		var other: AudioStreamPlayer = _vo_player[r]
		if other.playing and (normal or priority == 0 or int(_vo_prio.get(r, 0)) > priority):
			return
	for r in _vo_player:
		if r == "fish" and _vo_player[r].playing:
			_fish_quiet_until = maxf(_fish_quiet_until, now + FISH_VOICE_GAP)
		_vo_player[r].stop()
	var role := cue.get_slice("_", 0)
	if role == "fish":
		_mouth.stop()   # she can't chomp and talk at once
	if not _vo_player.has(role):
		var p := AudioStreamPlayer.new()
		p.bus = "Voice"
		add_child(p)
		p.finished.connect(_vo_finished.bind(role))
		_vo_player[role] = p
	var player: AudioStreamPlayer = _vo_player[role]
	var pick := randi() % variants.size()
	if variants.size() > 1 and pick == int(_last_variant.get(cue, -1)):
		pick = (pick + 1) % variants.size()
	_last_variant[cue] = pick
	player.stream = variants[pick]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.96, 1.04)
	player.play()
	_vo_prio[role] = priority
	if normal:
		_fish_last_normal = now


func _vo_finished(role: String) -> void:
	if role == "fish":
		_fish_quiet_until = Time.get_ticks_msec() / 1000.0 + FISH_VOICE_GAP
