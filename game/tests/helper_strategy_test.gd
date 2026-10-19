extends Node
## Isolated real-policy probes. No GPU, autoplatform bot, or player save access.
const PROFILE := "helper_strategy"
var checks: Array = []
var failures := 0
var runs: Array = []
var sprites: Array = []

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	if not ok:
		failures += 1
		push_error(label)
	print(("PASS " if ok else "FAIL ") + label)

func configure(extra: Dictionary) -> void:
	Game.reset_save()
	Game.version = 4
	Game.levels = {"start":1}
	Game.levels.merge(extra,true)
	Game._recompute()

func fresh_run() -> CanteenRun:
	var run := CanteenRun.new()
	run._read_stats()
	runs.append(run)
	return run

func food(id: String, quality := 0, hot := false, ghost := false) -> int:
	return CanteenRun.make(CanteenRun.KIND[id],quality,hot,ghost)

func box(run: CanteenRun, items: Array = [], crew := false, role := "sweep") -> Dictionary:
	var b := run._new_basin(Vector2(500,900))
	b.items = items.duplicate()
	if crew:
		b.merge({"crew":true,"crew_id":"wen","crew_role":role,"crew_recipe":-1,"crew_needed":{}})
	return b

func helper(run: CanteenRun, id: String, role := "sweep", items: Array = [], target := -1, x := 500.0) -> Dictionary:
	var b := box(run,items,true,role)
	b.crew_id = id
	b.crew_recipe = target
	b.pos = Vector2(x,900)
	return {"id":id,"role":role,"recipe":target,"state":"catch","box":b,"x":x,"rest":x,
		"hop":0.0,"still":0.0,"n":items.size(),"wait":0.0,"seen":0,"cheer":0.0}

func add_dummy_sprite(c: Dictionary) -> void:
	var tex := GradientTexture2D.new()
	tex.width = 4
	tex.height = 4
	var spr := Sprite2D.new()
	spr.texture = tex
	c.merge({"spr":spr,"awake":tex,"sleep":tex,"run_tex":null,"cheer_tex":null})
	sprites.append(spr)

func falling(run: CanteenRun, dishes: Array) -> void:
	run._fp.clear()
	run._fv.clear()
	run._fk.clear()
	run._fg.clear()
	for d in dishes:
		run._fp.append(Vector2(d[0],700))
		run._fv.append(Vector2(0,100))
		run._fk.append(int(d[1]))
		run._fg.append(900)

func has_recipe(id: String) -> bool:
	return Game.helper_recipe_options().any(func(r): return r.id == id)

