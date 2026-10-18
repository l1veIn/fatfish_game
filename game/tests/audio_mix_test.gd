extends Node
## Checks the mix in Audio (autoload): the buses and effects, the music layers locked to their
## track and fading in and out, stingers ducking the other sound effects, one voice line at a
## time. Prints PASS / FAIL lines and quits with the number of failures.
##   Godot --headless --path game res://tests/audio_mix_test.tscn

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _bus_peak(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))


func _max_peak(bus: String, seconds: float) -> float:
	var best := -200.0
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		best = maxf(best, _bus_peak(bus))
	return best


func _ready() -> void:
	# buses
	var bed := AudioServer.get_bus_index("SFXBed")
	_check(bed >= 0 and AudioServer.get_bus_send(bed) == &"SFX", "SFXBed bus sends into SFX")
	var master_fx := []
	for i in AudioServer.get_bus_effect_count(0):
		master_fx.append(AudioServer.get_bus_effect(0, i).get_class())
	_check("AudioEffectHardLimiter" in master_fx, "limiter on Master")

	# music layers
	for track in ["bgm_run", "bgm_trial"]:
		Audio.music(track, 0.1)
		var sync := Audio._music_cur.stream as AudioStreamSynchronized
		_check(sync != null and sync.stream_count == 3, "%s plays as track + 2 layers" % track)
		if sync != null:
			var lens := []
			for i in sync.stream_count:
				lens.append(snappedf(sync.get_sync_stream(i).get_length(), 0.001))
			_check(lens[0] == lens[1] and lens[1] == lens[2], "%s layers as long as the track %s" % [track, str(lens)])
	await _wait(0.3)
	var sync := Audio._music_cur.stream as AudioStreamSynchronized
	_check(sync.get_sync_stream_volume(1) <= -79.0 and sync.get_sync_stream_volume(2) <= -79.0, "layers start silent")
	Audio.music_layer("peak", true)
	await _wait(0.9)
	_check(sync.get_sync_stream_volume(1) > -1.5, "peak layer fades in (%.1f dB)" % sync.get_sync_stream_volume(1))
	_check(sync.get_sync_stream_volume(2) <= -79.0, "final layer stays out")
	# does the layer volume really reach the mix? the track muted, peak on vs off
	# (needs a real audio driver: with --headless nothing is mixed and this is skipped)
	sync.set_sync_stream_volume(0, -80.0)
	await _wait(0.3)
	var on := await _max_peak("Music", 0.6)
	Audio.music_layer("peak", false)
	await _wait(2.0)
	var off := await _max_peak("Music", 0.6)
	sync.set_sync_stream_volume(0, 0.0)
	if DisplayServer.get_name() == "headless":
		print("SKIP  peak layer audible (headless: no mixing)")
	else:
		_check(on > off + 20.0, "peak layer audible in the Music bus (on %.0f dB, off %.0f dB)" % [on, off])
	Audio.music_tempo(1.05)
	Audio.slowmo(true)
	await _wait(1.5)
	_check(absf(Audio._music_cur.pitch_scale - 1.05 * 0.94) < 0.01, "tempo and slow-mo set the speed (%.3f)" % Audio._music_cur.pitch_scale)
	_check(Audio._cutoff < 2000.0, "slow-mo muffles the music (%.0f Hz)" % Audio._cutoff)
	Audio.slowmo(false)
	Audio.settle()
	Audio.music_layer("final", true)
	await _wait(1.0)
	_check(Audio._layer_on["final"] == false and Audio._tempo == 1.0, "settle(): no layers, normal speed after the shift")
	_check(Audio._music_db < -5.0, "settle(): music steps back (%.1f dB)" % Audio._music_db)
	Audio.music("bgm_tree", 0.1)
	await _wait(1.5)
	_check(Audio._music_db > -1.0, "a new track brings the music back up")

	# stingers duck the bed
	Audio.sfx("catch", -4.0)
	await _wait(0.1)
	_check(absf(Audio._key_db) < 0.1, "a plain catch does not duck")
	Audio.sfx("version_up", -6.0)
	await _wait(0.25)
	_check(Audio._key_db < -3.0, "a stinger ducks the other sounds (%.1f dB)" % Audio._key_db)
	await _wait(3.5)
	_check(Audio._key_db > -0.3, "...and lets them back up (%.1f dB)" % Audio._key_db)

	# one voice at a time
	Audio.vo("auntie_rush", 2)
	Audio.vo("fish_munch", 0)
	_check(Audio._vo_player["auntie"].playing and not Audio._vo_player.has("fish"), "filler waits while 梁阿姨 talks")
	Audio.vo("fish_wait", 1)
	_check(Audio._vo_player["auntie"].playing and not Audio._vo_player.has("fish"), "a lower line does not cut her off")
	Audio.vo("fish_spit", 2)
	await _wait(0.05)
	_check(Audio._vo_player["fish"].playing and not Audio._vo_player["auntie"].playing, "an equal line cuts the other one off")

	# her mouth: chomps never overlap, and her own line cuts a chomp off
	await _wait(1.5)
	for r in Audio._vo_player:
		Audio._vo_player[r].stop()
	Audio._mouth_free = 0.0
	Audio._last_played.erase("chomp")
	Audio.sfx("chomp", -4.0)
	var first: AudioStream = Audio._mouth.stream
	await _wait(0.2)
	Audio.sfx("chomp", -4.0)
	_check(Audio._mouth.stream == first and Audio._mouth_free > Time.get_ticks_msec() / 1000.0, "a chomp waits for the last one to finish")
	Audio.vo("fish_savor", 1)
	await _wait(0.05)
	_check(not Audio._mouth.playing, "her voice line cuts the chomp off")
	await _wait(0.6)
	Audio.sfx("chomp", -4.0)
	_check(Audio._vo_player["fish"].playing == false or not Audio._mouth.playing, "no chomp while she speaks")

	print("audio_mix_test: %d failed" % _fails)
	Audio.music("", 0.05)
	for r in Audio._vo_player:
		Audio._vo_player[r].stop()
	await _wait(0.3)
	get_tree().quit(_fails)
