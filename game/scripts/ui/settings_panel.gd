class_name SettingsPanel
extends Control
## Shared modal settings. Four pages keep controls readable on a 1280 x 720 window.
## Changes apply immediately; focus stays inside the modal and returns to its opener.

signal closed

const TABS := ["声音", "画面", "辅助", "游戏"]

var _reset_armed := 0.0
var _reset_btn: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _back: Button
var _tabs: Array[Button] = []
var _controls: Array[Control] = []
var _active_tab := 0
var _return_focus: WeakRef
var _closing := false
var _language := ""
var _fullscreen_toggle: CheckButton
var _resolution: OptionButton
var _section_title: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_return_focus = weakref(get_viewport().gui_get_focus_owner())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	_language = Settings.language
	_build()
	resized.connect(_layout)
	Settings.changed.connect(_on_settings_changed)


func _build(focus_key := "") -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_tabs.clear()
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.07, 0.10, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.97, 0.945, 0.88), Color(0.65, 0.54, 0.35), 2, 20))
	add_child(_panel)
	var page := Control.new()
	page.custom_minimum_size = Vector2(1428, 876)
	_panel.add_child(page)
	var rail := Panel.new()
	rail.position = Vector2(0, 0)
	rail.size = Vector2(300, 876)
	rail.add_theme_stylebox_override("panel", UiKit.box(Color(0.065, 0.18, 0.25), Color.TRANSPARENT, 0, 12))
	page.add_child(rail)
	var title := UiKit.label(tr("设置"), 50, Color(0.97, 0.91, 0.76))
	title.position = Vector2(30, 40)
	rail.add_child(title)
	var subtitle := UiKit.label(tr("按你的节奏，安心开饭。"), 25, Color(0.73, 0.79, 0.78))
	subtitle.position = Vector2(30, 118)
	subtitle.size = Vector2(238, 100)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rail.add_child(subtitle)
	for i in TABS.size():
		var tab := UiKit.button(tr(TABS[i]), 30, Vector2(248, 72))
		tab.position = Vector2(26, 274 + i * 94)
		tab.toggle_mode = true
		tab.set_meta("focus_key", "tab_%d" % i)
		tab.pressed.connect(func(): _show_tab(i))
		_style_button(tab)
		rail.add_child(tab)
		_tabs.append(tab)
	_section_title = UiKit.label("", 38, Color(0.11, 0.25, 0.30))
	_section_title.position = Vector2(354, 42)
	page.add_child(_section_title)
	var rule := ColorRect.new()
	rule.color = Color(0.70, 0.61, 0.43, 0.45)
	rule.position = Vector2(354, 106)
	rule.size = Vector2(1010, 2)
	page.add_child(rule)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(354, 140)
	_scroll.size = Vector2(1010, 586)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	page.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 22)
	_scroll.add_child(_content)
	var footer := _hint(tr("方向键 · Enter / A 选择 · Esc / B 返回"))
	footer.position = Vector2(354, 784)
	footer.size = Vector2(690, 70)
	page.add_child(footer)
	_back = UiKit.button(tr("返回"), 30, Vector2(260, 72))
	_back.position = Vector2(1104, 774)
	_back.set_meta("ui_back", true)
	_back.set_meta("focus_key", "back")
	_back.pressed.connect(close)
	_style_button(_back, true)
	page.add_child(_back)
	_show_tab(_active_tab, false)
	_layout()
	_restore_internal_focus.call_deferred(focus_key)


func _layout() -> void:
	if not is_instance_valid(_panel):
		return
	var area := size if size.x > 1.0 else get_viewport_rect().size
	_panel.size = Vector2(1476, 900)
	_panel.position = (area - _panel.size) * 0.5


func _style_button(button: BaseButton, primary := false) -> void:
	var bg := Color(0.09, 0.25, 0.32) if primary else Color(0.99, 0.97, 0.91)
	var ink := Color(0.97, 0.94, 0.83) if primary else Color(0.14, 0.27, 0.30)
	button.add_theme_stylebox_override("normal", UiKit.box(bg, Color(0.69, 0.59, 0.40), 1, 10, 2))
	button.add_theme_stylebox_override("hover", UiKit.box(Color(0.95, 0.87, 0.69), Color(0.69, 0.59, 0.40), 2, 10))
	button.add_theme_stylebox_override("pressed", UiKit.box(Color(0.91, 0.78, 0.5), Color(0.69, 0.59, 0.40), 2, 10))
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_focus_color", ink)
	button.add_theme_color_override("font_hover_color", Color(0.14, 0.27, 0.30))
	button.add_theme_color_override("font_pressed_color", Color(0.14, 0.27, 0.30))


