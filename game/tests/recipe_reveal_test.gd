extends Node
## Formula visibility must never invent a crafted recipe or consume the player's save.
var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func write_save(data: Dictionary) -> void:
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _ready() -> void:
	if not Game.save_path.begins_with("user://qa_") or not Game._test_profile:
		push_error("Refusing formula tests without an isolated test profile")
		get_tree().quit(2)
		return
	Game.reset_save()
	check(not Game.all_recipes_revealed(), "a fresh profile starts with unrevealed formulas")
	check(not Game.recipe_formula_visible("deep"), "an uncrafted hidden recipe is initially hidden")
	check(not Game.recipe_formula_visible("egg_veg"), "an uncrafted ordinary recipe is initially hidden")
	check(Game.find_recipe("egg_veg"), "actually making an ordinary recipe records its first discovery")
	check(Game.recipe_formula_visible("egg_veg") and not Game.recipe_formula_visible("deep"), "crafting reveals only the recipe actually made")

	Game.reset_save()
	Game.version = 3
	Game.levels.agentwf = 1
	Game.tokens = 1000000.0
	Game._recompute()
	check(Game.buy("agirec"), "AGI Recipes can be bought at its first eligible version")
	check(Game.level("agirec") == 1 and Game.all_recipes_revealed(), "the first level reveals all formulas")
	check(Game._recipe_ids.all(func(id): return Game.recipe_formula_visible(id)), "all ordinary and hidden collection formulas become visible")
	check(not Game.recipe_formula_visible("missing_recipe") and not Game.recipe_formula_visible("emerge_stew"), "visibility does not invent invalid or skill-generated formulas")
	check(Game.recipes.is_empty(), "revealing formulas does not add crafted entries or counts")
	check(not Game.achievements.has("recipe_first") and not Game.achievements.has("recipe_all"), "revealing formulas does not award collection achievements")
	check(is_equal_approx(Game.stat("tier4"), 1.0), "the existing legendary value upgrade remains active")
	check(bool(Game._read_save(Game.save_path).get("recipes_revealed", false)), "the reveal is saved as a separate optional flag")
	check(Game.refund("agirec") > 0.0 and Game.level("agirec") == 0, "AGI Recipes still refunds normally")
	check(Game.all_recipes_revealed(), "refunding does not erase learned formulas")
	Game.recipes_revealed = false
	Game.load_game()
	check(Game.all_recipes_revealed() and Game.level("agirec") == 0, "learned formulas survive restart after refund")
	check(Game.find_recipe("deep") and int(Game.recipes.deep) == 1, "a revealed recipe still records its actual first craft")
	check(not Game.find_recipe("deep") and int(Game.recipes.deep) == 2, "later crafts increment the original counter normally")
	check(Game.recipes.size() == 1, "crafting one revealed recipe does not discover the others")
	Game.save_game()
	Game.recipes = {}
	Game.load_game()
	check(int(Game.recipes.get("deep", 0)) == 2 and Game.all_recipes_revealed(), "crafted counts and formula visibility persist independently")

	Game.reset_save()
	var legacy := Game._read_save(Game.save_path)
	legacy.erase("recipes_revealed")
	legacy.levels = {"start": 1, "agirec": 1}
	legacy.fish_version = 3
	write_save(legacy)
	Game.load_game()
	check(Game.all_recipes_revealed() and Game.recipe_formula_visible("full"), "existing saves with AGI Recipes immediately reveal formulas")
	check(Game.recipes.is_empty() and not Game.achievements.has("recipe_first"), "backfilling old saves does not invent discoveries")
	Game.refund("agirec")
	Game.recipes_revealed = false
	Game.load_game()
	check(Game.all_recipes_revealed() and Game.level("agirec") == 0, "an old save keeps its backfilled reveal after refund and restart")
	legacy.levels = {"start": 1}
	write_save(legacy)
	Game.load_game()
	check(not Game.all_recipes_revealed(), "old saves without AGI Recipes remain unrevealed")
	check(int(Game._read_save(Game.save_path).version) == Game.SAVE_VERSION, "the optional flag needs no save schema bump")

	Game.levels = {"start": 1, "agirec": 1, "fc": 1, "hire": 1, "stall_main": 1, "stall_sweet": 3}
	Game._recompute()
	check(Game.recipe_formula_visible("deep"), "a hidden formula is visible with ingredients available")
	check(not Game.helper_recipe_options().any(func(recipe): return recipe.id == "deep"), "showing a formula does not unlock an undiscovered hidden helper order")
	Game.reset_save()
	check(not Game.all_recipes_revealed() and Game.recipes.is_empty(), "explicit new game clears both reveal and crafting progress")
	Game.load_game()
	check(not Game.all_recipes_revealed(), "a new game's saved reveal remains cleared")

	var future := Game._read_save(Game.save_path)
	future.version = Game.SAVE_VERSION + 1
	future.recipes_revealed = "future representation"
	write_save(future)
	var future_text := FileAccess.get_file_as_string(Game.save_path)
	Game.load_game()
	check(Game._save_read_only, "future save protection runs before optional flag validation")
	check(not Game.save_game() and FileAccess.get_file_as_string(Game.save_path) == future_text, "future save stays byte-identical")
	Game.reset_save()
	print("RECIPE_REVEAL_TEST: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
