class_name SettingsPanel
extends Control
## Shared modal settings. Four pages keep controls readable on a 1280 x 720 window.
## Changes apply immediately; focus stays inside the modal and returns to its opener.

signal closed

const TABS := ["声音", "画面", "辅助", "游戏"]
const InputRemapPanel := preload("res://scripts/ui/input_remap_panel.gd")

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
var _web_mode_poll := 0.0
var _fullscreen_toggle: CheckButton
var _resolution: OptionButton
var _remap: Control
var _remap_focus: Array = []


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
	dim.color = Color(0.03, 0.02, 0.01, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	add_child(_panel)
	_layout()
	_panel.minimum_size_changed.connect(_layout.call_deferred)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	_panel.add_child(col)
	var title := UiKit.label(tr("设置"), 50, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var subtitle := _hint(tr("按你的节奏，安心开饭。"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(subtitle)
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 12)
	col.add_child(tabs_row)
	for i in TABS.size():
		var tab := UiKit.button(tr(TABS[i]), 29, Vector2(0, 66))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.set_meta("focus_key", "tab_%d" % i)
		tab.pressed.connect(func(): _show_tab(i))
		tabs_row.add_child(tab)
		_tabs.append(tab)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	col.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 18)
	_scroll.add_child(_content)
	var footer := _hint(tr("轻触选项调整 · 点「返回」关闭") if preload("res://scripts/ui/touch_controls.gd").available() else tr("方向键选择 · Enter / A 确认 · Esc / B 返回"))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(footer)
	_back = UiKit.button(tr("返回"), 32, Vector2(300, 70))
	_back.set_meta("ui_back", true)
	_back.set_meta("focus_key", "back")
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(close)
	col.add_child(_back)
	_show_tab(_active_tab, false)
	_layout()
	_restore_internal_focus.call_deferred(focus_key)


func _layout() -> void:
	if not is_instance_valid(_panel):
		return
	var area := size if size.x > 1.0 else get_viewport_rect().size
	_panel.size = Vector2(minf(1160.0, area.x - 80.0), minf(920.0, area.y - 64.0))
	_panel.position = (area - _panel.size) * 0.5


func _show_tab(index: int, focus_tab := true) -> void:
	_active_tab = index
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
	var touch := UiKit.button(tr("触控布局：位置与尺寸"), 28, Vector2(0, 66))
	_register(touch, "touch_layout")
	touch.pressed.connect(_open_touch_layout)
	_content.add_child(touch)
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
	var controls := UiKit.button(tr("键盘与手柄改键"), 28, Vector2(0, 66))
	_register(controls, "input_remap")
	controls.pressed.connect(_open_remap)
	_content.add_child(controls)
	var line := HSeparator.new()
	_content.add_child(line)
	_content.add_child(UiKit.label(tr("存档"), 30, UiKit.GOLD))
	_content.add_child(_hint(tr("清除后将失去全部饭票、升级和成就。此操作无法撤销。")))
	_reset_btn = UiKit.button(tr("清除存档，从头开始"), 27, Vector2(0, 66))
	_register(_reset_btn, "reset_save")
	_reset_btn.pressed.connect(_on_reset)
	_content.add_child(_reset_btn)


func _hint(text: String) -> Label:
	var label := UiKit.label(text, 24, Color(0.85, 0.78, 0.67))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var label := UiKit.label(text, 28)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	_content.add_child(row)
	return row


func _option(key: String) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(370, 64)
	option.add_theme_font_size_override("font_size", 28)
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
	row.add_child(slider)
	var pct := UiKit.label("%d%%" % int(slider.value), 27)
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
		tab.focus_neighbor_top = tab.get_path_to(_back)
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
	if OS.has_feature("web") and is_instance_valid(_fullscreen_toggle):
		_web_mode_poll -= delta
		if _web_mode_poll <= 0:
			_web_mode_poll = 0.25
			Settings.fullscreen = bool(JavaScriptBridge.eval("window.FatFishToy ? window.FatFishToy.isFullscreen() : !!document.fullscreenElement"))
			_fullscreen_toggle.set_pressed_no_signal(Settings.fullscreen)
	if _reset_armed > 0.0:
		_reset_armed -= delta
		if _reset_armed <= 0.0 and is_instance_valid(_reset_btn) and not _reset_btn.disabled:
			_reset_btn.text = tr("清除存档，从头开始")


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_remap): return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _open_remap() -> void:
	_open_controls_panel(InputRemapPanel.new())


func _open_touch_layout() -> void:
	_open_controls_panel(preload("res://scripts/ui/touch_layout_panel.gd").new(), true)


func _open_controls_panel(panel: Control, preview := false) -> void:
	if is_instance_valid(_remap):
		panel.free()
		return
	var opener := get_viewport().gui_get_focus_owner()
	var previous: WeakRef = weakref(opener) if opener != null else null
	_remap_focus.clear()
	for control in find_children("*", "Control", true, false):
		_remap_focus.append({"node": weakref(control), "mode": control.focus_mode})
		control.focus_mode = Control.FOCUS_NONE
	var hidden: Array[CanvasItem] = []
	if preview:
		for child in get_children():
			if child is CanvasItem and child.visible:
				hidden.append(child)
				child.hide()
	_remap = panel
	panel.closed.connect(func():
		if panel.get_parent() == self: remove_child(panel)
		_remap = null
		for child in hidden:
			if is_instance_valid(child): child.show()
		for state in _remap_focus:
			var control = state.node.get_ref()
			if is_instance_valid(control): control.focus_mode = state.mode
		_remap_focus.clear()
		var target = previous.get_ref() if previous != null else null
		if is_instance_valid(target): target.grab_focus.call_deferred()
		else: _tabs[_active_tab].grab_focus.call_deferred())
	add_child(panel)


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	var opener = _return_focus.get_ref() if _return_focus != null else null
	if is_instance_valid(opener) and opener is Control and opener.is_inside_tree() and opener.is_visible_in_tree():
		opener.grab_focus.call_deferred()
	queue_free()
