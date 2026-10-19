extends RefCounted
## Pure serving rules. Callers normalize item codes into dictionaries with
## kind, cells, ghost, is_set and tier. Previewing never spends a cache charge.
## Only an actual player submission commits plan()'s next state; helper/takeout
## boxes do not create, consume or interrupt these player build mechanics.


static func profile(items: Array, capacity: int) -> Dictionary:
	var used := 0
	var real_items := 0
	var same_kind := -1
	var uniform := true
	var has_set := false
	var high_sets := 0
	for item in items:
		if bool(item.get("ghost", false)):
			continue
		var kind := int(item.get("kind", -1))
		used += maxi(0, int(item.get("cells", 0)))
		real_items += 1
		if real_items == 1:
			same_kind = kind
		elif kind != same_kind:
			uniform = false
		if bool(item.get("is_set", false)):
			has_set = true
			uniform = false
			if int(item.get("tier", 0)) >= 2:
				high_sets += 1
	var full := capacity > 0 and used >= capacity
	# A two-cell bowl can make a two-bowl platter; a lone large dish cannot.
	var mono_kind := same_kind if full and uniform and real_items >= 2 and same_kind >= 0 else -1
	return {"full": full, "free_cells": maxi(0, capacity - used), "used_cells": used,
		"real_items": real_items, "mono_kind": mono_kind, "has_set": has_set, "high_sets": high_sets}


static func plan(box: Dictionary, previous_mono_kind: int, cache_ready: bool,
		mono_bonus: float, cache_bonus: float, rotation_bonus: float) -> Dictionary:
	var mono_kind := int(box.get("mono_kind", -1)) if mono_bonus > 0.0 else -1
	var mono := mono_kind >= 0
	var rotation := mono and previous_mono_kind >= 0 and previous_mono_kind != mono_kind and rotation_bonus > 0.0
	var full := bool(box.get("full", false))
	var cache_consumed := cache_ready and full and cache_bonus > 0.0
	var cache_primed := not full and bool(box.get("has_set", false)) and int(box.get("free_cells", 0)) >= 2 and cache_bonus > 0.0 and not cache_ready
	var next_cache := cache_bonus > 0.0 and ((cache_ready and not cache_consumed) or cache_primed)
	var mono_add := maxf(0.0, mono_bonus) if mono else 0.0
	var cache_add := maxf(0.0, cache_bonus) if cache_consumed else 0.0
	var rotation_add := maxf(0.0, rotation_bonus) if rotation else 0.0
	return {"mono_kind": mono_kind, "combo_eligible": int(box.get("high_sets", 0)) >= 2 or mono,
		"add_bonus": mono_add + cache_add + rotation_add,
		"mono_bonus": mono_add, "cache_bonus": cache_add, "rotation_bonus": rotation_add,
		"cache_ready": next_cache, "cache_consumed": cache_consumed, "cache_primed": cache_primed,
		"rotation": rotation, "next_mono_kind": mono_kind}