func test_data_and_configuration() -> void:
	check(Game.nodes.size() == 75,"same 75 nodes including root")
	check(Game.node("hire").parents == ["start"],"hire no longer forces automatic boxes")
	check(Game.node("clip").parents == ["hire"] and Game.node("sleep").parents == ["hire"],"global insurance needs recruitment, not nutrition or orchestration")
	check(Game.node("async").get("require_all",false),"async data requires all prerequisites")
	configure({"hire":1})
	Game.tokens = 1e9
	check(not Game.is_visible("async") and not Game.can_buy("async"),"recruitment alone cannot unlock Async")
	configure({"busy":1})
	Game.tokens = 1e9
	check(not Game.is_visible("async") and not Game.can_buy("async"),"appetite alone cannot unlock Async")
	Game.levels.hire = 1
	Game._recompute()
	check(Game.can_buy("async"),"both prerequisites permit Async")
	configure({"hire":2,"orch":2})
	check(is_equal_approx(Game.stat("crew_relay"),0.3) and is_equal_approx(Game.stat("helper_speed"),1.6),"orchestration adds relay while retaining speed")
	check(Game.active_helpers() == ["wen","pu"],"old missing helper config retains first N team")
	check(not Game.set_helper_config("ge",true,"sweep",""),"full roster rejects an extra member without evicting anyone")
	check(Game.set_helper_config("wen",false,"sweep","") and Game.set_helper_config("ge",true,"sweep",""),"one slot may select sixth character")
	check(Game.active_helpers() == ["pu","ge"],"free selection uses slot capacity, not recruitment order")
	Game.set_helper_config("pu",false,"sweep","")
	Game.set_helper_config("ge",false,"sweep","")
	check(Game.active_helpers().is_empty(),"all helpers can rest without default replacements")
	check(not Game.set_helper_config("unknown",true,"sweep","") and not Game.set_helper_config("wen",true,"unknown",""),"unknown character and role are rejected")
	check(not Game.set_helper_config("wen",true,"recipe","breakfast") and not Game.set_helper_config("wen",true,"nutrition",""),"locked roles cannot be assigned")
	configure({"hire":2,"fc":1,"nutri":1,"stall_main":1,"stall_wok":1,"stall_dim":2,"stall_fry":1,"menu":1})
	check(has_recipe("breakfast") and has_recipe("bento"),"reachable ordinary recipes are offered")
	check(not has_recipe("summer") and not has_recipe("stew"),"closed ingredients and stochastic special recipe are absent")
	check(Game.set_helper_config("wen",true,"recipe","breakfast"),"a helper accepts a chosen available recipe")
	Game.struck = ["youtiao"]
	check(not has_recipe("breakfast"),"banning one ingredient removes that recipe")
	var invalid := Game.helper_config("wen")
	check(invalid.role == "sweep" and invalid.requested_recipe == "breakfast" and not invalid.reason.is_empty(),"invalid order has explicit fallback while retaining requested target")
	check(not Game.set_helper_config("pu",true,"recipe","breakfast"),"cannot newly assign banned recipe")
	Game.struck = []
	check(Game.helper_config("wen").role == "recipe","restoring ingredients restores requested recipe")
	Game.levels.fc = 0
	Game._recompute()
	check(Game.helper_config("wen").role == "sweep" and not Game.helper_config("wen").reason.is_empty(),"refund of role skill falls back safely")
	Game.levels.fc = 1
	Game.levels.stall_dim = 1
	Game._recompute()
	check(not has_recipe("breakfast") and Game.helper_config("wen").role == "sweep","stall downgrade invalidates target instead of choosing an unrelated expensive meal")
	configure({"hire":1,"fc":1,"stall_main":1,"stall_wok":1,"stall_dim":1,"stall_fry":1,"stall_sweet":3})
	check(not has_recipe("deep"),"undiscovered hidden recipe is not revealed as an order")
	Game.recipes.deep = 1
	check(has_recipe("deep"),"discovered hidden recipe can be ordered when ingredients fit")
	var preview_recipes := Game.recipes.duplicate()
	Game.helper_recipe_options()
	check(Game.recipes == preview_recipes,"recipe assembly previews never discover food")
	# Six unrelated ingredients cannot merge until all arrive; 4 cells cannot assemble family.
	configure({"hire":1,"fc":1,"stall_main":1,"stall_wok":2,"stall_dim":3,"stall_fry":1,"stall_sweet":1})
	Game.recipes.family = 1
	check(not has_recipe("family"),"menu availability alone is insufficient: unassemblable family recipe is filtered")
	Game.levels.vram = 2
	Game._recompute()
	check(has_recipe("family"),"larger box makes the same family target genuinely assemblable")
	var options := Game.helper_recipe_options()
	options.clear()
	check(not Game.helper_recipe_options().is_empty(),"recipe-options cache returns a defensive copy")

