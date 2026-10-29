class_name MemoryDifficultyCard
extends Button

## 大厅里的难度卡。整张卡由 _draw 绘制，悬停时发光/抬起。

var level_id: String = ""
var data: Dictionary = {}
var accent: Color = Color("#c9a86a")
var accent_dim: Color = Color("#5e4a2b")
var font_title: Font
var font_body: Font
var font_latin: Font
var card_index: int = 0

var _hover_amount: float = 0.0
var _hover_target: float = 0.0
var _time: float = 0.0
var _bg: StyleBoxFlat


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	_bg = StyleBoxFlat.new()
	_bg.corner_radius_top_left = 10
	_bg.corner_radius_top_right = 10
	_bg.corner_radius_bottom_left = 10
	_bg.corner_radius_bottom_right = 10
	_bg.border_width_left = 1
	_bg.border_width_right = 1
	_bg.border_width_top = 1
	_bg.border_width_bottom = 1
	_bg.anti_aliasing = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

	if font_title == null:
		font_title = get_theme_default_font()
	if font_body == null:
		font_body = get_theme_default_font()
	if font_latin == null:
		font_latin = get_theme_default_font()

	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(_on_resized)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	set_process(true)
	queue_redraw()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _on_hover_in() -> void:
	_hover_target = 1.0
	z_index = 2


func _on_hover_out() -> void:
	_hover_target = 0.0
	z_index = 0


func _on_button_down() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(0.982, 0.982), 0.08).set_trans(Tween.TRANS_QUAD)
	queue_redraw()


func _on_button_up() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var previous := _hover_amount
	_hover_amount = move_toward(_hover_amount, _hover_target, delta * 6.5)
	if not is_equal_approx(previous, _hover_amount):
		queue_redraw()


func _text(font: Font, baseline: float, text: String, font_size: int, color: Color, width: float = -1.0) -> void:
	if font == null:
		return
	var w: float = width if width > 0.0 else size.x
	draw_string(font, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


func _spaced(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		out += text[i]
		if i != text.length() - 1:
			out += " "
	return out


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 40.0 or h < 40.0:
		return
	var hover: float = _hover_amount
	var focus: bool = has_focus()

	# 卡面
	_bg.bg_color = Color("#100e14").lerp(accent.darkened(0.68), 0.055 + 0.10 * hover)
	_bg.border_color = Color(accent.r, accent.g, accent.b, 0.34 + 0.42 * hover + (0.16 if focus else 0.0))
	_bg.shadow_color = Color(accent.r, accent.g, accent.b, 0.16 * hover)
	_bg.shadow_offset = Vector2(0, 5)
	_bg.shadow_size = int(round(10.0 * hover))
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))

	# 顶部细光带
	var band_alpha: float = 0.25 + hover * 0.55
	draw_rect(Rect2(14, 0, w - 28, 1.6), Color(accent.r, accent.g, accent.b, band_alpha), true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.5, -2), Vector2(w * 0.5 + 5, 4), Vector2(w * 0.5, 10), Vector2(w * 0.5 - 5, 4)
	]), Color(accent.r, accent.g, accent.b, 0.30 + hover * 0.45))

	# 内框与四角
	var inset := 11.0
	draw_rect(Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0), Color(accent.r, accent.g, accent.b, 0.12 + hover * 0.10), false, 1.0)
	var arm := 19.0
	var corners := [Vector2(inset, inset), Vector2(w - inset, inset), Vector2(inset, h - inset), Vector2(w - inset, h - inset)]
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for i in range(4):
		var p: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		draw_line(p, p + Vector2(arm * d.x, 0), Color(accent.r, accent.g, accent.b, 0.50), 1.0, true)
		draw_line(p, p + Vector2(0, arm * d.y), Color(accent.r, accent.g, accent.b, 0.50), 1.0, true)

	# 右侧大号罗马数字水印
	if font_latin != null:
		draw_string(font_latin, Vector2(w - 94, 98), String(data.get("roman", "I")), HORIZONTAL_ALIGNMENT_CENTER, 78, 62, Color(accent.r, accent.g, accent.b, 0.075 + hover * 0.04))

	# 顶部小标号
	var eyebrow := _spaced("LEVEL %02d" % card_index)
	_text(font_latin, 37, eyebrow, 10, Color(accent.r, accent.g, accent.b, 0.66 + hover * 0.25))

	# 难度数字
	var dims := "%d × %d" % [int(data.get("rows", 2)), int(data.get("columns", 3))]
	if font_title != null:
		draw_string(font_title, Vector2(0, 99 + 2), dims, HORIZONTAL_ALIGNMENT_CENTER, w, 45, Color(0.02, 0.01, 0.03, 0.75))
		draw_string(font_title, Vector2(0, 99), dims, HORIZONTAL_ALIGNMENT_CENTER, w, 45, Color("#eee3c9"))
	# 难度数字下的小分隔
	draw_line(Vector2(w * 0.5 - 56, 111), Vector2(w * 0.5 - 10, 111), Color(accent.r, accent.g, accent.b, 0.40), 1.0, true)
	draw_line(Vector2(w * 0.5 + 10, 111), Vector2(w * 0.5 + 56, 111), Color(accent.r, accent.g, accent.b, 0.40), 1.0, true)
	draw_circle(Vector2(w * 0.5, 111), 2.0, Color(accent.r, accent.g, accent.b, 0.65))

	# 名称与提示
	_text(font_body, 143, "%s · %s" % [String(data.get("name", "")), String(data.get("title", ""))], 18, Color("#e6dbc4"))
	_text(font_body, 166, String(data.get("hint", "")), 12, Color("#a99c86"))

	# 底部数值
	var pairs := int(data.get("pairs", 3))
	var cards := pairs * 2
	var seconds := int(round(float(data.get("time_limit", 45.0))))
	var mistakes := int(data.get("max_mistakes", 3))
	var meta := "%d 张牌 · %d 对" % [cards, pairs]
	var meta2 := "%d 秒 · %d 次失误" % [seconds, mistakes]
	_text(font_body, 198, meta, 13, Color(accent.r, accent.g, accent.b, 0.92))
	_text(font_body, 217, meta2, 12, Color("#a99c86"))

	# 难度菱形
	var count := 3
	var pip_gap := 13.0
	var start_x := w * 0.5 - float(count - 1) * pip_gap * 0.5
	var filled := int(data.get("difficulty", 1))
	for i in range(count):
		var p := Vector2(start_x + float(i) * pip_gap, h - 16.0)
		var dd := 4.2
		var pts := PackedVector2Array([p + Vector2(0, -dd), p + Vector2(dd, 0), p + Vector2(0, dd), p + Vector2(-dd, 0)])
		if i < filled:
			draw_colored_polygon(pts, Color(accent.r, accent.g, accent.b, 0.90))
		else:
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(accent.r, accent.g, accent.b, 0.30), 1.0, true)

	# 悬停时的一道柔光
	if hover > 0.01:
		draw_rect(Rect2(inset + 1, inset + 1, w - (inset + 1) * 2.0, (h - (inset + 1) * 2.0) * 0.5), Color(accent.r, accent.g, accent.b, 0.018 * hover), true)
