class_name ScreenLayout
extends Node
## Expand scenery into the screen's extra space; keep the authored stage undistorted.
## Safe areas constrain touch controls, never the canvas or the scenery.

signal changed

const DESIGN := Vector2(1920, 1080)
static var active: ScreenLayout
static var visible := Rect2(Vector2.ZERO, DESIGN)
static var safe := Rect2(Vector2.ZERO, DESIGN)
var _elapsed := 0.0
var _insets := Vector4.ZERO # CSS pixels: left, top, right, bottom
var _css_size := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = self
	if OS.has_feature("web") or OS.get_cmdline_user_args().has("--expand-screen"):
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	get_viewport().size_changed.connect(_reflow)
	_read_safe_area()
	_reflow()


func _process(delta: float) -> void:
	_elapsed += delta
	if OS.has_feature("web") and _elapsed >= 0.25:
		_elapsed = 0.0
		_read_safe_area()


func _read_safe_area() -> void:
	if not OS.has_feature("web"):
		return
	var data: Variant = JSON.parse_string(str(JavaScriptBridge.eval("""JSON.stringify((() => {
		const p = document.getElementById('safe-area-probe');
		const s = p && getComputedStyle(p);
		return {width: innerWidth, height: innerHeight,
			insets: s ? [s.paddingLeft, s.paddingTop, s.paddingRight, s.paddingBottom].map(parseFloat) : [0,0,0,0]};
	})())""")))
	if data is Dictionary and data.get("insets") is Array and data.insets.size() == 4:
		var next := Vector4(float(data.insets[0]), float(data.insets[1]), float(data.insets[2]), float(data.insets[3]))
		var css := Vector2(float(data.width), float(data.height))
		if next != _insets or css != _css_size:
			_insets = next
			_css_size = css
			_reflow()


func _reflow() -> void:
	var viewport := get_viewport()
	var area := viewport.get_visible_rect().size
	var offset := (area - DESIGN) * 0.5
	viewport.canvas_transform = Transform2D(0.0, offset)
	visible = Rect2(-offset, area)
	var units := area / _css_size if _css_size.x > 0 and _css_size.y > 0 else Vector2.ONE
	safe = Rect2(visible.position + Vector2(_insets.x, _insets.y) * units,
		area - Vector2(_insets.x + _insets.z, _insets.y + _insets.w) * units)
	get_tree().call_group("screen_canvas_layers", "set_offset", offset)
	get_tree().call_group("full_bleed_controls", "screen_layout_reflow")
	changed.emit()
	get_tree().call_group("full_bleed_drawings", "queue_redraw")


static func full_rect(item: CanvasItem) -> Rect2:
	return item.get_global_transform_with_canvas().affine_inverse() * item.get_viewport_rect()


static func background(item: CanvasItem, texture: Texture2D, tint := Color.WHITE) -> void:
	item.add_to_group("full_bleed_drawings")
	var rect := full_rect(item)
	var texture_size := texture.get_size()
	var factor := maxf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var source_size := rect.size / factor
	item.draw_texture_rect_region(texture, rect, Rect2((texture_size - source_size) * 0.5, source_size), tint)


static func touch_rect(rect: Rect2) -> Rect2:
	var lo := Vector2(16, 16).max(safe.position + Vector2(16, 16))
	var hi := Vector2(1904, 1064).min(safe.end - Vector2(16, 16)) - rect.size
	return Rect2(rect.position.clamp(lo, hi.max(lo)), rect.size)


class BleedRect extends ColorRect:
	func screen_layout_reflow() -> void:
		var rect := ScreenLayout.full_rect(get_parent())
		position = rect.position
		size = rect.size

class BleedTexture extends TextureRect:
	func screen_layout_reflow() -> void:
		var rect := ScreenLayout.full_rect(get_parent())
		position = rect.position
		size = rect.size

static func scenery(parent: CanvasItem, texture: Texture2D) -> TextureRect:
	var control := BleedTexture.new()
	control.texture = texture
	control.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	control.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.add_to_group("full_bleed_controls")
	control.screen_layout_reflow()
	return control

static func shade(parent: CanvasItem, color: Color) -> ColorRect:
	var control := BleedRect.new()
	control.color = color
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.add_to_group("full_bleed_controls")
	control.screen_layout_reflow()
	return control


func _exit_tree() -> void:
	if active == self:
		active = null
		visible = Rect2(Vector2.ZERO, DESIGN)
		safe = visible
		get_viewport().canvas_transform = Transform2D.IDENTITY
