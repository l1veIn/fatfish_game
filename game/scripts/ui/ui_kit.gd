class_name UiKit
extends RefCounted
## The game's look for standard controls (a warm canteen palette: cream buttons with a wooden
## edge, brown panels) and small helpers shared by the menus. build_theme() is set on the root
## window once (main.gd), so every Button / Slider / CheckButton / OptionButton picks it up.
## hook() gives a button hover/click sounds and a little bounce; main.gd hooks every button
## that enters the tree.

const CREAM := Color(1.0, 0.95, 0.84)
const CREAM_HI := Color(1.0, 0.86, 0.5)
const WOOD := Color(0.48, 0.29, 0.15)
const WOOD_DARK := Color(0.27, 0.15, 0.08)
const INK := Color(0.29, 0.16, 0.08)
const PANEL := Color(0.16, 0.1, 0.07, 0.97)
const GOLD := Color(1.0, 0.8, 0.42)
const TEXT := Color(1.0, 0.95, 0.86)

static var _bold := {}


static func box(bg: Color, border: Color = Color.TRANSPARENT, width := 0, radius := 18, bottom := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	if bottom >= 0:
		s.border_width_bottom = bottom
	s.set_corner_radius_all(radius)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	s.anti_aliasing = true
	return s


## The UI font (Noto Sans SC, variable) at another weight: 700 for buttons, 900 for the logo.
static func bold(weight := 700) -> Font:
	if not _bold.has(weight):
		var f := FontVariation.new()
		var ui: FontVariation = load("res://assets/ui/ui_font.tres")
		f.base_font = ui.base_font
		f.fallbacks = ui.fallbacks
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_bold[weight] = f
	return _bold[weight]


static func clear_cache() -> void:
	_bold.clear()


## Merged into the engine's default theme by main.gd, so it reaches every control, also those
## under Node / Node2D parents (which a theme set on a Control or the window would not).
static func build_theme() -> Theme:
	var t := Theme.new()
	# buttons: cream with a thick wooden bottom edge, lighter on hover, pressed sinks in
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(CREAM, WOOD, 3, 18, 8))
		t.set_stylebox("hover", type, box(CREAM_HI, WOOD, 3, 18, 8))
		t.set_stylebox("pressed", type, box(Color(0.93, 0.78, 0.48), WOOD_DARK, 3, 18, 3))
		t.set_stylebox("disabled", type, box(Color(0.6, 0.57, 0.52), Color(0.4, 0.36, 0.32), 3, 18, 8))
		var focus := box(Color.TRANSPARENT, GOLD, 5, 22)
		focus.draw_center = false
		focus.expand_margin_left = 4
		focus.expand_margin_right = 4
		focus.expand_margin_top = 4
		focus.expand_margin_bottom = 4
		t.set_stylebox("focus", type, focus)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(c, type, INK)
		t.set_color("font_disabled_color", type, Color(0.35, 0.32, 0.3))
		t.set_font("font", type, bold(700))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "Panel", box(PANEL, GOLD, 4, 26))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, GOLD, 4, 26))
	# toggles and sliders sit on dark panels: light text
	for type in ["CheckButton", "CheckBox"]:
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			t.set_stylebox(st, type, empty)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(c, type, TEXT)
		t.set_icon("checked", type, _switch(true))
		t.set_icon("unchecked", type, _switch(false))
		t.set_icon("checked_disabled", type, _switch(true))
		t.set_icon("unchecked_disabled", type, _switch(false))
		t.set_constant("h_separation", type, 24)
	var track := box(Color(0.08, 0.05, 0.03), WOOD, 2, 8)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(GOLD, Color.TRANSPARENT, 0, 8)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _circle(30, CREAM, WOOD)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _circle(30, CREAM_HI, WOOD))
	var pop := box(PANEL, GOLD, 3, 12)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", box(Color(1, 0.86, 0.5, 0.35), Color.TRANSPARENT, 0, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", 28)
	t.set_stylebox("panel", "TooltipPanel", box(PANEL, GOLD, 2, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


## A toggle switch: a wooden track with a cream knob, gold when on.
static func _switch(on: bool) -> ImageTexture:
	var w := 84
	var h := 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	var knob := Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := Vector2(clampf(p.x, r, w - r), r)   # distance to the pill's spine
			var d := p.distance_to(q)
			var a := clampf(r - d, 0.0, 1.0)
			var col := (GOLD if on else Color(0.3, 0.2, 0.13)) if d < r - 3.0 else WOOD_DARK
			var kd := p.distance_to(knob)
			if kd < r - 5.0:
				col = CREAM if kd < r - 7.0 else WOOD
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


static func _circle(d: int, fill: Color, edge: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(d * 0.5 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(edge if r > d * 0.5 - 3.5 else fill, a))
	return ImageTexture.create_from_image(img)


## Draws `t` into `r` as a nine-slice: the corners keep their size (`m` texture px, drawn at
## `m * k`), the edges and middle stretch. For the paper / chalkboard / badge art at any size.
static func nine(ci: CanvasItem, t: Texture2D, r: Rect2, m: float, k := 1.0, col := Color.WHITE) -> void:
	if t == null:
		return
	var ts := t.get_size()
	var d := minf(m * k, minf(r.size.x, r.size.y) * 0.5)
	var sx := [0.0, m, ts.x - m, ts.x]
	var sy := [0.0, m, ts.y - m, ts.y]
	var dx := [r.position.x, r.position.x + d, r.end.x - d, r.end.x]
	var dy := [r.position.y, r.position.y + d, r.end.y - d, r.end.y]
	for i in 3:
		for j in 3:
			ci.draw_texture_rect_region(t, Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]),
				Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j]), col)


