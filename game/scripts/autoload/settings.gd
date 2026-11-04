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
signal focus_changed(focused: bool)

const PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX", "Voice"]
const LANGUAGES := {"zh_CN": "简体中文", "en": "English"}
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const BINDABLE_ACTIONS := {"move_left": "向左移动", "move_right": "向右移动", "move_up": "向上移动", "move_down": "向下移动", "deliver": "拿起 / 送出饭盒", "think": "思考", "start_shift": "开始下一顿", "refund": "退还技能等级"}

var volume := {"Master": 0.8, "Music": 0.7, "SFX": 0.8, "Voice": 0.9}
var fullscreen := false
var vsync := true
var language := ""
var pause_unfocused := true
var mute_unfocused := false
var reduced_motion := false
var screen_shake := true
var hit_pause := true
var window_size := Vector2i(1280, 720)

const TOUCH_BASE := {"joystick": Vector2(184, 184), "interact": Vector2(236, 176), "think": Vector2(150, 128)}
const TOUCH_DEFAULT := {
	"joystick": {"x": 148.0 / 1920, "y": 976.0 / 1080, "scale": 1.0},
	"interact": {"x": 1766.0 / 1920, "y": 976.0 / 1080, "scale": 1.0},
	"think": {"x": 148.0 / 1920, "y": 770.0 / 1080, "scale": 1.0}}
var touch_layout: Dictionary = TOUCH_DEFAULT.duplicate(true)
var touch_arm_distance := 200.0

var _focused := true
var _testing := false      # test profiles / autotest / --lang never write player settings
var _applied_window_size := Vector2i.ZERO
var _was_fullscreen := false
var _config_path := PATH
var _bindings: Dictionary = {}
var _default_events: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			var i := AudioServer.bus_count
			# Godot Web 4.7.2 add_bus(-1) reorders sample buses and disconnects Master.
			# Growing the count appends without that path (godotengine/godot#119026).
			AudioServer.bus_count = i + 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	_load_translations()
	_add_actions()
	var forced_language := ""
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/") and arg.ends_with(".tscn"):
			_testing = true
	for a in OS.get_cmdline_user_args():
		if a == "--autotest" or a.begins_with("--test-profile="):
			_testing = true
			if a.begins_with("--test-profile="):
				var profile := a.trim_prefix("--test-profile=")
				var valid := not profile.is_empty() and profile.length() <= 48
				for ch in profile:
					if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(ch): valid = false
				_config_path = "user://qa_%s_settings.cfg" % (profile if valid else "invalid_profile")
		elif a.begins_with("--lang="):
			forced_language = a.get_slice("=", 1)
			_testing = true
	load_settings()
	if not forced_language.is_empty(): language = forced_language
	if OS.has_feature("web"):
		fullscreen = false   # the browser decides; the toggle still works on a click
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if (not _testing or _config_path != PATH) and cfg.load(_config_path) == OK:
		_read_config(cfg)
	if not LANGUAGES.has(language):
		language = "zh_CN" if OS.get_locale_language() == "zh" else "en"


func _read_config(cfg: ConfigFile) -> void:
	for k in volume:
		volume[k] = clampf(float(cfg.get_value("audio", k, volume[k])), 0.0, 1.0)
	mute_unfocused = bool(cfg.get_value("audio", "mute_unfocused", mute_unfocused))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	var saved_size = cfg.get_value("display", "window_size", window_size)
	if saved_size is Vector2i and saved_size in WINDOW_SIZES:
		window_size = saved_size
	language = str(cfg.get_value("game", "language", ""))
	pause_unfocused = bool(cfg.get_value("game", "pause_unfocused", pause_unfocused))
	reduced_motion = bool(cfg.get_value("accessibility", "reduced_motion", reduced_motion))
	screen_shake = bool(cfg.get_value("accessibility", "screen_shake", screen_shake))
	hit_pause = bool(cfg.get_value("accessibility", "hit_pause", hit_pause))
	_read_bindings(cfg.get_value("controls", "bindings", {}))
	touch_layout = sanitize_touch_layout(cfg.get_value("controls", "touch_layout", {}))
	# Move the old untouched default only; user-positioned/resized controls stay put.
	if int(cfg.get_value("controls", "touch_layout_version", 1)) < 2:
		var previous: Dictionary = touch_layout.think
		if is_equal_approx(previous.x, 1549.0 / 1920) and is_equal_approx(previous.y, 1000.0 / 1080) and is_equal_approx(previous.scale, 1.0):
			touch_layout.think = TOUCH_DEFAULT.think.duplicate(true)
	touch_arm_distance = sanitize_arm_distance(cfg.get_value("controls", "touch_arm_distance", 200.0))


