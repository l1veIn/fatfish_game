class_name GiftPanel
extends Control
## Toy 小礼物: optional thank-you gifts for following the author or liking the video. They add a
## few tokens once per save and unlock nothing else; the game is complete without them.
signal closed

const ROWS := [
	["follow", "关注作者", "关注「夸夸家族族长」，领一份加餐。", "去关注"],
	["like", "点赞视频", "给游戏的介绍视频点个赞，领一份加餐。", "去点赞"],
]

var _status: Label
var _close: Button
var _claims := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	ScreenLayout.shade(self, Color(0.03, 0.02, 0.01, 0.8))
	var panel := PanelContainer.new()
	panel.position = Vector2(400, 210)
	panel.custom_minimum_size = Vector2(1120, 620)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	panel.add_child(col)
	col.add_child(UiKit.label(tr("小礼物"), 42, UiKit.GOLD))
	var note := UiKit.label(tr("完全可选：不领也不影响任何内容。每份礼物是 %s token，每个存档只能领一次。") % Game.fmt(Game.gift_amount()), 26)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	var buttons: Array[Button] = []
	for row in ROWS:
		var id: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		col.add_child(line)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		text.add_child(UiKit.label(tr(row[1]), 30, UiKit.GOLD))
		var hint := UiKit.label(tr(row[2]), 24)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(hint)
		var go := UiKit.button(tr(row[3]), 26, Vector2(180, 70))
		go.name = "GiftOpen_" + id
		go.pressed.connect(func(): ToyPlatform.open_gift_page(id))
		line.add_child(go)
		buttons.append(go)
		var claim := UiKit.button(tr("领取"), 26, Vector2(180, 70))
		claim.name = "GiftClaim_" + id
		claim.pressed.connect(_claim.bind(id))
		line.add_child(claim)
		buttons.append(claim)
		_claims[id] = claim
		_refresh(id)
	_status = UiKit.label("", 26, Color(0.98, 0.84, 0.6))
	_status.name = "GiftStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1000, 70)
	col.add_child(_status)
	_close = UiKit.button(tr("返回"), 30, Vector2(0, 70))
	_close.name = "GiftClose"
	_close.set_meta("ui_back", true)
	_close.pressed.connect(_finish)
	col.add_child(_close)
	buttons.append(_close)
	for i in buttons.size():
		var b := buttons[i]
		b.focus_next = b.get_path_to(buttons[(i + 1) % buttons.size()])
		b.focus_previous = b.get_path_to(buttons[posmod(i - 1, buttons.size())])
	_close.grab_focus.call_deferred()


func _refresh(id: String) -> void:
	var claim: Button = _claims[id]
	if Game.gifts.has(id):
		claim.text = tr("已领取")
		claim.disabled = true


func _claim(id: String) -> void:
	var claim: Button = _claims[id]
	if Game.gifts.has(id) or claim.disabled:
		return
	claim.disabled = true
	_status.text = tr("正在查询……")
	var result: Dictionary = await ToyPlatform.active.check_gift(id) if is_instance_valid(ToyPlatform.active) else {"ok": false, "status": "unsupported"}
	if not is_inside_tree():
		return
	claim.disabled = false
	if result.get("ok", false) == true:
		var amount := Game.claim_gift(id)
		_status.text = tr("领到了 %s token，谢谢你！") % Game.fmt(amount)
		_refresh(id)
		return
	match str(result.get("status", "")):
		"unauthorized":
			_status.text = tr("要先登录 B 站账号才能领取。")
		"unsupported":
			_status.text = tr("这里查不到，请在 B 站 App 或网页版里打开游戏。")
		"error":
			_status.text = tr("网络有点忙，等一下再试。")
		_:
			_status.text = tr("还没查到，操作完回来再点一次领取。")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	closed.emit()
	queue_free()
