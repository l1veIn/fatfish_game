extends Node
## Isolated persistence boundary tests; no platform requests are issued.
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_"):
		get_tree().quit(2)
		return
	Game.reset_save()
	Game.tokens = 125.0
	Game.total_tokens = 250.0
	Game.runs = 2
	Game.save_game()
	var original := Game.cloud_snapshot()
	var data: Dictionary = JSON.parse_string(original)
	data.tokens = 550.0
	data.total_tokens = 900.0
	data.runs = 5
	check(Game.restore_cloud_save(JSON.stringify(data)), "valid cloud save imports")
	check(Game.tokens == 550.0 and Game.runs == 5, "game state reloads from imported progress")
	check(FileAccess.get_file_as_string(Game.save_path + ".before-cloud") == original,
		"previous local progress has a separate recoverable copy")
	var valid := FileAccess.get_file_as_string(Game.save_path)
	for invalid in ["{bad", "[]", "{\"version\":3}", "{\"version\":99}"]:
		check(not Game.restore_cloud_save(invalid), "reject damaged or future cloud save: " + invalid)
		check(FileAccess.get_file_as_string(Game.save_path) == valid, "reject leaves active save byte-identical")
	check(not Game.platform_sync_allowed(), "test profile cannot upload to the real account")
	var file := FileAccess.open(Game.save_path + ".bak", FileAccess.WRITE)
	file.store_string(original)
	file.close()
	file = FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(Game.cloud_snapshot() == original, "cloud startup receives recovered backup instead of broken primary")
	check(Game.restore_cloud_save(valid), "cloud import can replace a corrupt primary")
	check(FileAccess.get_file_as_string(Game.save_path + ".before-cloud") == original,
		"backup recovery is preserved before cloud replacement")
	Game.reset_save()
	print(JSON.stringify({"suite": "toy_save", "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)