func save_settings() -> void:
	if _testing and _config_path == PATH:
		return
	_create_config().save(_config_path)


func _create_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	for k in volume:
		cfg.set_value("audio", k, volume[k])
	cfg.set_value("audio", "mute_unfocused", mute_unfocused)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "window_size", window_size)
	cfg.set_value("game", "language", language)
	cfg.set_value("game", "pause_unfocused", pause_unfocused)
	cfg.set_value("accessibility", "reduced_motion", reduced_motion)
	cfg.set_value("accessibility", "screen_shake", screen_shake)
	cfg.set_value("accessibility", "hit_pause", hit_pause)
	cfg.set_value("controls", "bindings", _bindings.duplicate(true))
	cfg.set_value("controls", "touch_layout", touch_layout.duplicate(true))
	cfg.set_value("controls", "touch_layout_version", 2)
	cfg.set_value("controls", "touch_arm_distance", touch_arm_distance)
	return cfg


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
		if not fullscreen and (_applied_window_size != window_size or _was_fullscreen):
			_apply_window_size()
		_was_fullscreen = fullscreen
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	TranslationServer.set_locale(language)
	save_settings()
	changed.emit()


func _apply_window_size() -> void:
	# Work in the current monitor's usable rectangle (including its desktop offset).
	# Leave room for the OS title bar and borders; large choices scale down to fit.
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var rect := safe_window_rect(window_size, usable)
	DisplayServer.window_set_size(rect.size)
	DisplayServer.window_set_position(rect.position)
	_applied_window_size = window_size


func safe_window_rect(requested: Vector2i, usable: Rect2i) -> Rect2i:
	var available := Vector2i(maxi(1, usable.size.x - 32), maxi(1, usable.size.y - 72))
	var ratio := minf(1.0, minf(float(available.x) / requested.x, float(available.y) / requested.y))
	var fitted := Vector2i(Vector2(requested) * ratio)
	return Rect2i(usable.position + (usable.size - fitted) / 2, fitted)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	if OS.has_feature("web"):
		var handled = JavaScriptBridge.eval("window.FatFishToy && window.FatFishToy.setFullscreen(%s)" % ("true" if fullscreen else "false"))
		if not handled:
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
		_set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_focused(true)


func _set_focused(focused: bool) -> void:
	_focused = focused
	if not focused:
		# OS popups can consume key-up events; do not resume stale gameplay input.
		release_gameplay_inputs()
	_apply_focus_mute()
	focus_changed.emit(focused)


