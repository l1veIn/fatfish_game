extends Node
## Player settings, kept apart from the save (user://settings.cfg), applied at startup and
## whenever they change:
##   volumes      Master / Music / SFX / Voice audio buses (created here), 0..1
##   fullscreen   borderless fullscreen or a window (F11 / Alt+Enter toggle it anywhere)
##   vsync
##   language     "zh_CN" or "en" (translations: res://data/i18n/<locale>.json, Chinese is the
##                source text, so zh_CN needs no file); the first start follows the OS language
##   pause_unfocused  a shift pauses when the window loses focus
##   mute_unfocused   all sound is muted while the window is in the background
## Input actions for keyboard and gamepad are also registered here (see _add_actions).

signal changed

const PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX", "Voice"]
const LANGUAGES := {"zh_CN": "简体中文", "en": "English"}

var volume := {"Master": 0.8, "Music": 0.7, "SFX": 0.8, "Voice": 0.9}
var fullscreen := false
var vsync := true
var language := ""
var pause_unfocused := true
var mute_unfocused := false

var _focused := true
var _testing := false      # autotest / --lang: never write the player's settings file


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	_load_translations()
	_add_actions()
	load_settings()
	for a in OS.get_cmdline_user_args():
		if a == "--autotest":
			_testing = true
		elif a.begins_with("--lang="):
			language = a.get_slice("=", 1)
			_testing = true
	if OS.has_feature("web"):
		fullscreen = false   # the browser decides; the toggle still works on a click
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in volume:
			volume[k] = clampf(float(cfg.get_value("audio", k, volume[k])), 0.0, 1.0)
		mute_unfocused = bool(cfg.get_value("audio", "mute_unfocused", mute_unfocused))
		fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
		vsync = bool(cfg.get_value("display", "vsync", vsync))
		language = str(cfg.get_value("game", "language", ""))
		pause_unfocused = bool(cfg.get_value("game", "pause_unfocused", pause_unfocused))
	if not LANGUAGES.has(language):
		language = "zh_CN" if OS.get_locale_language() == "zh" else "en"


func save_settings() -> void:
	if _testing:
		return
	var cfg := ConfigFile.new()
	for k in volume:
		cfg.set_value("audio", k, volume[k])
	cfg.set_value("audio", "mute_unfocused", mute_unfocused)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("game", "language", language)
	cfg.set_value("game", "pause_unfocused", pause_unfocused)
	cfg.save(PATH)


## Applies everything and saves; call after changing any field.
func apply() -> void:
	for k in volume:
		var i := AudioServer.get_bus_index(k)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume[k], 0.0001)))
			AudioServer.set_bus_mute(i, volume[k] <= 0.001)
	_apply_focus_mute()
	if not OS.has_feature("web") and not DisplayServer.get_name() == "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	TranslationServer.set_locale(language)
	save_settings()
	changed.emit()


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	apply()


func is_english() -> bool:
	return language == "en"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_apply_focus_mute()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_apply_focus_mute()


func _apply_focus_mute() -> void:
	AudioServer.set_bus_mute(0, (mute_unfocused and not _focused) or volume["Master"] <= 0.001)


## Chinese is the source language: every tr() key is the Chinese text. Other languages are
## flat JSON dictionaries {chinese: translation} in res://data/i18n/.
func _load_translations() -> void:
	for loc in LANGUAGES:
		var path := "res://data/i18n/%s.json" % loc
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			push_warning("bad translation file " + path)
			continue
		var t := Translation.new()
		t.locale = loc
		for k in data:
			if not str(k).begins_with("_") and str(data[k]) != "":
				t.add_message(k, data[k])
		TranslationServer.add_translation(t)


## Keyboard and gamepad controls, so the game is playable without a mouse (Steam Deck).
func _add_actions() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"deliver": [KEY_E, KEY_ENTER], "think": [KEY_SPACE, KEY_SHIFT], "pause": [KEY_ESCAPE, KEY_P],
		"toggle_fullscreen": [KEY_F11], "start_shift": [KEY_G],
	}
	var pads := {
		"deliver": [JOY_BUTTON_A], "think": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
		"pause": [JOY_BUTTON_START], "start_shift": [JOY_BUTTON_Y],
	}
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.25)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
	var alt := InputEventKey.new()
	alt.physical_keycode = KEY_ENTER
	alt.alt_pressed = true
	InputMap.action_add_event("toggle_fullscreen", alt)
	for a in pads:
		for b in pads[a]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(a, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = axes[a][0]
		e.axis_value = axes[a][1]
		InputMap.action_add_event(a, e)
	# the right trigger also thinks
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("think", rt)
