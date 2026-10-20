class_name ToyPlatform
extends Node
## Optional Web bridge. Local atomic saves always complete before a cloud write is queued.

signal initialized
signal image_saved(ok: bool, message: String)

static var active: ToyPlatform
var _bridge: JavaScriptObject
var _init_callback: JavaScriptObject
var _image_callback: JavaScriptObject
var _initialized := false
var _image_done := false
var _image_result := {}


func startup() -> void:
	active = self
	if not OS.has_feature("web") or not Game.platform_sync_allowed():
		return
	_bridge = JavaScriptBridge.get_interface("FatFishToy")
	if _bridge == null:
		return
	_bridge.setLanguage(Settings.language)
	Settings.changed.connect(func(): _bridge.setLanguage(Settings.language))
	_init_callback = JavaScriptBridge.create_callback(_on_initialized)
	_image_callback = JavaScriptBridge.create_callback(_on_image_saved)
	_bridge.init(Game.cloud_snapshot(), _init_callback)
	if not _initialized:
		await initialized
	Game.save_committed.connect(func(payload: String): _bridge.queueSave(payload))


func _on_initialized(args: Array) -> void:
	if _initialized:
		return
	var result: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	if result is Dictionary and result.get("save", "") is String and not result.save.is_empty():
		var accepted := Game.restore_cloud_save(result.save)
		_bridge.acknowledgeRestore(accepted)
	elif not result is Dictionary:
		_bridge.disableCloud("Invalid startup response")
	_initialized = true
	initialized.emit()


static func open_author() -> void:
	if is_instance_valid(active) and active._bridge != null:
		active._bridge.openAuthor()
	else:
		OS.shell_open("https://space.bilibili.com/2501012")


static func start_gesture() -> void:
	if is_instance_valid(active) and active._bridge != null:
		active._bridge.startGesture()


func save_image(png: PackedByteArray, filename: String) -> Dictionary:
	if _bridge == null:
		JavaScriptBridge.download_buffer(png, filename, "image/png")
		return {"ok": true, "message": ""}
	_image_done = false
	_bridge.saveImage("data:image/png;base64," + Marshalls.raw_to_base64(png), filename, _image_callback)
	if not _image_done:
		await image_saved
	return _image_result


func _on_image_saved(args: Array) -> void:
	var result: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	_image_result = {"ok": result is Dictionary and result.get("ok", false) == true,
		"message": str(result.get("message", "")) if result is Dictionary else ""}
	_image_done = true
	image_saved.emit(_image_result.ok, _image_result.message)


func _exit_tree() -> void:
	if active == self:
		active = null
