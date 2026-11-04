class_name EndingScreen
extends Control
## A player-paced epilogue. It only reports completion; main owns the persistent marker.
## Leaving the app midway therefore keeps the ending available on the next Continue.

signal finished
signal share_capture_changed(active: bool)

const PAPER := preload("res://assets/canteen/ui_paper.png")
const WALL := preload("res://assets/canteen/bg_wall.png")
const STAR := preload("res://assets/canteen/fx_star.png")
const INK_SOFT := Color(0.45, 0.31, 0.2)

var replay := false
var _page := 0
var _content: Control
var _cast: Control
var _next: Button
var _previous: Button
var _skip: Button
var _page_label: Label
var _heading: Label
var _hint: Label
var _save: Button
var _credits: Label
var _summary := {}
var _exporting := false
var _last_export_path := ""
var _last_export_error := OK
var export_directory := "user://keepsakes"
var _closed := false
var _t := 0.0
var _reveal: Tween


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_summary = _capture_summary()
	_content = Control.new()
	_content.position = Vector2(150, 192)
	_content.size = Vector2(970, 642)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_cast = Control.new()
	_cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cast)
	_heading = UiKit.label(tr("一张留给你的饭票"), 28, UiKit.GOLD, 6)
	_heading.position = Vector2(152, 72)
	add_child(_heading)
	_page_label = UiKit.label("", 24, UiKit.TEXT, 4)
	_page_label.position = Vector2(940, 74)
	_page_label.size.x = 180
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_page_label)
	_previous = UiKit.button(tr("上一页"), 27, Vector2(220, 72))
	_previous.position = Vector2(150, 900)
	_previous.pressed.connect(func(): _show_page(_page - 1))
	add_child(_previous)
	_next = UiKit.button(tr("继续"), 32, Vector2(480, 82))
	_next.position = Vector2(640, 894)
	_next.pressed.connect(_advance)
	add_child(_next)
	_save = UiKit.button(tr("保存纪念饭票"), 25, Vector2(300, 82))
	_save.name = "SaveKeepsake"
	_save.position = Vector2(390, 894)
	_save.pressed.connect(save_keepsake)
	add_child(_save)
	_skip = UiKit.button(tr("跳过 · 回技能树"), 25, Vector2(420, 72))
	_skip.position = Vector2(1340, 58)
	_skip.set_meta("ui_back", true)
	_skip.pressed.connect(_finish)
	add_child(_skip)
	_hint = UiKit.label(tr("按自己的节奏翻页 · Esc / B 返回技能树"), 22, Color(0.94, 0.85, 0.68), 4)
	_hint.position = Vector2(150, 988)
	_hint.size = Vector2(1660, 58)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	_credits = UiKit.label(tr("角色原型「溟月」：上善无形 · 女仆版：ZipZipPipe · CC BY-NC-SA 4.0 · 免费非商用粉丝作品 · 与 DeepSeek 官方无关"), 17, Color(0.94, 0.85, 0.68), 3)
	_credits.position = Vector2(150, 1052)
	_credits.size = Vector2(1650, 28)
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_credits)
	Audio.music("bgm_title")
	Audio.ambience("")
	_show_page(0)
	_next.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _exporting:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()


func _process(delta: float) -> void:
	if not Settings.reduced_motion:
		_t += delta
		queue_redraw()


func _draw() -> void:
	ScreenLayout.background(self, WALL, Color(0.68, 0.56, 0.43))
	draw_rect(ScreenLayout.full_rect(self), Color(0.12, 0.06, 0.02, 0.3))
	draw_texture_rect(UiKit.glow(), Rect2(1050, 80, 900, 900), false, Color(1.0, 0.76, 0.36, 0.42))
	UiKit.nine(self, PAPER, Rect2(96, 142, 1080, 720), 80.0)
	draw_line(Vector2(150, 300), Vector2(1120, 300), Color(0.47, 0.29, 0.12, 0.3), 2.0)
	for i in 7:
		var p := Vector2(1240 + (i * 97) % 510, 180 + (i * 139) % 590)
		var a := 0.3 + sin(_t * 0.8 + i) * 0.13
		draw_texture_rect(STAR, Rect2(p, Vector2(22, 22)), false, Color(1, 0.87, 0.53, a))
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, 1920, 1080), false, Color(0.12, 0.06, 0.01, 0.3))


