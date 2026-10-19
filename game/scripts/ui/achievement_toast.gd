class_name AchievementToast
extends Control
## A compact medal notification. No pause, focus or input is taken from the player.
var _pending: Array[String] = []
var _card: Panel
var _badge: TextureRect
var _name: Label
var _remaining := 0.0
var _warning: PanelContainer
var _title: Label
var _warning_title: Label
var _warning_body: Label
var _current_name := ""
var _current_id := ""
var _run: WeakRef


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = Panel.new()
	_card.position = Vector2(1240, 886)
	_card.size = Vector2(620, 158)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, UiKit.WOOD, 3, 16, 7))
	add_child(_card)
	_badge = TextureRect.new()
	_badge.position = Vector2(20, 27)
	_badge.size = Vector2(104, 104)
	_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_badge)
	_title = UiKit.label(tr("成就达成"), 23, Color(0.5, 0.32, 0.13))
	_title.position = Vector2(148, 21)
	_title.size = Vector2(442, 34)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_title)
	_name = UiKit.label("", 30, UiKit.INK)
	_name.position = Vector2(148, 65)
	_name.size = Vector2(442, 82)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_name)
	_card.hide()
	Game.achievement_unlocked.connect(_enqueue)
	get_tree().node_added.connect(_on_node_added)
	_warning = PanelContainer.new()
	_warning.position = Vector2(490, 22)
	_warning.custom_minimum_size = Vector2(940, 112)
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.add_theme_stylebox_override("panel", UiKit.box(Color("69382d"), Color("d8b673"), 2, 12))
	add_child(_warning)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.add_child(col)
	_warning_title = UiKit.label(tr("进度暂时无法保存"), 27, Color("fff3d5"))
	_warning_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_warning_title)
	_warning_body = UiKit.label(tr("请先不要退出游戏，检查磁盘空间和存档文件夹的写入权限。"), 23, Color("fff3d5"))
	_warning_body.custom_minimum_size.x = 890
	_warning_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_warning_body)
	_warning.hide()
	Game.save_failed.connect(_save_warning)
	Settings.changed.connect(_translate)
	if Game.save_status != "" and not Game.save_status.begins_with("Recovered"):
		_save_warning(Game.save_status)


func _enqueue(id: String) -> void:
	_pending.append(id)


func _on_node_added(node: Node) -> void:
	if node is CanteenRun:
		_run = weakref(node)
		# A player may start the next shift while the previous medal is still visible.
		# Return it to the front so no toast covers the live serving table.
		if not node._ended and not _current_id.is_empty():
			_pending.push_front(_current_id)
			_current_id = ""
			_remaining = 0.0
			_card.hide()


func _shift_is_active() -> bool:
	var run: CanteenRun = _run.get_ref() if _run != null else null
	if not is_instance_valid(run) or not run.is_inside_tree():
		# Only search when a notification is ready to leave the queue. Once found,
		# the weak reference makes waiting through a shift a constant-time check.
		run = _find_run(get_tree().root)
		_run = weakref(run) if run != null else null
	return run != null and not run._ended


func _find_run(node: Node) -> CanteenRun:
	if node is CanteenRun:
		return node
	for child in node.get_children():
		var run := _find_run(child)
		if run != null:
			return run
	return null


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
	if _remaining > 0.0:
		_remaining -= delta
		_card.modulate.a = 1.0 if Settings.reduced_motion else minf(1.0, _remaining / 0.25)
		if _remaining <= 0.0:
			_card.hide()
			_current_id = ""
	elif not _pending.is_empty():
		if _shift_is_active():
			return
		var id: String = _pending.pop_front()
		for item in Game.achievement_catalog():
			if str(item.id) == id:
				_current_id = id
				_current_name = str(item.name)
				_name.text = tr(_current_name)
				_badge.texture = load(AchievementsPanel.badge_path(item))
				_remaining = 4.5
				_card.modulate.a = 1.0
				_card.show()
				return