func test_persistence_and_switches() -> void:
	configure({"hire":2,"fc":1,"nutri":1,"skills":1,"temp":1,"fuse3":1,"regen":1,"overfit":1,"bon":1,"warm":1,"stall_wok":1,"stall_dim":2})
	for key in Game.AUTOMATION_KEYS:
		check(Game.automation_enabled(key),"missing automation config keeps owned default: "+key)
	Game.set_helper_config("wen",false,"sweep","")
	Game.set_helper_config("ge",true,"nutrition","")
	Game.set_helper_config("pu",true,"recipe","breakfast")
	check(Game.set_automation("auto_push",false) and Game.automation_enabled("auto_return"),"empty delivery and full return are independent toggles")
	for key in ["fuse3","temp","regen","overfit","bon"]:
		check(Game.set_automation(key,false) and not Game.automation_enabled(key),"owned disruptive behavior can pause: "+key)
	check(not Game.set_automation("made_up",false),"unknown automation cannot be saved")
	Game.save_game()
	var team := Game.helper_plan.duplicate(true)
	var switches := Game.automation.duplicate(true)
	Game.helper_plan.clear()
	Game.automation.clear()
	Game.load_game()
	check(Game.helper_plan == team and Game.automation == switches,"team roles, recipe, rest and switches survive disk round-trip")
	check(Game.active_helpers() == ["pu","ge"],"chosen non-default team persists")
	var frozen := fresh_run()
	check(frozen.hired == ["pu","ge"] and frozen._helper_configs.pu.recipe == "breakfast","shift freezes selected team and chosen recipe")
	check(not frozen.auto_push and frozen.auto_return and frozen.temp == 0 and not frozen.fuse3 and frozen.regen == 0 and not frozen.overfit and not frozen.best_of_n,"shift reads all seven switches independently")
	var reserved := box(frozen, [food("leg", 2)])
	frozen._put_warm(reserved)
	var bulk := box(frozen, [food("leg", 1), food("leg", 1), food("leg", 1)])
	frozen._serve(bulk)
	check(is_same(frozen._warm, reserved) and frozen._queue.has(bulk),"paused Best-of-N preserves a deliberate high-single-bite reserve when a higher-total box arrives")
	Game.set_helper_config("pu",false,"sweep","")
	Game.set_automation("temp",true)
	Game.set_automation("bon",true)
	check(frozen.hired == ["pu","ge"] and frozen.temp == 0 and frozen._helper_configs.pu.recipe == "breakfast","between-meal edits cannot mutate an already-created run")
	var next := fresh_run()
	check(next.hired == ["ge"] and next.temp > 0,"new run sees updated configuration")
	check(not frozen.best_of_n and next.best_of_n,"Best-of-N edits affect only the next meal")
	next.regen = 0.0 # isolate selection, not random rerolls, in this branch fixture
	var next_reserve := box(next, [food("leg", 2)])
	next._put_warm(next_reserve)
	var next_bulk := box(next, [food("leg", 1), food("leg", 1), food("leg", 1)])
	next._serve(next_bulk)
	check(is_same(next._warm, next_bulk) and next._queue.has(next_reserve),"enabled Best-of-N retains its original highest-total-box behavior")
	Game.respec()
	check(Game.active_helpers().is_empty() and Game.helper_config("ge").role == "sweep","full refund safely disables team and unavailable nutrition role")
	check(not Game.automation_enabled("auto_return") and not Game.set_automation("auto_return",true),"unowned behavior cannot be enabled after refund")
	Game._load_helper_preferences({"helper_plan":{"wen":{"active":true,"role":"nonsense","recipe":123},"unknown":{"active":true}},"automation":{"temp":"false","auto_push":false,"unknown":true}})
	check(Game.helper_plan.keys() == ["wen"] and Game.helper_plan.wen.role == "sweep" and Game.helper_plan.wen.recipe == "","malformed preferences are bounded and normalized")
	check(Game.automation == {"auto_push":false},"only known boolean automation fields survive normalization")

func test_value_and_catches() -> void:
	configure({"hire":6,"grok":1,"aftertaste":4,"fp32":1,"hot":2})
	var run := fresh_run()
	check(run._helper_item_value(food("veg")) == 14,"training greens have useful future value before enlightenment")
	check(run._helper_item_value(food("leg",2,true)) == 60,"actual gold and heat affect helper value")
	check(run._helper_item_value(food("ji")) == 0,"glitch food is never a useful target")
	var c := helper(run,"wen")
	check(run._helper_accepts(c,food("veg")),"sweep accepts training greens with Grok owned")
	run.grok = false
	check(not run._helper_accepts(c,food("veg")),"sweep avoids uneatable greens without Grok or injection")
	run.grok = true
	run._crew = [c]
	check(is_same(run._crew_catch(Vector2(500,850),Vector2(500,950),Vector2(0,200),food("veg")),c.box),"real swept catch admits training greens")
	run._crew = [helper(run,"g")]
	check(run._crew_catch(Vector2(500,800),Vector2(500,850),Vector2(0,200),food("veg")) != null,"jump catch uses same green policy")
	run._crew = [helper(run,"pu")]
	var pulled := run._crew_tricks(Vector2(450,840),Vector2(0,100),food("veg"),0.1,false)
	check(pulled.x > 0,"magnet pulls accepted training greens")
	run._crew = [helper(run,"ke")]
	check(run._crew_floor(500,food("veg")) and run._crew[0].box.items.size() == 1,"floor pickup collects accepted training greens")
	run._crew = [helper(run,"ge")]
	check(run._crew_tricks(Vector2(490,860),Vector2(0,100),food("veg"),0.1,false) == Vector2(0,100),"swatter preserves greens")
	check(run._crew_tricks(Vector2(490,860),Vector2(0,100),food("ji"),0.1,false).y < 0,"swatter still rejects glitch food")
	run._hand = box(run)
	run._hand.pos = Vector2(500,700)
	check(run._crew_catch(Vector2(500,850),Vector2(500,950),Vector2(0,200),food("veg")) == null and not run._crew_floor(500,food("veg")),"helper catch and floor routes respect player column")
	run._hand = null
	var full := helper(run,"wen","sweep",[food("bun"),food("bun"),food("bun"),food("bun")])
	check(not run._helper_accepts(full,food("leg",2,true)),"highest value does not override box fit")
	falling(run,[[350,food("leg")],[650,food("leg",2,true)]])
	run._crew = [helper(run,"wen","sweep",[],-1,500)]
	run.helper_speed = 2
	check(is_equal_approx(run._plan_crew(900).wen,650),"sweep decision prefers actual gold-hot value at equal travel distance")

