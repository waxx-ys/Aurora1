class_name MemoryOrnamentLine
extends Control

## 标题下方的细线 + 中央菱形装饰。

@export var ink: Color = Color("#c9b58b")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 40.0:
		return
	var y: float = h * 0.5
	var cx: float = w * 0.5
	var gap: float = 42.0

	# 两端渐隐的双层细线
	for i in range(14):
		var t0: float = float(i) / 14.0
		var t1: float = float(i + 1) / 14.0
		var aa: float = lerpf(0.02, 0.32, t0)
		var left0: Vector2 = Vector2(lerpf(0.0, cx - gap, t0), y)
		var left1: Vector2 = Vector2(lerpf(0.0, cx - gap, t1), y)
		var right0: Vector2 = Vector2(lerpf(w, cx + gap, t0), y - 2.0)
		var right1: Vector2 = Vector2(lerpf(w, cx + gap, t1), y - 2.0)
		draw_line(left0, left1, Color(ink.r, ink.g, ink.b, aa), 1.0, true)
		draw_line(right0, right1, Color(ink.r, ink.g, ink.b, aa), 1.0, true)

	# 中央菱形
	var d: float = 5.5
	var diamond := PackedVector2Array([
		Vector2(cx, y - d), Vector2(cx + d, y), Vector2(cx, y + d), Vector2(cx - d, y)
	])
	draw_colored_polygon(diamond, Color(ink.r, ink.g, ink.b, 0.82))
	draw_circle(Vector2(cx - 24.0, y), 2.0, Color(ink.r, ink.g, ink.b, 0.38))
	draw_circle(Vector2(cx + 24.0, y), 2.0, Color(ink.r, ink.g, ink.b, 0.38))
