class_name MemoryScreenFrame
extends Control

## 屏幕四角的细线装饰，给界面一点"古旧手稿"的框感。

@export var ink: Color = Color("#c9b58b")
@export var margin: float = 18.0
@export var arm: float = 72.0

var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 200.0 or h < 200.0:
		return
	var m: float = margin
	var a: float = arm
	var alpha: float = 0.16 + 0.025 * sin(_pulse * 0.8)
	var col := Color(ink.r, ink.g, ink.b, alpha)
	var col_soft := Color(ink.r, ink.g, ink.b, 0.06)
	var corners: Array[Vector2] = [
		Vector2(m, m), Vector2(w - m, m), Vector2(m, h - m), Vector2(w - m, h - m)
	]
	var dirs: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for i in range(4):
		var p: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		draw_line(p, p + Vector2(a * d.x, 0), col, 1.0, true)
		draw_line(p, p + Vector2(0, a * d.y), col, 1.0, true)
		draw_line(p + Vector2(0, 8 * d.y), p + Vector2(a * 0.36 * d.x, 8 * d.y), col_soft, 1.0, true)
		draw_line(p + Vector2(8 * d.x, 0), p + Vector2(8 * d.x, a * 0.36 * d.y), col_soft, 1.0, true)
		var tip: Vector2 = p + Vector2(6 * d.x, 6 * d.y)
		var diamond := PackedVector2Array([
			tip + Vector2(0, -3), tip + Vector2(3, 0), tip + Vector2(0, 3), tip + Vector2(-3, 0)
		])
		draw_colored_polygon(diamond, Color(ink.r, ink.g, ink.b, alpha * 1.8))