func test_recipes_and_decisions() -> void:
	configure({"hire":2,"fc":1,"stall_main":1,"stall_wok":1,"stall_dim":2,"stall_fry":1,"grok":1})
	var run := fresh_run()
	var target: int = CanteenRun.KIND.breakfast
	var c := helper(run,"wen","recipe",[food("soymilk")],target)
	check(run._helper_accepts(c,food("youtiao")) and not run._helper_accepts(c,food("leg",2,true)),"recipe role chooses missing ingredient over valuable unrelated food")
	check(not run._helper_accepts(c,food("soymilk")),"recipe role does not overcollect already-present ingredient")
	var ghost_missing := run._helper_recipe_missing(box(run,[food("soymilk",0,false,true)]),target)
	check(ghost_missing[CanteenRun.KIND.soymilk] == 1,"ghost food cannot satisfy recipe needs")
	var complete := [food("soymilk"),food("youtiao")]
	run._merge_items(complete)
	c.box.items = complete
	check(run._helper_ready_to_deliver(c) and not run._helper_accepts(c,food("youtiao")),"completed order ships immediately, even with empty cells")
	c.box.items = [food("soymilk")]
	c.still = 20.0
	check(not run._helper_ready_to_deliver(c),"incomplete recipe is not silently delivered as a timed-out miscellaneous box")
	var nested := [food("egg"),food("veg")]
	run._merge_items(nested)
	var missing := run._helper_recipe_missing(box(run,nested),CanteenRun.KIND.homestyle)
	check(missing[CanteenRun.I.BOWL] == 1 and missing[CanteenRun.I.VEG] == 0,"nested recipe ingredients reduce remaining base needs")
	var wrong := helper(run,"wen","recipe",[food("bun"),food("bun"),food("bun")],CanteenRun.KIND.bento)
	check(not run._helper_accepts(wrong,food("ball")),"matching ingredient rejected when contaminated cargo leaves no assembly route")
	var left := helper(run,"wen","recipe",[food("ball"),food("veg")],CanteenRun.KIND.bento,500)
	var right := helper(run,"pu","recipe",[food("soymilk")],target,520)
	run._crew = [left,right]
	run.helper_speed = 2
	falling(run,[[350,food("youtiao")],[680,food("leg")]])
	var plan := run._plan_crew(900)
	check(is_equal_approx(plan.wen,680) and is_equal_approx(plan.pu,350),"crossing destinations stay with their assigned recipes; spreading never swaps tasks")
	# Protected order cargo must survive owned random/fusion behaviors.
	run.temp = 1.0
	run.overfit = true
	run.fuse3 = true
	run._grokked = true
	var protected := helper(run,"wen","recipe",[],target)
	run._catch(protected.box,food("soymilk"),false)
	check(CanteenRun.K(protected.box.items[0]) == CanteenRun.KIND.soymilk,"recipe duty preserves specified ingredients despite random behavior settings")
	run._crew.clear()
	var all_orders: Array = []
	for i in Game.HELPER_IDS.size():
		var x := 150.0 + i * 200.0
		run._crew.append(helper(run,Game.HELPER_IDS[i],"recipe",[food("soymilk")],target,x))
		all_orders.append([x,food("youtiao")])
	falling(run,all_orders)
	var six := run._plan_crew(900)
	var distinct := {}
	for x in six.values():
		distinct[x] = true
	check(six.size() == 6 and distinct.size() == 6,"six helpers sharing one recipe receive distinct reachable ingredients")
	run._crew = []
	run.spec = 1.0 # isolate the proc branch, not a purchasable 100% probability
	Game.recipes.egg_veg = 1 # this fixture tests policy, not discovery audiovisual effects
	Game.recipes.homestyle = 1
	var chained := helper(run,"wen","recipe",[food("egg")],CanteenRun.KIND.homestyle)
	run._catch(chained.box,food("veg"),false)
	check(CanteenRun.find_kind(chained.box.items,CanteenRun.KIND.homestyle) >= 0,"Speculative Decoding completes the assigned recipe instead of disabling its positive synergy")

