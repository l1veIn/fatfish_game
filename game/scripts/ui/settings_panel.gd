class_name SettingsPanel
extends Control
## The settings overlay (title, skill tree and pause menu all open this one): sound volumes,
## fullscreen / vsync, language, pause-when-unfocused, and resetting the save (two clicks).
## Changes apply at once (Settings.apply). Esc / B / 返回 closes it; `closed` is emitted.

signal closed

var _reset_armed := 0.0
var _reset_btn: Button
var _first: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.7)
	dim.size = Vector2(1920, 1080)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(510, 70)
	panel.size = Vector2(900, 940)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := UiKit.label(tr("设置"), 52, UiKit.GOLD, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_section(col, tr("声音"))
	var grid := _grid(col)
	_first = _slider(grid, tr("总音量"), "Master")
	_slider(grid, tr("音乐"), "Music")
	_slider(grid, tr("音效"), "SFX")
	_slider(grid, tr("配音"), "Voice")
	_toggle(col, tr("切到后台时静音"), Settings.mute_unfocused, func(on): Settings.mute_unfocused = on)

	_section(col, tr("画面"))
	_toggle(col, tr("全屏（F11）"), Settings.fullscreen, func(on):
		if on != Settings.fullscreen:
			Settings.toggle_fullscreen())
	if not OS.has_feature("web"):
		_toggle(col, tr("垂直同步"), Settings.vsync, func(on): Settings.vsync = on)

	_section(col, tr("游戏"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lang_label := UiKit.label(tr("语言 / Language"), 28)
	lang_label.custom_minimum_size.x = 300
	row.add_child(lang_label)
	var lang := OptionButton.new()
	lang.add_theme_font_size_override("font_size", 28)
	lang.custom_minimum_size = Vector2(300, 60)
	var i := 0
	for code in Settings.LANGUAGES:
		lang.add_item(Settings.LANGUAGES[code])
		if code == Settings.language:
			lang.select(i)
		i += 1
	lang.item_selected.connect(func(idx):
		Settings.language = Settings.LANGUAGES.keys()[idx]
		Settings.apply()
		_build.call_deferred())
	row.add_child(lang)
	col.add_child(row)
	_toggle(col, tr("切到后台时暂停上班"), Settings.pause_unfocused, func(on): Settings.pause_unfocused = on)

	_section(col, tr("存档"))
	_reset_btn = UiKit.button(tr("清除存档，从头开始"), 26, Vector2(420, 64))
	_reset_btn.pressed.connect(_on_reset)
	col.add_child(_reset_btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var back := UiKit.button(tr("返回"), 34, Vector2(280, 76))
	back.set_meta("ui_back", true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	col.add_child(back)
	if is_instance_valid(_first):
		_first.grab_focus.call_deferred()


func _section(col: VBoxContainer, text: String) -> void:
	var l := UiKit.label(text, 30, UiKit.GOLD)
	col.add_child(l)


func _grid(col: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 6)
	col.add_child(g)
	return g


func _slider(grid: GridContainer, text: String, bus: String) -> HSlider:
	var l := UiKit.label(text, 28)
	l.custom_minimum_size.x = 160
	grid.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = round(Settings.volume[bus] * 100.0)
	s.custom_minimum_size = Vector2(480, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(s)
	var pct := UiKit.label("%d%%" % int(s.value), 26)
	pct.custom_minimum_size.x = 90
	grid.add_child(pct)
	s.value_changed.connect(func(v):
		Settings.volume[bus] = v / 100.0
		pct.text = "%d%%" % int(v)
		Settings.apply())
	s.drag_ended.connect(func(_c):
		if bus == "SFX" or bus == "Master":
			Audio.sfx("token")
		elif bus == "Voice":
			Audio.vo("fish_happy", 2))
	return s


func _toggle(col: VBoxContainer, text: String, on: bool, set_fn: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 28)
	c.toggled.connect(func(v):
		set_fn.call(v)
		Settings.apply())
	col.add_child(c)


func _on_reset() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = 4.0
		_reset_btn.text = tr("真的吗？所有进度都会消失。再点一次确认")
		return
	_reset_armed = 0.0
	Game.reset_save()
	_reset_btn.text = tr("存档已清除")
	_reset_btn.disabled = true


func _process(delta: float) -> void:
	if _reset_armed > 0.0:
		_reset_armed -= delta
		if _reset_armed <= 0.0 and is_instance_valid(_reset_btn) and not _reset_btn.disabled:
			_reset_btn.text = tr("清除存档，从头开始")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()
