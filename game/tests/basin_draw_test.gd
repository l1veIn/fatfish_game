extends Node
## Draws one lunch box (n x n) filled with every kind of food and saves a screenshot, to check
## the food sprites and the box drawing.
##   Godot --path game --resolution 1920x1080 res://tests/basin_draw_test.tscn -- --n=3 --out=<png>
## --trial: the 春节前夜 trial with a heavy floor pile (梁阿姨 panics)

func _ready() -> void:
	var n := 3
	var trial := false
	var out := "basin_draw.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--n="):
			n = int(a.get_slice("=", 1))
		elif a == "--trial":
			trial = true
	var fills := {2: [0, 5, 2, 3], 3: [0, 1, 2, 3, 4, 5, 0], 4: [0, 1, 2, 3, 4, 5, 0, 0, 5, 5, 1, 2]}
	var proto := CanteenRun.new()
	if trial:
		proto.trial = "spring"
	add_child(proto)
	await get_tree().process_frame
	proto.set_process(false)
	proto.box_n = n
	proto._hand.items = fills[n]
	proto._hand.pos = Vector2(700, 600)
	proto._hand.vel = Vector2.ZERO
	proto._hand.slosh = 0.0
	if trial:
		for i in int(proto.pile_max * 0.8):
			proto._pile.append(Vector2(randf_range(60, 1400), proto.FLOOR_Y - 10))
			proto._pile_k.append(randi() % 6)
		proto._busy_t = 1.0
	proto._back.queue_redraw()
	proto.queue_redraw()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