func test_nutrition() -> void:
	configure({"hire":2,"nutri":1,"grok":1,"drift":1})
	var run := fresh_run()
	run._cat = {"主":0.0,"荤":0.0,"素":0.0}
	var shared := box(run,[food("ball")],true)
	run._queue = [shared]
	run._flying = [{"basin":shared}]
	run._crew = [helper(run,"wen")]
	run._crew[0].box = shared
	run._hand = box(run,[food("leg")])
	run._eating = box(run,[food("veg")])
	run._warm = box(run,[food("potato")])
	var projected := run._projected_nutrition()
	check(projected["主"] == 1 and projected["荤"] == 1 and projected["素"] == 2,"nutrition includes queued/flight/cargo once plus hand/eating/warm food")
	run._grokked = true
	var drifted := run._projected_nutrition()
	check(drifted["荤"] == 1.5 and drifted["素"] == 1.5,"post-grok projected greens follow actual drift nutrition")
	run._queue = []
	run._flying = []
	run._hand = null
	run._eating = null
	run._warm = null
	run._grokked = false
	run._cat = {"主":4.0,"荤":3.0,"素":2.0}
	run._crew = [helper(run,"wen","nutrition",[],-1,450),helper(run,"pu","nutrition",[],-1,650)]
	run.helper_speed = 2
	falling(run,[[300,food("potato")],[500,food("fries")],[800,food("ball")]])
	var plan := run._plan_crew(900)
	var destinations: Array = plan.values()
	check(destinations.has(800.0) and (destinations.has(300.0) or destinations.has(500.0)),"first nutrition reservation updates deficits before second helper chooses")
	var c := helper(run,"wen","nutrition")
	check(run._helper_accepts(c,food("potato"),{"主":4.0,"荤":3.0,"素":2.0}) and not run._helper_accepts(c,food("leg"),{"主":4.0,"荤":3.0,"素":2.0}),"nutrition duty filters actual deficit rather than applying a cosmetic bonus")
	var delivered: Dictionary = c.box
	run._crew = [c]
	run._cat = {"主":10.0,"荤":10.0,"素":0.0}
	run._catch(delivered,food("potato"),false)
	run._catch(delivered,food("potato"),false)
	check(float(delivered.crew_needed.get("素",0)) == 2.0,"real nutrition catches record the category that was needed")

func test_ge_inspection() -> void:
	configure({"hire":1,"grok":1,"stall_wok":1})
	var run := fresh_run()
	var ge := helper(run,"ge")
	run._catch(ge.box,food("veg"),false)
	run._catch(ge.box,food("veg"),false)
	check(CanteenRun.grade(ge.box.items[0]) == 1 and CanteenRun.grade(ge.box.items[1]) == 0,"Ge upgrades a training green, exactly once per box")
	var next_box := helper(run,"ge")
	run._catch(next_box.box,food("leg"),false)
	check(CanteenRun.grade(next_box.box.items[0]) == 1,"Ge gets a fresh inspection on a new box")
	var other := helper(run,"wen")
	run._catch(other.box,food("leg"),false)
	check(CanteenRun.grade(other.box.items[0]) == 0,"inspection belongs to Ge, not every helper")
	for skipped in [food("leg",1),food("leg",2),food("leg",0,false,true),food("breakfast"),food("ji")]:
		var protected := helper(run,"ge")
		run._catch(protected.box,skipped,false)
		run._catch(protected.box,food("potato"),false)
		check(protected.box.items[0] == skipped and CanteenRun.grade(protected.box.items.back()) == 1,"silver/gold/ghost/set/glitch does not spend inspection: "+str(skipped))
	var order := helper(run,"ge","recipe",[],CanteenRun.KIND.egg_veg)
	Game.recipes.egg_veg = 1
	run._catch(order.box,food("veg"),false)
	run._catch(order.box,food("egg"),false)
	check(order.box.items.size() == 1 and CanteenRun.K(order.box.items[0]) == CanteenRun.KIND.egg_veg and CanteenRun.raw_of(order.box.items[0]) == 5.0,"Ge's silver ingredient value survives recipe merge")

