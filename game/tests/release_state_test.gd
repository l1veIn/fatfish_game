extends Node
## Fault injection for persistent state. Always use --test-profile=release_state.
var failures: Array[String] = []
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func write_save(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_"):
		push_error("Refusing persistence tests without --test-profile")
		get_tree().quit(2)
		return
	Game.reset_save()
	var p := Game.save_path
	Game.tokens = 100.0
	Game.total_tokens = 100.0
	check(Game.save_game(), "first save succeeds")
	Game.tokens = 250.0
	Game.total_tokens = 250.0
	check(Game.save_game(), "replacement save succeeds on Windows")
	write_save(p, {"version": 3})
	Game.load_game()
	check(Game.tokens == 100.0, "syntactically valid empty shell falls back to good backup")
	write_save(p, "broken primary")
	Game.load_game()
	check(Game.tokens == 100.0, "corrupt primary recovers previous good backup")
	Game.tokens = 175.0
	check(Game.save_game(), "save after recovery succeeds")
	check(float(Game._read_save(p + ".bak").tokens) == 100.0, "corrupt primary never replaces good backup")
	DirAccess.remove_absolute(p)
	Game.load_game()
	check(Game.tokens == 100.0, "missing primary recovers backup")
	var pending := Game._read_save(p + ".bak")
	pending.tokens = 222.0
	write_save(p + ".tmp", pending)
	Game.load_game()
	check(Game.tokens == 222.0, "complete interrupted temporary save recovers when primary is missing")
	check(Game.save_game(), "recovered temporary save commits")
	var legacy := {"version": 2, "tokens": 321.0, "total_tokens": 50000.0, "runs": 12,
		"fish_version": 5, "best_run": 12000, "levels": {"start": 1}, "recipes": {},
		"signatures": [], "struck": [], "seen_buttons": {"settings": true}}
	write_save(p, legacy)
	Game.load_game()
	check(Game.tokens == 321.0 and Game.version == 5 and Game.runs == 12, "v2 migration keeps currency, version and runs")
	check(Game.ending_pending(), "completed old save receives new ending")
	check(Game.achievements.has("release_agi") and Game.achievements.has("regular"), "old save backfills proven milestones")
	check(not Game.achievements.has("bites_100"), "old save does not invent missing bite counters")
	Game.mark_ending_seen()
	Game.ending_seen = false
	Game.load_game()
	check(Game.ending_seen and not Game.ending_pending(), "ending seen flag persists")
	legacy.version = 99
	write_save(p, legacy)
	var future_text := FileAccess.get_file_as_string(p)
	Game.load_game()
	check(not Game.save_game(), "older game refuses to overwrite future save")
	check(FileAccess.get_file_as_string(p) == future_text, "future save stays byte-identical")
	Game.reset_save()
	check(Game.save_status == "", "explicit reset clears future-save protection")
	legacy.version = 3
	legacy.tokens = -10.0
	legacy.runs = -1
	legacy.levels = {"start": -5, "missing_skill": 99, "stall_wok": "bad"}
	legacy.recipes = {"unknown_recipe": 20}
	legacy.achievements = {"unknown_achievement": 1}
	legacy.lifetime = {"eaten": -4}
	legacy.signatures = ["missing", 123]
	write_save(p, legacy)
	Game.load_game()
	check(Game.tokens == 0 and Game.runs == 0 and Game.level("start") == 1, "negative counts clamp, root skill survives")
	check(not Game.levels.has("missing_skill") and Game.recipes.is_empty(), "unknown skill and recipe ids are discarded")
	check(Game.signatures.is_empty() and not Game.achievements.has("unknown_achievement"), "bad selections and achievement ids are discarded")
	check(not Game.pay_trial("not_a_trial"), "unknown evaluation cannot charge a ticket")
	check(not Game.pay_trial("spring"), "locked or completed evaluation cannot charge a ticket")
	Game.reset_save()
	Game.version = 5
	Game.tokens = 100000000.0
	for n in Game.nodes:
		Game.levels[n.id] = 1
	var skill := ""
	for n in Game.nodes:
		if n.get("kind", "") != "ticket" and int(n.max) >= 3 and float(n.growth) != 1.0 and float(n.cost) < 1000 and Game.refund_dependents(n.id).is_empty():
			skill = n.id
			break
	check(not skill.is_empty(), "full-refund fixture has a scaling-price skill with no purchased dependents")
	Game.levels.erase(skill)
	Game._recompute()
	var before := Game.tokens
	for i in 3:
		check(Game.buy(skill), "buy scaling skill level %d" % i)
	Game.refund(skill)
	check(Game.tokens == before, "individual refund exactly equals rounded purchase costs")
	for i in 3:
		Game.buy(skill)
	Game.refund(skill)
	check(Game.tokens == before, "repeat buy/refund cannot create currency")
	Game.reset_save()
	Game.tokens = 1000000.0
	before = Game.tokens
	for i in 3:
		for n in Game.nodes:
			if n.get("kind", "") != "ticket" and n.id != "start" and Game.can_buy(n.id):
				Game.buy(n.id)
	Game.respec()
	check(Game.tokens == before, "whole-tree respec refunds exact purchase prices")
	var after := Game.tokens
	check(Game.respec() == 0.0 and Game.tokens == after, "repeated respec does not duplicate refunds")
	check(Game.achievements.has("checkpoint"), "respec records its achievement")
	Game.reset_save()
	Game.runs = 1
	Game.record_run({"eaten": 100, "caught": 25, "spilled": 0, "full_boxes": 25, "balance": 1.95, "grokked": true})
	check(Game.achievements.has("first_meal") and Game.achievements.has("balanced") and Game.achievements.has("full_boxes"), "real settlement summary unlocks eligible achievements")
	var earned_at: float = Game.achievements.first_meal
	Game._check_achievements()
	check(float(Game.achievements.first_meal) == earned_at, "achievement timestamp is awarded only once")
	Game.save_game()
	Game.achievements = {}
	Game.load_game()
	check(Game.achievements.has("grokked") and int(Game.lifetime.eaten) == 100, "achievements and lifetime counters survive restart")
	Game.signatures = ["ball"]
	Game.reset_save()
	check(Game.signatures.is_empty() and Game.achievements.is_empty() and not Game.ending_seen, "reset clears all new progress and signature picks")
	DirAccess.remove_absolute(p)
	Game.load_game()
	check(Game.runs == 0 and Game.achievements.is_empty(), "backup after explicit reset cannot resurrect old progress")
	var old := p + ".legacy"
	var old_good := Game._read_save(p + ".bak")
	old_good.tokens = 789.0
	write_save(old, {"version": 3})
	write_save(old + ".bak", old_good)
	check(Game._import_legacy_save(old), "legacy directory imports good backup when primary is damaged")
	Game.load_game()
	check(Game.tokens == 789.0, "legacy backup preserves actual progress")
	Game.reset_save()
	Game.recipes = {}
	for id in Game._recipe_ids:
		Game.recipes[id] = 1
	Game._check_achievements()
	check(Game._recipe_ids.size() == 20 and Game.achievements.has("recipe_all"), "all-recipes achievement matches all 20 attainable collection entries")
	check(Game.achievements.has("recipe_twentyfive"), "mid-collection milestone is attainable")
	Game.levels["hire"] = 6
	Game._recompute()
	Game._check_achievements()
	check(Game.achievements.has("full_crew"), "six actually hired assistants unlock full crew")
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(old + suffix)
	print("RELEASE_STATE_TEST: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
