class_name MemoryCard
extends Control

## 一张记忆牌：正面是卡面画，背面是女巫月纹。
## 翻面、抬起、配对消散、失误抖动都在这里处理；配对规则由主场景决定。

signal flip_requested(card: MemoryCard)

var data: Dictionary = {}
var pair_id: String = ""
var card_size: Vector2 = Vector2(136, 184)
var accent: Color = Color("#c9a86a")
var accent_dim: Color = Color("#5e4a2b")
var face_up: bool = true
var matched: bool = false
var selected: bool = false
var interactive: bool = false
var card_index: int = 0

var _font_body: Font
var _font_latin: Font
var _lift: Control
var _frame: Panel
var _frame_style: StyleBoxFlat
var _front: Control
var _back: Control
var _flash: Panel
var _name_label: Label
var _flipping: bool = false
var _hovered: bool = false
var _move_tween: Tween
var _flash_tween: Tween
var _back_medallion: TextureRect
var _back_sigil: MemorySigil
var _back_title: Label
var _back_footer: Label

const MEDALLION_TEXTURE := preload("res://memory_game/art/ui/medallion.png")


func setup(p_data: Dictionary, p_size: Vector2, body_font: Font, latin_font: Font, p_accent: Color, p_accent_dim: Color, p_index: int) -> void:
	data = p_data.duplicate(true)
	pair_id = String(data.get("pair_id", data.get("id", "unknown")))
	card_size = p_size
	card_index = p_index
	_font_body = body_font
	_font_latin = latin_font
	accent = p_accent
	accent_dim = p_accent_dim
	custom_minimum_size = card_size
	size = card_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	clip_contents = false
	_build()
	_refresh_cursor()


func _build() -> void:
	_lift = Control.new()
	_lift.size = card_size
	_lift.pivot_offset = card_size * 0.5
	_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lift)

	_frame = Panel.new()
	_frame.size = card_size
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_style = StyleBoxFlat.new()
	_frame_style.bg_color = Color("#0d0b11")
	_frame_style.border_color = Color(accent_dim.r, accent_dim.g, accent_dim.b, 0.95)
	_frame_style.set_border_width_all(2)
	_frame_style.corner_radius_top_left = 7
	_frame_style.corner_radius_top_right = 7
	_frame_style.corner_radius_bottom_left = 7
	_frame_style.corner_radius_bottom_right = 7
	_frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	_frame_style.shadow_size = 7
	_frame_style.shadow_offset = Vector2(0, 4)
	_frame_style.anti_aliasing = true
	_frame.add_theme_stylebox_override("panel", _frame_style)
	_lift.add_child(_frame)

	_build_front()
	_build_back()

	# 红闪罩层，失误时短暂显示。
	_flash = Panel.new()
	_flash.size = card_size
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flash_style := StyleBoxFlat.new()
	flash_style.bg_color = Color(0.55, 0.05, 0.08, 0.10)
	flash_style.border_color = Color(0.95, 0.28, 0.26, 0.9)
	flash_style.set_border_width_all(2)
	flash_style.corner_radius_top_left = 7
	flash_style.corner_radius_top_right = 7
	flash_style.corner_radius_bottom_left = 7
	flash_style.corner_radius_bottom_right = 7
	_flash.add_theme_stylebox_override("panel", flash_style)
	_flash.modulate.a = 0.0
	_flash.z_index = 5
	_lift.add_child(_flash)

	resized.connect(_on_resized)


