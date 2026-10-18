extends Node
## Food grades in the air and in a box: plain, 优质 (silver sheen) and 金牌 (gold outline glow,
## sheen, stars). Time is frozen and stepped, so each shot catches a different moment.
##   Godot --path game --resolution 1920x1080 res://tests/grade_test.tscn -- --autotest --out=<dir>

var _out := "user://grades"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	var run := CanteenRun.new()
	add_child(run)
	await get_tree().create_timer(0.4).timeout
	run.set_process(false)
	run._fp.clear()
	run._fv.clear()
	run._fk.clear()
	run._fr.clear()
	var I := CanteenRun.I
	var kinds := [I.BALL, I.LEG, I.GOLD, CanteenRun.KIND["porkrice"]]
	for row in 3:
		for j in kinds.size():
			run._add_item(Vector2(420 + j * 170, 470 + row * 150), Vector2.ZERO, CanteenRun.make(kinds[j], row))
	run._hand = run._new_basin(Vector2(1180, 640))
	run._hand.items = [CanteenRun.make(I.BALL, 1), CanteenRun.make(I.LEG, 2), CanteenRun.make(I.GOLD, 2), CanteenRun.make(I.DUMP, 1)]
	for i in 4:
		run._t = 10.0 + i * 0.13
		run.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("grade_%d.png" % i))
	print("shots done")
	get_tree().quit()
