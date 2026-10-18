extends Node
## Screen flow: title -> shift (CanteenRun) -> skill tree (TreeScreen) -> shift -> ...
## Command line (after `--`):
##   --autotest          play shifts by itself (a bot catches and serves, 4x speed), buy the
##                       cheapest node after each one, print a pacing summary and quit
##   --runs=<n>          shifts to play in autotest (default 5)
##   --shots=<dir>       also save screenshots of the title, a shift, the result card and the tree
##   --trial=<id>        autotest only that trial (spring / hybrid / ji), --runs times, with every
##                       node of the earlier rings maxed: a quick balance check
##   --debug             tuning keys during a shift (see canteen_run.gd)
##   --lang=en|zh_CN     play in that language (not saved), e.g. for screenshots

## Full credits page (keep in sync with CREDITS.md at the repo root).
const CREDITS_FULL := """吃白饭的大肥鱼 —— 免费、开源、非商用的粉丝作品，与 DeepSeek 官方无关
素材按 CC BY-NC-SA 4.0 发布，代码按 MIT 发布

角色
原型「溟月」：上善无形（B站）· CC BY-NC-SA 4.0
女仆版「蓝色大肥鱼」：ZipZipPipe（B站）· CC BY-NC-SA 4.0

大肥鱼立绘与动画：依上述角色重新绘制的高清立绘（AI 辅助生成后人工修整），在游戏里拆成网格实时变形动画

字体：Noto Sans SC、站酷快乐体 · SIL Open Font License
引擎：Godot Engine · MIT"""

## Shown on the credits page under the list above.
const AI_NOTE := "部分美术（场景、梁阿姨、食物、饭盒）、音效和音乐由 AI 辅助生成（gpt-image、ElevenLabs），再由人工挑选、修整和拼装。"

var _screen: Node = null
var _autotest := false
var _runs_left := 5
var _shots := ""
var _log: Array = []
var _debug := false
var _only_trial := ""
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	ThemeDB.get_default_theme().merge_with(UiKit.build_theme())
	get_tree().node_added.connect(func(n):
		if n is BaseButton:
			UiKit.hook(n))
	if not OS.has_feature("web"):   # on the web the page sizes the canvas
		get_tree().root.min_size = Vector2i(960, 540)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.03, 0.02, 0.0)
	_fade.size = Vector2(1920, 1080)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	Settings.changed.connect(_on_settings_changed)
	for a in OS.get_cmdline_user_args():
		if a == "--autotest":
			_autotest = true
		elif a.begins_with("--runs="):
			_runs_left = int(a.get_slice("=", 1))
		elif a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
		elif a.begins_with("--trial="):
			_only_trial = a.get_slice("=", 1)
		elif a == "--debug":
			_debug = true
	if _autotest:
		Engine.time_scale = 4.0
		if _shots != "":
			_show_title()
			await get_tree().create_timer(2.0).timeout
			await _shot("title")
			var s := SettingsPanel.new()
			_screen.add_child(s)
			await get_tree().create_timer(0.3).timeout
			await _shot("settings")
			s.queue_free()
			_show_credits(_screen)
			await _shot("credits")
		if _only_trial != "":
			_prepare_trial(_only_trial)
			_show_run(_only_trial)
			return
		_show_run()
	else:
		_show_title()


func _exit_tree() -> void:
	UiKit.clear_cache()   # static font cache, freed before the engine checks for leaks


## Swaps the current screen; with a short fade through dark except in the autotest.
func _swap(n: Node) -> void:
	if _autotest or _screen == null:
		_set_screen(n)
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.18)
	await tw.finished
	_set_screen(n)
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.25)
	await tw.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _set_screen(n: Node) -> void:
	if _screen:
		_screen.queue_free()
	_screen = n
	add_child(n)


var _lang := ""


## A language change rebuilds the title (its texts are made once); other screens draw their
## text every frame or are rebuilt on the next visit.
func _on_settings_changed() -> void:
	if _lang != "" and _lang != Settings.language and _screen is TitleScreen:
		var panel_open := _screen.get_children().any(func(c): return c is SettingsPanel)
		_set_screen(_make_title())
		if panel_open:
			_open_settings(_screen)
	_lang = Settings.language


func _show_title() -> void:
	_swap(_make_title())


func _make_title() -> TitleScreen:
	var t := TitleScreen.new()
	t.play.connect(func(): _show_run() if Game.runs == 0 else _show_tree())
	t.open_settings.connect(func(): _open_settings(t))
	t.open_credits.connect(func(): _show_credits(t))
	t.quit.connect(func(): get_tree().quit())
	return t


func _open_settings(parent: Node) -> void:
	var s := SettingsPanel.new()
	var runs := Game.runs
	Audio.duck(true)
	s.closed.connect(func():
		Audio.duck(false)
		if parent is TitleScreen and is_instance_valid(parent) and Game.runs != runs:
			_set_screen(_make_title()))   # the save was reset: 继续上班 -> 开始上班
	parent.add_child(s)