func _build_front() -> void:
	_front = Control.new()
	_front.size = card_size
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lift.add_child(_front)

	var name_h: float = clampf(card_size.y * 0.155, 21.0, 34.0)
	var inset: float = 5.0
	var art_size := Vector2(card_size.x - inset * 2.0, card_size.y - name_h - inset * 2.0)

	var art_area := Control.new()
	art_area.position = Vector2(inset, inset)
	art_area.size = art_size
	art_area.clip_contents = true
	art_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.add_child(art_area)

	var art := TextureRect.new()
	art.size = art_size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var art_path := String(data.get("art", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		art.texture = load(art_path)
	else:
		art.modulate = Color(0.3, 0.3, 0.3)
	art_area.add_child(art)

	# 底部压暗，让牌名可读，也让画与牌框自然衔接。
	var shade := TextureRect.new()
	shade.size = art_size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.02, 0.015, 0.025, 0.0), Color(0.02, 0.015, 0.025, 0.18), Color(0.015, 0.01, 0.02, 0.86)])
	grad.offsets = PackedFloat32Array([0.0, 0.56, 1.0])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_LINEAR
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	shade.texture = grad_tex
	art_area.add_child(shade)

	# 画面内框
	var art_border := Panel.new()
	art_border.size = art_size
	art_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ab_style := StyleBoxFlat.new()
	ab_style.bg_color = Color(0, 0, 0, 0)
	ab_style.border_color = Color(accent.r, accent.g, accent.b, 0.24)
	ab_style.set_border_width_all(1)
	ab_style.corner_radius_top_left = 3
	ab_style.corner_radius_top_right = 3
	ab_style.corner_radius_bottom_left = 3
	ab_style.corner_radius_bottom_right = 3
	art_border.add_theme_stylebox_override("panel", ab_style)
	art_area.add_child(art_border)

	# 牌名底板
	var plate := Panel.new()
	plate.position = Vector2(inset, card_size.y - name_h - inset)
	plate.size = Vector2(card_size.x - inset * 2.0, name_h)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.035, 0.028, 0.043, 0.96)
	plate_style.border_color = Color(accent.r, accent.g, accent.b, 0.24)
	plate_style.border_width_top = 1
	plate_style.corner_radius_bottom_left = 4
	plate_style.corner_radius_bottom_right = 4
	plate.add_theme_stylebox_override("panel", plate_style)
	_front.add_child(plate)

	_name_label = Label.new()
	_name_label.position = Vector2.ZERO
	_name_label.size = plate.size
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.text = String(data.get("name", "?"))
	_name_label.add_theme_font_size_override("font_size", int(clampf(card_size.x * 0.112, 9.0, 16.0)))
	_name_label.add_theme_color_override("font_color", Color("#ded1b5"))
	_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_name_label.add_theme_constant_override("shadow_offset_x", 0)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.add_theme_color_override("font_outline_color", Color(0.015, 0.01, 0.02, 0.9))
	_name_label.add_theme_constant_override("outline_size", 2)
	if _font_body != null:
		_name_label.add_theme_font_override("font", _font_body)
	plate.add_child(_name_label)


func _build_back() -> void:
	_back = Control.new()
	_back.size = card_size
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.visible = false
	_lift.add_child(_back)

	var inset: float = 4.0
	var plate := Panel.new()
	plate.position = Vector2(inset, inset)
	plate.size = card_size - Vector2(inset * 2.0, inset * 2.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color("#0a080e")
	plate_style.border_color = Color(accent.r, accent.g, accent.b, 0.20)
	plate_style.set_border_width_all(1)
	plate_style.corner_radius_top_left = 5
	plate_style.corner_radius_top_right = 5
	plate_style.corner_radius_bottom_left = 5
	plate_style.corner_radius_bottom_right = 5
	plate.add_theme_stylebox_override("panel", plate_style)
	_back.add_child(plate)

	var short_side: float = minf(card_size.x, card_size.y)
	var glow_size: float = short_side * 0.94
	var glow := TextureRect.new()
	glow.position = (card_size - Vector2(glow_size, glow_size)) * 0.5
	glow.size = Vector2(glow_size, glow_size)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var glow_grad := Gradient.new()
	glow_grad.colors = PackedColorArray([Color(accent.r, accent.g, accent.b, 0.20), Color(accent.r, accent.g, accent.b, 0.05), Color(0, 0, 0, 0)])
	glow_grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 128
	glow_tex.height = 128
	glow.texture = glow_tex
	_back.add_child(glow)

	var med_size: float = short_side * 0.58
	_back_medallion = TextureRect.new()
	_back_medallion.position = (card_size - Vector2(med_size, med_size)) * 0.5 + Vector2(0, card_size.y * 0.012)
	_back_medallion.size = Vector2(med_size, med_size)
	_back_medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back_medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_back_medallion.texture = MEDALLION_TEXTURE
	_back_medallion.modulate = Color(0.72, 0.85, 0.78, 0.25)
	_back.add_child(_back_medallion)

	var sigil_size: float = short_side * 0.40
	_back_sigil = MemorySigil.new()
	_back_sigil.ink = Color(accent.r, accent.g, accent.b, 0.92)
	_back_sigil.line_width = 1.0
	_back_sigil.position = (card_size - Vector2(sigil_size, sigil_size)) * 0.5 + Vector2(0, card_size.y * 0.012)
	_back_sigil.size = Vector2(sigil_size, sigil_size)
	_back.add_child(_back_sigil)

	if card_size.x >= 118.0:
		_back_title = Label.new()
		_back_title.position = Vector2(0, 8)
		_back_title.size = Vector2(card_size.x, 16)
		_back_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_back_title.text = "M E M O R Y"
		_back_title.add_theme_font_size_override("font_size", int(clampf(card_size.x * 0.062, 7.0, 10.0)))
		_back_title.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.56))
		if _font_latin != null:
			_back_title.add_theme_font_override("font", _font_latin)
		_back.add_child(_back_title)

		_back_footer = Label.new()
		_back_footer.position = Vector2(0, card_size.y - 20)
		_back_footer.size = Vector2(card_size.x, 14)
		_back_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_back_footer.text = "遗忘之前"
		_back_footer.add_theme_font_size_override("font_size", int(clampf(card_size.x * 0.065, 7.0, 10.0)))
		_back_footer.add_theme_color_override("font_color", Color("#8d806a"))
		if _font_body != null:
			_back_footer.add_theme_font_override("font", _font_body)
		_back.add_child(_back_footer)


