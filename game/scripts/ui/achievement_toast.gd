class_name AchievementToast
extends Control
## A short, non-interactive receipt. It neither pauses play nor steals the focused button.

var _pending: Array[String] = []
var _card: PanelContainer
var _name: Label
var _remaining := 0.0
var _warning: PanelContainer
var _title: Label
var _warning_title: Label
var _warning_body: Label
var _current_name := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.position = Vector2(1280, 906)
	_card.custom_minimum_size = Vector2(590, 124)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, UiKit.WOOD, 3, 16, 7))
	add_child(_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	_card.add_child(row)
	var portrait := TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var art := "res://assets/portraits/release/fish_achievement_trophy.png"
	if ResourceLoader.exists(art):
		portrait.texture = load(art)
	portrait.custom_minimum_size = Vector2(94, 100)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_title = UiKit.label(tr("成就达成"), 22, Color(0.5, 0.32, 0.13))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)
	_name = UiKit.label("", 30, UiKit.INK)
	_name.custom_minimum_size.x = 430
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name)
	_card.hide()
	Game.achievement_unlocked.connect(_enqueue)
	_warning = PanelContainer.new()
	_warning.position = Vector2(490, 22)
	_warning.custom_minimum_size = Vector2(940, 112)
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.add_theme_stylebox_override("panel", UiKit.box(Color(0.37, 0.12, 0.06, 0.97), UiKit.GOLD, 3, 14))
	add_child(_warning)
	var warning_col := VBoxContainer.new()
	warning_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.add_child(warning_col)
	_warning_title = UiKit.label(tr("进度暂时无法保存"), 27, UiKit.GOLD)
	_warning_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warning_col.add_child(_warning_title)
	_warning_body = UiKit.label(tr("请先不要退出游戏，检查磁盘空间和存档文件夹的写入权限。"), 23)
	_warning_body.custom_minimum_size.x = 900
	_warning_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warning_col.add_child(_warning_body)
	_warning.hide()
	Game.save_failed.connect(_save_warning)
	Settings.changed.connect(_translate)
	if Game.save_status != "" and not Game.save_status.begins_with("Recovered"):
		_save_warning(Game.save_status)


func _enqueue(id: String) -> void:
	_pending.append(id)


func _translate() -> void:
	_title.text = tr("成就达成")
	_warning_title.text = tr("进度暂时无法保存")
	_warning_body.text = tr("请先不要退出游戏，检查磁盘空间和存档文件夹的写入权限。")
	_name.text = tr(_current_name)


func _save_warning(message: String) -> void:
	_warning.tooltip_text = message
	_warning.show()


func _process(delta: float) -> void:
	if _warning.visible and Game.save_status == "":
		_warning.hide()
	if _remaining > 0:
		_remaining -= delta
		if not Settings.reduced_motion:
			_card.modulate.a = minf(1.0, _remaining / 0.25)
		if _remaining <= 0:
			_card.hide()
	elif not _pending.is_empty():
		var id: String = _pending.pop_front()
		for item in Game.achievement_catalog():
			if str(item.id) == id:
				_current_name = str(item.name)
				_name.text = tr(_current_name)
				_remaining = 4.5
				_card.modulate.a = 1.0
				_card.show()
				return
