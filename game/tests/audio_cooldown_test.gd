extends Node
## Real-time voice scheduling with the shipped OGG streams. Headless checks playback state,
## not physical speakers or the player's subjective listening fatigue. Never writes player data.
var _failures: Array[String] = []
var _checks := 0
var _events: Array = []
var _out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().has("--test-profile=audio_cooldown") or not Game.save_path.begins_with("user://qa_audio_cooldown") or not Settings._testing:
		push_error("Use --test-profile=audio_cooldown; refusing player-save access")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	var player_before := FileAccess.get_file_as_bytes("user://save.json")
	var voice_bus := AudioServer.get_bus_index("Voice")
	var master_muted := AudioServer.is_bus_mute(0)
	var voice_muted := AudioServer.is_bus_mute(voice_bus)
	seed(71829)
	_check(Audio.FISH_VOICE_COOLDOWN == 4.0 and Audio.FISH_VOICE_GAP == 0.65, "authored ordinary cadence is 4.0s plus 0.65s end gap")
	_check(Audio.process_mode == Node.PROCESS_MODE_ALWAYS, "audio clock and playback continue through menus")
	await _test_flood()
	await _test_priority()
	await _test_end_gap()
	await _test_pause_and_mute(voice_bus)
	Engine.time_scale = 1.0
	get_tree().paused = false
	AudioServer.set_bus_mute(0, master_muted)
	AudioServer.set_bus_mute(voice_bus, voice_muted)
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before, "player settings bytes unchanged")
	_check(FileAccess.get_file_as_bytes("user://save.json") == player_before, "player save bytes unchanged")
	var streams := {}
	for cue in Audio._vo:
		if str(cue).begins_with("fish_"):
			for stream in Audio._vo[cue]:
				streams[stream.resource_path] = {"seconds": stream.get_length(), "sha256": FileAccess.get_sha256(stream.resource_path)}
	var report := {"checks": _checks, "failures": _failures, "events": _events, "driver": AudioServer.get_driver_name(), "mix_rate": AudioServer.get_mix_rate(), "renderer": DisplayServer.get_name(), "scope": "Real-time scheduling with shipped OGG streams; no speaker capture or listening review", "source_sha256": {}, "voice_streams": streams}
	for path in ["scripts/autoload/audio.gd", "tests/audio_cooldown_test.gd"]:
		report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("AUDIO_COOLDOWN_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures, "events": _events, "driver": report.driver}))
	Audio._exit_tree()
	await _wait(0.15)
	UiKit.clear_cache()
	get_tree().quit(_failures.size())


func _test_flood() -> void:
	_reset()
	Engine.time_scale = 4.0
	var started: Array[float] = []
	var requests := 0
	var until := _now() + 8.35
	while _now() < until:
		var before: float = Audio._fish_last_normal
		var cue: String = Audio.FISH_NORMAL_CUES[requests % Audio.FISH_NORMAL_CUES.size()]
		Audio.vo(cue, 1, 1.0)
		if Audio._fish_last_normal != before:
			started.append(Audio._fish_last_normal)
			_events.append({"scenario": "4x_flood", "cue": cue, "at": Audio._fish_last_normal})
		requests += 1
		await _wait(0.035)
	_check(requests > 150 and started.size() >= 2 and started.size() <= 3, "high-frequency mixed ordinary cues produce only 2–3 lines in 8.35 real seconds")
	for i in range(1, started.size()):
		_check(started[i] - started[i - 1] >= 3.99, "different ordinary cues share the same real-time cooldown at 4x speed")
	Engine.time_scale = 1.0


func _test_priority() -> void:
	_reset()
	Audio.vo("fish_munch", 0)
	_check(_playing("fish_munch"), "ordinary line actually starts when idle")
	var last_normal: float = Audio._fish_last_normal
	Audio.vo("fish_spit", 2)
	_check(_playing("fish_spit"), "spitting cuts through ordinary cooldown and playback")
	Audio._fish_last_normal = -100.0
	Audio._fish_quiet_until = 0.0
	Audio.vo("fish_bliss", 2)
	_check(_playing("fish_spit"), "equal-priority ordinary bliss cannot cut off spit even after cooldown is cleared")
	Audio.vo("fish_grok", 3)
	_check(_playing("fish_grok"), "Grokking can interrupt spit by its higher priority")
	Audio.vo("fish_spit", 2)
	_check(_playing("fish_grok"), "spit retains existing priority and cannot interrupt Grokking")
	for cue in ["fish_full", "fish_broke"]:
		Audio._fish_last_normal = _now()
		Audio.vo(cue, 3)
		_check(_playing(cue), "closing event bypasses cooldown: " + cue)
	_reset()
	Audio._fish_last_normal = last_normal
	Audio.vo("fish_savor", 3)
	_check(_playing("fish_savor") and Audio._vo_prio.fish == 3, "receipt priority-3 savor is an event, not ordinary chatter")
	for cue in ["fish_happy", "fish_not_fat"]:
		_stop_voices()
		Audio._fish_last_normal = _now()
		Audio.vo(cue, 1)
		_check(_playing(cue), "purchase/pat/preview feedback bypasses eating cooldown: " + cue)
	_reset()
	Audio.vo("auntie_start", 1)
	Audio.vo("fish_bliss", 2)
	_check(_playing("auntie_start"), "ordinary fish never cuts off Auntie's line")
	_stop_voices()
	Audio.vo("fish_munch", 1, 0.0)
	_check(not _playing("fish_munch") and Audio._fish_last_normal == -100.0, "chance-zero request is discarded without spending cooldown")
	Audio.sfx("version_up")
	_check(Audio._key_pool.any(func(p): return p.playing), "upgrade stinger still starts immediately")
	await _wait(0.05)


func _test_end_gap() -> void:
	_reset()
	Audio.vo("fish_full", 3)
	var player: AudioStreamPlayer = Audio._vo_player.fish
	var timeout := _now() + player.stream.get_length() / player.pitch_scale + 2.0
	while player.playing and _now() < timeout:
		await _wait(0.025)
	_check(not player.playing and Audio._fish_quiet_until > _now(), "real stream completion begins a quiet gap")
	var finished_at := _now()
	Audio.vo("fish_munch", 1)
	_check(not _playing("fish_munch"), "ordinary cue waits after a critical line finishes")
	await _wait(Audio.FISH_VOICE_GAP + 0.06)
	Audio.vo("fish_munch", 1)
	_check(_playing("fish_munch"), "ordinary cue resumes after the end gap")
	_events.append({"scenario": "end_gap", "silence_seconds": _now() - finished_at})


func _test_pause_and_mute(voice_bus: int) -> void:
	_reset()
	AudioServer.set_bus_mute(0, true)
	AudioServer.set_bus_mute(voice_bus, true)
	Audio.vo("fish_munch", 1)
	var started: float = Audio._fish_last_normal
	_check(_playing("fish_munch"), "muted voice keeps its playback clock")
	Audio.vo("fish_savor", 1)
	_check(Audio._fish_last_normal == started, "muting does not bypass ordinary cooldown")
	get_tree().paused = true
	Engine.time_scale = 0.2
	await _wait(Audio.FISH_VOICE_COOLDOWN + 0.08)
	_check(Audio._fish_last_normal == started, "pause/mute do not queue or replay skipped speech")
	_check(not Audio._vo_player.fish.playing, "voice finishes naturally during pause")
	_check(AudioServer.is_bus_mute(0) and AudioServer.is_bus_mute(voice_bus), "voice requests preserve Master and Voice mute")
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_mute(voice_bus, false)
	Audio.vo("fish_savor", 1)
	_check(_playing("fish_savor") and Audio._fish_last_normal - started >= 4.0, "resume uses elapsed real time, not paused/scaled game time")
	_events.append({"scenario": "paused_0.2x", "real_seconds": Audio._fish_last_normal - started})


func _playing(cue: String) -> bool:
	var role := cue.get_slice("_", 0)
	var player: AudioStreamPlayer = Audio._vo_player.get(role)
	return player != null and player.playing and player.stream != null and player.stream.resource_path.get_file().begins_with(cue + "_v")


func _reset() -> void:
	_stop_voices()
	Audio._fish_last_normal = -100.0
	Audio._fish_quiet_until = 0.0


func _stop_voices() -> void:
	for player in Audio._vo_player.values():
		player.stop()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
		push_error(label)
