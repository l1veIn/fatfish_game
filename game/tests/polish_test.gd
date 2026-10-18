extends Node
## Screenshots of the polished effects: graded / hot food, a 套餐 burst, the warm box holding a
## box, the two table trays with count tags, the take-a-box hint, 深度思考, and the skill tree
## (affordable glow, padlocks, the buy burst).
##   Godot --path game --resolution 1920x1080 res://tests/polish_test.tscn -- --autotest --out=<dir>

var _out := "user://polish"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("shot ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	Game._stats["warm"] = 1.0
	Game._stats["think"] = 1.0
	var run := CanteenRun.new()
	add_child(run)
	await _wait(0.5)
	run.set_physics_process(false)
	var I := CanteenRun.I
	run._fp.clear()
	run._hand = run._new_basin(Vector2(800, 640))
	run._hand.items = [CanteenRun.make(I.GOLD, 2), CanteenRun.make(I.LEG, 1), CanteenRun.make(I.BALL, 0, true), CanteenRun.make(I.DUMP, 2)]
	run._hand.pos = Vector2(800, 640)
	run._hand.vel = Vector2.ZERO
	run._hand.slosh = 0.0
	run.warm = true
	run._warm = run._new_basin(Vector2.ZERO)
	run._warm.items = [CanteenRun.make(I.LEG, 2), CanteenRun.make(I.GOLD, 1)]
	for i in 3:
		var b := run._new_basin(Vector2.ZERO)
		b.items = [CanteenRun.make(I.BALL), CanteenRun.make(I.BOWL)]
		run._queue.append(b)
	run._empty = 3
	await _wait(0.1)
	await _shot("food")
	run._flash.append({"pos": run._hand.pos, "t": 0.12})
	await _wait(0.06)
	await _shot("shift")
	run.can_think = true
	run._think = 3.0
	Input.action_press("think")
	await _wait(0.5)
	await _shot("think")
	Input.action_release("think")
	run._hand = null
	await _wait(0.3)
	await _shot("take_hint")
	run.queue_free()

	Game.tokens = 1e6
	var tree := TreeScreen.new()
	add_child(tree)
	await _wait(0.8)
	tree._flash_at = Vector2(960, 540)
	tree._flash_time = 0.18
	await _shot("tree")
	get_tree().quit()
