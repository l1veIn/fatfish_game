extends Node
## A shift with all six helpers hired and no empty box left, to check the sleepers (and, with
## --awake, the helpers at work). Saves one screenshot to --out=<png>. Nothing is saved.

func _ready() -> void:
	var out := "crew.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	for id in ["helper", "hire_pu", "hire_g", "hire_ke", "hire_zi", "hire_ge"]:
		Game.levels[id] = 1
	Game._recompute()
	var run := CanteenRun.new()
	add_child(run)
	await get_tree().process_frame
	run._empty = 0
	run._hand = run._new_basin(Vector2(700, 760))
	await get_tree().create_timer(3.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