func release_gameplay_inputs() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "think", "deliver", "start_shift", "refund", "pause", "ui_accept", "ui_cancel"]:
		if InputMap.has_action(action):
			Input.action_release(action)


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
		"toggle_fullscreen": [KEY_F11], "start_shift": [KEY_G], "refund": [KEY_BACKSPACE],
	}
	var pads := {
		"deliver": [JOY_BUTTON_A], "think": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
		"pause": [JOY_BUTTON_START], "start_shift": [JOY_BUTTON_Y], "refund": [JOY_BUTTON_X],
		"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B],
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
			e.device = -1
			e.button_index = b
			if not InputMap.action_has_event(a, e):
				InputMap.action_add_event(a, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.device = -1
		e.axis = axes[a][0]
		e.axis_value = axes[a][1]
		InputMap.action_add_event(a, e)
	# the right trigger also thinks
	var rt := InputEventJoypadMotion.new()
	rt.device = -1
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("think", rt)
	for action in BINDABLE_ACTIONS:
		_default_events[action] = InputMap.action_get_events(action).duplicate()


## Gameplay bindings only; built-in menu navigation/confirm/cancel remain independent.
func binding_label(action: String, device := "keyboard") -> String:
	var names: Array[String] = []
	if not InputMap.has_action(action): return ""
	for event in InputMap.action_get_events(action):
		if _event_device(event) != device: continue
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			names.append(OS.get_keycode_string(code))
		elif event is InputEventJoypadButton:
			var labels := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓", JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →"}
			names.append(labels.get(event.button_index, tr("按钮 %d") % event.button_index))
		elif event is InputEventJoypadMotion:
			if event.axis == JOY_AXIS_TRIGGER_LEFT: names.append("LT")
			elif event.axis == JOY_AXIS_TRIGGER_RIGHT: names.append("RT")
			else:
				var stick := "LS" if event.axis <= JOY_AXIS_LEFT_Y else "RS"
				var horizontal: bool = event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]
				names.append(stick + " " + (("←" if event.axis_value < 0 else "→") if horizontal else ("↑" if event.axis_value < 0 else "↓")))
	return " / ".join(names)


func _event_device(event: InputEvent) -> String:
	if event is InputEventKey: return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion: return "gamepad"
	return ""


func _binding_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# A modifier alone is useful (the default Think uses Shift); chords are not.
		if (event.alt_pressed and code != KEY_ALT) or (event.ctrl_pressed and code != KEY_CTRL) or (event.meta_pressed and code != KEY_META): return {}
		if event.shift_pressed and code != KEY_SHIFT: return {}
		return {"kind": "key", "code": code}
	if event is InputEventJoypadButton:
		return {"kind": "button", "code": event.button_index}
	if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65:
		return {"kind": "axis", "code": event.axis, "sign": -1 if event.axis_value < 0 else 1}
	return {}


func _binding_event(data: Dictionary) -> InputEvent:
	if typeof(data.get("code")) != TYPE_INT: return null
	var code: int = data.code
	match data.get("kind", ""):
		"key":
			if code <= 0 or OS.find_keycode_from_string(OS.get_keycode_string(code)) != code: return null
			var event := InputEventKey.new()
			event.physical_keycode = code
			return event
		"button":
			if code < 0 or code >= JOY_BUTTON_MAX: return null
			var event := InputEventJoypadButton.new()
			event.device = -1
			event.button_index = code
			return event
		"axis":
			if code < 0 or code > JOY_AXIS_TRIGGER_RIGHT or data.get("sign", 0) not in [-1, 1]: return null
			if code >= JOY_AXIS_TRIGGER_LEFT and int(data.sign) < 0: return null
			var event := InputEventJoypadMotion.new()
			event.device = -1
			event.axis = code
			event.axis_value = int(data.sign)
			return event
	return null


func _reserved_binding(data: Dictionary) -> bool:
	# Fixed pause/fullscreen and tutorial escape controls must never become gameplay keys.
	return (data.get("kind") == "key" and data.code in [KEY_ESCAPE, KEY_P, KEY_F11, KEY_T]) or (data.get("kind") == "button" and data.code in [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE])


func binding_error(action: String, device: String, event: InputEvent) -> String:
	if not BINDABLE_ACTIONS.has(action) or device not in ["keyboard", "gamepad"]: return tr("无法修改这个操作。")
	if _event_device(event) != device: return tr("请使用所选设备，按一个按键或推动摇杆。")
	var data := _binding_data(event)
	if data.is_empty() or _binding_event(data) == null: return tr("请选择单个按键、手柄按钮或摇杆方向，不使用组合键。")
	if _reserved_binding(data): return tr("这个按键保留给暂停、全屏或教学，不能重新分配。")
	if data.get("kind") == "axis" and action not in ["move_left", "move_right", "move_up", "move_down", "think"]:
		return tr("摇杆和扳机仅用于移动或思考；这个操作请使用按键或手柄按钮。")
	if action in ["start_shift", "refund"] and ((data.get("kind") == "key" and data.code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]) or (data.get("kind") == "button" and data.code in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN])):
		return tr("这个输入用于固定菜单导航、确认或返回，不能分配给开饭或退款。")
	for other in BINDABLE_ACTIONS:
		if other == action: continue
		for bound in InputMap.action_get_events(other):
			if _event_device(bound) == device and _binding_data(bound) == data:
				return tr("冲突：这个输入已用于「%s」。请换一个。") % tr(BINDABLE_ACTIONS[other])
	return ""