func _label(text: String, at: Vector2, font_size: int, color := UiKit.INK, width := 950.0) -> Label:
	var l := UiKit.label(text, font_size, color)
	l.position = at
	l.size.x = width
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(l)
	return l


func _show_page(page: int) -> void:
	if _exporting:
		return
	_page = clampi(page, 0, 2)
	if _reveal != null and _reveal.is_running():
		_reveal.kill()
	for parent in [_content, _cast]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	_page_label.text = "%02d / 03" % (_page + 1)
	_previous.disabled = _page == 0
	_next.text = tr("继续开饭") if _page == 2 else tr("继续")
	_next.position.x = 710 if _page == 2 else 640
	_next.custom_minimum_size.x = 410 if _page == 2 else 480
	_next.size.x = _next.custom_minimum_size.x
	_save.visible = _page == 2
	_credits.visible = _page == 2
	_heading.text = tr("吃白饭的大肥鱼") if _page == 2 else tr("一张留给你的饭票")
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.text = tr("保存一张干净的饭票，也可以直接截图。食堂还会开门。") if _page == 2 else tr("按自己的节奏翻页 · Esc / B 返回技能树")
	_skip.text = tr("返回技能树") if _page == 2 else tr("跳过 · 回技能树")
	match _page:
		0:
			_label(tr("终章 / 最后一场评测"), Vector2.ZERO, 26, INK_SOFT)
			_label(tr("AGI，开饭了。"), Vector2(0, 128), 70)
			_label(tr("从第一盒热饭，到最后一场评测。\n你接住的每一口，都成了她长大的养分。"), Vector2(0, 250), 32)
			_label(tr("这张饭票，记着你们一起走过的路。"), Vector2(0, 365), 27, INK_SOFT)
			_stat(0, str(Game.runs), tr("一起吃过的饭"))
			_stat(1, str(Game.recipes.size()), tr("尝过的套餐"))
			_stat(2, Game.fmt(Game.total_tokens), tr("累计获得 token"))
			_make_fish(false)
		1:
			_label(tr("后来 / 最普通的愿望"), Vector2.ZERO, 26, INK_SOFT)
			_label(tr("然后，她又饿了。"), Vector2(0, 128), 64)
			_label(tr("梁阿姨敲了敲勺子："), Vector2(0, 254), 29, INK_SOFT)
			_label(tr("「了不起的事明天再说，\n今天还吃不吃？」"), Vector2(0, 317), 40)
			_label(tr("大肥鱼没说话。\n她把空饭盆，又往前推了推。"), Vector2(0, 485), 30, INK_SOFT)
			_make_fish(true)
		2:
			_show_keepsake()
			_make_fish(false)
			var note := UiKit.label(tr("下一顿，才刚开始。"), 33, UiKit.CREAM, 8)
			note.position = Vector2(1280, 928)
			note.size.x = 480
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_cast.add_child(note)
	_wire_focus()
	if _previous.disabled and _previous.has_focus():
		_next.grab_focus()
	_content.modulate.a = 1.0
	_cast.modulate.a = 1.0
	if not Settings.reduced_motion:
		_content.modulate.a = 0.0
		_cast.modulate.a = 0.0
		_reveal = create_tween().set_parallel(true)
		_reveal.tween_property(_content, "modulate:a", 1.0, 0.28)
		_reveal.tween_property(_cast, "modulate:a", 1.0, 0.38)
	queue_redraw()


func _stat(index: int, value: String, caption: String) -> void:
	var x := index * 326.0
	_label(value, Vector2(x, 465), 50, UiKit.INK, 310)
	_label(caption, Vector2(x, 540), 23, INK_SOFT, 310)


