extends Node
## The closing checkout with everything on: leftovers eaten in her dreams, the 保温箱 with a
## 套餐 in it and its <EOS> last bite, 梯度裁剪, 均衡 and 评鉴 stamped. Screenshots along the way,
## prints the steps the receipt got.
##   Godot --path game --resolution 1920x1080 res://tests/checkout_test.tscn -- --autotest --out=<dir>

var _out := "user://checkout"


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
	Game._stats["final"] = 1.0
	Game._stats["eos"] = 2.0
	Game._stats["sleep"] = 1.0
	Game._stats["critic"] = 0.04
	Game._stats["clip"] = 1.0
	var run := CanteenRun.new()
	add_child(run)
	await _wait(0.4)
	var I := CanteenRun.I
	var set_k: int = CanteenRun.KIND["porkrice"]
	run._warm = run._new_basin(Vector2.ZERO)
	run._warm.items = [CanteenRun.make(set_k, 0, false, false, 0, 20.0), CanteenRun.make(I.GOLD, 2)]
	for i in 2:
		var b := run._new_basin(Vector2.ZERO)
		b.items = [CanteenRun.make(I.BALL), CanteenRun.make(I.LEG)]
		run._queue.append(b)
	run._hand = run._new_basin(Vector2(800, 640))
	run._hand.items = [CanteenRun.make(I.BOWL)]
	run._box_vals = [40.0, 60.0, 10.0, 80.0, 70.0, 20.0]
	run.earned = 1240.0
	run.eaten = 37
	for kk in ["carb", "two_one", "bento", "dimsum", "happy", "tea"]:
		run._kinds_eaten[CanteenRun.KIND[kk]] = true
	run._end("食堂关门了")
	await _wait(1.3)
	var card: CheckoutReceipt = null
	for c in run.get_children():
		if c is CheckoutReceipt:
			card = c
	print("receipt ", card != null)
	if card != null:
		for st in card.steps:
			print("  step ", st.get("text", st.get("note", "")), " ", st.get("add", st.get("lost", 0.0)), " ", st.get("mark", ""))
		print("  subtotal ", card.subtotal, " mults ", card.mults, " total ", card.total)
	await _wait(1.2)
	await _shot("checkout_1")
	await _wait(0.9)
	await _shot("checkout_2")
	await _wait(1.6)
	await _shot("checkout_3")
	await _wait(4.0)
	await _shot("checkout_4")
	await _wait(4.0)
	await _shot("checkout_5")
	get_tree().quit()
