extends RefCounted
## Passive local observations. No RNG, score mutation or disk I/O until closing.
## Catch counts are contacts (a spilled dish may be caught again), not unique supply.
const MAX_EVENTS := 2048
const MAX_RECORDS := 30
var data := {}
var _ids := {}
var _next_box := 0
var _next_sample := 0.0


func begin(run) -> void:
	for id in run.KIND:
		_ids[int(run.KIND[id])] = str(id)
	var spent := 0.0
	for id in Game.levels:
		var node: Dictionary = Game.node(id)
		if id == "start" or node.get("kind", "") == "ticket":
			continue
		for level in int(Game.levels[id]):
			spent += floor(float(node.cost) * pow(float(node.get("growth", 1.0)), level))
	var effective := {}
	for key in Game.AUTOMATION_KEYS:
		effective[key] = Game.automation_enabled(key)
	data = {"schema": 1, "started_utc": Time.get_datetime_string_from_system(true),
		"mode": "autotest" if run.autotest else ("fixture" if Game._test_profile else ("debug" if run.debug else "manual")),
		"build": {"game_version": ProjectSettings.get_setting("application/config/version", ""),
			"stage": Game.version, "levels": Game.levels.duplicate(true), "skill_spend": spent,
			"bans": Game.active_struck(), "signatures": Game.active_signatures(),
			"automation": effective, "helpers": run._helper_configs.duplicate(true),
			"stall_order": run.stall_order.duplicate(), "capacity": run._cap(),
			"trial": run.trial, "target": run.target, "duration": run.meal_time},
		"source_sha256": {}, "food": {}, "events": [], "dropped_events": 0,
		"nutrition": [], "first_grok_seconds": -1.0, "transforms": {}, "active_seconds": 0.0,
		"paid_bites": {"live": 0, "warm": 0, "sleep": 0}, "input_devices": {}}
	for path in ["scripts/run/canteen_run.gd", "scripts/run/meal_rules.gd", "scripts/run/meal_journal.gd", "scripts/autoload/game.gd", "data/menu.json", "data/skill_tree.json"]:
		data.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	sample(run, true)


func count(channel: String, it: int, run, source := "all") -> void:
	var key: String = _ids.get(run.K(it), "unknown")
	var foods: Dictionary = data.food
	if not foods.has(channel):
		foods[channel] = {}
	if not foods[channel].has(source):
		foods[channel][source] = {}
	var counts: Dictionary = foods[channel][source]
	# Ghost output is separate from actual ingredients even when the kind is identical.
	if run.is_ghost(it):
		key += ":ghost"
	counts[key] = int(counts.get(key, 0)) + 1


func transform(rule: String, before: int, after: int, fallback: bool, run) -> void:
	var key := rule + ("_capacity_fallback" if fallback else ("_changed_kind" if run.K(before) != run.K(after) else "_quality_heat"))
	data.transforms[key] = int(data.transforms.get(key, 0)) + 1


func event(kind: String, seconds: float, details: Dictionary = {}) -> void:
	if data.events.size() >= MAX_EVENTS:
		data.dropped_events += 1
		return
	var entry := details.duplicate(true)
	entry["event"] = kind
	entry["seconds"] = seconds
	data.events.append(entry)


func box(stage: String, b: Dictionary, run) -> void:
	if not b.has("journal_id"):
		_next_box += 1
		b["journal_id"] = _next_box
	var items: Array = []
	for it in b.items:
		items.append({"kind": _ids.get(run.K(it), "unknown"), "grade": run.grade(it),
			"hot": run.is_hot(it), "ghost": run.is_ghost(it), "value": run._item_value(it)})
	event(stage, run._meal_elapsed(), {"box": b.journal_id, "source": source(b), "items": items,
		"full": bool(b.get("full", false)), "rule": b.get("meal_rule", {}).duplicate(true),
		"chain": b.get("chain_multiplier", 1.0), "relay": b.get("crew_relay_bonus", 0.0),
		"multiplier": b.get("mult", 1.0)})


static func source(b: Dictionary) -> String:
	return "helper:" + str(b.get("crew_id", "unknown")) if b.get("crew", false) else ("takeout" if b.get("takeout", false) else "player")


func sample(run, force := false) -> void:
	var elapsed: float = run._meal_elapsed()
	if not force and elapsed < _next_sample:
		return
	_next_sample = elapsed + 5.0
	# Ordinary meals are at most 120 world seconds; keep malformed/debug sessions bounded.
	if data.nutrition.size() < 128:
		data.nutrition.append({"seconds": elapsed, "categories": run._cat.duplicate(),
			"paid_bites": run._bites, "recipes_eaten": run._kinds_eaten.size(), "earned": run.earned})


func finish(run, subtotal: float) -> void:
	sample(run, true)
	var kinds: Array = []
	for k in run._kinds_eaten:
		kinds.append(_ids.get(k, "unknown"))
	var scores: Dictionary = run._score.duplicate()
	data["result"] = {"run": Game.runs, "reason": run._end_reason, "world_seconds": run._meal_elapsed(),
		"earned": run.earned, "subtotal": subtotal, "score": scores, "active_seconds": data.active_seconds,
		"paid_bites": run._bites, "recipes_eaten": kinds, "grok_training_bites": run._grok_n,
		"caught": run.caught, "spilled": run.spilled, "wasted": run.wasted, "fish_wait_seconds": run.fish_wait,
		"warm_share": float(scores.get("warm", 0.0)) / subtotal if subtotal > 0.0 else 0.0,
		"eos_share": float(scores.get("eos", 0.0)) / subtotal if subtotal > 0.0 else 0.0,
		"passed": run.passed}


func save_record(directory: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		return err
	var filename := "meal_%016d_%012d.json" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	var path := directory.path_join(filename)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	err = file.get_error()
	file.close()
	if err != OK:
		DirAccess.remove_absolute(path + ".tmp")
		return err
	err = DirAccess.rename_absolute(path + ".tmp", path)
	if err != OK:
		return err
	var files: Array[String] = []
	for name in DirAccess.get_files_at(directory):
		if name.begins_with("meal_") and name.ends_with(".json"):
			files.append(name)
	files.sort()
	for i in maxi(0, files.size() - MAX_RECORDS):
		DirAccess.remove_absolute(directory.path_join(files[i]))
	return OK