func _make_fish(seated: bool) -> void:
	if seated:
		var aunt := TextureRect.new()
		aunt.texture = preload("res://assets/canteen/auntie_happy.png")
		aunt.position = Vector2(1420, 198)
		aunt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		aunt.size = Vector2(410, 330)
		aunt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		aunt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cast.add_child(aunt)
	var fish := FishRig.new()
	fish.seated = seated
	fish.emote = 2
	fish.height = 660 if seated else 850
	fish.position = Vector2(1410, 860) if seated else Vector2(1480, 890)
	fish.idle_clip = "idle" if seated else "title_idle"
	_cast.add_child(fish)
	if Settings.reduced_motion:
		fish.set_process(false)
	if seated:
		var table := TextureRect.new()
		table.texture = preload("res://assets/canteen/table.png")
		table.position = Vector2(1210, 760)
		table.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		table.size = Vector2(600, 260)
		table.stretch_mode = TextureRect.STRETCH_SCALE
		table.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cast.add_child(table)


func _wire_focus() -> void:
	var buttons: Array = [_next, _skip] if _page == 0 else [_previous, _next, _skip]
	if _page == 2:
		buttons = [_previous, _save, _next, _skip]
	for i in buttons.size():
		var b: Button = buttons[i]
		var before: Button = buttons[posmod(i - 1, buttons.size())]
		var after: Button = buttons[(i + 1) % buttons.size()]
		b.focus_neighbor_left = b.get_path_to(before)
		b.focus_neighbor_right = b.get_path_to(after)
		b.focus_neighbor_top = b.get_path_to(before)
		b.focus_neighbor_bottom = b.get_path_to(after)
		b.focus_previous = b.get_path_to(before)
		b.focus_next = b.get_path_to(after)


func _advance() -> void:
	if _exporting:
		return
	if _page == 2:
		_finish()
	else:
		_show_page(_page + 1)


func _finish() -> void:
	if _closed or _exporting:
		return
	_closed = true
	_next.disabled = true
	_previous.disabled = true
	_skip.disabled = true
	_save.disabled = true
	finished.emit()


## This is today's real build, including on replay; it is not a fabricated first-clear record.
func _capture_summary() -> Dictionary:
	var key_skills: Array = []
	for id in ["grok", "mtp", "prompt", "memory", "compress", "lora", "eos", "rag", "think"]:
		if Game.level(id) > 0 and key_skills.size() < 3:
			key_skills.append({"id": id, "name": str(Game.node(id).get("name", id)), "level": Game.level(id)})
	if key_skills.size() < 3:
		for node in Game.nodes:
			var id := str(node.id)
			if id != "start" and not node.get("kind", "") == "ticket" and Game.level(id) > 0 and not key_skills.any(func(skill): return skill.id == id):
				key_skills.append({"id": id, "name": str(node.name), "level": Game.level(id)})
			if key_skills.size() == 3:
				break
	return {"runs": Game.runs, "total_tokens": Game.total_tokens, "best_run": Game.best_run,
		"recipes": Game.recipes.size(), "levels": Game.total_levels(), "signatures": Game.active_signatures().duplicate(),
		"struck": Game.active_struck().duplicate(), "skills": key_skills}


func _food_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id in ids:
		if CanteenRun.KIND.has(id):
			names.append(tr(CanteenRun.NAMES[CanteenRun.KIND[id]]))
	return " · ".join(names) if not names.is_empty() else tr("暂无")