func _on_resized() -> void:
	_lift.pivot_offset = size * 0.5
	_refresh_cursor()


func _refresh_cursor() -> void:
	if matched or not interactive or face_up or _flipping:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _refresh_frame() -> void:
	if _frame_style == null:
		return
	if selected:
		_frame_style.border_color = accent.lightened(0.20)
		_frame_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
		_frame_style.shadow_size = 15
	elif _hovered:
		_frame_style.border_color = accent
		_frame_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.20)
		_frame_style.shadow_size = 12
	else:
		_frame_style.border_color = Color(accent_dim.r, accent_dim.g, accent_dim.b, 0.95)
		_frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
		_frame_style.shadow_size = 7


func _move_lift_to(target_y: float, duration: float = 0.14) -> void:
	if not is_instance_valid(_lift):
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(_lift, "position:y", target_y, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_hover_in() -> void:
	if matched:
		return
	_hovered = true
	z_index = 2
	_refresh_frame()
	if not _flipping:
		_move_lift_to(-6.0 if not selected else -8.0)


func _on_hover_out() -> void:
	_hovered = false
	if not selected:
		z_index = 0
	_refresh_frame()
	if not _flipping:
		_move_lift_to(-8.0 if selected else 0.0)


func _gui_input(event: InputEvent) -> void:
	if matched or not interactive or face_up or _flipping:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			flip_requested.emit(self)
			accept_event()


func set_interactive(value: bool) -> void:
	interactive = value
	_refresh_cursor()


func set_selected(value: bool) -> void:
	selected = value
	_refresh_frame()
	z_index = 2 if value else (2 if _hovered else 0)
	if not _flipping:
		_move_lift_to(-8.0 if value else (-6.0 if _hovered else 0.0))


func set_face_up(value: bool, animate: bool = true, duration: float = 0.26) -> void:
	if matched:
		return
	if not animate:
		_face_up_visual(value)
		return
	if _flipping or value == face_up:
		return
	_flipping = true
	_refresh_cursor()
	_move_lift_to(-8.0 if selected else (-6.0 if _hovered else 0.0), 0.08)
	var half: float = maxf(0.06, duration * 0.5)
	var t := create_tween()
	t.tween_property(_lift, "scale:x", 0.025, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_swap_face.bind(value))
	t.tween_property(_lift, "scale:x", 1.0, half).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	_flipping = false
	_refresh_cursor()


func _swap_face(value: bool) -> void:
	_face_up_visual(value)


func _face_up_visual(value: bool) -> void:
	face_up = value
	if is_instance_valid(_front):
		_front.visible = value
	if is_instance_valid(_back):
		_back.visible = not value
	_refresh_cursor()


func flash_error(strength: float = 1.0) -> void:
	if _flash == null or matched:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = 0.9 * strength
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.42).set_ease(Tween.EASE_OUT)

	var shake := create_tween()
	var base_y: float = _lift.position.y
	shake.tween_property(_lift, "position:x", -5.0, 0.04)
	shake.tween_property(_lift, "position:x", 4.0, 0.05)
	shake.tween_property(_lift, "position:x", -3.0, 0.05)
	shake.tween_property(_lift, "position:x", 2.0, 0.05)
	shake.tween_property(_lift, "position:x", 0.0, 0.05)
	shake.parallel().tween_property(_lift, "position:y", base_y, 0.1)


func play_match() -> void:
	if matched:
		return
	matched = true
	selected = false
	interactive = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	z_index = 3
	if _flash != null:
		var glow_style := _flash.get_theme_stylebox("panel") as StyleBoxFlat
		if glow_style != null:
			glow_style.bg_color = Color(0.65, 0.95, 0.72, 0.16)
			glow_style.border_color = Color(0.75, 1.0, 0.82, 0.95)
		_flash.modulate.a = 0.9
		var ft := create_tween()
		ft.tween_property(_flash, "modulate:a", 0.0, 0.38)
	_refresh_frame()
	var t := create_tween()
	t.tween_property(_lift, "scale", Vector2(1.045, 1.045), 0.10).set_trans(Tween.TRANS_QUAD)
	t.tween_property(_lift, "scale", Vector2(0.02, 0.02), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_lift, "modulate:a", 0.0, 0.24).set_ease(Tween.EASE_IN)
	await t.finished
	_lift.visible = false


func appear(delay: float = 0.0) -> void:
	modulate.a = 0.0
	_lift.scale = Vector2(0.92, 0.92)
	_lift.pivot_offset = card_size * 0.5
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_lift, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