func test_queue_relay_and_budget() -> void:
	configure({"hire":6,"orch":2,"busy":1,"async":1,"prompt":3,"multiturn":1})
	var run := fresh_run()
	var a := box(run,[food("leg")],true)
	a.tag = "crew1"
	var b := box(run,[food("bun")])
	b.tag = "player1"
	var c := box(run,[food("leg")],true)
	c.tag = "crew2"
	var d := box(run,[food("bun")])
	d.tag = "player2"
	run.async_feed = false
	run._queue = [a,b,c,d]
	var order: Array = []
	for i in 4:
		order.append(run._pop_next_box().tag)
	check(order == ["crew1","player1","crew2","player2"],"default table queue is FIFO")
	run.async_feed = true
	run._queue = [a,b,c,d]
	order.clear()
	for i in 4:
		order.append(run._pop_next_box().tag)
	check(order == ["player1","player2","crew1","crew2"],"Async prioritizes player boxes with FIFO inside each group")
	run._crave_t = 7.0
	run._start_box(a)
	check(a.mult == 1.0 and run._crave_t == 7.0,"helper meal neither earns nor consumes saved appetite")
	run._start_box(b)
	check(b.mult > 1.0 and run._crave_t == 0.0,"player meal consumes saved appetite")
	var weak := box(run,[food("leg"),food("bun",0,false,true)],true)
	check(not run._award_helper_relay(weak),"one useful item plus ghost cannot farm sweep relay")
	var sweep := box(run,[food("leg"),food("bun")],true)
	check(run._award_helper_relay(sweep) and not run._award_helper_relay(sweep),"valid sweep grants exactly one relay charge")
	check(not run._award_helper_relay(box(run,[food("leg"),food("bun")],true)),"same role cannot stack additional charges")
	var meal := [food("soymilk"),food("youtiao")]
	run._merge_items(meal)
	var recipe := box(run,meal,true,"recipe")
	recipe.crew_recipe = CanteenRun.KIND.breakfast
	check(run._award_helper_relay(recipe),"completed specified recipe grants independent relay")
	var fake_order := box(run,[food("leg"),food("leg")],true,"recipe")
	fake_order.crew_recipe = CanteenRun.KIND.breakfast
	check(not run._award_helper_relay(fake_order),"uncompleted order cannot claim recipe relay")
	var nutrition := box(run,[food("potato"),food("potato")],true,"nutrition")
	nutrition.crew_needed = {"素":2.0}
	check(run._award_helper_relay(nutrition),"two portions of actually-needed nutrition grant third charge")
	check(run._helper_relay.size() == 3,"relay is bounded to three different roles")
	var combo_before := run._combo_n
	run._note_served(recipe)
	check(run._combo_n == combo_before and run._helper_relay.size() == 3,"helper submission never consumes relay or advances player combo")
	var empty := box(run)
	check(run._consume_helper_relay(empty) == 0 and run._helper_relay.size() == 3,"empty box cannot spend charges")
	var player := box(run,[food("leg")])
	check(is_equal_approx(run._consume_helper_relay(player),0.9) and run._helper_relay.is_empty(),"next nonempty player box spends all role charges at 30% each")
	check(run._consume_helper_relay(player) == 0 and run._combo_n == combo_before,"relay consumption is once-only and does not invent combo progress")
	run._start_box(player)
	check(is_equal_approx(player.mult,1.9),"earned relay feeds the actual box multiplier additively")
	var bad_nutrition := box(run,[food("leg"),food("leg")],true,"nutrition")
	bad_nutrition.crew_needed = {"素":2.0}
	check(not run._award_helper_relay(bad_nutrition),"unneeded cargo cannot claim nutrition relay")
	# Count every reserved helper box once; currently eaten box has released its slot.
	run._crew = [helper(run,"wen")]
	var reserved: Dictionary = run._crew[0].box
	run._queue = [reserved,box(run,[food("bun")])]
	run._flying = [{"basin":reserved},{"basin":box(run,[food("leg")],true)}]
	run._warm = box(run,[food("leg")],true)
	run._eating = box(run,[food("leg")],true)
	check(run._helper_box_count() == 3,"reservation counter deduplicates collection/flight/queue aliases and includes warmer, excludes player/eating")
	run._crew.clear()
	run._queue.clear()
	run._flying.clear()
	run._warm = null
	run._eating = null
	for id in Game.HELPER_IDS:
		var h := helper(run,id)
		h.box = null
		h.state = "fetch"
		h.wait = 1.0
		add_dummy_sprite(h)
		run._crew.append(h)
	var empty_before := run._empty
	run._update_crew(0.01)
	check(run._crew.all(func(h): return h.box != null) and run._helper_box_count() == 6,"six selected helpers can all reserve boxes within max(3,team) budget")
	check(run._empty == empty_before,"helper reservations never take player boxes")
	# One vacant reservation: the longest-waiting member must win, not fixed array order.
	for i in [0,5]:
		run._crew[i].box = null
		run._crew[i].state = "fetch"
		run._crew[i].wait = 1.0 if i == 0 else 10.0
	run._queue = [box(run,[food("leg")],true)]
	run._update_crew(0.01)
	check(run._crew[5].box != null and run._crew[0].box == null and run._helper_box_count() == 6,"longest wait wins limited reservation; no fixed-order starvation or over-budget allocation")