func _show_keepsake() -> void:
	_label(tr("AGI 纪念饭票 · 当前进度"), Vector2.ZERO, 26, INK_SOFT)
	_label(tr("实现 AGI 了吗？\n……又饿了。"), Vector2(0, 110), 49)
	_label(tr("通用人工智能，专用干饭系统。"), Vector2(0, 247), 28, INK_SOFT)
	var values := [str(_summary.runs), Game.fmt(_summary.total_tokens), Game.fmt(_summary.best_run), str(_summary.recipes)]
	var captions := [tr("一起吃过的饭"), tr("累计获得 token"), tr("最佳单顿 token"), tr("尝过的套餐")]
	for i in 4:
		var value := _label(values[i], Vector2(i * 240, 315), 42, UiKit.INK, 230)
		value.name = "KeepsakeStat%d" % i
		_label(captions[i], Vector2(i * 240, 371), 20, INK_SOFT, 230)
	_label(tr("当前构筑 · 技能总等级 %d") % _summary.levels, Vector2(0, 426), 22, INK_SOFT)
	_label(tr("招牌菜：%s") % _food_names(_summary.signatures), Vector2(0, 467), 22)
	_label(tr("今日划掉：%s") % _food_names(_summary.struck), Vector2(0, 519), 22)
	var skills: PackedStringArray = []
	for skill in _summary.skills:
		skills.append("%s Lv.%d" % [tr(skill.name), skill.level])
	_label(tr("关键技能：%s") % (" · ".join(skills) if not skills.is_empty() else tr("暂无")), Vector2(0, 576), 21)


## Save exactly the presented card, without navigation, focus rings, or the local path.
## Export is optional and never changes progress or the ending-seen marker.
func save_keepsake() -> void:
	if _page != 2 or _exporting or _closed:
		return
	_last_export_path = ""
	if DisplayServer.get_name() == "headless":
		_last_export_error = ERR_UNAVAILABLE
		_hint.text = tr("未能保存饭票，请检查保存目录后重试。")
		return
	var directory := ProjectSettings.globalize_path(export_directory)
	_last_export_error = OK if OS.has_feature("web") else DirAccess.make_dir_recursive_absolute(directory)
	if _last_export_error != OK:
		_hint.text = tr("未能保存饭票，请检查保存目录后重试。")
		return
	_exporting = true
	share_capture_changed.emit(true)
	var focus := get_viewport().gui_get_focus_owner()
	for control in [_previous, _save, _next, _skip, _page_label, _hint]:
		control.hide()
	if _reveal != null and _reveal.is_running():
		_reveal.kill()
	_content.modulate.a = 1.0
	_cast.modulate.a = 1.0
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var filename := "fatfish-agi-%s-%d.png" % [stamp, Time.get_ticks_msec()]
	var path := directory.path_join(filename)
	if OS.has_feature("web"):
		var png := picture.save_png_to_buffer()
		# Toy recommends base64 below 2 MB. Reduce only the exported keepsake when
		# necessary; game textures and the displayed card retain their resolution.
		while png.size() > 1400000 and picture.get_width() > 960:
			var width := maxi(960, int(picture.get_width() * 0.8))
			var height := roundi(float(picture.get_height()) * width / picture.get_width())
			picture.resize(width, height, Image.INTERPOLATE_LANCZOS)
			png = picture.save_png_to_buffer()
		if is_instance_valid(ToyPlatform.active):
			var result := await ToyPlatform.active.save_image(png, filename)
			_last_export_error = OK if result.ok else FAILED
		else:
			JavaScriptBridge.download_buffer(png, filename, "image/png")
			_last_export_error = OK
	else:
		_last_export_error = picture.save_png(path)
	for control in [_previous, _save, _next, _skip, _page_label, _hint]:
		control.show()
	_exporting = false
	share_capture_changed.emit(false)
	if _last_export_error == OK:
		_last_export_path = filename if OS.has_feature("web") else path
		_hint.add_theme_font_size_override("font_size", 19)
		_hint.text = tr("已请求保存饭票，请查看相册或下载。") if OS.has_feature("web") else tr("饭票已保存：%s") % path
	else:
		_hint.text = tr("未能保存饭票，请重试。") if OS.has_feature("web") else tr("未能保存饭票，请检查保存目录后重试。")
	if is_instance_valid(focus):
		focus.grab_focus()
