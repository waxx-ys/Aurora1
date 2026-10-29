class_name MemoryMistakeTrack
extends Control

## 失误次数指示：菱形烛火。已用掉的是暗红裂隙，未用掉的是空槽。

var limit: int = 4
var used: int = 0
var accent: Color = Color("#c9a86a")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 28)
	resized.connect(queue_redraw)
	queue_redraw()


func set_values(new_limit: int, new_used: int, new_accent: Color) -> void:
	limit = maxi(1, new_limit)
	used = clampi(new_used, 0, limit)
	accent = new_accent
	queue_redraw()


func _draw() -> void:
	if limit <= 0:
		return
	var gap: float = 11.0
	var d: float = 6.6
	var total: float = float(limit) * d * 2.0 + float(limit - 1) * gap
	var start_x: float = (size.x - total) * 0.5 + d
	var cy: float = size.y * 0.5
	var danger := Color("#d4635f")

	# 连接线
	draw_line(Vector2(start_x - d, cy), Vector2(start_x + (limit - 1) * (d * 2.0 + gap) + d, cy), Color(accent.r, accent.g, accent.b, 0.14), 1.0, true)

	for i in range(limit):
		var cx: float = start_x + float(i) * (d * 2.0 + gap)
		var center: Vector2 = Vector2(cx, cy)
		var diamond := PackedVector2Array([
			center + Vector2(0, -d), center + Vector2(d, 0),
			center + Vector2(0, d), center + Vector2(-d, 0)
		])
		if i < used:
			draw_circle(center, d * 1.55, Color(danger.r, danger.g, danger.b, 0.14))
			draw_colored_polygon(diamond, Color(danger.r, danger.g, danger.b, 0.90))
			# 裂痕
			draw_line(center + Vector2(-d * 0.55, -d * 0.20), center + Vector2(d * 0.15, d * 0.18), Color(0.06, 0.02, 0.03, 0.85), 1.2, true)
			draw_line(center + Vector2(d * 0.15, d * 0.18), center + Vector2(d * 0.55, -d * 0.25), Color(0.06, 0.02, 0.03, 0.85), 1.0, true)
		else:
			draw_colored_polygon(diamond, Color(accent.r, accent.g, accent.b, 0.055))
			var outline := PackedVector2Array([
				center + Vector2(0, -d), center + Vector2(d, 0),
				center + Vector2(0, d), center + Vector2(-d, 0),
				center + Vector2(0, -d)
			])
			draw_polyline(outline, Color(accent.r, accent.g, accent.b, 0.42), 1.0, true)
			draw_circle(center, 1.2, Color(accent.r, accent.g, accent.b, 0.35))
