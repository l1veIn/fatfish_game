extends Node
## Pure-rule and save-compatible skill checks. Only runs with its isolated profile.
const RULES := preload("res://scripts/run/meal_rules.gd")
var _failures := 0
var _checks := 0


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
	print(("PASS  " if ok else "FAIL  ") + message)


func food(kind: int, cells := 1, ghost := false, is_set := false, tier := 0) -> Dictionary:
	return {"kind": kind, "cells": cells, "ghost": ghost, "is_set": is_set, "tier": tier}


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=mechanic_synergy") or not Game.save_path.begins_with("user://qa_"):
		push_error("Refusing mechanic test without --test-profile=mechanic_synergy")
		get_tree().quit(2)
		return
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	_check(Game.nodes.size() == 75, "74 purchasable nodes plus the unchanged root")
	var effects_known := true
	for node in Game.nodes:
		for stat in node.effects:
			effects_known = effects_known and Game.BASE.has(stat)
	_check(effects_known, "every generated skill effect has a defined Game stat")
	Game.levels = {"start": 1, "prompt": 5, "compress": 1, "memory": 2}
	Game._recompute()
	_check(is_equal_approx(Game.stat("mono_bonus"), 0.5), "existing Prompt levels grant +10 percent platter value each")
	_check(is_equal_approx(Game.stat("cache_bonus"), 0.15), "existing compression level grants one 15 percent cache")
	_check(is_equal_approx(Game.stat("rotation_bonus"), 0.2), "existing memory levels grant +10 percent rotation each")
	_check(Game.stat("tier1") == 5.0 and Game.stat("compress") == 1.0 and Game.stat("memory") == 2.0, "all three previous skill effects survive unchanged")
	var full := RULES.profile([food(1, 2), food(1, 2)], 4)
	_check(full.full and full.mono_kind == 1 and full.real_items == 2, "two bowls can fill a box and form a single-dish platter")
	var with_ghost := RULES.profile([food(1, 2), food(1, 2), food(9, 4, true)], 4)
	_check(with_ghost == full, "a different ghost neither fills nor spoils a real platter")
	var half := RULES.profile([food(1), food(1)], 4)
	_check(half.mono_kind == -1 and not half.full, "half-full repeated dishes are not a platter")
	_check(RULES.profile([food(1, 4)], 4).mono_kind == -1, "one large dish is not a platter")
	_check(RULES.profile([food(1, 2), food(2, 2)], 4).mono_kind == -1, "mixed dishes do not get the single-dish bonus")
	_check(RULES.profile([food(1), food(1)], 0).mono_kind == -1, "invalid capacity cannot create a platter")
	var recipe_box := RULES.profile([food(20, 1, false, true, 2)], 4)
	var standard := RULES.profile([food(20, 1, false, true, 2), food(21, 1, false, true, 3)], 4)
	var no_skill := RULES.plan(full, -1, false, 0.0, 0.0, 0.0)
	_check(not no_skill.combo_eligible and no_skill.add_bonus == 0.0, "a platter requires Prompt before it gives a bonus or combo")
	_check(RULES.plan(standard, -1, false, 0.0, 0.0, 0.0).combo_eligible, "two higher-tier recipes retain their original combo eligibility")
	var ghost_sets := RULES.profile([food(20, 1, true, true, 2), food(21, 1, true, true, 3)], 4)
	_check(not RULES.plan(ghost_sets, -1, false, 0.1, 0.15, 0.1).combo_eligible, "ghost recipes cannot manufacture a real combo")
	var a := RULES.plan(full, -1, false, 0.1, 0.15, 0.1)
	_check(a.combo_eligible and is_equal_approx(a.add_bonus, 0.1) and a.next_mono_kind == 1, "first single-dish platter starts the line with its own bonus")
	var repeat := RULES.plan(full, a.next_mono_kind, a.cache_ready, 0.1, 0.15, 0.1)
	_check(not repeat.rotation and is_equal_approx(repeat.add_bonus, 0.1), "repeating one dish keeps combo eligibility but earns no rotation bonus")
	var other := RULES.profile([food(2), food(2), food(2), food(2)], 4)
	var rotated := RULES.plan(other, repeat.next_mono_kind, false, 0.1, 0.15, 0.2)
	_check(rotated.rotation and is_equal_approx(rotated.add_bonus, 0.3), "switching the whole platter combines Prompt and Memory bonuses additively")
	var interrupted := RULES.plan(half, rotated.next_mono_kind, false, 0.1, 0.15, 0.2)
	_check(interrupted.next_mono_kind == -1, "an ordinary player box ends the rotation sequence")
	_check(not RULES.plan(full, interrupted.next_mono_kind, false, 0.1, 0.15, 0.2).rotation, "one ordinary box prevents a stale rotation reward")
	var charged := RULES.plan(recipe_box, -1, false, 0.1, 0.15, 0.2)
	_check(charged.cache_primed and charged.cache_ready and charged.cache_bonus == 0.0, "a roomy real recipe box stores value for a later full box")
	var charged_again := RULES.plan(recipe_box, -1, charged.cache_ready, 0.1, 0.15, 0.2)
	_check(not charged_again.cache_primed and charged_again.cache_ready, "repeated recipe boxes never stack cache charges or duplicate the stored prompt")
	var held := RULES.plan(half, -1, charged_again.cache_ready, 0.1, 0.15, 0.2)
	_check(held.cache_ready and not held.cache_consumed, "an ordinary partial box does not consume the cache")
	var payout := RULES.plan(other, 1, held.cache_ready, 0.1, 0.15, 0.2)
	_check(payout.cache_consumed and not payout.cache_ready and is_equal_approx(payout.add_bonus, 0.45), "a full alternating platter combines 10 percent base, 15 percent cache and 20 percent rotation")
	_check(is_equal_approx(payout.add_bonus, payout.mono_bonus + payout.cache_bonus + payout.rotation_bonus), "receipt components sum to the exact additive box bonus")
	_check(RULES.plan(other, 1, held.cache_ready, 0.1, 0.15, 0.2) == payout, "repeated HUD previews are pure and cannot spend a cache")
	var after := RULES.plan(full, payout.next_mono_kind, payout.cache_ready, 0.1, 0.15, 0.2)
	_check(not after.cache_consumed and after.cache_bonus == 0.0, "cache can pay out only once until another recipe box primes it")
	_check(not RULES.plan(recipe_box, -1, false, 0.1, 0.0, 0.2).cache_ready, "unlearned compression cannot charge a cache")
	_check(not RULES.plan(RULES.profile([food(20, 3, false, true, 2)], 4), -1, false, 0.1, 0.15, 0.2).cache_ready, "one free cell does not qualify for the two-cell reserve")
	_check(not RULES.plan(half, -1, false, 0.1, 0.15, 0.2).cache_ready, "an empty-looking box without a recipe cannot farm reserves")
	# Exercise reachable consecutive submissions instead of injecting a previous dish
	# and a charged cache that the old state machine could never retain together.
	var bridge := RULES.plan(recipe_box, a.next_mono_kind, a.cache_ready, 0.1, 0.15, 0.2)
	_check(bridge.cache_bridge and bridge.combo_eligible and bridge.next_mono_kind == a.next_mono_kind,
		"a single cache-preparation recipe bridges the preceding platter without breaking its chain")
	var real_payout := RULES.plan(other, bridge.next_mono_kind, bridge.cache_ready, 0.1, 0.15, 0.2)
	_check(real_payout.rotation and real_payout.cache_consumed and is_equal_approx(real_payout.add_bonus, 0.45),
		"platter A then cache recipe then platter B reaches the combined bonus through real state transitions")
	var repeated_bridge := RULES.plan(recipe_box, bridge.next_mono_kind, bridge.cache_ready, 0.1, 0.15, 0.2)
	_check(not repeated_bridge.cache_bridge and not repeated_bridge.combo_eligible and repeated_bridge.next_mono_kind == -1,
		"another partial recipe cannot farm a chain from an already charged cache")
	_check(not RULES.plan(recipe_box, a.next_mono_kind, false, 0.1, 0.15, 0.0).cache_bridge,
		"cache bridging requires learned rotation rather than granting a hidden early chain")
	Game.levels = {"start": 1, "stall_wok": 1, "menu": 4, "lora": 1}
	Game._recompute()
	Game.struck = []
	var available := Game._available_menu()
	var main_dishes: Array = []
	for id in available:
		if available[id] == "main":
			main_dishes.append(id)
	_check(main_dishes.size() >= 2, "menu fixture has at least two available main dishes")
	for i in main_dishes.size() - 1:
		_check(Game.toggle_struck(main_dishes[i]), "menu accepts exclusion while another dish remains")
	var valid_menu := Game.active_struck().duplicate()
	var stored_before := FileAccess.get_file_as_bytes(Game.save_path)
	_check(Game.struck_toggle_reason(main_dishes.back()) == "每个档口至少保留一道菜。", "last available dish has an explicit refusal reason")
	_check(not Game.toggle_struck(main_dishes.back()) and Game.active_struck() == valid_menu, "last-dish exclusion is rejected without changing the effective menu")
	_check(FileAccess.get_file_as_bytes(Game.save_path) == stored_before, "rejected menu choices never rewrite the save")
	Game.struck = main_dishes.duplicate()
	Game.struck.append("unavailable_or_unknown_food")
	_check(Game.active_struck().size() == main_dishes.size() - 1, "legacy all-excluded menu deterministically leaves one dish available")
	Game.save_game()
	Game.load_game()
	_check(Game.struck == valid_menu, "loading a legacy menu persists only the effective in-memory choices")
	var run := CanteenRun.new()
	run._read_stats()
	_check(run.struck.size() == valid_menu.size() and is_equal_approx(run.g_good, Game.stat("lora") * valid_menu.size()), "actual shift and LoRA use only the effective menu")
	run.free()
	Game.levels["menu"] = 1
	Game._recompute()
	Game.struck = [main_dishes[0]]
	_check(Game.struck_toggle_reason(main_dishes[1]).is_empty() and Game.toggle_struck(main_dishes[1]), "at capacity a valid replacement can restore the old dish and exclude another")
	_check(Game.active_struck() == [main_dishes[1]], "capacity replacement keeps exactly the newest valid choice")
	_check(not Game.struck_toggle_reason("unavailable_or_unknown_food").is_empty(), "unknown or locked food cannot inflate menu bonuses")
	# A caught one-cell dish may mutate into a two-cell dish after admission.
	# Exercise real packing, including the last free cell, with no player snapshot.
	CanteenRun.load_menu()
	Game.levels = {"start": 1}
	Game.struck = []
	Game._recompute()
	var heated := CanteenRun.new()
	heated._read_stats()
	heated.temp = 1.0 # deterministic branch probe, not a purchasable probability
	var bun := CanteenRun.make(CanteenRun.KIND.bun)
	var leg := CanteenRun.make(CanteenRun.KIND.leg)
	var tight := heated._new_basin(Vector2.ZERO)
	tight.items = [bun, bun, bun]
	_check(heated._accepts(tight, leg), "last free cell admits the falling one-cell leg")
	heated._catch(tight, leg, false)
	_check(heated._space(tight) == 4 and not heated._pack(tight.items).is_empty(), "heat mutation cannot overfill an admitted box")
	_check(CanteenRun.K(tight.items.back()) == CanteenRun.KIND.leg and CanteenRun.grade(tight.items.back()) == 1 and CanteenRun.is_hot(tight.items.back()), "blocked larger replacement retains the dish with heat and quality improvement")
	var roomy := heated._new_basin(Vector2.ZERO)
	heated._catch(roomy, leg, false)
	_check(CanteenRun.K(roomy.items.back()) == CanteenRun.KIND.burger and not heated._pack(roomy.items).is_empty(), "a larger replacement is still allowed when it fits")
	heated.free()
	_check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before, "mechanic validation preserves player settings")
	print("MECHANIC_SYNERGY_TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(_failures)