func _show_credits(parent: Control) -> void:
	var panel := Control.new()
	panel.size = Vector2(1920, 1080)
	panel.z_index = 200
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.75)
	dim.size = panel.size
	panel.add_child(dim)
	var box := PanelContainer.new()
	box.position = Vector2(150, 60)
	box.custom_minimum_size = Vector2(1620, 960)
	panel.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	box.add_child(col)
	var title := UiKit.label(tr("鸣谢"), 48, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var text := UiKit.label((tr(CREDITS_FULL) + "\n\n" + tr(AI_NOTE)).replace("\r", ""), 25)   # CRLF checkouts would double every line
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(1560, 0)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(text)
	var back := UiKit.button(tr("返回"), 32, Vector2(240, 72))
	back.set_meta("ui_back", true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(panel.queue_free)
	col.add_child(back)
	back.grab_focus.call_deferred()


func _show_run(trial := "") -> void:
	var run := CanteenRun.new()
	run.autotest = _autotest
	run.debug = _debug
	run.trial = trial
	run.finished.connect(_on_run_finished.bind(run))
	run.to_title.connect(_show_title)
	if _shots != "":
		run.card_shown.connect(func():
			await get_tree().create_timer(1.2).timeout   # after the score has counted up
			_shot("card_%d" % Game.runs))
	_swap(run)
	if _autotest and _shots != "":
		await get_tree().create_timer(4.0).timeout
		if is_instance_valid(run):
			await _shot("run_%d" % Game.runs)
			if Game.runs == 0:   # the pause menu, once
				run.pause()
				await get_tree().create_timer(0.3).timeout
				await _shot("pause")
				run._pause.resume()
		await get_tree().create_timer(8.0).timeout
		if is_instance_valid(run) and not run._ended:
			await _shot("run_%d_b" % Game.runs)


func _on_run_finished(earned: float, run: CanteenRun) -> void:
	if _autotest:
		if run.trial != "":
			_log.append("第 %d 顿【评测 %s】+%s token：%s → %s" % [Game.runs, Game.trial_name(run.trial), Game.fmt(earned),   # notr
				run.trial_log(), Game.plate()])   # notr
		else:
			_log.append("第 %d 顿 [%s] +%s token：吃了 %d 份，%s，接住率 %d%%，她空等 %.0f 秒" % [Game.runs, Game.plate(), Game.fmt(earned), run.eaten, run.trial_log(),   # notr
				int(run.catch_rate() * 100), run.fish_wait])   # notr
	_show_tree()


func _show_tree() -> void:
	var tree := TreeScreen.new()
	tree.start_run.connect(_show_run)
	tree.start_trial.connect(_show_run)
	tree.open_settings.connect(func(): _open_settings(tree))
	tree.to_title.connect(_show_title)
	_swap(tree)
	if _autotest:
		_auto_shop(tree)


## Autotest player: buy the cheapest affordable node until broke, then work again.
func _auto_shop(tree: TreeScreen) -> void:
	await get_tree().process_frame
	while true:
		var best := ""
		for n in Game.nodes:
			if Game.can_buy(n["id"]) and (best == "" or Game.cost(n["id"]) < Game.cost(best)):
				best = n["id"]
		if best == "":
			break
		_log.append("    买了「%s」→ %d 级" % [Game.node(best)["name"], Game.level(best) + 1])   # notr
		tree.try_buy(best)
	if _shots != "":
		await get_tree().create_timer(0.6).timeout   # let a new-feature card slide in
		await _shot("tree_%d" % Game.runs)
		if Game.runs == 1:   # the 菜谱图鉴, once
			var book := RecipeBook.new()
			tree.add_child(book)
			await get_tree().create_timer(0.3).timeout
			await _shot("recipes")
			book.queue_free()
	_runs_left -= 1
	if _only_trial != "" and _runs_left > 0:
		if Game.open_trial() == "":   # passed: try it again from the version before
			_prepare_trial(_only_trial)
		_show_run(_only_trial)
		return
	if _runs_left <= 0:
		print("\n".join(_log))
		print("菜谱：", Game.recipes)   # notr
		print("AUTOTEST OK: %d 顿, 累计 %s token, 技能总等级 %d, 版本 %s" % [Game.runs, Game.fmt(Game.total_tokens), Game.total_levels(), Game.plate()])   # notr
		get_tree().quit()
		return
	var t := Game.open_trial()   # the bot takes the 评测 once its best shift is close to the target
	_show_run(t if t != "" and Game.best_run >= Game.trial_target(t) * 0.9 and Game.pay_trial(t) else "")


## Autotest --trial: the version just before that trial, every earlier ring maxed, its ticket bought.
func _prepare_trial(trial: String) -> void:
	for i in Game.VERSIONS.size():
		if Game.VERSIONS[i].get("trial", "") == trial:
			Game.version = i - 1
	for n in Game.nodes:
		if int(n.get("ring", 0)) <= Game.version and not n.get("locked", false):
			Game.levels[n["id"]] = int(n["max"])
	Game._recompute()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shots)
	get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))
