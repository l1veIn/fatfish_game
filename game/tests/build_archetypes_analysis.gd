extends Node
## Read-only rule probes. Never loads or writes the player's save.
const SNAPSHOT := "res://../build/qa/player-build-analysis/save-snapshot.json"
const OUT := "res://../build/qa/player-build-analysis/engine-report.json"
var report := {"checks": [], "scope": "Rule and arithmetic probes, not gameplay completion or human validation"}
var failures := 0
var runs: Array = []

func check(ok: bool, label: String) -> void:
	report.checks.append({"ok": ok, "label": label})
	if not ok:
		failures += 1
		push_error(label)

func make_run(levels: Dictionary, bans: Array = [], signatures: Array = []) -> CanteenRun:
	Game.levels = levels.duplicate(true)
	Game.struck = bans.duplicate()
	Game.signatures = signatures.duplicate()
	Game.version = 4
	Game._recompute()
	var run := CanteenRun.new() # deliberately not added: no render, _ready, bot or game clock
	run._read_stats()
	runs.append(run)
	return run

func code(id: String, quality := 0, hot := false, ghost := false) -> int:
	return CanteenRun.make(CanteenRun.KIND[id], quality, hot, ghost)

func box(run: CanteenRun, foods: Array) -> Dictionary:
	var b := run._new_basin(Vector2.ZERO)
	b.items = foods.duplicate()
	return b

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile=build_archetypes") or not Game.save_path.begins_with("user://qa_"):
		get_tree().quit(2)
		return
	Game._save_read_only = true
	var source_hash := FileAccess.get_sha256(SNAPSHOT)
	var settings_hash := FileAccess.get_sha256(Settings.PATH)
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	CanteenRun.load_menu()
	for r in CanteenRun.RECIPES:
		Game.recipes[r.id] = 1 # prevent discovery effects; in-memory, isolated profile only
	seed(20261019)
	report.base_stats = Game.BASE
	var run := make_run(snap.levels, snap.struck, snap.signatures)
	report.snapshot = {"sha256": source_hash, "runs": snap.runs, "fish_version": snap.fish_version,
		"best_run": snap.best_run, "ending_seen": snap.ending_seen,
		"stats": Game._stats.duplicate(), "effective_bans": Game.active_struck(),
		"effective_signatures": Game.active_signatures(), "runtime": {"capacity": run._cap(),
		"grok_need": run.grok_need, "veg_base": run.veg_x, "g_good": run.g_good,
		"g_gold_conditional": run.g_gold, "gold_x": run.gold_x, "tentacles": run.tentacles,
		"crave": run.crave, "combo_step": run.combo, "meal_time": run.meal_time,
		"warm_x": run.warm_x, "material_mult": run._g, "stream_from": run.stream_from}}
	check(run.grok_need == 12 and run.veg_x == 14.0, "snapshot: 12 forced greens, then value 14")
	check(is_equal_approx(run.g_good, 0.43) and is_equal_approx(run.g_gold, 0.6), "snapshot: 43% good roll; conditional 60% gold")
	var pure := true
	for i in 10000:
		pure = pure and run._stall_kind("wok") == CanteenRun.I.VEG
	check(pure, "wok level 1 with egg banned produces only greens (10,000 rolls)")
	var plain := code("veg")
	check(run._item_value(plain) == 0.0, "pre-grok green has no item value")
	run._grokked = true
	check(run._item_value(plain) == 14.0 and run._item_value(code("veg", 2)) == 70.0, "grok green values 14 / 28 / 70")
	var ingredients := [code("veg", 2), code("egg", 2)]
	run._merge_items(ingredients)
	check(ingredients.size() == 1 and CanteenRun.K(ingredients[0]) == CanteenRun.KIND.egg_veg, "gold green plus egg auto-merges")
	report.snapshot.gold_egg_veg_value = run._item_value(ingredients[0])
	check(is_equal_approx(run._item_value(ingredients[0]), 43.2), "snapshot Prompt 3 + RAG 1: gold green+gold egg = (5+2+15+2)*1.8=43.2, versus 85 separately")
	var fused := box(run, [])
	for i in 3:
		run._catch(fused, plain, false)
	check(fused.items.size() == 1 and CanteenRun.grade(fused.items[0]) == 1, "three normal greens fuse to one silver: 42 raw value becomes 28; three bites become one")
	run._cat = {"主": 0.0, "荤": 50.0, "素": 50.0}
	check(is_equal_approx(run.balance_score(), 1.0 / 3.0), "all drift greens leave starch absent: balance score 1/3")
	report.snapshot.drift_only_balance_mult = run.balance_mult()
	run._bites = 200
	report.snapshot.stream_at_200 = run._stream_mult()
	run._bites = 600
	report.snapshot.stream_at_600 = run._stream_mult()
	var greens: Array = []
	for i in 8:
		greens.append(code("veg", 2))
	var green_box := box(run, greens)
	green_box.full = true
	var rule := run._plan_box(green_box)
	check(rule.combo_eligible and is_equal_approx(rule.add_bonus, 0.3), "snapshot full greens grant +30% platter and delivery combo")
	green_box.meal_rule = rule
	for i in 13:
		run._commit_delivery_chain(green_box, true)
	run._start_box(green_box)
	check(is_equal_approx(green_box.chain_multiplier, 2.2), "snapshot delivery chain reaches x2.2 on 13th eligible box")
	report.snapshot.green_box_pool = 1.0 + run.box_bonus + run.fill_bonus + rule.add_bonus
	report.snapshot.mature_chain = green_box.chain_multiplier
	# Distribution probe: actual _catch/fusion, but perfect green selection, no movement or clock.
	var caught_total := 0
	var retained_value := 0.0
	var inputs: Array = []
	for trial in 10000:
		var fb := box(run, [])
		var catches := 0
		while run._space(fb) < run._cap():
			var g := 0
			if randf() < run.g_good:
				g = 2 if randf() < run.g_gold else 1
			run._catch(fb, code("veg", g), false)
			catches += 1
		caught_total += catches
		inputs.append(catches)
		retained_value += run._box_worth(fb)
	inputs.sort()
	report.green_fusion_sampling = {"seed":20261019,"boxes":10000,"scope":"perfectly selected green items; no flight/catching/timing simulation",
		"mean_input_per_8_bite_box":caught_total/10000.0,"median_input":inputs[5000],"p90_input":inputs[9000],
		"retained_value_per_input":retained_value/caught_total,"retained_value_per_box":retained_value/10000.0,
		"paid_bites_per_input":80000.0/caught_total,"input_per_paid_bite":caught_total/80000.0}
	# A six-cell box cannot be filled by three two-cell bowls: each row is three cells wide.
	var small := make_run({"start":1, "vram":1, "prompt":1})
	check(small._pack([code("bowl"), code("bowl"), code("bowl")]).is_empty(), "2x3 grid has fragmentation: three 2-cell bowls do not fit")
	# Cache/rotation are additive and only advance on player submissions.
	var rules_run := make_run({"start":1,"vram":1,"prompt":3,"compress":1,"memory":2,"multiturn":1})
	var breakfast := [code("soymilk"), code("youtiao")]
	rules_run._merge_items(breakfast)
	var primer := box(rules_run, breakfast)
	rules_run._note_served(primer)
	check(rules_run._cache_ready and primer.meal_rule.cache_primed, "one real breakfast in roomy box primes cache")
	var buns: Array = []
	for i in 6:
		buns.append(code("bun", i % 3))
	var full := box(rules_run, buns)
	full.full = true
	rules_run._note_served(full)
	check(is_equal_approx(full.meal_rule.add_bonus, 0.45) and not rules_run._cache_ready, "next full platter receives +30% platter +15% cache, only once")
	var legs: Array = []
	for i in 6:
		legs.append(code("leg", i % 3))
	var switched := box(rules_run, legs)
	switched.full = true
	rules_run._note_served(switched)
	check(is_equal_approx(switched.meal_rule.add_bonus, 0.5), "next changed platter receives +30% platter +20% rotation")
	var crew := box(rules_run, breakfast)
	crew.crew = true
	rules_run._note_served(crew)
	check(not rules_run._cache_ready and rules_run._previous_mono_kind == CanteenRun.KIND.leg, "helpers do not prime cache or break rotation")
	var ghost := box(rules_run, buns + [code("leg", 0, true, true)])
	check(rules_run._box_profile(ghost).mono_kind == CanteenRun.KIND.bun, "ghosts take no space and do not spoil platter purity")
	var pair := box(rules_run, [CanteenRun.make(CanteenRun.KIND.bento,0,false,false,0,8.0), CanteenRun.make(CanteenRun.KIND.chicken_rice,0,false,false,0,12.0)])
	var pair_rule := rules_run._plan_box(pair)
	check(pair_rule.combo_eligible and pair_rule.cache_primed and pair_rule.next_mono_kind == -1, "two high sets in roomy box can prime cache and maintain combo, but reset mono rotation")
	# Reachability, not just the pure plan formula: cache+rotation cannot coexist in normal play.
	var profiles := [rules_run._box_profile(full), rules_run._box_profile(switched), rules_run._box_profile(primer), rules_run._box_profile(pair), rules_run._box_profile(box(rules_run,[code("leg")]))]
	var frontier: Array = [[-1,false]]
	var seen := {}
	var simultaneous := false
	while not frontier.is_empty():
		var state: Array = frontier.pop_back()
		var key := str(state)
		if seen.has(key):
			continue
		seen[key] = true
		for p in profiles:
			var planned: Dictionary = CanteenRun.MEAL_RULES.plan(p,state[0],state[1],0.3,0.15,0.2)
			simultaneous = simultaneous or (planned.cache_consumed and planned.rotation)
			frontier.append([planned.next_mono_kind,planned.cache_ready])
	check(not simultaneous, "reachable submission states never combine cache consumption with rotation bonus")
	report.cache_rotation_reachable_states = seen.keys()
	# Real merge probes: only the outer tier multiplies stored raw ingredients.
	var recipe_run := make_run({"start":1,"vram":2,"prompt":3,"fewshot":3,"agentwf":2,"agirec":1,"rag":1,"cot":1,"compress":1})
	var all_recipes := {}
	for recipe in CanteenRun.RECIPES:
		if recipe.needs.is_empty():
			continue
		var items: Array = []
		for k in recipe_run._ingredients(recipe.result):
			items.append(CanteenRun.make(k))
		var b := box(recipe_run, items)
		recipe_run._merge(b, false)
		var at := CanteenRun.find_kind(b.items, recipe.result)
		all_recipes[recipe.id] = {"expanded_ingredients":recipe_run._ingredients(recipe.result).size(),
			"tier":CanteenRun.TIER[recipe.result], "made_from_flat_bag":at >= 0,
			"chains":b.get("chains",0), "result_count":b.items.size()}
		if at >= 0:
			all_recipes[recipe.id].value = recipe_run._item_value(b.items[at])
			all_recipes[recipe.id].raw = CanteenRun.raw_of(b.items[at])
			all_recipes[recipe.id].cells = recipe_run._cells(b.items[at])
	report.recipes = all_recipes
	check(all_recipes.deep.made_from_flat_bag and is_equal_approx(all_recipes.deep.value, 32.4), "hidden deep recipe: (3+6)*3.6 =32.4; one cell, one bite")
	check(all_recipes.full.made_from_flat_bag and is_equal_approx(all_recipes.full.raw, 27.0), "full banquet flat bag resolves; nested multipliers are not multiplied repeatedly")
	# Grade/heat mutation edge: once grokked, green stays green, but pre-grok may become potato.
	var mut := make_run({"start":1,"stall_wok":1,"temp":5,"hot":4})
	mut.temp = 1.0 # branch probe only: deliberately forced, not a legal 100% build
	var pre := box(mut, [])
	mut._catch(pre, plain, false)
	check(CanteenRun.K(pre.items[0]) == CanteenRun.KIND.potato, "Temperature can produce a locked higher-level dish; pre-grok green becomes potato")
	mut._grokked = true
	var post := box(mut, [])
	mut._catch(post, plain, false)
	check(CanteenRun.K(post.items[0]) == CanteenRun.I.VEG and CanteenRun.grade(post.items[0]) == 1 and CanteenRun.is_hot(post.items[0]), "post-grok Temperature keeps green, raises grade and heats it")
	var near_full := box(mut, [code("bun"),code("bun"),code("bun")])
	var accepted_before := mut._accepts(near_full,code("leg"))
	mut._catch(near_full,code("leg"),false)
	var retained: int = near_full.items.back()
	check(accepted_before and mut._space(near_full) == mut._cap() and not mut._pack(near_full.items).is_empty() and CanteenRun.K(retained) == CanteenRun.I.LEG and CanteenRun.grade(retained) == 1 and CanteenRun.is_hot(retained), "Temperature near-full box retains one-cell leg, upgrades grade/heat, and remains packable")
	var room := box(mut, [code("bun"),code("bun")])
	mut._catch(room,code("leg"),false)
	check(CanteenRun.K(room.items.back()) == CanteenRun.KIND.burger and mut._space(room) == mut._cap() and not mut._pack(room.items).is_empty(), "Temperature still upgrades leg to two-cell burger when it fits")
	report.scope_limitations = ["Temperature capacity branches force proc=1 to isolate behavior, not a legal 100% stat. No movement, UI, catching, whole-shift performance or human play validation."]
	# Async explicitly exempts helper boxes from both crave gain and consumption.
	var async_run := make_run({"start":1,"busy":5,"queue":2,"async":1})
	async_run._crave_t = 7.0
	var cb := box(async_run, [code("leg")])
	cb.crew = true
	async_run._start_box(cb)
	check(cb.mult == 1.0 and async_run._crave_t == 7.0, "Async helper box does not receive or consume saved appetite")
	var pb := box(async_run, [code("leg")])
	async_run._start_box(pb)
	check(is_equal_approx(pb.mult, 1.0+3.0*(1.0-exp(-2.0))) and async_run._crave_t == 0.0, "player box receives accumulated appetite and resets it")
	check(FileAccess.get_sha256(SNAPSHOT) == source_hash, "authorized snapshot remained byte-identical")
	check(FileAccess.get_sha256(Settings.PATH) == settings_hash, "settings remained byte-identical")
	report.failures = failures
	report.check_count = report.checks.size()
	report.hashes = {}
	for path in ["res://scripts/autoload/game.gd", "res://scripts/run/canteen_run.gd", "res://scripts/run/meal_rules.gd", "res://data/menu.json", "res://data/skill_tree.json", "res://tests/build_archetypes_analysis.gd"]:
		report.hashes[path] = FileAccess.get_sha256(path)
	var out := FileAccess.open(OUT, FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t"))
	out.close()
	for r in runs:
		r.free()
	for child in Audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	await get_tree().create_timer(0.12, true, false, true).timeout
	print("BUILD_ARCHETYPES_ANALYSIS " + ("PASS" if failures == 0 else "FAIL") + " checks=" + str(report.check_count) + " failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
