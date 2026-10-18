extends Node
## Screenshots of the early, deadpan 大肥鱼: the title (idle, fed up, basin on her head), the skill
## tree, and closing time on a full belly (吃饱躺平 on the table, then the result card).
##   Godot --path game --resolution 1920x1080 res://tests/deadpan_test.tscn -- --autotest --out=<dir>
## (--autotest: the test save, never the player's)

var _out := "user://deadpan"


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
	Game.version = 0
	Game.runs = 3
	var title := TitleScreen.new()
	add_child(title)
	await _wait(1.5)
	await _shot("title_idle")
	for i in 5:
		title._pat()
		await _wait(0.15)
	await _wait(0.6)
	await _shot("title_annoyed")
	for i in 8:
		if title._helmet_t > 0.0:
			break
		title._pat()
		await _wait(0.15)
	await _wait(0.8)
	await _shot("title_helmet")
	print("helmet ", title._helmet_t > 0.0, " clip ", title._fish.clip)
	title._pat()
	await _wait(0.1)
	print("knock clip ", title._fish.clip)
	title.queue_free()

	var tree := TreeScreen.new()
	add_child(tree)
	await _wait(1.0)
	tree._fish.play("happy")
	await _wait(0.3)
	print("tree buy clip ", tree._fish.clip)
	await _shot("tree")
	tree.queue_free()

	var run := CanteenRun.new()
	add_child(run)
	await _wait(1.5)
	run._end("食堂关门了")
	await _wait(1.0)
	await _shot("shift_full")
	await _wait(2.5)
	await _shot("result_full")
	get_tree().quit()
