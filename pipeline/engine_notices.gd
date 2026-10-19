extends SceneTree
## Read the notices from the exact engine used to export the game.
func _initialize() -> void:
	var destination := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			destination = arg.trim_prefix("--out=")
	if destination.is_empty():
		quit(2)
		return
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string("GODOT ENGINE\nhttps://godotengine.org/license/\n\n" + Engine.get_license_text())
	file.store_string("\n\nTHIRD-PARTY COPYRIGHT NOTICES\n" + JSON.stringify(Engine.get_copyright_info(), "\t"))
	file.store_string("\n\nTHIRD-PARTY LICENSE TEXTS\n" + JSON.stringify(Engine.get_license_info(), "\t"))
	file.close()
	quit()