func _show_tab(index: int, focus_tab := true) -> void:
	_active_tab = index
	_section_title.text = tr(TABS[index])
	_reset_armed = 0.0
	_reset_btn = null
	_fullscreen_toggle = null
	_resolution = null
	_controls.clear()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == index)
	_scroll.scroll_vertical = 0
	match index:
		0: _sound_page()
		1: _display_page()
		2: _accessibility_page()
		3: _game_page()
	_link_focus()
	if focus_tab:
		_tabs[index].grab_focus()


func _sound_page() -> void:
	_content.add_child(_hint(tr("音量即时生效，音乐、音效和配音可以分别调整。")))
	_slider(tr("总音量"), "Master")
	_slider(tr("音乐"), "Music")
	_slider(tr("音效"), "SFX")
	_slider(tr("配音"), "Voice")
	_toggle(tr("切到后台时静音"), Settings.mute_unfocused, "mute_unfocused", func(on): Settings.mute_unfocused = on)


func _display_page() -> void:
	_fullscreen_toggle = _toggle(tr("全屏（F11）"), Settings.fullscreen, "fullscreen", func(on):
		if on != Settings.fullscreen:
			Settings.toggle_fullscreen())
	if not OS.has_feature("web"):
		var row := _row(tr("窗口分辨率"))
		_resolution = _option("resolution")
		for i in Settings.WINDOW_SIZES.size():
			var resolution: Vector2i = Settings.WINDOW_SIZES[i]
			_resolution.add_item("%d × %d" % [resolution.x, resolution.y])
			if resolution == Settings.window_size:
				_resolution.select(i)
		_resolution.item_selected.connect(func(index):
			Settings.window_size = Settings.WINDOW_SIZES[index]
			Settings.apply())
		row.add_child(_resolution)
		_content.add_child(_hint(tr("窗口会居中并自动适应可用屏幕；全屏时保留所选窗口尺寸。")))
		_toggle(tr("垂直同步"), Settings.vsync, "vsync", func(on): Settings.vsync = on)
	_content.add_child(_hint(tr("设置会自动保存，下次开饭继续沿用。")))


func _accessibility_page() -> void:
	_toggle(tr("减少动态效果"), Settings.reduced_motion, "reduced_motion", func(on): Settings.reduced_motion = on)
	_content.add_child(_hint(tr("减少装饰动画和漂浮粒子，保留接菜所需的运动提示。")))
	_toggle(tr("接菜顿帧"), Settings.hit_pause, "hit_pause", func(on): Settings.hit_pause = on)
	_content.add_child(_hint(tr("合成或重要接菜时短暂停顿，关闭后保持连续动作。")))


func _game_page() -> void:
	var row := _row(tr("语言 / Language"))
	var lang := _option("language")
	for code in Settings.LANGUAGES:
		lang.add_item(Settings.LANGUAGES[code])
		if code == Settings.language:
			lang.select(lang.item_count - 1)
	lang.item_selected.connect(func(index):
		Settings.language = Settings.LANGUAGES.keys()[index]
		Settings.apply())
	row.add_child(lang)
	_toggle(tr("切到后台时暂停上班"), Settings.pause_unfocused, "pause_unfocused", func(on): Settings.pause_unfocused = on)
	var line := HSeparator.new()
	_content.add_child(line)
	_content.add_child(UiKit.label(tr("存档"), 30, Color(0.61, 0.25, 0.19)))
	_content.add_child(_hint(tr("清除后将失去全部饭票、升级和成就。此操作无法撤销。")))
	_reset_btn = UiKit.button(tr("清除存档，从头开始"), 27, Vector2(0, 66))
	_style_button(_reset_btn)
	_reset_btn.add_theme_color_override("font_color", Color(0.65, 0.22, 0.16))
	_register(_reset_btn, "reset_save")
	_reset_btn.pressed.connect(_on_reset)
	_content.add_child(_reset_btn)


func _hint(text: String) -> Label:
	var label := UiKit.label(text, 25, Color(0.36, 0.40, 0.39))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.custom_minimum_size.y = 70
	var label := UiKit.label(text, 28, Color(0.14, 0.27, 0.30))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	_content.add_child(row)
	return row


func _option(key: String) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(370, 64)
	option.add_theme_font_size_override("font_size", 28)
	_style_button(option)
	_register(option, key)
	return option


