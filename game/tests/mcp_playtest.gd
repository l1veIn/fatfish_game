extends "res://scripts/main.gd"
## An editor/MCP entry for live input and screenshots with isolated progress.
func _ready() -> void:
	if not Game._test_profile or not Settings._testing:
		push_error("MCP playtest requires automatic test-scene isolation")
		get_tree().quit(2)
		return
	Game.reset_save()
	Settings.pause_unfocused = false
	Settings.language = "zh_CN"
	Settings.fullscreen = false
	Settings.apply()
	super._ready()
