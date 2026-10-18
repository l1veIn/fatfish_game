extends Node
## Four helpers and every badge on, the bot playing: checks that the helpers keep apart and out
## from under the player's box (min distances over the run), then saves a screenshot.
##   Godot --path game --resolution 1920x1080 res://tests/crew_spread_test.tscn -- --autotest --out=<dir>

var _out := "user://crew_spread"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	Game._stats["helper"] = 4.0
	Game._stats["crave"] = 1.0
	Game._stats["stream"] = 1.0
	Game._stats["combo"] = 1.0
	Game._stats["critic"] = 0.04
	Game._stats["grok"] = 1.0
	var run := CanteenRun.new()
	run.autotest = true
	add_child(run)
	await get_tree().process_frame
	var gap := INF        # closest two catching helpers' targets ever got
	var under := INF      # closest a catching helper ever stood to the player's box
	var close_frames := 0
	var frames := 0
	var pgap := INF
	var punder := INF
	var parked := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
		var xs: Array = []
		for c in run._crew:
			if c.state == "catch" and c.box != null:
				xs.append(float(c.x))
				if run._hand != null:
					under = minf(under, absf(c.x - run._hand.pos.x))
		xs.sort()
		frames += 1
		var plan: Dictionary = run._plan_crew(run.FLOOR_Y + 40 - run.HELPER_BOX_Y)
		var gs: Array = plan.values()
		gs.sort()
		for i in range(1, gs.size()):
			pgap = minf(pgap, gs[i] - gs[i - 1])
		if run._hand != null:
			for g in gs:
				punder = minf(punder, absf(g - run._hand.pos.x))
		var still := 0
		for c in run._crew:
			if c.state == "catch" and c.box != null and plan.has(c.id) and absf(c.x - plan[c.id]) < 4.0 and run._hand != null and absf(c.x - run._hand.pos.x) < run._width() * 0.5:
				still += 1
		parked += still
		for i in range(1, xs.size()):
			gap = minf(gap, xs[i] - xs[i - 1])
			if xs[i] - xs[i - 1] < run._width() * 0.5:
				close_frames += 1
	print("helpers ", run._crew.size(), " box width ", run._width())
	print("closest two helpers %.0f px; frames with two overlapping %d of %d" % [gap, close_frames, frames])
	print("closest helper to the player's box %.0f px" % under)
	print("planned: closest two %.0f px, closest to the player's box %.0f px; frames a helper stood still under the box %d" % [pgap, punder, parked])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("crew_badges.png"))
	get_tree().quit()
