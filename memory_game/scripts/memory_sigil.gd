class_name MemorySigil
extends Control

## 女巫牌阵的月亮徽记。纯矢量绘制，缩放不会糊。

@export var ink: Color = Color("#d8c7a0")
@export var style: String = "moon"   # moon | simple
@export var line_width: float = 1.2

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(style == "moon")
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s: float = min(size.x, size.y)
	if s < 8.0:
		return
	var c: Vector2 = size * 0.5
	var r: float = s * 0.42
	var a: float = ink.a
	var lw: float = maxf(1.0, line_width)

	# 淡光与底盘
	draw_circle(c, r * 1.26, Color(ink.r, ink.g, ink.b, a * 0.035))
	draw_circle(c, r * 1.02, Color(0.025, 0.020, 0.032, 0.72))
	draw_circle(c, r * 0.96, Color(0.055, 0.045, 0.065, 0.55))

	# 外环 + 内环
	draw_arc(c, r * 0.92, 0.0, TAU, 96, Color(ink.r, ink.g, ink.b, a * 0.45), lw, true)
	draw_arc(c, r * 0.74, 0.0, TAU, 96, Color(ink.r, ink.g, ink.b, a * 0.20), lw, true)

	# 十二枚刻度
	for i in range(12):
		var ang: float = TAU * float(i) / 12.0 - PI * 0.5
		var long_tick: bool = i % 3 == 0
		var r0: float = r * (0.76 if long_tick else 0.80)
		var r1: float = r * (0.88 if long_tick else 0.85)
		var p0: Vector2 = c + Vector2(cos(ang), sin(ang)) * r0
		var p1: Vector2 = c + Vector2(cos(ang), sin(ang)) * r1
		draw_line(p0, p1, Color(ink.r, ink.g, ink.b, a * (0.72 if long_tick else 0.30)), lw, true)

	# 月牙：先画月盘，再用夜色圆盘切出缺口
	var moon_c: Vector2 = c + Vector2(-r * 0.12, 0.0)
	draw_circle(moon_c, r * 0.46, Color(ink.r, ink.g, ink.b, a * 0.82))
	draw_circle(c + Vector2(r * 0.12, -r * 0.015), r * 0.425, Color(0.028, 0.023, 0.036, 0.98))
	draw_arc(moon_c, r * 0.46, deg_to_rad(70.0), deg_to_rad(292.0), 48, Color(1.0, 0.93, 0.74, a * 0.55), lw, true)

	# 月牙里的星
	var star_c: Vector2 = c + Vector2(-r * 0.30, -r * 0.10)
	var star_r: float = r * 0.105
	var star := PackedVector2Array([
		star_c + Vector2(0, -star_r * 2.0),
		star_c + Vector2(star_r * 0.48, -star_r * 0.42),
		star_c + Vector2(star_r * 2.0, 0),
		star_c + Vector2(star_r * 0.48, star_r * 0.42),
		star_c + Vector2(0, star_r * 2.0),
		star_c + Vector2(-star_r * 0.48, star_r * 0.42),
		star_c + Vector2(-star_r * 2.0, 0),
		star_c + Vector2(-star_r * 0.48, -star_r * 0.42),
	])
	draw_colored_polygon(star, Color(1.0, 0.94, 0.78, a * 0.92))

	if style == "simple":
		return

	# 环上四枚小菱形
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0 - PI * 0.5
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * r * 0.92
		var d: float = r * 0.055
		var diamond := PackedVector2Array([
			p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)
		])
		draw_colored_polygon(diamond, Color(ink.r, ink.g, ink.b, a * 0.72))

	# 两点漂浮的星屑
	var twinkle: float = 0.55 + 0.35 * sin(_time * 1.7)
	draw_circle(c + Vector2(r * 0.72, -r * 0.58), maxf(1.0, r * 0.025), Color(1.0, 0.93, 0.76, a * twinkle))
	draw_circle(c + Vector2(r * 0.48, r * 0.70), maxf(0.8, r * 0.018), Color(0.72, 0.95, 0.78, a * twinkle * 0.8))
