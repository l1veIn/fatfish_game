extends Node
## The V4.1 chapters: ladder and old-save migration, 识图 / 视觉过滤, Fetch 跑腿, the new scoring
## skills and the Toy gifts. Rule-level checks on an isolated profile; no bot and no real save.
var _failures := 0
var _checks := 0


func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
	print(("PASS  " if ok else "FAIL  ") + message)


func _write(save: Dictionary) -> void:
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(save))
	f.close()
	DirAccess.remove_absolute(Game.save_path + ".bak")


func _setup(extra := {}) -> void:
	Game.reset_save()
	Game.version = 5
	Game.levels = {"start": 1, "vram": 2, "stall_main": 3, "stall_wok": 3, "stall_dim": 3, "stall_fry": 3, "stall_sweet": 3, "vision": 1}
	for id in extra:
		Game.levels[id] = extra[id]
	Game._recompute()


func _run() -> CanteenRun:
	var run := CanteenRun.new()
	run._read_stats()
	return run


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=v41_chapters") or not Game.save_path.begins_with("user://qa_"):
		push_error("Refusing V4.1 test without --test-profile=v41_chapters")
		get_tree().quit(2)
		return
	CanteenRun.load_menu()
	_ladder()
	_migration()
	_vision()
	_build_hidden("family")
	_build_hidden("full")
	_fetch()
	_scoring()
	_gifts()
	Game.reset_save()
	print("V41_CHAPTERS_TEST %s: %d checks, %d failures" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	# Fetch queued a sound on the final frame: let the audio thread release it before teardown.
	await get_tree().create_timer(0.3, true, false, true).timeout
	Audio._exit_tree()
	await get_tree().create_timer(0.12, true, false, true).timeout
	UiKit.clear_cache()
	get_tree().quit(1 if _failures > 0 else 0)


func _ladder() -> void:
	var plates: Array = Game.VERSIONS.map(func(v): return str(v.plate))
	check(plates == ["大肥鱼 V3", "大肥鱼 R1", "大肥鱼 V3.1", "大肥鱼 V3.2", "大肥鱼 V4", "大肥鱼 V4.1 Flash", "大肥鱼 V4.1 Flash-1017", "大肥鱼 V4.1 Pro", "大肥鱼 AGI"], "the ladder runs V4 -> three V4.1 versions -> AGI")
	var rising := true
	for i in range(2, Game.VERSIONS.size()):
		rising = rising and float(Game.VERSIONS[i].target) > float(Game.VERSIONS[i - 1].target)
	check(rising, "every review target is higher than the one before")
	for table in [CanteenRun.STREAM_CAP, CanteenRun.COMBO_CAP, CanteenRun.SIG_CAP, CanteenRun.WINDOW_NAME, CanteenRun.MEAL_TIME]:
		check(table.size() == Game.VERSIONS.size(), "per-version table covers every version")
	var openers := {}
	for n in Game.nodes:
		if n.get("kind", "") == "ticket":
			openers[str(n.opens)] = n
	for i in range(1, Game.VERSIONS.size()):
		var trial := str(Game.VERSIONS[i].trial)
		check(openers.has(trial) and int(openers[trial].get("ring", 0)) == i - 1, "a ticket in ring %d opens %s" % [i - 1, trial])
	for id in ["vision", "fetch"]:
		check(float(Game.node(id).cost) == 0.0, "%s is the free reward of its version" % id)
	Game.reset_save()
	Game.version = 4
	check(not Game.is_visible("smallcup") and not Game.is_visible("vision"), "V4.1 skills stay hidden before the release")
	Game.levels["ticket_flash"] = 1
	Game.tokens = 1e12
	check(Game.open_trial() == "flash", "buying the ticket opens the Flash review")
	check(Game.pay_trial("flash"), "the review ticket can be paid")
	Game.pass_trial()
	check(Game.version == 5 and Game.is_visible("smallcup") and Game.is_visible("vision"), "passing it reveals the Flash skills")
	check(Game.achievements.has("release_flash"), "passing it earns the achievement")


func _migration() -> void:
	_write({"version": 3, "tokens": 5000.0, "total_tokens": 9000.0, "runs": 40, "best_run": 2500000.0, "fish_version": 5,
		"levels": {"start": 1, "ticket_agi": 1, "ticket_v4": 1}, "ending_seen": true, "achievements": {"release_agi": 1000.0}})
	Game.load_game()
	check(Game.version == 4 and Game.agi_cleared, "a finished old save returns to V4 with the clear remembered")
	check(Game.achievements.has("release_agi") and Game.ending_unlocked() and not Game.ending_pending(), "it keeps its achievement and ending, with no repeat of the ending")
	check(Game.tokens == 5000.0 and Game.runs == 40, "it keeps tokens and shifts")
	Game.version = 6
	Game.pass_trial()
	check(Game.version == Game.VERSIONS.size() - 1, "passing V4.1 Pro takes it straight back to AGI")
	_write({"version": 3, "tokens": 5.0, "total_tokens": 9.0, "runs": 4, "best_run": 90.0, "fish_version": 4, "levels": {"start": 1}})
	Game.load_game()
	check(Game.version == 4 and not Game.agi_cleared and not Game.ending_unlocked(), "an unfinished V4 save is untouched")
	check(Game.save_game(), "the migrated save commits")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(int(d.version) == 4, "saves are written as schema 4")
	_write({"version": 4, "tokens": 1.0, "total_tokens": 1.0, "runs": 1, "best_run": 1.0, "fish_version": 2, "levels": {"start": 1},
		"vision_target": "not_a_recipe", "gifts": {"follow": true, "other": true, "like": false}})
	Game.load_game()
	check(Game.vision_target == "" and Game.gifts == {"follow": true}, "bad target and gift entries are discarded")


func _vision() -> void:
	_setup()
	var ids: Array = Game.helper_recipe_options(true).map(func(r): return str(r.id))
	check(ids.has("homestyle") and not ids.has("family"), "hidden recipes stay hidden until revealed")
	check(not Game.set_vision_target("family"), "an unrevealed hidden recipe cannot be chosen")
	Game.levels["agirec"] = 1
	Game._recompute()
	ids = Game.helper_recipe_options(true).map(func(r): return str(r.id))
	check(ids.has("family") and ids.has("full") and ids.has("deep"), "AGI 菜谱 opens the hidden recipes to 识图")
	check(not Game.helper_recipe_options().map(func(r): return str(r.id)).has("family"), "helper orders still need a real discovery")
	check(Game.set_vision_target("family") and Game.vision_kind() == CanteenRun.KIND["family"], "the target is stored")
	check(Game.set_vision_target("") and Game.vision_kind() == -1, "the target can be cleared")
	check(not Game.set_vision_target("not_a_recipe"), "an unknown target is refused")
	Game.levels.erase("vision")
	Game.levels["agirec"] = 1
	Game._recompute()
	Game.vision_target = "family"
	check(Game.vision_kind() == -1, "a saved target does nothing without the skill")


## With 视觉过滤 the hardest recipes can be built in a real 2x4 box by only catching what passes.
func _build_hidden(id: String) -> void:
	_setup({"agirec": 1, "vfilter": 1})
	Game.set_vision_target(id)
	var run := _run()
	var target: int = CanteenRun.KIND[id]
	check(run.vision_kind == target and run.vision_filter, "%s is the target" % id)
	run._hand = run._new_basin(Vector2(900, 700))
	run._update_vision()
	check(run._vision_open and not run._vision_need.is_empty(), "%s: the empty box asks for its ingredients" % id)
	var junk := CanteenRun.make(CanteenRun.KIND["gold"])
	check(run._vision_blocks(junk), "%s: a useless dish passes through" % id)
	var steps := 0
	while steps < 16 and CanteenRun.find_kind(run._hand.items, target) < 0:
		run._update_vision()
		var next := -1
		for kind in run._vision_need:
			if run._vision_wants(CanteenRun.make(int(kind))):
				next = int(kind)
				break
		if next < 0:
			break
		run._catch(run._hand, CanteenRun.make(next), false)
		steps += 1
	check(CanteenRun.find_kind(run._hand.items, target) >= 0, "%s: built by catching only what the filter lets through (%d dishes)" % [id, steps])
	run._update_vision()
	check(not run._vision_open and not run._vision_blocks(junk), "%s: once made, the box catches normally again" % id)
	run.free()


func _fetch() -> void:
	_setup({"fetch": 1, "fetchfast": 3, "fetchgold": 1})
	var run := _run()
	check(is_equal_approx(run.fetch_every, 6.0), "Search 预查询 shortens the interval by 2 s a level")
	run._hand = run._new_basin(Vector2(900, 700))
	run._update_vision()
	run._update_fetch(1.0)
	check(run._fp.is_empty(), "nothing arrives before the interval is up")
	run._update_fetch(6.0)
	check(run._fp.size() == 1 and CanteenRun.grade(int(run._fk[0])) == 1, "a graded dish arrives over the box")
	check(absf(run._fp[0].x - 900.0) < 1.0 and run._fp[0].y < 700.0, "it falls from straight above the box")
	run.free()
	_setup({"agirec": 1, "fetch": 1})
	Game.set_vision_target("deep")
	run = _run()
	run._hand = run._new_basin(Vector2(900, 700))
	run._update_vision()
	run._update_fetch(13.0)
	var kind := CanteenRun.K(int(run._fk[0]))
	check(kind == CanteenRun.KIND["congee"] or kind == CanteenRun.KIND["icecream"], "with a target it brings a missing ingredient")
	run.free()
	_setup({"fetch": 1, "hire": 3, "harness": 1, "fetchfast": 1})
	Game.helper_plan = {}
	run = _run()
	check(is_equal_approx(run.fetch_every, 12.0 - 2.0 - 3.0), "Harness takes 1 s off per helper on shift")
	run.free()
	_setup({"fetch": 1})
	run = _run()
	run._update_fetch(99.0)
	check(run._fp.is_empty(), "no box in hand: nothing is delivered")
	run.free()


func _scoring() -> void:
	_setup({"smallcup": 2})
	var run := _run()
	check(is_equal_approx(run._item_value(CanteenRun.make(CanteenRun.KIND["leg"])), 6.0 * 1.4), "小杯反超大杯 raises a one-cell dish")
	check(is_equal_approx(run._item_value(CanteenRun.make(CanteenRun.KIND["bowl"])), 4.0), "a two-cell dish is unchanged")
	run.free()
	_setup({"pro_full": 2})
	run = _run()
	check(is_equal_approx(run._g, 2.0), "满血 Pro level 2 doubles the whole meal")
	run.free()
	_setup({"waitlist": 1})
	Game.trial_fails["flash"] = 2
	run = _run()
	run.trial = "flash"
	run._setup_trial()
	check(is_equal_approx(run._g, 1.4), "这周一定 adds 20% per failed try")
	run.free()
	_setup({"godfeast": 2})
	run = _run()
	run._kinds_eaten = {CanteenRun.KIND["full"]: true, CanteenRun.KIND["family"]: true, CanteenRun.KIND["tea"]: true}
	check(is_equal_approx(run.review_mult(), 1.6), "神级宴席 counts only the 神级 kinds eaten")
	run.free()
	_setup()
	Game.version = 7
	run = _run()
	var base_cap := run._combo_cap()
	run.free()
	Game.levels["longctx"] = 2
	Game._recompute()
	run = _run()
	check(run._combo_cap() == base_cap + 4, "超长上下文 raises the combo cap")
	run.stream = 100.0
	run._bites = 100000
	check(is_equal_approx(run._stream_mult(), CanteenRun.STREAM_CAP[7] + 2.0), "超长上下文 raises the stream cap")
	run.free()
	_setup({"agirec": 1, "vmatch": 2})
	Game.set_vision_target("deep")
	run = _run()
	var kind: int = CanteenRun.KIND["deep"]
	check(is_equal_approx(run._box_rule_bonus({"items": [CanteenRun.make(kind)]}), 0.6), "看图说话 pays on the box holding the target")
	check(is_equal_approx(run._box_rule_bonus({"items": [CanteenRun.make(CanteenRun.KIND["ball"])]}), 0.0), "not on any other box")
	check(is_equal_approx(run._box_rule_bonus({"items": [CanteenRun.make(kind)], "crew": true}), 0.0), "and not on a helper's box")
	run.free()


func _gifts() -> void:
	Game.reset_save()
	Game.version = 4
	var amount := Game.gift_amount()
	check(amount >= 300.0 and is_equal_approx(amount, ceilf(Game.next_target() * 0.05)), "a gift scales with the next target")
	Game.tokens = 0.0
	check(is_equal_approx(Game.claim_gift("follow"), amount) and is_equal_approx(Game.tokens, amount), "the follow gift pays out once")
	check(Game.claim_gift("follow") == 0.0 and is_equal_approx(Game.tokens, amount), "and only once")
	check(Game.claim_gift("nonsense") == 0.0, "unknown gifts pay nothing")
	Game.load_game()
	check(Game.gifts.has("follow") and is_equal_approx(Game.tokens, amount), "the claim survives a reload")
	check(not ToyPlatform.gifts_available(), "outside Toy the gift button stays hidden")