func _slider(text: String, bus: String) -> void:
	var row := _row(text)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = round(Settings.volume[bus] * 100.0)
	slider.custom_minimum_size = Vector2(400, 56)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_register(slider, "volume_" + bus)
	for style in [["slider", Color(0.79, 0.80, 0.75)], ["grabber_area", Color(0.17, 0.36, 0.42)], ["grabber_area_highlight", Color(0.21, 0.43, 0.48)]]:
		var track := UiKit.box(style[1], Color.TRANSPARENT, 0, 4)
		track.content_margin_left = 0
		track.content_margin_right = 0
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		slider.add_theme_stylebox_override(style[0], track)
	row.add_child(slider)
	var pct := UiKit.label("%d%%" % int(slider.value), 27, Color(0.14, 0.27, 0.30))
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.custom_minimum_size.x = 92
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	slider.value_changed.connect(func(value):
		Settings.volume[bus] = value / 100.0
		pct.text = "%d%%" % int(value)
		Settings.apply())
	slider.drag_ended.connect(func(_changed):
		if bus == "SFX" or bus == "Master":
			Audio.sfx("token")
		elif bus == "Voice":
			Audio.vo("fish_happy", 2))


func _toggle(text: String, on: bool, key: String, set_fn: Callable) -> CheckButton:
	# Separate long labels so translations wrap instead of widening the panel.
	var row := _row(text)
	var toggle := CheckButton.new()
	toggle.button_pressed = on
	toggle.custom_minimum_size = Vector2(112, 60)
	toggle.tooltip_text = text
	_register(toggle, key)
	toggle.toggled.connect(func(value):
		set_fn.call(value)
		Settings.apply())
	row.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			toggle.grab_focus()
			toggle.button_pressed = not toggle.button_pressed
			row.accept_event())
	row.add_child(toggle)
	return toggle


func _register(control: Control, key: String) -> void:
	control.focus_mode = Control.FOCUS_ALL
	control.set_meta("focus_key", key)
	var focus := UiKit.box(Color.TRANSPARENT, UiKit.GOLD, 3, 10)
	focus.draw_center = false
	control.add_theme_stylebox_override("focus", focus)
	_controls.append(control)


func _link_focus() -> void:
	var chain: Array[Control] = []
	for tab in _tabs:
		chain.append(tab)
	chain.append_array(_controls)
	chain.append(_back)
	for i in chain.size():
		var control := chain[i]
		control.focus_next = control.get_path_to(chain[(i + 1) % chain.size()])
		control.focus_previous = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
	for i in _tabs.size():
		var tab := _tabs[i]
		tab.focus_neighbor_left = tab.get_path_to(_tabs[(i + _tabs.size() - 1) % _tabs.size()])
		tab.focus_neighbor_right = tab.get_path_to(_tabs[(i + 1) % _tabs.size()])
		tab.focus_neighbor_top = tab.get_path_to(_tabs[posmod(i - 1, _tabs.size())])
		tab.focus_neighbor_bottom = tab.get_path_to(_controls[0] if not _controls.is_empty() else _back)
	for i in _controls.size():
		var control := _controls[i]
		control.focus_neighbor_top = control.get_path_to(_controls[i - 1] if i > 0 else _tabs[_active_tab])
		control.focus_neighbor_bottom = control.get_path_to(_controls[i + 1] if i + 1 < _controls.size() else _back)
		control.focus_neighbor_left = control.get_path_to(control)
		control.focus_neighbor_right = control.get_path_to(control)
	_back.focus_neighbor_top = _back.get_path_to(_controls.back() if not _controls.is_empty() else _tabs[_active_tab])
	_back.focus_neighbor_bottom = _back.get_path_to(_tabs[_active_tab])
	_back.focus_neighbor_left = _back.get_path_to(_back)
	_back.focus_neighbor_right = _back.get_path_to(_back)


func _restore_internal_focus(key: String) -> void:
	if _closing or not is_inside_tree():
		return
	for control in _controls + _tabs + [_back]:
		if control.get_meta("focus_key", "") == key:
			control.grab_focus()
			return
	_tabs[_active_tab].grab_focus()


func _on_settings_changed() -> void:
	if _closing:
		return
	if _language != Settings.language:
		_language = Settings.language
		var focus := get_viewport().gui_get_focus_owner()
		var key: String = focus.get_meta("focus_key", "") if is_instance_valid(focus) else ""
		_build.call_deferred(key)
	elif is_instance_valid(_fullscreen_toggle):
		_fullscreen_toggle.set_pressed_no_signal(Settings.fullscreen)


func _on_reset() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = 4.0
		_reset_btn.text = tr("再次确认：清除全部进度")
		return
	_reset_armed = 0.0
	Game.reset_save()
	_reset_btn.text = tr("存档已清除")
	_reset_btn.disabled = true
	_back.grab_focus()


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
	if _closing:
		return
	_closing = true
	closed.emit()
	var opener = _return_focus.get_ref() if _return_focus != null else null
	if is_instance_valid(opener) and opener is Control and opener.is_inside_tree() and opener.is_visible_in_tree():
		opener.grab_focus.call_deferred()
	queue_free()