## Real closing-time scoring, not a replacement/stub for _end or its multiplier rules.
## A real FishRig satisfies the presentation endpoint; no _ready/GPU scene is needed.
func settlement_run() -> CanteenRun:
	var run := fresh_run()
	run._fish = FishRig.new()
	run.add_child(run._fish)
	return run

func test_relay_and_leftover_settlement() -> void:
	# These independent endings would otherwise start/replace several audio streams in
	# one engine frame. Let the real audio server mix between settlement scenarios.
	await get_tree().create_timer(0.12,true,false,true).timeout
	configure({"hire":1,"orch":2,"ocr":1,"warm":1})
	var normal := settlement_run()
	check(normal._award_helper_relay(box(normal,[food("ball"),food("ball")],true)),"settlement setup earns a real sweep relay")
	var served := box(normal,[food("ball")])
	normal._note_served(served)
	normal._queue.append(served)
	var wallet_before := Game.tokens
	normal._update_fish(0.0,1.0) # Actual queue selection and initial eating animation.
	normal._update_fish(0.0,1.0) # Actual bite, income attribution, and empty-box return.
	var normal_expected := normal._g * (1.0 + normal.box_bonus + 0.3)
	check(is_equal_approx(served.mult,1.5) and normal._eating == null,"ordinary delivered box eats with relay exactly once")
	check(is_equal_approx(normal.earned,normal_expected) and is_equal_approx(Game.tokens-wallet_before,normal_expected),"ordinary relay reaches actual credited income")
	check(is_equal_approx(float(served.rule_share),0.3/1.5) and is_equal_approx(normal._rule_income,normal._g*0.3),"ordinary rule_share includes exactly the earned relay contribution")
	await get_tree().create_timer(0.12,true,false,true).timeout
	normal._end("提前下班",false)
	check(is_equal_approx(normal.earned,normal_expected),"ordinary closing does not credit a consumed relay box twice")
	await get_tree().create_timer(0.12,true,false,true).timeout

	configure({"hire":1,"orch":2,"ocr":1,"warm":1})
	var kept := settlement_run()
	kept._award_helper_relay(box(kept,[food("ball"),food("ball")],true))
	var warm_box := box(kept,[food("ball")])
	kept._put_warm(warm_box) # Actual submission consumes/fixes the charge before closing.
	check(is_equal_approx(float(warm_box.get("crew_relay_bonus",0.0)),0.3) and kept._helper_relay.is_empty(),"putting a player box in the warmer freezes and consumes its earned relay")
	wallet_before = Game.tokens
	kept._end("提前下班",false)
	var warm_expected := normal_expected * kept.warm_x
	check(is_equal_approx(float(kept._score.get("warm",0.0)),warm_expected),"real _end warmer settlement includes relay in its additive pool")
	check(is_equal_approx(kept.earned,warm_expected) and is_equal_approx(Game.tokens-wallet_before,warm_expected),"warmer relay reaches actual credited income")
	check(is_equal_approx(kept._rule_income,kept._g*0.3*kept.warm_x),"warmer attribution credits relay share after the warm multiplier")
	kept._end("提前下班",false)
	check(is_equal_approx(Game.tokens-wallet_before,warm_expected) and Game.runs == 1,"repeated close cannot consume or pay the warm relay again")
	await get_tree().create_timer(0.12,true,false,true).timeout

	configure({"hire":1,"sleep":1,"warm":1,"ocr":1})
	var closing := settlement_run()
	var reserved := box(closing,[food("ball")])
	closing._put_warm(reserved)
	var shared := box(closing,[food("ball")])
	var equal_a := box(closing,[food("ball")])
	var equal_b := box(closing,[food("ball")])
	var hand := box(closing,[food("ball")])
	var cargo := box(closing,[food("ball")],true)
	closing._queue = [reserved,shared,equal_a,shared]
	closing._eating = shared
	closing._hand = hand
	closing._flying = [{"basin":reserved},{"basin":shared},{"basin":equal_b},{"basin":null}]
	closing._crew = [{"box":reserved},{"box":cargo},{"box":null}]
	var leftovers: Array = closing._leftover_boxes()
	check(leftovers.size() == 5 and leftovers.filter(func(b): return is_same(b,shared)).size() == 1,"leftovers deduplicate queue/eating/hand/flight/crew by identity and exclude the warmer")
	check(leftovers.any(func(b): return is_same(b,equal_a)) and leftovers.any(func(b): return is_same(b,equal_b)),"equal-content but distinct boxes are both retained for settlement")
	wallet_before = Game.tokens
	closing._end("提前下班",false)
	var closed_warm := closing._g * 1.2 * closing.warm_x
	var closed_sleep := closing._g * 5.0 * 0.5
	check(is_equal_approx(float(closing._score.get("sleep",0.0)),closed_sleep),"real sleep settlement pays every remaining box including in-flight food exactly once")
	check(is_equal_approx(float(closing._score.get("warm",0.0)),closed_warm) and is_equal_approx(closing.earned,closed_warm+closed_sleep),"warm aliases cannot be eaten again by sleep after the warmer is cleared")
	check(is_equal_approx(Game.tokens-wallet_before,closed_warm+closed_sleep) and closing.eaten == 6,"wallet and eaten count agree with one warm portion plus five unique leftovers")
	check([shared,equal_a,equal_b,hand,cargo].all(func(b): return b.items.is_empty()) and closing._hand == null,"sleep consumes the actual referenced in-flight and remaining cargo")
	await get_tree().create_timer(0.12,true,false,true).timeout

	configure({"hire":1,"sleep":1,"ocr":2,"stream":2,"hot":2,"fp32":1})
	var value_run := settlement_run()
	var premium := food("ball",2,true)
	var transit := box(value_run,[premium],true)
	transit.mult = 99.0
	transit.chain_multiplier = 99.0
	transit.crew_relay_bonus = 0.9
	value_run._flying = [{"basin":transit}]
	value_run._bites = 100 # Mid-shift stream state; sleep must ignore it and box multipliers.
	var half_raw := value_run._item_value(premium) * value_run._g * 0.5
	check(value_run._stream_mult() > 1.0 and is_equal_approx(value_run._item_value(premium),10.0),"premium sleep fixture has real FP32 gold/hot value and an active stream multiplier")
	value_run._end("提前下班",false)
	check(is_equal_approx(float(value_run._score.get("sleep",0.0)),half_raw),"in-flight sleep retains gold and heat value but excludes stream, box, chain and relay bonuses")
	await get_tree().create_timer(0.12,true,false,true).timeout

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile="+PROFILE) or not Game.save_path.begins_with("user://qa_"):
		push_error("Refusing helper strategy test outside isolated profile")
		get_tree().quit(2)
		return
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	CanteenRun.load_menu()
	seed(20261019)
	test_data_and_configuration()
	test_persistence_and_switches()
	test_value_and_catches()
	test_recipes_and_decisions()
	test_nutrition()
	test_ge_inspection()
	test_queue_relay_and_budget()
	await test_relay_and_leftover_settlement()
	check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before,"player settings remain byte-identical")
	var report := {"checks":checks,"check_count":checks.size(),"failures":failures,"scope":"Headless real-policy fixtures; not human play, visual quality or build balance evidence","hashes":{}}
	for path in ["res://scripts/autoload/game.gd","res://scripts/run/canteen_run.gd","res://scripts/run/meal_rules.gd","res://data/skill_tree.json","res://tests/helper_strategy_test.gd"]:
		report.hashes[path] = FileAccess.get_sha256(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../build/qa/helper-strategy"))
	# Keep the original 113-check report bound to its original source hashes.
	var file := FileAccess.open("res://../build/qa/helper-strategy/strategy-settlement-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	Game.reset_save()
	for run in runs:
		run.free()
	for spr in sprites:
		spr.free()
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.12,true,false,true).timeout
	print("HELPER_STRATEGY_TEST: %d checks, %d failures" % [checks.size(),failures])
	get_tree().quit(failures)
