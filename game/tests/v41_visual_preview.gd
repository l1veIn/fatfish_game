extends Node
## Real GPU captures of the V4.1 additions. Explicit fixtures on an isolated profile: not a playthrough.
## godot --path game res://tests/v41_visual_preview.tscn -- --test-profile=v41_visual --out=<absolute dir>
var out := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty() or not Game.save_path.begins_with("user://qa_"):
		push_error("Refusing without an isolated profile and --out")
		get_tree().quit(2)
		return
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	Game.reset_save()
	Game.version = 7
	Game.runs = 40
	Game.tokens = 3e7
	for n in Game.nodes:
		if n.get("kind", "") != "ticket" and int(n.get("ring", 0)) <= 7 and str(n.id) not in ["temp", "halluc", "regen", "overfit", "fuse3", "hodge"]:
			Game.levels[n.id] = int(n.max)
	Game.levels["ticket_v4"] = 1
	Game.levels["ticket_flash"] = 1
	Game.levels["ticket_1017"] = 1
	Game.levels["ticket_pro"] = 1
	Game.levels["hire"] = 2
	Game.seen_buttons = {"intro_canteen_complete": true, "intro_think": true, "intro_warm": true, "intro_grok": true}
	Game._recompute()
	Game.set_vision_target("family")
	var run := CanteenRun.new()
	add_child(run)
	await get_tree().create_timer(5.0).timeout
	run._hand = run._hand if run._hand != null else run._new_basin(Vector2(960, 700))
	run._aim = Vector2(960, 700)
	await _shot("vision_shift_a")
	run.set_process(false)
	run._hand = run._new_basin(Vector2(960, 700))
	run._catch(run._hand, CanteenRun.make(CanteenRun.KIND["bowl"]), false)
	run._catch(run._hand, CanteenRun.make(CanteenRun.KIND["leg"]), false)
	run._update_vision()
	run.queue_redraw()
	await get_tree().create_timer(0.3).timeout
	await _shot("vision_shift_b")
	run.queue_free()
	await get_tree().process_frame
	var tree := TreeScreen.new()
	add_child(tree)
	await get_tree().create_timer(0.8).timeout
	await _shot("tree_default")
	tree._pan = Vector2(1000, 760)
	tree._zoom = 0.72
	tree.queue_redraw()
	await get_tree().create_timer(0.3).timeout
	await _shot("tree_v41_zone")
	tree._open_vision()
	await get_tree().create_timer(0.5).timeout
	await _shot("vision_picker")
	tree.queue_free()
	await get_tree().process_frame
	Settings.language = "zh_CN"
	var gift := GiftPanel.new()
	add_child(gift)
	await get_tree().create_timer(0.3).timeout
	await _shot("gift_panel")
	Game.reset_save()
	print("V41_VISUAL_PREVIEW DONE")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
