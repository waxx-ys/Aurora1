class_name MemoryTimerRing
extends Control

## 圆形倒计时。进度、读数、标题全部可以在运行时更新。
## 倒计时的数值来自 game_config.gd，不写死在这里。

var progress: float = 1.0
var time_text: String = "01:15"
var caption_text: String = "剩余时间"
var accent: Color = Color("#c9a86a")
var low_time: bool = false
var preview_mode: bool = false

var _main_font: Font
var _label_font: Font
var _latin_font: Font
var _time_label: Label
var _caption_label: Label
var _pulse := 0.0


func configure(main_font: Font, label_font: Font, latin_font: Font) -> void:
	_main_font = main_font
	_label_font = label_font
	_latin_font = latin_font
	_apply_fonts()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(170, 170)
	_build_labels()
	resized.connect(_layout_labels)
	_layout_labels()
	set_process(true)
	queue_redraw()


func _build_labels() -> void:
	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_label)

	_caption_label = Label.new()
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_label)
	_apply_fonts()
	_apply_text()


func _apply_fonts() -> void:
	if not is_instance_valid(_time_label):
		return
	if _main_font != null:
		_time_label.add_theme_font_override("font", _main_font)
	if _label_font != null:
		_caption_label.add_theme_font_override("font", _label_font)


func _layout_labels() -> void:
	if not is_instance_valid(_time_label):
		return
	_time_label.position = Vector2(0, size.y * 0.34)
	_time_label.size = Vector2(size.x, size.y * 0.30)
	_caption_label.position = Vector2(0, size.y * 0.63)
	_caption_label.size = Vector2(size.x, 22)


func set_values(new_progress: float, new_time_text: String, new_caption: String, new_accent: Color, is_low: bool = false, is_preview: bool = false) -> void:
	progress = clampf(new_progress, 0.0, 1.0)
	time_text = new_time_text
	caption_text = new_caption
	accent = new_accent
	low_time = is_low
	preview_mode = is_preview
	_apply_text()
	queue_redraw()


func _apply_text() -> void:
	if is_instance_valid(_time_label):
		_time_label.text = time_text
		_time_label.add_theme_font_size_override("font_size", 36)
		_time_label.add_theme_color_override("font_color", accent.lightened(0.18))
		_time_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.0, 0.03, 0.85))
		_time_label.add_theme_constant_override("shadow_offset_x", 0)
		_time_label.add_theme_constant_override("shadow_offset_y", 2)
	if is_instance_valid(_caption_label):
		_caption_label.text = caption_text
		_caption_label.add_theme_font_size_override("font_size", 11)
		_caption_label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.72))
		_caption_label.add_theme_constant_override("outline_size", 0)


func _process(delta: float) -> void:
	if low_time:
		_pulse += delta
		queue_redraw()


func _draw() -> void:
	var s: float = min(size.x, size.y)
	if s < 20.0:
		return
	var c: Vector2 = size * 0.5
	var r: float = s * 0.5 - 17.0
	var col: Color = accent
	var lw: float = 5.0
	var pulse_amt: float = 0.0
	if low_time:
		pulse_amt = (sin(_pulse * 5.2) * 0.5 + 0.5)

	# 光晕
	draw_circle(c, r + 7.0, Color(0.02, 0.015, 0.025, 0.46))
	draw_arc(c, r + 12.0, 0.0, TAU, 128, Color(col.r, col.g, col.b, 0.10 + pulse_amt * 0.10), 1.0, true)

	# 轨道
	draw_arc(c, r, 0.0, TAU, 128, Color(0.62, 0.56, 0.46, 0.13), 9.0, true)
	draw_arc(c, r, 0.0, TAU, 128, Color(0.92, 0.85, 0.68, 0.045), 1.0, true)

	# 六十道刻度
	for i in range(60):
		var ang: float = TAU * float(i) / 60.0 - PI * 0.5
		var major: bool = i % 5 == 0
		var r0: float = r + (9.0 if major else 10.5)
		var r1: float = r + (15.0 if major else 12.5)
		var alpha: float = 0.30 if major else 0.12
		draw_line(c + Vector2(cos(ang), sin(ang)) * r0, c + Vector2(cos(ang), sin(ang)) * r1, Color(col.r, col.g, col.b, alpha), 1.0, true)

	# 进度弧
	if progress > 0.001:
		var start: float = -PI * 0.5
		var end: float = start + TAU * progress
		var points: int = maxi(3, int(128.0 * progress))
		draw_arc(c, r, start, end, points, Color(col.r, col.g, col.b, 0.10 + pulse_amt * 0.10), 18.0, true)
		draw_arc(c, r, start, end, points, Color(col.r, col.g, col.b, 0.24), 10.0, true)
		draw_arc(c, r, start, end, points, col.lightened(0.08 + pulse_amt * 0.20), lw, true)

		# 弧线末端的光点
		var tip: Vector2 = c + Vector2(cos(end), sin(end)) * r
		draw_circle(tip, 4.2 + pulse_amt * 1.4, Color(1.0, 0.93, 0.75, 0.24))
		draw_circle(tip, 2.2, col.lightened(0.35))

	# 内盘
	draw_circle(c, r - 15.0, Color(0.035, 0.029, 0.043, 0.92))
	draw_circle(c, r - 21.0, Color(0.055, 0.046, 0.066, 0.82))
	draw_arc(c, r - 15.0, 0.0, TAU, 96, Color(col.r, col.g, col.b, 0.18), 1.0, true)

	# 内盘里的一枚小暗纹
	for i in range(4):
		var ang2: float = TAU * float(i) / 4.0 + PI * 0.25
		var p: Vector2 = c + Vector2(cos(ang2), sin(ang2)) * (r - 27.0)
		var d: float = 2.4
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)
		]), Color(col.r, col.g, col.b, 0.18))
