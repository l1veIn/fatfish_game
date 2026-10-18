extends Node2D
## Renders 大肥鱼's rig in every action and saves one frame each into --out=<dir>, plus
## idle frames 0.25 s apart (to check the motion), for a contact sheet. --seat: the seated rig.
##   Godot --path game --resolution 1920x1080 res://tests/rig_test.tscn -- --out=<dir>

func _ready() -> void:
	var out := "rig_shots"
	var seated := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a == "--seat":
			seated = true
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.set_default_clear_color(Color(0.3, 0.25, 0.22))
	var fish := FishRig.new()
	fish.seated = seated
	fish.height = 1200.0
	fish.position = Vector2(960, 1050)
	add_child(fish)
	for i in 6:
		await get_tree().create_timer(0.25).timeout
		await _shot(out, "idle_%d" % i)
	var clips := ["happy", "not_fat", "beg", "slurp", "full_belly", "think", "basin", "broke"]
	if seated:
		clips = ["basin", "bang", "sulk", "dig_in", "slurp", "yum", "spit", "full_belly", "think"]
	for c in clips:
		fish.play(c, true)
		await get_tree().create_timer(0.55).timeout
		await _shot(out, c)
	get_tree().quit()


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
