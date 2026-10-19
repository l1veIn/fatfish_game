class_name EndingScreen
extends Control
## A player-paced epilogue. It only reports completion; main owns the persistent marker.
## Leaving the app midway therefore keeps the ending available on the next Continue.

signal finished

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
var _closed := false
var _t := 0.0
var _reveal: Tween


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_content = Control.new()
	_content.position = Vector2(150, 192)
	_content.size = Vector2(970, 642)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_cast = Control.new()
	_cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cast)
	var label := UiKit.label(tr("一张留给你的饭票"), 28, UiKit.GOLD, 6)
	label.position = Vector2(152, 72)
	add_child(label)
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
	_skip = UiKit.button(tr("跳过 · 回技能树"), 25, Vector2(420, 72))
	_skip.position = Vector2(1340, 58)
	_skip.set_meta("ui_back", true)
	_skip.pressed.connect(_finish)
	add_child(_skip)
	var hint := UiKit.label(tr("按自己的节奏翻页 · Esc / B 返回技能树"), 22, Color(0.94, 0.85, 0.68), 4)
	hint.position = Vector2(150, 1007)
	add_child(hint)
	Audio.music("bgm_title")
	Audio.ambience("")
	_show_page(0)
	_next.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()


func _process(delta: float) -> void:
	if not Settings.reduced_motion:
		_t += delta
		queue_redraw()


func _draw() -> void:
	draw_texture_rect(WALL, Rect2(0, 0, 1920, 1080), false, Color(0.68, 0.56, 0.43))
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.12, 0.06, 0.02, 0.3))
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
	_page = clampi(page, 0, 2)
	if _reveal != null and _reveal.is_running():
		_reveal.kill()
	for parent in [_content, _cast]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	_page_label.text = "%02d / 03" % (_page + 1)
	_previous.disabled = _page == 0
	_next.text = tr("回食堂，继续玩") if _page == 2 else tr("继续")
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
			_label(tr("尾声 / 明天见"), Vector2.ZERO, 26, INK_SOFT)
			_label(tr("谢谢你，陪她好好吃饭。"), Vector2(0, 125), 55)
			_label(tr("食堂还会开门。\n还没点亮的技能、没尝过的套餐，都在等你。\n下次开饭，也请多关照。"), Vector2(0, 247), 31)
			_label(tr("送给每一个认真接住生活里那一口热饭的人。"), Vector2(0, 410), 25, INK_SOFT)
			_label(tr("角色原型「溟月」：上善无形\n女仆版「蓝色大肥鱼」：ZipZipPipe\n免费、非商用粉丝作品 · CC BY-NC-SA 4.0\n与 DeepSeek 官方无关"), Vector2(0, 490), 21, INK_SOFT)
			_make_fish(false)
			var note := UiKit.label(tr("明天，还在这里。"), 33, UiKit.CREAM, 8)
			note.position = Vector2(1280, 940)
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
	if _page == 2:
		_finish()
	else:
		_show_page(_page + 1)


func _finish() -> void:
	if _closed:
		return
	_closed = true
	_next.disabled = true
	_previous.disabled = true
	_skip.disabled = true
	finished.emit()