static var _numerals: Font
## 「饭票数字」(docs/font_plan.md, pipeline/make_numerals.py): the number font, a bitmap font
## drawn white with a dark ink edge, so the colour asked for when drawing tints it. What it has
## no glyph for falls back to 站酷快乐体.
static func numerals() -> Font:
	if _numerals == null:
		var d: Font = load("res://assets/ui/ZCOOLKuaiLe.ttf") if ResourceLoader.exists("res://assets/ui/ZCOOLKuaiLe.ttf") else ThemeDB.fallback_font
		if ResourceLoader.exists("res://assets/ui/numerals.fnt"):
			var f: FontFile = load("res://assets/ui/numerals.fnt")
			f.fallbacks = [d]
			_numerals = f
		else:
			_numerals = d
	return _numerals


static var _glow: GradientTexture2D
## A soft round glow (white in the middle, fading out), tinted when drawn: halos, shadows.
static func glow() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow


static var _vignette: GradientTexture2D
## Clear in the middle, dark at the edges: drawn over the whole screen, tinted.
static func vignette() -> GradientTexture2D:
	if _vignette == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0))
		_vignette = GradientTexture2D.new()
		_vignette.gradient = g
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.5)
		_vignette.fill_to = Vector2(1.05, 0.5)
		_vignette.width = 256
		_vignette.height = 144
	return _vignette


## Hover / click sounds and a small bounce for one button (called for every button by main.gd).
static func hook(b: BaseButton) -> void:
	if b.has_meta("ui_hooked"):
		return
	b.set_meta("ui_hooked", true)
	b.mouse_entered.connect(func():
		if not b.disabled:
			Audio.sfx("ui_hover", -12.0)
			_bounce(b, 1.04))
	b.focus_entered.connect(func(): Audio.sfx("ui_hover", -12.0))
	b.mouse_exited.connect(func(): _bounce(b, 1.0))
	b.pressed.connect(func(): Audio.sfx("ui_back" if b.has_meta("ui_back") else "ui_click", -4.0))


static func _bounce(b: Control, to: float) -> void:
	if not b.is_inside_tree():
		return
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * to, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A big menu button.
static func button(text: String, font_size := 36, min_size := Vector2(360, 84)) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = min_size
	return b


## A label with an outline, for text on top of art.
static func label(text: String, font_size: int, color: Color = TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font_size >= 40:
		l.add_theme_font_override("font", bold(900 if font_size >= 90 else 700))
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.03))
	return l
