class_name ComicPlayer
extends CanvasLayer
## Opening comic: full-screen pages with a slow Ken Burns push-in and crossfades. Each page
## has one or more voiced lines (narration or a named speaker) shown in the caption band;
## lines advance when their voice ends (plus a beat) or on a key press (main.gd calls
## advance()), and the last line of a page moves on to the next page. skip() ends it at once.

signal finished

const SCREEN := Vector2(1920, 1080)
const HOLD_AFTER_VOICE := 1.0

var _pages: Array = []    # [{texture, lines: [{speaker, text, voice}]}]
var _index := -1
var _line := 0
var _line_time := 0.0
var _page_time := 0.0
var _fade := 0.0          # 0..1 fade-in of the current page
var _prev_tex: Texture2D = null
var _voice_done_at := -1.0
var _board: Control


func _ready() -> void:
	layer = 20
	_board = Control.new()
	add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.draw.connect(_draw_page)


func start(pages: Array) -> void:
	_pages = pages
	_next_page()


func advance() -> void:
	if _fade < 0.6 or _line_time < 0.25:
		return  # ignore mashing during the crossfade / right after a line starts
	_next_line()


func _next_line() -> void:
	if _line + 1 < _pages[_index]["lines"].size():
		_line += 1
		_start_line()
	else:
		_next_page()


func _start_line() -> void:
	_line_time = 0.0
	_voice_done_at = -1.0
	Audio.voice(_pages[_index]["lines"][_line]["voice"])


func skip() -> void:
	Audio.voice("")
	finished.emit()
	queue_free()


func _next_page() -> void:
	if _index >= 0:
		_prev_tex = _pages[_index]["texture"]
	_index += 1
	if _index >= _pages.size():
		skip()
		return
	_page_time = 0.0
	_fade = 0.0
	_line = 0
	_start_line()


func _process(delta: float) -> void:
	if _index < 0 or _index >= _pages.size():
		return
	_page_time += delta
	_line_time += delta
	_fade = minf(_fade + delta / 0.8, 1.0)
	if _voice_done_at < 0.0 and not Audio.voice_playing() and _line_time > 0.5:
		_voice_done_at = _line_time
	if _voice_done_at >= 0.0 and _line_time - _voice_done_at > HOLD_AFTER_VOICE:
		_next_line()
	_board.queue_redraw()


func _draw_page() -> void:
	if _index < 0 or _index >= _pages.size():
		return
	_board.draw_rect(Rect2(Vector2.ZERO, SCREEN), Color.BLACK)
	if _prev_tex and _fade < 1.0:
		_board.draw_texture_rect(_prev_tex, Rect2(Vector2.ZERO, SCREEN), false, Color(1, 1, 1, 1.0 - _fade))
	var zoom := 1.0 + minf(_page_time, 14.0) * 0.006
	var size := SCREEN * zoom
	var tex: Texture2D = _pages[_index]["texture"]
	_board.draw_texture_rect(tex, Rect2((SCREEN - size) / 2.0, size), false, Color(1, 1, 1, _fade))
	# caption band
	_board.draw_rect(Rect2(0, SCREEN.y - 200, SCREEN.x, 200), Color(0, 0, 0, 0.55 * _fade))
	var font := ThemeDB.fallback_font
	var line: Dictionary = _pages[_index]["lines"][_line]
	var text: String = line["text"]
	var speaker: String = line.get("speaker", "")
	var a := _fade * clampf(_line_time / 0.2, 0.0, 1.0)   # each new line fades in
	var y := SCREEN.y - 128.0
	if speaker != "":
		# a spoken line: speaker name in gold above it, text in quotes
		_board.draw_string_outline(font, Vector2(0, SCREEN.y - 150), speaker, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 28, 6, Color(0, 0, 0, a))
		_board.draw_string(font, Vector2(0, SCREEN.y - 150), speaker, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 28, Color(0.95, 0.8, 0.45, a))
		text = "「" + text + "」"
		y = SCREEN.y - 98.0
	_board.draw_multiline_string_outline(font, Vector2(160, y), text, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x - 320, 36, 3, 8, Color(0, 0, 0, a))
	_board.draw_multiline_string(font, Vector2(160, y), text, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x - 320, 36, 3, Color(1, 0.96, 0.88, a))
	_board.draw_string(font, Vector2(SCREEN.x - 420, SCREEN.y - 24), "J / 空格 下一页　　Esc 跳过", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.5 * _fade))
