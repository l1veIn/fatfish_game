extends Node
## Real Game/CanteenRun rules under an isolated profile. No production methods replaced.
const PROFILE := "progression_layout"
const OUTPUT := "res://../build/qa/stall-layout"
const DEFAULT_ORDER := ["dim","wok","main","fry","sweet"]
const SWAPPED := ["sweet","main","fry","dim","wok"]
var checks: Array = []
var failures := 0
var runtime: CanteenRun
var changed_count := 0

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	if not ok:
		failures += 1
		push_error(label)
	print(("PASS " if ok else "FAIL ") + label)

func fresh(version := 4) -> void:
	Game.reset_save()
	Game.version = version
	Game.tokens = 10000000000.0
	Game._recompute()

func buy_levels(id: String, n: int) -> Array:
	var paid: Array = []
	for i in n:
		var before := Game.tokens
		if not Game.buy(id):
			check(false,"fixture could not purchase %s level %d" % [id,i+1])
			break
		paid.append(before-Game.tokens)
	return paid

func total(values: Array) -> float:
	var out := 0.0
	for v in values:
		out += float(v)
	return out

func player_save_fingerprint() -> Dictionary:
	var out := {}
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = "user://save.json"+suffix
		out[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return out

func test_refunds() -> void:
	fresh()
	var original := Game.tokens
	var eat_paid := buy_levels("eat",3)
	var stream_paid := buy_levels("stream",1)
	check(Game.refund_floor("eat") == 1 and Game.refund_dependents("eat") == ["stream"],"purchased direct child sets parent refund floor to one")
	var before := Game.tokens
	var back: float = Game.refund("eat")
	check(is_equal_approx(back,total(eat_paid.slice(1))) and is_equal_approx(Game.tokens-before,back),"parent refund returns precisely the higher levels actually paid")
	check(Game.level("eat") == 1 and Game.level("stream") == 1 and Game.is_visible("stream"),"parent retains level one and purchased child remains usable")
	check(is_equal_approx(Game.stat("eat_rate"),float(Game.BASE.eat_rate)*1.25),"retained parent level is reflected in recomputed gameplay stats")
	before = Game.tokens
	check(Game.refund("eat") == 0.0 and Game.tokens == before,"repeated protected-parent refunds cannot create currency")
	check(is_equal_approx(Game.refund("stream"),total(stream_paid)) and Game.level("stream") == 0,"leaf refund removes all levels at exact purchase prices")
	check(Game.refund_floor("eat") == 0 and Game.refund_dependents("eat").is_empty(),"removing last child releases the parent floor")
	check(is_equal_approx(Game.refund("eat"),float(eat_paid[0])) and Game.tokens == original,"final parent refund completes an exact money round trip")
	check(Game.refund("eat") == 0.0 and Game.refund("stream") == 0.0 and Game.tokens == original,"already-refunded nodes cannot pay a second time")
	check(Game.refund("start") == 0.0 and Game.refund("unknown") == 0.0,"root and unknown IDs cannot be refunded")

	fresh()
	buy_levels("eat",1)
	var branching_paid := buy_levels("stream",3)
	buy_levels("ttft",1)
	buy_levels("mtp",1)
	var dependents: Array = Game.refund_dependents("stream")
	dependents.sort()
	check(dependents == ["mtp","ttft"],"all purchased direct dependents are reported")
	check(is_equal_approx(Game.refund("stream"),total(branching_paid.slice(1))) and Game.level("stream") == 1,"branching parent also refunds only excess levels")
	Game.refund("ttft")
	check(Game.refund_floor("stream") == 1 and Game.refund("stream") == 0.0,"one remaining purchased sibling still protects its parent")
	Game.refund("mtp")
	check(Game.refund_floor("stream") == 0 and is_equal_approx(Game.refund("stream"),float(branching_paid[0])),"last sibling removal makes remaining parent level refundable")

	fresh()
	buy_levels("stall_main",1)
	buy_levels("stall_wok",1)
	buy_levels("menu",1)
	buy_levels("sft",1)
	buy_levels("lora",1)
	check(not Game.node("lora").get("require_all",false) and Game.node("lora").parents.size() == 2,"multi-parent OR fixture uses the production LoRA dependency")
	check(Game.refund_floor("menu") == 1 and Game.refund_floor("sft") == 1,"purchased OR child protects both purchased parents even when either would suffice")
	before = Game.tokens
	check(Game.refund("menu") == 0.0 and Game.refund("sft") == 0.0 and Game.tokens == before,"OR alternatives cannot bypass protection to refund an active parent")
	Game.refund("lora")
	check(Game.refund_floor("menu") == 0 and Game.refund_floor("sft") == 0,"removing OR child releases both parents")

	fresh()
	original = Game.tokens
	var hire_paid := buy_levels("hire",2)
	var busy_paid := buy_levels("busy",2)
	var async_paid := buy_levels("async",1)
	check(Game.node("async").get("require_all",false) and Game.refund_floor("hire") == 1 and Game.refund_floor("busy") == 1,"AND dependency protects both required parents")
	check(is_equal_approx(Game.refund("hire"),float(hire_paid[1])) and is_equal_approx(Game.refund("busy"),float(busy_paid[1])),"AND parents each refund only the actually-paid excess level")
	check(Game.is_visible("async") and Game.level("async") == 1,"protected AND child keeps both prerequisites after refunds")
	Game.levels.ticket_r1 = 1 # A released version ticket is retained by full rollback.
	Game._recompute()
	var rollback_expected := float(hire_paid[0])+float(busy_paid[0])+total(async_paid)
	check(is_equal_approx(Game.respec(),rollback_expected) and Game.tokens == original,"full rollback still refunds protected skills exactly once")
	check(Game.level("start") == 1 and Game.level("ticket_r1") == 1 and Game.version == 4 and Game.level("async") == 0,"full rollback retains root, version ticket and release progress")
	check(Game.respec() == 0.0 and Game.refund("ticket_r1") == 0.0 and Game.tokens == original,"repeated rollback and ticket refunds cannot create currency")
	check(Game.buy("hire") and Game.active_helpers().size() == 1,"ordinary progression still works after full rollback")

func test_preview() -> void:
	fresh(0)
	check(Game.is_visible("eat") and not Game.is_preview("eat"),"normally visible first-layer skills are not blank previews")
	check(not Game.is_visible("stream") and Game.is_preview("stream"),"one visible unpurchased parent exposes its immediate blank preview")
	check(not Game.is_preview("ttft") and not Game.is_preview("mtp"),"preview nodes never recursively expose their children")
	var before := Game.tokens
	check(not Game.can_buy("stream") and not Game.buy("stream") and Game.tokens == before and Game.level("stream") == 0,"blank preview cannot leak purchase eligibility or debit money")
	for release in [0,1,4]:
		Game.version = release
		var definitions_ok := true
		var purchases_blocked := true
		for node in Game.nodes:
			var expected: bool = not Game.is_visible(node.id) and node.parents.any(func(p): return Game.is_visible(p))
			definitions_ok = definitions_ok and Game.is_preview(node.id) == expected
			if expected:
				purchases_blocked = purchases_blocked and not Game.can_buy(node.id) and not Game.buy(node.id)
		check(definitions_ok,"all 75 nodes follow exactly one normal-visible-parent preview layer at release %d" % release)
		check(purchases_blocked and Game.tokens == before,"preview purchases remain blocked across release %d" % release)
	buy_levels("eat",1)
	check(Game.is_visible("stream") and not Game.is_preview("stream") and Game.is_preview("ttft"),"buying the parent advances normal visibility and preview by one layer")
	buy_levels("hire",1)
	check(Game.is_preview("async") and not Game.is_visible("async") and not Game.can_buy("async"),"partial AND prerequisites permit only a blank preview")
	buy_levels("busy",1)
	check(Game.is_visible("async") and not Game.is_preview("async") and Game.can_buy("async"),"both AND prerequisites restore ordinary purchase eligibility")
	check(not Game.is_preview("unknown"),"unknown IDs do not become previews")

func write_save(data: Dictionary) -> void:
	assert(Game.save_path == "user://qa_%s.json" % PROFILE)
	var file := FileAccess.open(Game.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func test_stall_preferences() -> void:
	fresh()
	check(Game.DEFAULT_STALL_ORDER == DEFAULT_ORDER and Game.active_stall_order() == DEFAULT_ORDER,"new profile keeps the original five-window ordering")
	Game.runs = 2
	Game.levels.stall_wok = 1
	Game._recompute()
	check(not Game.stall_layout_intro_due(),"layout guidance waits until at least three completed meals")
	Game.runs = 3
	check(Game.stall_layout_intro_due(),"three completed meals with two open stalls makes guidance eligible")
	Game.levels.erase("stall_wok")
	Game._recompute()
	check(not Game.stall_layout_intro_due(),"guidance remains unnecessary with only one open stall")
	Game.levels.stall_wok = 1
	Game._recompute()
	changed_count = 0
	var notify_change := func(): changed_count += 1
	Game.changed.connect(notify_change)
	var supplied := SWAPPED.duplicate()
	check(Game.set_stall_order(supplied) and changed_count == 1,"complete legal permutation is persisted and emits changed")
	check(not Game.stall_layout_intro_due(),"explicitly choosing a layout suppresses repeat introduction")
	supplied[0] = "unknown"
	check(Game.active_stall_order() == SWAPPED,"saved order does not alias the caller's input array")
	var returned: Array = Game.active_stall_order()
	returned.reverse()
	check(Game.active_stall_order() == SWAPPED,"active order is a defensive copy")
	var before := FileAccess.get_file_as_bytes(Game.save_path)
	for invalid in [[],["main"],["dim","wok","main","fry","fry"],["dim","wok","main","fry","unknown"],["dim","wok","main","fry","sweet","main"],["dim","wok","main","fry",9]]:
		check(not Game.set_stall_order(invalid) and Game.active_stall_order() == SWAPPED,"invalid permutation is rejected atomically: %s" % str(invalid))
	check(changed_count == 1 and FileAccess.get_file_as_bytes(Game.save_path) == before,"rejected edits neither emit changed nor overwrite saved preferences")
	Game.changed.disconnect(notify_change)
	Game.stall_order = DEFAULT_ORDER.duplicate()
	Game.load_game()
	check(Game.active_stall_order() == SWAPPED,"custom layout survives actual save/load")
	check(not Game.stall_layout_intro_due(),"seen guidance preference persists with the layout")
	buy_levels("eat",2)
	Game.respec()
	check(Game.active_stall_order() == SWAPPED,"full skill rollback preserves the user's layout preference")
	Game.load_game()
	check(Game.active_stall_order() == SWAPPED,"rollback preserves the layout on disk as well")
	Game.reset_save()
	check(Game.active_stall_order() == DEFAULT_ORDER,"reset save restores the default layout")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(int(base.version) == Game.SAVE_VERSION,"optional layout field does not bump or break the save schema")
	base.erase("stall_order")
	Game.stall_order = SWAPPED.duplicate()
	write_save(base)
	Game.load_game()
	check(Game.active_stall_order() == DEFAULT_ORDER,"old schema-3 save without layout replaces stale memory with default")
	for malformed in [null,"main",{},["dim"],["dim","wok","main","fry","fry"],["dim","wok","main","fry",false]]:
		var bad := base.duplicate(true)
		bad.stall_order = malformed
		Game.stall_order = SWAPPED.duplicate()
		write_save(bad)
		Game.load_game()
		check(Game.active_stall_order() == DEFAULT_ORDER,"malformed saved layout safely falls back to default: %s" % str(malformed))
	Game.stall_order = ["main","main"]
	check(Game.active_stall_order() == DEFAULT_ORDER,"runtime invalid layout cannot escape through the public getter")
	Game.reset_save()

func arm_counts(run: CanteenRun) -> Dictionary:
	var out := {}
	for a in run._arms:
		out[a.stall] = int(out.get(a.stall,0))+1
	return out

func test_runtime_readiness_and_intro() -> void:
	fresh()
	Game.set_stall_order(DEFAULT_ORDER)
	var early := CanteenRun.new()
	early.autotest = true
	get_tree().paused = true
	check(not early.apply_stall_order(SWAPPED) and Game.active_stall_order() == DEFAULT_ORDER,"off-tree uninitialized runs reject layout edits without touching preferences")
	var attempt := {"called":false,"ready":true,"accepted":true,"unchanged":false}
	var disk_before := FileAccess.get_file_as_bytes(Game.save_path)
	early.tree_entered.connect(func():
		attempt.called = true
		attempt.ready = early.is_node_ready()
		attempt.accepted = early.apply_stall_order(SWAPPED)
		attempt.unchanged = Game.active_stall_order() == DEFAULT_ORDER and FileAccess.get_file_as_bytes(Game.save_path) == disk_before)
	add_child(early) # Exercise the real enter-tree/ready lifecycle, not a readiness stub.
	early.process_mode = Node.PROCESS_MODE_DISABLED
	check(attempt.called and not attempt.ready and not attempt.accepted and attempt.unchanged,"in-tree but not-ready lifecycle callback cannot apply or save a premature swap")
	early.free()
	get_tree().paused = false
	await get_tree().process_frame

	fresh()
	Game.runs = 3
	Game.levels.stall_wok = 1
	Game._recompute()
	var intro := CanteenRun.new()
	intro._read_stats()
	intro.autotest = true
	intro._maybe_stall_layout_intro()
	check(intro._banners.is_empty() and not Game.seen_buttons.has("intro_stall_layout"),"automatic tests cannot consume or display the layout introduction")
	intro.autotest = false
	intro.trial = "r1"
	intro._maybe_stall_layout_intro()
	check(intro._banners.is_empty() and not Game.seen_buttons.has("intro_stall_layout"),"trial runs cannot consume or display the layout introduction")
	intro.trial = ""
	intro._coach = RunCoach.new()
	intro._maybe_stall_layout_intro()
	check(intro._learning() and intro._banners.is_empty() and not Game.seen_buttons.has("intro_stall_layout"),"active real RunCoach defers layout introduction until teaching ends")
	intro._coach.active = false
	intro._maybe_stall_layout_intro()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(intro._banners.size() == 1 and bool(saved.seen_buttons.get("intro_stall_layout",false)),"eligible normal run records one real banner and persists its seen mark")
	intro._maybe_stall_layout_intro()
	check(intro._banners.size() == 1 and not get_tree().paused,"layout introduction is once-only and does not interrupt play with a pause")
	intro._coach.free()
	intro.free()

func test_failed_apply(run: CanteenRun) -> void:
	var arms_before := run._arms.duplicate(true)
	var disk_before := FileAccess.get_file_as_bytes(Game.save_path)
	Game.seen_buttons.erase("intro_stall_layout")
	var seen_before := Game.seen_buttons.duplicate(true)
	var observed := {"changed":0,"errors":[]}
	var on_change := func(): observed.changed += 1
	var on_failure := func(message): observed.errors.append(message)
	Game.changed.connect(on_change)
	Game.save_failed.connect(on_failure)
	# This is the real save guard used for future-format saves, not a replacement save method.
	Game._save_read_only = true
	var expected := "This save belongs to a newer game version; it has not been overwritten."
	print("EXPECTED_WARNING: "+expected)
	var accepted := run.apply_stall_order(SWAPPED)
	Game._save_read_only = false
	Game.changed.disconnect(on_change)
	Game.save_failed.disconnect(on_failure)
	check(not accepted and observed.errors == [expected] and observed.changed == 0,"real save rejection makes apply fail and emits only save_failed, never changed")
	check(run.stall_order == DEFAULT_ORDER and Game.active_stall_order() == DEFAULT_ORDER and run._arms == arms_before,"failed save leaves runtime mapping, ladle state and global preferences unchanged")
	check(Game.seen_buttons == seen_before and FileAccess.get_file_as_bytes(Game.save_path) == disk_before,"failed save restores absent introduction mark and preserves previous save bytes")

func test_runtime_apply() -> void:
	fresh()
	Game.levels = {"start":1,"stall_wok":1,"stall_dim":1,"stall_fry":1,"conc":3,"hire":1}
	Game.seen_buttons = {"intro_canteen_complete":true,"intro_think":true}
	Game._recompute()
	Game.set_stall_order(DEFAULT_ORDER)
	runtime = CanteenRun.new()
	runtime.autotest = true # No teaching flow or simulated-input ticks; _ready is real.
	add_child(runtime)
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	check(runtime.stall_order == DEFAULT_ORDER and runtime._arms.size() == runtime.tentacles,"real CanteenRun initialization binds saved ordering and all actual ladles")
	var distribution := arm_counts(runtime)
	check(distribution.size() == 4 and not distribution.has("sweet") and runtime.tentacles > 4,"fixture has a closed stall and real extra-tentacle allocation")
	for i in runtime._arms.size():
		runtime._arms[i].t = 10.0+i
		runtime._arms[i].t0 = 20.0+i
		runtime._arms[i].raise = 0.12 if i == 0 else 0.0
	runtime._update_arm_art()
	var arm_state := runtime._arms.duplicate(true)
	var arm_refs := runtime._arms.duplicate()
	var ladles := runtime._arm_ladles.duplicate()
	var positions: Array = ladles.map(func(s): return s.position)
	var lines := runtime._arm_lines.duplicate()
	runtime._fp = PackedVector2Array([Vector2(321,654),Vector2(765,432)])
	runtime._fv = PackedVector2Array([Vector2(10,22),Vector2(-10,33)])
	runtime._fk = PackedInt32Array([CanteenRun.make(CanteenRun.KIND.ball),CanteenRun.make(CanteenRun.KIND.leg,2,true)])
	runtime._fg = PackedFloat32Array([901.0,902.0])
	runtime._fr = PackedFloat32Array([0.3,0.5])
	runtime._hand = runtime._new_basin(Vector2(830,880))
	var flight := [runtime._fp.duplicate(),runtime._fv.duplicate(),runtime._fk.duplicate(),runtime._fg.duplicate(),runtime._fr.duplicate()]
	var hand: Dictionary = runtime._hand.duplicate(true)
	var crew := runtime._crew.duplicate(true)
	check(not runtime.apply_stall_order(SWAPPED) and runtime.stall_order == DEFAULT_ORDER and Game.active_stall_order() == DEFAULT_ORDER,"live unpaused swap is rejected without runtime or saved-state changes")
	get_tree().paused = true
	check(not runtime.apply_stall_order(["main"]) and runtime.stall_order == DEFAULT_ORDER,"paused invalid layout is rejected before partial application")
	test_failed_apply(runtime)
	check(runtime.apply_stall_order(SWAPPED) and runtime.stall_order == SWAPPED and Game.active_stall_order() == SWAPPED,"paused apply synchronizes actual run and persisted valid ordering")
	check(arm_counts(runtime) == distribution and runtime._arms.size() == arm_state.size(),"swap preserves each identity's extra-tentacle allocation and total count")
	var stable := true
	var art_moved := true
	for i in runtime._arms.size():
		var a: Dictionary = runtime._arms[i]
		for key in ["t","t0","dish","raise","stall","ladle"]:
			stable = stable and a[key] == arm_state[i][key]
		stable = stable and is_same(a,arm_refs[i]) and runtime._arm_ladles[i] == ladles[i] and runtime._arm_lines[i] == lines[i]
		var pose: Array = runtime._arm_pose(a,runtime._arm_lift(a))
		art_moved = art_moved and runtime._arm_ladles[i].position == pose[1] and runtime._arm_ladles[i].position != positions[i]
	check(stable,"existing arm dictionaries, sprite/line objects, timers, announced dishes, raise and ladle numbers survive apply")
	check(art_moved,"real ladle Sprite2D positions update to the mapped physical slot while retaining lift")
	var mapping_ok := true
	for id in DEFAULT_ORDER:
		var slot: int = SWAPPED.find(id)
		var physical: Array = CanteenRun.PANS[DEFAULT_ORDER[slot]]
		mapping_ok = mapping_ok and runtime.stall_slot(id) == slot and runtime.stall_pans(id) == physical
		mapping_ok = mapping_ok and is_equal_approx(runtime._win_span(id),float(physical[-1])-float(physical[0]))
	check(mapping_ok and runtime.stall_lv.sweet == 0,"all five identities map to fixed pans/spans, including the still-closed stall")
	check(runtime._fp == flight[0] and runtime._fv == flight[1] and runtime._fk == flight[2] and runtime._fg == flight[3] and runtime._fr == flight[4],"already airborne food retains exact position, velocity, identity/quality, gravity and spin")
	check(runtime._hand == hand and runtime._crew == crew,"swapping stalls does not relocate player cargo or helpers")
	Game.load_game()
	check(Game.active_stall_order() == SWAPPED,"paused runtime edit survives actual disk reload")
	var next_run := CanteenRun.new()
	next_run.autotest = true
	add_child(next_run)
	next_run.process_mode = Node.PROCESS_MODE_DISABLED
	check(next_run.stall_order == SWAPPED and arm_counts(next_run) == distribution,"next-run real arm setup honors saved positions without redistributing extra tentacles")
	var initialized_positions := true
	for a in next_run._arms:
		var identity: String = a.stall
		var center: float = next_run._win_x(SWAPPED.find(identity))
		initialized_positions = initialized_positions and absf(a.x-center) <= next_run._win_span(identity)*0.5+0.001
	check(initialized_positions,"new run creates its actual ladles inside the saved identity's physical window")
	next_run.free()
	get_tree().paused = false
	var first: Dictionary = runtime._arms[0]
	var promised := int(first.dish)
	var new_x := float(first.x)
	var old_count := runtime._fp.size()
	runtime._update_arms(0.13) # The preserved raised scoop actually launches after resume.
	check(runtime._fp.size() > old_count and CanteenRun.K(runtime._fk[old_count]) == promised,"resuming completes the previously announced raised dish without rerolling it")
	var from_new_slot := true
	for i in range(old_count,runtime._fp.size()):
		from_new_slot = from_new_slot and absf(runtime._fp[i].x-new_x) <= 14.001 and is_equal_approx(runtime._fp[i].y,CanteenRun.COUNTER_Y-10.0)
	check(from_new_slot,"actual future _fling food originates at the swapped source, not the old window")
	get_tree().paused = true
	check(runtime.apply_stall_order(DEFAULT_ORDER) and arm_counts(runtime) == distribution,"restore default is a real reversible move without reallocating tentacles")
	runtime._ended = true
	check(not runtime.apply_stall_order(SWAPPED) and Game.active_stall_order() == DEFAULT_ORDER,"ended runs reject swaps even while paused")
	get_tree().paused = false
	runtime.queue_free()
	await get_tree().process_frame
	runtime = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().has("--test-profile="+PROFILE) or Game.save_path != "user://qa_%s.json" % PROFILE:
		push_error("Refusing progression/layout test outside its isolated profile")
		get_tree().quit(2)
		return
	var settings_before := FileAccess.get_file_as_bytes(Settings.PATH)
	var player_before := player_save_fingerprint()
	var source_hashes := {}
	for path in ["res://scripts/autoload/game.gd","res://scripts/run/canteen_run.gd","res://scripts/ui/run_coach.gd","res://data/skill_tree.json","res://tests/progression_layout_test.gd"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	var rules_only := OS.get_cmdline_user_args().has("--rules-only")
	CanteenRun.load_menu()
	seed(20261019)
	test_refunds()
	test_preview()
	test_stall_preferences()
	if not rules_only:
		await test_runtime_readiness_and_intro()
		await test_runtime_apply()
	check(FileAccess.get_file_as_bytes(Settings.PATH) == settings_before,"player settings remain byte-identical")
	check(player_save_fingerprint() == player_before,"player save and backup fingerprints remain unchanged")
	check(source_hashes.keys().all(func(path): return FileAccess.get_sha256(path) == source_hashes[path]),"source hashes remain stable throughout the recorded run")
	var scope := "Real refund, preview and save/load rules only; runtime apply not executed" if rules_only else "Real refund, save/load, pause-state apply, arm Sprite2D and fling rules; headless only, no GPU/UI or human play claims"
	var report := {"checks":checks,"check_count":checks.size(),"failures":failures,"profile":PROFILE,"scope":scope,"hashes":source_hashes,"player_save_unchanged":player_save_fingerprint() == player_before}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT+("/progression-rules-report.json" if rules_only else "/progression-layout-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	Game.reset_save()
	await get_tree().create_timer(0.12,true,false,true).timeout
	for player in Audio.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.12,true,false,true).timeout
	print(("PROGRESSION_RULES_TEST" if rules_only else "PROGRESSION_LAYOUT_TEST")+": %d checks, %d failures" % [checks.size(),failures])
	get_tree().quit(failures)