func set_binding(action: String, device: String, event: InputEvent) -> String:
	var error := binding_error(action, device, event)
	if not error.is_empty(): return error
	if not _bindings.has(action): _bindings[action] = {}
	_bindings[action][device] = _binding_data(event)
	release_gameplay_inputs()
	_apply_bindings()
	save_settings()
	changed.emit()
	return ""


func reset_bindings() -> void:
	_bindings.clear()
	release_gameplay_inputs()
	_apply_bindings()
	save_settings()
	changed.emit()


func _apply_bindings() -> void:
	for action in BINDABLE_ACTIONS:
		InputMap.action_erase_events(action)
		for event in _default_events.get(action, []):
			if not _bindings.get(action, {}).has(_event_device(event)):
				InputMap.action_add_event(action, event)
		for device in _bindings.get(action, {}):
			var event := _binding_event(_bindings[action][device])
			if event != null: InputMap.action_add_event(action, event)


func _read_bindings(saved: Variant) -> void:
	_bindings.clear()
	_apply_bindings()
	if not saved is Dictionary: return
	# First validate the complete candidate, so legitimate swaps survive a reload.
	for action in BINDABLE_ACTIONS:
		var entry = saved.get(action, {})
		if not entry is Dictionary: continue
		for device in ["keyboard", "gamepad"]:
			var data = entry.get(device, {})
			if not data is Dictionary: continue
			var event := _binding_event(data)
			if event != null and _event_device(event) == device and not _reserved_binding(data):
				if not _bindings.has(action): _bindings[action] = {}
				_bindings[action][device] = _binding_data(event)
	_apply_bindings()
	# Corrupt/conflicting profiles fall back as a whole; no action is left unbound.
	for action in _bindings:
		for device in _bindings[action]:
			var event := _binding_event(_bindings[action][device])
			if not binding_error(action, device, event).is_empty():
				_bindings.clear()
				_apply_bindings()
				return


func sanitize_touch_layout(raw: Variant) -> Dictionary:
	var result: Dictionary = TOUCH_DEFAULT.duplicate(true)
	if not raw is Dictionary:
		return result
	for id in TOUCH_BASE:
		if not raw.get(id) is Dictionary:
			continue
		for key in ["x", "y", "scale"]:
			var value = raw[id].get(key)
			if (value is float or value is int) and is_finite(float(value)):
				result[id][key] = clampf(float(value), 0.65 if key == "scale" else 0.0, 1.6 if key == "scale" else 1.0)
		var half: Vector2 = TOUCH_BASE[id] * result[id].scale * 0.5
		var center := Vector2(result[id].x * 1920, result[id].y * 1080).clamp(half + Vector2(16, 16), Vector2(1904, 1064) - half)
		result[id].x = center.x / 1920.0
		result[id].y = center.y / 1080.0
	return result


func sanitize_arm_distance(raw: Variant) -> float:
	if (raw is float or raw is int) and is_finite(float(raw)):
		return clampf(float(raw), 80.0, 360.0)
	return 200.0


func touch_rect(id: String, layout: Dictionary = {}) -> Rect2:
	var spec: Dictionary = (touch_layout if layout.is_empty() else layout)[id]
	var dimensions: Vector2 = TOUCH_BASE[id] * spec.scale
	return ScreenLayout.touch_rect(Rect2(Vector2(spec.x * 1920, spec.y * 1080) - dimensions * 0.5, dimensions))
