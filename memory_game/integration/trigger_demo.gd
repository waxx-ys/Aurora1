extends Control

## 模拟“另一个游戏”的触发测试台。
## 用 Godot 打开本场景按 F6，点击按钮发送 GameLink 指令。
## 记忆翻牌会覆盖到本场景上方；按 Esc 或右上角 × 关闭后回到这里。

var _status: Label
var _latency: Label
var _events: Label
var _font_serif: Font
var _font_latin: Font


func _ready() -> void:
	_font_serif = _system_font(400)
	_font_latin = load("res://hakidame.TTF")
	_build_ui()
	GameLink.memory_game_opened.connect(_on_opened)
	GameLink.memory_game_closed.connect(_on_closed)
	GameLink.memory_run_finished.connect(_on_run_finished)
	_refresh()
	_maybe_capture()


func _system_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Songti SC", "STSong", "Noto Serif CJK SC", "SimSun", "Microsoft YaHei"])
	f.font_weight = weight
	f.allow_system_fallback = true
	return f


func _label(text: String, f: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _font_serif_bold())
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color("#ecdfc7"))
	b.add_theme_color_override("font_hover_color", Color("#fff4dc"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.05, 0.07, 0.94)
	normal.border_color = Color(0.61, 0.50, 0.33, 0.42)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.10, 0.08, 0.98)
	hover.border_color = Color(0.82, 0.67, 0.42, 0.90)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal if state == "normal" else hover)
	b.pressed.connect(on_press)
	return b


func _font_serif_bold() -> Font:
	return _system_font(600)


func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = load("res://output/witch-ui/background-forest.png")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.02, 0.02, 0.035, 0.68)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

	var eyebrow := _label("PARKOUR PLACEHOLDER", _font_latin, 13, Color(0.64, 0.57, 0.44, 0.88))
	eyebrow.position = Vector2(0, 56)
	eyebrow.size = Vector2(1024, 20)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(eyebrow)

	var title := _label("其 他 游 戏 · 触 发 测 试", _font_serif_bold(), 34, Color("#efe4cd"))
	title.position = Vector2(0, 80)
	title.size = Vector2(1024, 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var subtitle := _label("模拟跑酷场景：调用 GameLink 指令，记忆翻牌以 overlay 打开，关闭后本场景从暂停处继续。", _font_serif, 13, Color(0.74, 0.67, 0.56, 0.95))
	subtitle.position = Vector2(0, 138)
	subtitle.size = Vector2(1024, 24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(subtitle)

	var panel := Panel.new()
	panel.position = Vector2(222, 192)
	panel.size = Vector2(580, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.03, 0.042, 0.94)
	style.border_color = Color(0.67, 0.55, 0.36, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var inner := _label("OTHER GAME  ·  INTERGAME TRIGGER", _font_latin, 9, Color(0.58, 0.50, 0.38, 0.82))
	inner.position = Vector2(26, 20)
	inner.size = Vector2(528, 18)
	inner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(inner)

	_status = _label("记忆翻牌状态：未打开", _font_serif, 17, Color("#e7d9c0"))
	_status.position = Vector2(26, 52)
	_status.size = Vector2(528, 28)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_status)

	_latency = _label("最近指令耗时：-- ms", _font_serif, 12, Color(0.66, 0.59, 0.48, 0.95))
	_latency.position = Vector2(26, 82)
	_latency.size = Vector2(528, 20)
	_latency.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_latency)

	var row1 := HBoxContainer.new()
	row1.position = Vector2(70, 124)
	row1.size = Vector2(440, 48)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 14)
	panel.add_child(row1)
	row1.add_child(_button("打开大厅", _on_open_menu))
	row1.add_child(_button("直接进入 3×4", _on_open_3x4))

	var row2 := HBoxContainer.new()
	row2.position = Vector2(70, 184)
	row2.size = Vector2(440, 48)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 14)
	panel.add_child(row2)
	row2.add_child(_button("直接进入 4×5", _on_open_4x5))
	row2.add_child(_button("关闭记忆翻牌", _on_close))

	_events = _label("等待指令…", _font_serif, 11, Color(0.62, 0.56, 0.46, 0.95))
	_events.position = Vector2(40, 258)
	_events.size = Vector2(500, 50)
	_events.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_events.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_events.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_events)

	var note := _label("GameLink 会预加载并预实例化记忆翻牌；打开时暂停本场景，Esc / × 关闭后恢复。", _font_serif, 10, Color(0.55, 0.50, 0.43, 0.9))
	note.position = Vector2(26, 340)
	note.size = Vector2(528, 40)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(note)

	var port := _label("UDP trigger: 127.0.0.1:%d" % GameLink.get_trigger_port(), _font_latin, 9, Color(0.51, 0.45, 0.36, 0.8))
	port.position = Vector2(26, 384)
	port.size = Vector2(528, 18)
	port.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(port)


func _send(payload: Dictionary) -> void:
	var result: Dictionary = GameLink.send_command("open_memory_game", payload)
	_latency.text = "最近指令耗时：%.3f ms" % float(result.get("latency_ms", 0.0))
	_events.text = "发送 open_memory_game → %s" % ("OK" if bool(result.get("ok", false)) else String(result.get("error", "failed")))
	_refresh()


func _on_open_menu() -> void:
	_send({"view": "menu"})


func _on_open_3x4() -> void:
	_send({"view": "level", "level": "3x4"})


func _on_open_4x5() -> void:
	_send({"view": "level", "level": "4x5"})


func _on_close() -> void:
	var result: Dictionary = GameLink.send_command("close_memory_game", {"reason": "demo"})
	_events.text = "发送 close_memory_game → %s" % ("OK" if bool(result.get("ok", false)) else String(result.get("error", "failed")))
	_refresh()


func _on_opened(options: Dictionary, latency_ms: float) -> void:
	_status.text = "记忆翻牌状态：已打开（%s）" % String(options.get("view", "menu"))
	_latency.text = "最近指令耗时：%.3f ms" % latency_ms
	_events.text = "memory_game_opened 信号已收到，宿主已暂停。按 Esc 或右上角 × 返回。"


func _on_closed(reason: String) -> void:
	_status.text = "记忆翻牌状态：未打开"
	_events.text = "memory_game_closed 信号已收到（reason=%s），宿主已恢复。" % reason
	_refresh()


func _on_run_finished(result: Dictionary) -> void:
	var buff: Dictionary = result.get("buff", {})
	_events.text = "memory_run_finished：success=%s，刻印=%s" % [
		str(result.get("success", false)), String(buff.get("polarity", "?"))
	]


func _refresh() -> void:
	var open := GameLink.is_memory_game_open()
	_status.text = "记忆翻牌状态：%s" % ("已打开" if open else "未打开")


func _maybe_capture() -> void:
	var capture := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture-embedded":
			capture = true
	if not capture:
		return
	await get_tree().create_timer(0.5).timeout
	_on_open_3x4()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("/tmp/memory_embedded_final.png")
	print("CAPTURE /tmp/memory_embedded_final.png")
	get_tree().quit()
