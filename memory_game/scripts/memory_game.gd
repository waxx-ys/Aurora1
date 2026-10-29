extends Control

## 供“其他游戏 / 调度器”使用的信号：关闭请求与一局结束结果。
signal close_requested(reason: String)
signal run_finished(result: Dictionary)

## ===========================================================================
## 记忆翻牌 · 女巫牌阵
## ---------------------------------------------------------------------------
## 一个完整的 Godot 4 记忆配对游戏：
##   · 大厅：标题 + 三档难度（2×3 / 3×4 / 4×5）
##   · 牌局：左侧牌阵，右侧倒计时、失误上限、命运刻印槽
##   · 记忆阶段：所有牌先亮出，倒计时结束后翻面
##   · 配对：翻两张，相同则消散；失误超限或倒计时归零则触发负面刻印
##   · 胜利：触发正面刻印；所有结果通过 RunBuffs 写入跑酷命运池
##
## 数值在 game_config.gd；Buff 内容在 buff_catalog.gd；
## 跑酷接入示例在 integration/parkour_buff_receiver.gd。
## ===========================================================================

const CONFIG = preload("res://memory_game/scripts/game_config.gd")
const BUFF_CATALOG = preload("res://memory_game/scripts/buff_catalog.gd")
const TIMER_RING_SCRIPT = preload("res://memory_game/scripts/memory_timer_ring.gd")
const MISTAKE_TRACK_SCRIPT = preload("res://memory_game/scripts/memory_mistake_track.gd")
const SIGIL_SCRIPT = preload("res://memory_game/scripts/memory_sigil.gd")
const ORNAMENT_SCRIPT = preload("res://memory_game/scripts/memory_ornament_line.gd")
const SCREEN_FRAME_SCRIPT = preload("res://memory_game/scripts/memory_screen_frame.gd")
const DIFFICULTY_CARD_SCRIPT = preload("res://memory_game/scripts/memory_difficulty_card.gd")
const MEMORY_CARD_SCRIPT = preload("res://memory_game/scripts/memory_card.gd")

enum State { MENU, PREVIEW, DEALING, PLAYING, RESOLVING, ENDED }

const INK := Color("#e6d9bd")
const INK_DIM := Color("#a99c86")
const INK_FAINT := Color("#7c705e")
const DANGER := Color("#d4635f")
const GOOD := Color("#8fce9f")
const PURPLE := Color("#a58bd2")
const PANEL_BG := Color(0.043, 0.035, 0.052, 0.88)
const PANEL_BG_SOFT := Color(0.055, 0.045, 0.065, 0.76)

var font_serif: Font
var font_serif_bold: Font
var font_latin: Font
var font_latin_spaced: FontVariation
var font_title_spaced: FontVariation

var _state: int = State.MENU
var _run_id: int = 0
var _level_id: String = ""
var _level: Dictionary = {}
var _accent: Color = Color("#c9a86a")
var _accent_dim: Color = Color("#5e4a2b")
var _cards: Array[MemoryCard] = []
var _selected_cards: Array[MemoryCard] = []
var _pairs_found: int = 0
var _mistakes: int = 0
var _time_left: float = 0.0
var _preview_left: float = 0.0
var _busy: bool = false
var _finish_started: bool = false
var _current_buff: Dictionary = {}
var _background_kind: String = ""

var bg: TextureRect
var _menu_root: Control
var _game_root: Control
var _veil: ColorRect
var _result_root: Control
var _dust: CPUParticles2D
var _dot_texture: ImageTexture
var _frame_overlay: MemoryScreenFrame

# 大厅节点
var _menu_anim_controls: Array[Control] = []
var _menu_fate_label: Label
var _difficulty_cards: Array[MemoryDifficultyCard] = []

# 牌局节点
var _board_panel: Panel
var _board_panel_style: StyleBoxFlat
var _board_grid: GridContainer
var _board_status: Label
var _board_roman: Label
var _level_badge_label: Label
var _phase_label: Label
var _pairs_label: Label
var _fate_top_label: Label
var _timer_ring: MemoryTimerRing
var _mistake_track: MemoryMistakeTrack
var _mistake_count_label: Label
var _buff_status_label: Label
var _buff_pending_label: Label
var _buff_sigil: MemorySigil
var _level_badge_style: StyleBoxFlat
var _phase_style: StyleBoxFlat

# 结算节点
var _result_dim: ColorRect
var _result_panel: Panel
var _result_panel_style: StyleBoxFlat
var _result_sigil: MemorySigil
var _result_eyebrow: Label
var _result_title: Label
var _result_reason: Label
var _result_stats_box: HBoxContainer
var _result_buff_panel: Panel
var _result_buff_style: StyleBoxFlat
var _result_buff_sigil: MemorySigil
var _result_buff_kicker: Label
var _result_buff_title: Label
var _result_buff_desc: Label
var _result_buff_meta: Label
var _result_buff_stamp: Panel
var _result_buff_stamp_style: StyleBoxFlat
var _result_buff_stamp_label: Label
var _result_note: Label
var _result_primary: Button
var _result_secondary: Button
var _result_particles: CPUParticles2D
var _result_divider: MemoryOrnamentLine

# 嵌入到其他游戏时显示的返回入口
var _embedded: bool = false
var _embedded_close: Button
var _embedded_hint: Label


# ===========================================================================
# 初始化
# ===========================================================================

func _ready() -> void:
	randomize()
	add_to_group("memory_game")
	_setup_fonts()
	_install_theme()
	_dot_texture = _make_dot_texture()
	_build_background()
	_build_menu()
	_build_game()
	_build_frame_overlay()
	_build_veil()
	_build_result()
	_build_embedded_controls()
	_connect_bridge()
	_show_menu(true)
	_maybe_capture()


func _setup_fonts() -> void:
	font_serif = _system_font(400)
	font_serif_bold = _system_font(600)
	font_latin = load("res://hakidame.TTF")
	font_latin_spaced = FontVariation.new()
	font_latin_spaced.base_font = font_latin
	font_latin_spaced.spacing_glyph = 2
	font_title_spaced = FontVariation.new()
	font_title_spaced.base_font = font_serif_bold
	font_title_spaced.spacing_glyph = 6


func _system_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Songti SC", "STSong", "Noto Serif CJK SC", "Source Han Serif SC",
		"PingFang SC", "SimSun", "Microsoft YaHei", "Arial Unicode MS"
	])
	f.font_weight = weight
	f.allow_system_fallback = true
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


func _install_theme() -> void:
	var t := Theme.new()
	t.default_font = font_serif
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	theme = t


# ===========================================================================
# 小工具 / 视觉基础件
# ===========================================================================

func _label(text: String, f: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _place_label(parent: Control, text: String, f: Font, font_size: int, color: Color, pos: Vector2, box_size: Vector2, align := HORIZONTAL_ALIGNMENT_CENTER, valign := VERTICAL_ALIGNMENT_CENTER) -> Label:
	var l := _label(text, f, font_size, color)
	l.position = pos
	l.size = box_size
	l.horizontal_alignment = align
	l.vertical_alignment = valign
	parent.add_child(l)
	return l


func _style(bg_color: Color, border_color: Color = Color(0, 0, 0, 0), border_width: int = 1, radius: int = 8, shadow: bool = false, shadow_size: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.border_color = border_color
	s.set_border_width_all(border_width)
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
		s.shadow_size = shadow_size
		s.shadow_offset = Vector2(0, 5)
	return s


func _panel(parent: Control, pos: Vector2, panel_size: Vector2, stylebox: StyleBox) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = panel_size
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", stylebox)
	parent.add_child(p)
	return p


func _radial_texture(inner: Color, mid: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([inner, mid, outer])
	g.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _vertical_texture(top: Color, middle: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([top, middle, bottom])
	g.offsets = PackedFloat32Array([0.0, 0.46, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 16
	tex.height = 256
	return tex


func _make_dot_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d: float = Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
			var a: float = pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_button(text: String, font_size: int, primary: bool, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font_serif_bold)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color("#f1e7d3") if primary else Color("#d4c7ae"))
	b.add_theme_color_override("font_hover_color", Color("#fff8e8"))
	b.add_theme_color_override("font_pressed_color", Color("#e8dcc4"))
	b.add_theme_constant_override("outline_size", 0)

	var normal := _style(
		accent.darkened(0.66) if primary else Color(0.055, 0.047, 0.064, 0.94),
		Color(accent.r, accent.g, accent.b, 0.58 if primary else 0.28),
		1, 6, false
	)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.darkened(0.48) if primary else Color(0.10, 0.085, 0.11, 0.98)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.92)
	hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.14)
	hover.shadow_size = 7
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.darkened(0.60) if primary else Color(0.075, 0.062, 0.085, 1.0)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	focus.set_border_width_all(1)
	focus.corner_radius_top_left = 6
	focus.corner_radius_top_right = 6
	focus.corner_radius_bottom_left = 6
	focus.corner_radius_bottom_right = 6
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", normal)
	return b


func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _format_clock(seconds: float) -> String:
	var total: int = maxi(0, int(ceil(seconds)))
	var m: int = total / 60
	var s: int = total % 60
	return "%02d:%02d" % [m, s]


# ===========================================================================
# 背景
# ===========================================================================

func _build_background() -> void:
	bg = TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture = load("res://output/witch-ui/background-library.png")
	add_child(bg)

	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.035, 0.020, 0.055, 0.30)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

	var vignette := TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.texture = _radial_texture(
		Color(0.01, 0.0, 0.02, 0.0),
		Color(0.01, 0.0, 0.02, 0.15),
		Color(0.005, 0.0, 0.015, 0.86)
	)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture = _vertical_texture(
		Color(0.01, 0.0, 0.02, 0.70),
		Color(0.01, 0.0, 0.02, 0.0),
		Color(0.005, 0.0, 0.015, 0.48)
	)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_dust = CPUParticles2D.new()
	_dust.position = get_viewport_rect().size * 0.5
	_dust.amount = 38
	_dust.lifetime = 10.0
	_dust.preprocess = 10.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(500, 380)
	_dust.direction = Vector2(0, -1)
	_dust.spread = 38.0
	_dust.gravity = Vector2(0, -2.5)
	_dust.initial_velocity_min = 2.0
	_dust.initial_velocity_max = 11.0
	_dust.scale_amount_min = 0.22
	_dust.scale_amount_max = 0.75
	_dust.color = Color(0.74, 0.91, 0.76, 0.22)
	_dust.texture = _dot_texture
	_dust.emitting = true
	add_child(_dust)


func _set_background(kind: String) -> void:
	if kind == _background_kind or bg == null:
		return
	_background_kind = kind
	var path := "res://output/witch-ui/background-library.png"
	match kind:
		"apothecary":
			path = "res://output/witch-ui/background-apothecary.png"
		"forest":
			path = "res://output/witch-ui/background-forest.png"
		"library":
			path = "res://output/witch-ui/background-library.png"
	bg.texture = load(path)


# ===========================================================================
# 大厅：标题 + 难度选择 + 跑酷命运池状态
# ===========================================================================

var _menu_anim_tween: Tween


func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_menu_root)

	# 标题后方的一团紫色月晕
	var glow := TextureRect.new()
	glow.position = Vector2(92, 12)
	glow.size = Vector2(840, 260)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.texture = _radial_texture(
		Color(0.52, 0.36, 0.70, 0.20),
		Color(0.30, 0.19, 0.45, 0.09),
		Color(0.0, 0.0, 0.0, 0.0)
	)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(glow)
	_menu_anim_controls.append(glow)

	var eyebrow := _place_label(
		_menu_root, "THE WITCH'S MEMORY", font_latin_spaced, 12,
		Color(0.72, 0.63, 0.49, 0.92), Vector2(0, 38), Vector2(1024, 20)
	)
	_menu_anim_controls.append(eyebrow)

	var title := _place_label(
		_menu_root, "记忆翻牌", font_title_spaced, 82,
		Color("#f2e7ce"), Vector2(0, 52), Vector2(1024, 116)
	)
	title.add_theme_color_override("font_outline_color", Color("#160d1d"))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_shadow_color", Color(0.02, 0.0, 0.03, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	_menu_anim_controls.append(title)

	var subtitle := _place_label(
		_menu_root, "女巫把记忆封进了牌里。翻开它们，别让遗忘先找到你。",
		font_serif, 15, Color(0.79, 0.72, 0.61, 0.94),
		Vector2(0, 174), Vector2(1024, 24)
	)
	_menu_anim_controls.append(subtitle)

	var ornament := ORNAMENT_SCRIPT.new()
	ornament.position = Vector2(272, 206)
	ornament.size = Vector2(480, 18)
	ornament.ink = Color(0.79, 0.70, 0.53, 0.85)
	_menu_root.add_child(ornament)
	_menu_anim_controls.append(ornament)

	var section_latin := _place_label(
		_menu_root, "C H O O S E   Y O U R   T R I A L", font_latin_spaced, 9,
		Color(0.61, 0.53, 0.41, 0.82), Vector2(0, 236), Vector2(1024, 14)
	)
	_menu_anim_controls.append(section_latin)

	var section_cn := _place_label(
		_menu_root, "选 择 难 度", font_serif_bold, 20,
		Color(0.90, 0.84, 0.72), Vector2(0, 252), Vector2(1024, 30)
	)
	_menu_anim_controls.append(section_cn)

	var row := HBoxContainer.new()
	row.position = Vector2(0, 294)
	row.size = Vector2(1024, 252)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu_root.add_child(row)

	for i in range(CONFIG.LEVEL_ORDER.size()):
		var id: String = CONFIG.LEVEL_ORDER[i]
		var level: Dictionary = CONFIG.get_level(id)
		var card: MemoryDifficultyCard = DIFFICULTY_CARD_SCRIPT.new()
		card.level_id = id
		card.data = level
		card.accent = CONFIG.accent_of(level)
		card.accent_dim = CONFIG.accent_dim_of(level)
		card.font_title = font_serif_bold
		card.font_body = font_serif
		card.font_latin = font_latin
		card.card_index = i + 1
		card.custom_minimum_size = Vector2(286, 252)
		card.pressed.connect(_on_difficulty_pressed.bind(id))
		row.add_child(card)
		_difficulty_cards.append(card)
		_menu_anim_controls.append(card)

	var hint := _place_label(
		_menu_root, "翻开两张相同的秘术牌 · 牌面会先亮出数秒，然后全部翻面",
		font_serif, 12, Color(0.66, 0.60, 0.51, 0.92),
		Vector2(0, 558), Vector2(1024, 20)
	)
	_menu_anim_controls.append(hint)

	# 跑酷命运池的小状态条
	var pill := Panel.new()
	pill.position = Vector2(282, 588)
	pill.size = Vector2(460, 42)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := _style(Color(0.045, 0.038, 0.055, 0.82), Color(0.56, 0.46, 0.30, 0.35), 1, 21)
	pill.add_theme_stylebox_override("panel", pill_style)
	_menu_root.add_child(pill)
	_menu_anim_controls.append(pill)

	var pill_sigil := SIGIL_SCRIPT.new()
	pill_sigil.position = Vector2(12, 9)
	pill_sigil.size = Vector2(24, 24)
	pill_sigil.ink = Color(0.83, 0.73, 0.52, 0.90)
	pill_sigil.line_width = 0.8
	pill.add_child(pill_sigil)

	_menu_fate_label = _place_label(
		pill, "跑酷命运池 · 0 枚刻印待带入", font_serif, 12,
		Color(0.80, 0.73, 0.60, 0.95), Vector2(44, 0), Vector2(404, 42),
		HORIZONTAL_ALIGNMENT_LEFT
	)

	var note := _place_label(
		_menu_root, "失败留下负面刻印，胜利留下正面刻印。两者都会写入跑酷模式共享的命运池。",
		font_serif, 11, Color(0.58, 0.53, 0.46, 0.88),
		Vector2(0, 638), Vector2(1024, 18)
	)
	_menu_anim_controls.append(note)

	var footer_left := _place_label(
		_menu_root, "地铁跑酷 · 女巫牌阵", font_serif, 10,
		Color(0.50, 0.46, 0.39, 0.72), Vector2(26, 706), Vector2(360, 18),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_menu_anim_controls.append(footer_left)
	var footer_right := _place_label(
		_menu_root, "EVERY CARD REMEMBERS", font_latin_spaced, 8,
		Color(0.50, 0.46, 0.39, 0.62), Vector2(638, 706), Vector2(360, 18),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	_menu_anim_controls.append(footer_right)


func _on_difficulty_pressed(level_id: String) -> void:
	if _state != State.MENU:
		return
	_start_level(level_id)


func _menu_animate_in(immediate: bool = false) -> void:
	if _menu_anim_tween != null and _menu_anim_tween.is_valid():
		_menu_anim_tween.kill()
	if immediate:
		for c in _menu_anim_controls:
			c.modulate.a = 1.0
		return
	for c in _menu_anim_controls:
		c.modulate.a = 0.0
	if _menu_anim_controls.is_empty():
		return
	_menu_anim_tween = create_tween()
	_menu_anim_tween.tween_property(_menu_anim_controls[0], "modulate:a", 1.0, 0.42).set_delay(0.04)
	for i in range(1, _menu_anim_controls.size()):
		_menu_anim_tween.parallel().tween_property(
			_menu_anim_controls[i], "modulate:a", 1.0, 0.42
		).set_delay(0.04 + float(i) * 0.035)


# ===========================================================================
# 牌局：顶栏 + 左侧牌阵 + 右侧 HUD
# ===========================================================================

func _build_game() -> void:
	_game_root = Control.new()
	_game_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_game_root.visible = false
	add_child(_game_root)

	var top_shade := TextureRect.new()
	top_shade.position = Vector2(0, 0)
	top_shade.size = Vector2(1024, 120)
	top_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_shade.stretch_mode = TextureRect.STRETCH_SCALE
	top_shade.texture = _vertical_texture(
		Color(0.008, 0.0, 0.014, 0.68),
		Color(0.008, 0.0, 0.014, 0.16),
		Color(0.008, 0.0, 0.014, 0.0)
	)
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_root.add_child(top_shade)

	var back := _make_button("←  返回", 13, false, Color("#b9a782"))
	back.position = Vector2(26, 24)
	back.size = Vector2(94, 36)
	back.pressed.connect(_return_to_menu)
	_game_root.add_child(back)

	var game_title := _place_label(
		_game_root, "记忆翻牌", font_serif_bold, 23, Color("#eee2c9"),
		Vector2(136, 12), Vector2(360, 34), HORIZONTAL_ALIGNMENT_LEFT
	)
	game_title.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.03, 0.75))
	game_title.add_theme_constant_override("outline_size", 4)
	_place_label(
		_game_root, "THE WITCH'S MEMORY", font_latin_spaced, 8,
		Color(0.64, 0.56, 0.43, 0.8), Vector2(138, 43), Vector2(260, 16),
		HORIZONTAL_ALIGNMENT_LEFT
	)

	# 难度徽章
	_level_badge_style = _style(Color(0.05, 0.042, 0.06, 0.88), Color(_accent.r, _accent.g, _accent.b, 0.38), 1, 16)
	var badge_panel := Panel.new()
	badge_panel.position = Vector2(300, 24)
	badge_panel.size = Vector2(184, 34)
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_theme_stylebox_override("panel", _level_badge_style)
	_game_root.add_child(badge_panel)
	_level_badge_label = _place_label(
		badge_panel, "LEVEL II  ·  3 × 4", font_serif, 12,
		Color(0.86, 0.78, 0.63), Vector2.ZERO, badge_panel.size
	)

	# 阶段提示
	_phase_style = _style(Color(0.045, 0.038, 0.058, 0.80), Color(_accent.r, _accent.g, _accent.b, 0.24), 1, 16)
	var phase_panel := Panel.new()
	phase_panel.position = Vector2(508, 24)
	phase_panel.size = Vector2(236, 34)
	phase_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_panel.add_theme_stylebox_override("panel", _phase_style)
	_game_root.add_child(phase_panel)
	_phase_label = _place_label(
		phase_panel, "记住牌面 · 3", font_serif, 11.5,
		Color(0.82, 0.74, 0.60, 0.96), Vector2.ZERO, phase_panel.size
	)

	_pairs_label = _place_label(
		_game_root, "已配对  0 / 6", font_serif_bold, 15, Color("#e6d9bd"),
		Vector2(740, 10), Vector2(258, 28), HORIZONTAL_ALIGNMENT_RIGHT
	)
	_fate_top_label = _place_label(
		_game_root, "跑酷命运池 · 0", font_serif, 10,
		Color(0.63, 0.57, 0.47, 0.85), Vector2(740, 38), Vector2(258, 18),
		HORIZONTAL_ALIGNMENT_RIGHT
	)

	# —— 左侧牌阵 ——
	_board_panel_style = _style(Color(0.029, 0.024, 0.036, 0.78), Color(_accent.r, _accent.g, _accent.b, 0.17), 1, 12, true, 16)
	_board_panel = _panel(_game_root, Vector2(26, 88), Vector2(666, 656), _board_panel_style)
	_board_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var board_frame := SCREEN_FRAME_SCRIPT.new()
	board_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_frame.margin = 9
	board_frame.arm = 30
	board_frame.ink = Color(0.80, 0.69, 0.49, 0.8)
	_board_panel.add_child(board_frame)

	var header_sigil := SIGIL_SCRIPT.new()
	header_sigil.position = Vector2(16, 14)
	header_sigil.size = Vector2(22, 22)
	header_sigil.ink = Color(_accent.r, _accent.g, _accent.b, 0.90)
	header_sigil.line_width = 0.8
	_board_panel.add_child(header_sigil)

	_place_label(
		_board_panel, "牌阵", font_serif_bold, 14.5, Color(0.86, 0.78, 0.64),
		Vector2(44, 8), Vector2(100, 30), HORIZONTAL_ALIGNMENT_LEFT
	)
	_place_label(
		_board_panel, "THE DECK", font_latin_spaced, 7.5, Color(0.55, 0.49, 0.39, 0.85),
		Vector2(82, 16), Vector2(100, 16), HORIZONTAL_ALIGNMENT_LEFT
	)
	_board_status = _place_label(
		_board_panel, "翻开两张相同的秘术牌", font_serif, 11.5,
		Color(0.67, 0.61, 0.51, 0.90), Vector2(352, 8), Vector2(296, 30),
		HORIZONTAL_ALIGNMENT_RIGHT
	)

	var header_line := ColorRect.new()
	header_line.position = Vector2(16, 42)
	header_line.size = Vector2(634, 1)
	header_line.color = Color(_accent.r, _accent.g, _accent.b, 0.13)
	header_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_panel.add_child(header_line)

	_board_roman = _place_label(
		_board_panel, "II", font_latin, 124, Color(_accent.r, _accent.g, _accent.b, 0.032),
		Vector2(500, 520), Vector2(150, 126), HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM
	)

	var center := CenterContainer.new()
	center.position = Vector2(16, 52)
	center.size = Vector2(634, 588)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_panel.add_child(center)

	_board_grid = GridContainer.new()
	_board_grid.columns = 3
	_board_grid.add_theme_constant_override("h_separation", 13)
	_board_grid.add_theme_constant_override("v_separation", 13)
	_board_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_board_grid)

	# —— 右侧 HUD ——
	var timer_panel := _panel(
		_game_root, Vector2(710, 88), Vector2(288, 252),
		_style(Color(0.035, 0.029, 0.043, 0.84), Color(0.58, 0.49, 0.35, 0.24), 1, 10, true, 12)
	)
	_place_label(
		timer_panel, "倒计时", font_serif_bold, 15, Color(0.86, 0.79, 0.66),
		Vector2(16, 10), Vector2(150, 28), HORIZONTAL_ALIGNMENT_LEFT
	)
	_place_label(
		timer_panel, "TIME REMAINING", font_latin_spaced, 7,
		Color(0.58, 0.51, 0.40, 0.80), Vector2(120, 17), Vector2(152, 16),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	_timer_ring = TIMER_RING_SCRIPT.new()
	_timer_ring.configure(font_serif, font_serif, font_latin)
	_timer_ring.position = Vector2(59, 48)
	_timer_ring.size = Vector2(170, 170)
	_timer_ring.custom_minimum_size = Vector2(170, 170)
	timer_panel.add_child(_timer_ring)
	_place_label(
		timer_panel, "归零会触发负面刻印", font_serif, 9.5,
		Color(0.60, 0.53, 0.44, 0.72), Vector2(0, 224), Vector2(288, 16)
	)

	var mistake_panel := _panel(
		_game_root, Vector2(710, 352), Vector2(288, 150),
		_style(Color(0.035, 0.029, 0.043, 0.84), Color(0.58, 0.49, 0.35, 0.22), 1, 10, true, 12)
	)
	_place_label(
		mistake_panel, "失误次数", font_serif_bold, 15, Color(0.86, 0.79, 0.66),
		Vector2(16, 10), Vector2(160, 28), HORIZONTAL_ALIGNMENT_LEFT
	)
	_mistake_count_label = _place_label(
		mistake_panel, "0 / 4", font_serif_bold, 16, Color("#e6d9bd"),
		Vector2(154, 8), Vector2(118, 28), HORIZONTAL_ALIGNMENT_RIGHT
	)
	_mistake_track = MISTAKE_TRACK_SCRIPT.new()
	_mistake_track.position = Vector2(18, 50)
	_mistake_track.size = Vector2(252, 30)
	mistake_panel.add_child(_mistake_track)
	_place_label(
		mistake_panel, "超过次数限制会立即失败", font_serif, 9.5,
		Color(0.60, 0.53, 0.44, 0.72), Vector2(16, 100), Vector2(256, 16),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var mistake_rule := ColorRect.new()
	mistake_rule.position = Vector2(16, 126)
	mistake_rule.size = Vector2(256, 1)
	mistake_rule.color = Color(0.66, 0.56, 0.40, 0.10)
	mistake_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mistake_panel.add_child(mistake_rule)

	var buff_panel := _panel(
		_game_root, Vector2(710, 516), Vector2(288, 156),
		_style(Color(0.035, 0.029, 0.043, 0.84), Color(0.58, 0.49, 0.35, 0.22), 1, 10, true, 12)
	)
	_place_label(
		buff_panel, "命运刻印", font_serif_bold, 15, Color(0.86, 0.79, 0.66),
		Vector2(16, 10), Vector2(170, 28), HORIZONTAL_ALIGNMENT_LEFT
	)
	_place_label(
		buff_panel, "PARKOUR LINK", font_latin_spaced, 7,
		Color(0.58, 0.51, 0.40, 0.80), Vector2(166, 17), Vector2(106, 16),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	_buff_sigil = SIGIL_SCRIPT.new()
	_buff_sigil.position = Vector2(16, 44)
	_buff_sigil.size = Vector2(42, 42)
	_buff_sigil.ink = Color(_accent.r, _accent.g, _accent.b, 0.92)
	_buff_sigil.line_width = 0.8
	buff_panel.add_child(_buff_sigil)
	_buff_status_label = _place_label(
		buff_panel, "等待试炼结果", font_serif, 13, Color(0.84, 0.77, 0.64),
		Vector2(68, 40), Vector2(204, 24), HORIZONTAL_ALIGNMENT_LEFT
	)
	_buff_pending_label = _place_label(
		buff_panel, "命运池 · 0 枚待带入", font_serif, 10,
		Color(0.65, 0.58, 0.47, 0.88), Vector2(68, 62), Vector2(204, 18),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_place_label(
		buff_panel, "结果会写入跑酷命运池，由跑酷模式\n读取并消耗。", font_serif, 9.5,
		Color(0.58, 0.53, 0.45, 0.82), Vector2(16, 98), Vector2(256, 40),
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP
	)

	var restart := _make_button("重新开始", 12.5, false, _accent)
	restart.position = Vector2(710, 686)
	restart.size = Vector2(138, 46)
	restart.pressed.connect(_retry_current_level)
	_game_root.add_child(restart)

	var menu_btn := _make_button("返回厅堂", 12.5, false, _accent)
	menu_btn.position = Vector2(860, 686)
	menu_btn.size = Vector2(138, 46)
	menu_btn.pressed.connect(_return_to_menu)
	_game_root.add_child(menu_btn)


# ===========================================================================
# 转场遮罩 + 结算界面
# ===========================================================================

func _build_frame_overlay() -> void:
	_frame_overlay = SCREEN_FRAME_SCRIPT.new()
	_frame_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_overlay.margin = 18
	_frame_overlay.arm = 66
	_frame_overlay.ink = Color(0.82, 0.71, 0.52, 0.90)
	add_child(_frame_overlay)


func _build_veil() -> void:
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(0.015, 0.005, 0.025, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)


func _veil_flash() -> void:
	if _veil == null:
		return
	_veil.color.a = 0.76
	var t := create_tween()
	t.tween_property(_veil, "color:a", 0.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


var _result_stat_value_labels: Array[Label] = []
var _result_tween: Tween


func _build_result() -> void:
	_result_root = Control.new()
	_result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.visible = false
	add_child(_result_root)

	_result_dim = ColorRect.new()
	_result_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_dim.color = Color(0.004, 0.0, 0.01, 0.74)
	_result_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.add_child(_result_dim)

	var back_glow := TextureRect.new()
	back_glow.position = Vector2(272, 120)
	back_glow.size = Vector2(480, 480)
	back_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_glow.stretch_mode = TextureRect.STRETCH_SCALE
	back_glow.texture = _radial_texture(
		Color(0.40, 0.25, 0.55, 0.16),
		Color(0.22, 0.12, 0.33, 0.07),
		Color(0, 0, 0, 0)
	)
	back_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(back_glow)

	_result_particles = CPUParticles2D.new()
	_result_particles.position = Vector2(512, 440)
	_result_particles.amount = 36
	_result_particles.lifetime = 1.35
	_result_particles.one_shot = true
	_result_particles.explosiveness = 0.92
	_result_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_result_particles.emission_rect_extents = Vector2(210, 16)
	_result_particles.direction = Vector2(0, -1)
	_result_particles.spread = 72.0
	_result_particles.initial_velocity_min = 70.0
	_result_particles.initial_velocity_max = 230.0
	_result_particles.gravity = Vector2(0, 430)
	_result_particles.scale_amount_min = 0.25
	_result_particles.scale_amount_max = 1.15
	_result_particles.color = Color(0.85, 0.72, 0.42, 0.7)
	_result_particles.texture = _dot_texture
	_result_particles.emitting = false
	_result_root.add_child(_result_particles)

	_result_panel_style = _style(Color(0.028, 0.023, 0.034, 0.985), Color(0.58, 0.49, 0.35, 0.50), 1, 13, true, 28)
	_result_panel = _panel(_result_root, Vector2(202, 94), Vector2(620, 580), _result_panel_style)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_panel.pivot_offset = Vector2(310, 290)

	var panel_frame := SCREEN_FRAME_SCRIPT.new()
	panel_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_frame.margin = 10
	panel_frame.arm = 34
	panel_frame.ink = Color(0.82, 0.72, 0.54, 0.90)
	_result_panel.add_child(panel_frame)

	_result_eyebrow = _place_label(
		_result_panel, "TRIAL COMPLETE", font_latin_spaced, 9,
		Color(0.64, 0.56, 0.43, 0.88), Vector2(0, 22), Vector2(620, 16)
	)

	_result_sigil = SIGIL_SCRIPT.new()
	_result_sigil.position = Vector2(287, 40)
	_result_sigil.size = Vector2(46, 46)
	_result_sigil.ink = Color(0.88, 0.77, 0.55, 0.95)
	_result_sigil.line_width = 1.0
	_result_panel.add_child(_result_sigil)

	_result_title = _place_label(
		_result_panel, "记忆完整", font_serif_bold, 40, Color("#efe3c8"),
		Vector2(0, 92), Vector2(620, 52)
	)
	_result_title.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.03, 0.7))
	_result_title.add_theme_constant_override("outline_size", 5)
	_result_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_result_title.add_theme_constant_override("shadow_offset_y", 3)

	_result_reason = _place_label(
		_result_panel, "所有秘术牌都已归位。", font_serif, 13,
		Color(0.70, 0.64, 0.54, 0.95), Vector2(60, 148), Vector2(500, 22)
	)

	_result_stats_box = HBoxContainer.new()
	_result_stats_box.position = Vector2(60, 180)
	_result_stats_box.size = Vector2(500, 60)
	_result_stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_stats_box.add_theme_constant_override("separation", 54)
	_result_stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(_result_stats_box)

	var stat_captions := ["用时", "失误", "配对"]
	for i in range(3):
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(120, 60)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_result_stats_box.add_child(col)
		var value := _label("--", font_serif_bold, 21, Color("#e6d9bd"))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(value)
		_result_stat_value_labels.append(value)
		var caption := _label(stat_captions[i], font_serif, 10, Color(0.60, 0.54, 0.45, 0.88))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(caption)

	_result_divider = ORNAMENT_SCRIPT.new()
	_result_divider.position = Vector2(90, 250)
	_result_divider.size = Vector2(440, 18)
	_result_divider.ink = Color(0.79, 0.70, 0.53, 0.75)
	_result_panel.add_child(_result_divider)

	# 刻印 / Buff 展示槽
	_result_buff_style = _style(Color(0.045, 0.035, 0.055, 0.92), Color(0.65, 0.54, 0.34, 0.36), 1, 9)
	_result_buff_panel = Panel.new()
	_result_buff_panel.position = Vector2(50, 276)
	_result_buff_panel.size = Vector2(520, 182)
	_result_buff_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_buff_panel.add_theme_stylebox_override("panel", _result_buff_style)
	_result_panel.add_child(_result_buff_panel)

	_result_buff_kicker = _place_label(
		_result_buff_panel, "负面刻印 · 未配置", font_serif, 9.5,
		Color(0.75, 0.58, 0.48, 0.95), Vector2(20, 14), Vector2(480, 16),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_result_buff_sigil = SIGIL_SCRIPT.new()
	_result_buff_sigil.position = Vector2(20, 42)
	_result_buff_sigil.size = Vector2(58, 58)
	_result_buff_sigil.ink = Color(0.84, 0.62, 0.55, 0.95)
	_result_buff_sigil.line_width = 1.0
	_result_buff_panel.add_child(_result_buff_sigil)

	_result_buff_title = _place_label(
		_result_buff_panel, "未命名的刻印", font_serif_bold, 20,
		Color(0.91, 0.83, 0.68), Vector2(96, 36), Vector2(400, 30), HORIZONTAL_ALIGNMENT_LEFT
	)
	_result_buff_meta = _place_label(
		_result_buff_panel, "目标：跑酷模式  ·  状态：待消耗", font_serif, 10,
		Color(0.62, 0.56, 0.46, 0.90), Vector2(96, 65), Vector2(400, 18),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_result_buff_desc = _place_label(
		_result_buff_panel, "效果内容尚未填写。数据槽位与跑酷接口已经就绪。",
		font_serif, 12, Color(0.73, 0.67, 0.56, 0.95),
		Vector2(20, 112), Vector2(480, 38), HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP
	)
	_result_buff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 未配置内容的印章，让“预留槽位”在视觉上是一个明确状态。
	_result_buff_stamp_style = _style(Color(0, 0, 0, 0), Color(0.78, 0.60, 0.50, 0.46), 1, 3)
	_result_buff_stamp = Panel.new()
	_result_buff_stamp.position = Vector2(418, 148)
	_result_buff_stamp.size = Vector2(82, 22)
	_result_buff_stamp.rotation = deg_to_rad(-3.0)
	_result_buff_stamp.pivot_offset = _result_buff_stamp.size * 0.5
	_result_buff_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_buff_stamp.add_theme_stylebox_override("panel", _result_buff_stamp_style)
	_result_buff_panel.add_child(_result_buff_stamp)
	_result_buff_stamp_label = _place_label(
		_result_buff_stamp, "待 配 置", font_serif, 10,
		Color(0.78, 0.60, 0.50, 0.75), Vector2.ZERO, _result_buff_stamp.size
	)

	_result_note = _place_label(
		_result_panel, "已写入跑酷命运池  ·  RunBuffs.consume_pending() 可读取",
		font_serif, 9.5, Color(0.58, 0.52, 0.43, 0.85),
		Vector2(0, 464), Vector2(620, 18)
	)

	_result_primary = _make_button("再试一次", 14, true, Color("#c9a86a"))
	_result_primary.position = Vector2(92, 494)
	_result_primary.size = Vector2(210, 48)
	_result_primary.pressed.connect(_retry_current_level)
	_result_panel.add_child(_result_primary)

	_result_secondary = _make_button("返回厅堂", 14, false, Color("#c9a86a"))
	_result_secondary.position = Vector2(318, 494)
	_result_secondary.size = Vector2(210, 48)
	_result_secondary.pressed.connect(_return_to_menu)
	_result_panel.add_child(_result_secondary)


# ===========================================================================
# 大厅 / 牌局切换
# ===========================================================================

func _show_menu(immediate: bool = false) -> void:
	_run_id += 1
	_state = State.MENU
	_busy = false
	_finish_started = false
	_current_buff = {}
	_selected_cards.clear()
	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	if _result_root != null:
		_result_root.visible = false
	if _game_root != null:
		_game_root.visible = false
	if _menu_root != null:
		_menu_root.visible = true
	_set_background("library")
	_clear_board()
	_refresh_fate_ui()
	if _menu_root != null:
		_menu_animate_in(immediate)
	if not immediate:
		_veil_flash()


func _return_to_menu() -> void:
	_show_menu(false)


func _start_level(level_id: String, instant: bool = false) -> void:
	var level: Dictionary = CONFIG.get_level(level_id)
	if level.is_empty():
		push_warning("MemoryGame: 未知难度 %s" % level_id)
		return

	_run_id += 1
	_level_id = level_id
	_level = level
	_accent = CONFIG.accent_of(level)
	_accent_dim = CONFIG.accent_dim_of(level)
	_state = State.PREVIEW
	_busy = false
	_finish_started = false
	_current_buff = {}
	_pairs_found = 0
	_mistakes = 0
	_time_left = float(level.get("time_limit", 45.0))
	_preview_left = float(level.get("preview_time", 3.0))
	_selected_cards.clear()

	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	_result_root.visible = false
	_menu_root.visible = false
	_game_root.visible = true

	_set_background(_level_background(level_id))
	_apply_level_theme()
	_build_board()
	_update_hud()
	_update_timer()
	_board_status.text = "记住牌面与位置 · 然后它们会翻面"
	_buff_status_label.text = "等待试炼结果"
	_buff_sigil.ink = Color(_accent.r, _accent.g, _accent.b, 0.92)
	_refresh_fate_ui()
	if not instant:
		_veil_flash()


func _level_background(level_id: String) -> String:
	match level_id:
		"2x3":
			return "apothecary"
		"3x4":
			return "library"
		"4x5":
			return "forest"
	return "apothecary"


func _apply_level_theme() -> void:
	_level_badge_label.text = "LEVEL %s  ·  %d × %d" % [
		String(_level.get("roman", "I")),
		int(_level.get("rows", 2)),
		int(_level.get("columns", 3))
	]
	_level_badge_label.add_theme_color_override("font_color", _accent.lightened(0.36))
	_level_badge_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_level_badge_label.add_theme_constant_override("shadow_offset_y", 1)
	if _level_badge_style != null:
		_level_badge_style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.52)
		_level_badge_style.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.055).blend(Color(0.05, 0.042, 0.06, 0.88))
	if _phase_style != null:
		_phase_style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.24)
	if _board_panel_style != null:
		_board_panel_style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.18)
	_board_roman.text = String(_level.get("roman", "I"))
	_board_roman.add_theme_color_override("font_color", Color(_accent.r, _accent.g, _accent.b, 0.035))
	_mistake_count_label.add_theme_color_override("font_color", _accent.lightened(0.24))
	_pairs_label.add_theme_color_override("font_color", _accent.lightened(0.34))
	_buff_sigil.ink = Color(_accent.r, _accent.g, _accent.b, 0.92)


func _build_board() -> void:
	_clear_board()
	var columns: int = int(_level.get("columns", 3))
	var gap: int = int(_level.get("gap", 12))
	_board_grid.columns = columns
	_board_grid.add_theme_constant_override("h_separation", gap)
	_board_grid.add_theme_constant_override("v_separation", gap)

	var pairs: int = int(_level.get("pairs", 3))
	var pool_indices: Array = range(CONFIG.CARD_POOL.size())
	pool_indices.shuffle()
	var chosen: Array = pool_indices.slice(0, mini(pairs, pool_indices.size()))
	var deck: Array[Dictionary] = []
	for pool_index in chosen:
		var design: Dictionary = CONFIG.CARD_POOL[int(pool_index)]
		for copy_index in range(2):
			deck.append({
				"pair_id": String(design.get("id", "")),
				"design_id": String(design.get("id", "")),
				"name": String(design.get("name", "?")),
				"full_name": String(design.get("full_name", design.get("name", "?"))),
				"art": String(design.get("art", "")),
				"lore": String(design.get("lore", "")),
				"copy": copy_index
			})
	deck.shuffle()

	var card_size := Vector2(float(_level["card_size"][0]), float(_level["card_size"][1]))
	for i in range(deck.size()):
		var card: MemoryCard = MEMORY_CARD_SCRIPT.new()
		card.setup(deck[i], card_size, font_serif, font_latin, _accent, _accent_dim, i)
		card.flip_requested.connect(_on_card_flip_requested)
		_board_grid.add_child(card)
		_cards.append(card)
		card.appear(float(i) * 0.018)

	_set_cards_interactive(false)


func _clear_board() -> void:
	if _board_grid != null:
		for child in _board_grid.get_children():
			_board_grid.remove_child(child)
			child.queue_free()
	_cards.clear()
	_selected_cards.clear()


func _set_cards_interactive(value: bool) -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.set_interactive(value and not card.matched)


# ===========================================================================
# HUD 刷新
# ===========================================================================

func _update_hud() -> void:
	if _level.is_empty():
		return
	var pairs_total: int = int(_level.get("pairs", 3))
	var mistake_limit: int = int(_level.get("max_mistakes", 3))
	_pairs_label.text = "已配对  %d / %d" % [_pairs_found, pairs_total]
	_mistake_count_label.text = "%d / %d" % [_mistakes, mistake_limit]
	if _mistakes >= mistake_limit - 1 and mistake_limit > 0:
		_mistake_count_label.add_theme_color_override("font_color", DANGER.lightened(0.12))
	else:
		_mistake_count_label.add_theme_color_override("font_color", _accent.lightened(0.24))
	_mistake_track.set_values(mistake_limit, _mistakes, _accent)
	_refresh_fate_ui()


func _update_timer() -> void:
	if _timer_ring == null or _level.is_empty():
		return
	var preview_total: float = maxf(0.001, float(_level.get("preview_time", 3.0)))
	var time_limit: float = maxf(0.001, float(_level.get("time_limit", 45.0)))
	match _state:
		State.PREVIEW:
			var frac: float = clampf(_preview_left / preview_total, 0.0, 1.0)
			_timer_ring.set_values(frac, "%d" % ceili(_preview_left), "记忆牌面", PURPLE, false, true)
			_set_phase("记住牌面 · %d" % ceili(_preview_left), PURPLE)
			if _board_status != null:
				_board_status.text = "记住牌面与位置 · 还剩 %d 秒" % ceili(_preview_left)
		State.DEALING:
			_timer_ring.set_values(1.0, _format_clock(time_limit), "牌阵封印中", _accent, false, false)
			_set_phase("牌阵封印中", _accent)
		State.PLAYING, State.RESOLVING:
			var frac2: float = clampf(_time_left / time_limit, 0.0, 1.0)
			var is_low: bool = _time_left <= 10.0
			var col: Color = DANGER if is_low else _accent
			_timer_ring.set_values(frac2, _format_clock(_time_left), "剩余时间", col, is_low, false)
			if _state == State.PLAYING:
				if _selected_cards.size() == 1:
					_set_phase("再翻一张", _accent)
				else:
					_set_phase("配对阶段", _accent)
			else:
				_set_phase("命运判定中", _accent)
		State.ENDED:
			_timer_ring.set_values(clampf(_time_left / time_limit, 0.0, 1.0), _format_clock(_time_left), "试炼结束", _accent, false, false)
			_set_phase("试炼结束", _accent)


func _set_phase(text: String, color: Color) -> void:
	if _phase_label == null:
		return
	_phase_label.text = text
	_phase_label.add_theme_color_override("font_color", color.lightened(0.26))
	if _phase_style != null:
		_phase_style.border_color = Color(color.r, color.g, color.b, 0.28)


func _process(delta: float) -> void:
	match _state:
		State.PREVIEW:
			_preview_left = maxf(0.0, _preview_left - delta)
			if _preview_left <= 0.0:
				_begin_deal()
			else:
				_update_timer()
		State.PLAYING, State.RESOLVING:
			_time_left = maxf(0.0, _time_left - delta)
			_update_timer()
			if _time_left <= 0.0:
				_fail("timeout")


# ===========================================================================
# 牌局流程
# ===========================================================================

func _begin_deal() -> void:
	if _state != State.PREVIEW:
		return
	_state = State.DEALING
	_preview_left = 0.0
	_update_timer()
	_board_status.text = "牌阵正在封印…"
	_set_cards_interactive(false)
	var rid := _run_id
	for i in range(_cards.size()):
		if _run_id != rid:
			return
		var card: MemoryCard = _cards[i]
		if is_instance_valid(card):
			card.set_face_up(false, true, 0.24)
		await get_tree().create_timer(0.032).timeout
	await get_tree().create_timer(0.24).timeout
	if _run_id != rid or _state != State.DEALING:
		return
	_state = State.PLAYING
	_time_left = float(_level.get("time_limit", 45.0))
	_busy = false
	_set_cards_interactive(true)
	_board_status.text = "翻开两张相同的秘术牌"
	_update_timer()


func _on_card_flip_requested(card: MemoryCard) -> void:
	if _state != State.PLAYING or _busy:
		return
	if not is_instance_valid(card) or card.matched or card.face_up:
		return
	if _selected_cards.has(card):
		return
	var rid := _run_id
	_selected_cards.append(card)
	card.set_selected(true)
	card.set_face_up(true, true, 0.24)
	if _selected_cards.size() == 1:
		_board_status.text = "再翻开一张相同的牌"
		_update_timer()
		return

	_busy = true
	_state = State.RESOLVING
	_board_status.text = "命运正在判定…"
	_update_timer()
	await get_tree().create_timer(0.30).timeout
	if _run_id != rid or _state != State.RESOLVING:
		return
	if _selected_cards.size() != 2:
		return
	var first: MemoryCard = _selected_cards[0]
	var second: MemoryCard = _selected_cards[1]
	if not is_instance_valid(first) or not is_instance_valid(second):
		return

	if first.pair_id == second.pair_id:
		await _resolve_match(first, second, rid)
	else:
		await _resolve_miss(first, second, rid)


func _resolve_match(first: MemoryCard, second: MemoryCard, rid: int) -> void:
	_pairs_found += 1
	_update_hud()
	_board_status.text = "一对秘术牌归位"
	_spawn_match_sparks(first, second)
	first.play_match()
	second.play_match()
	await get_tree().create_timer(0.44).timeout
	if _run_id != rid or _state != State.RESOLVING:
		return
	_selected_cards.clear()
	if _pairs_found >= int(_level.get("pairs", 3)):
		_win()
		return
	_busy = false
	_state = State.PLAYING
	_board_status.text = "翻开两张相同的秘术牌"
	_update_timer()


func _resolve_miss(first: MemoryCard, second: MemoryCard, rid: int) -> void:
	_mistakes += 1
	_update_hud()
	_board_status.text = "不对… 记住它们的位置"
	first.flash_error()
	second.flash_error()
	await get_tree().create_timer(0.68).timeout
	if _run_id != rid or _state != State.RESOLVING:
		return
	first.set_selected(false)
	second.set_selected(false)
	first.set_face_up(false, true, 0.22)
	second.set_face_up(false, true, 0.22)
	await get_tree().create_timer(0.28).timeout
	if _run_id != rid or _state != State.RESOLVING:
		return
	_selected_cards.clear()
	var mistake_limit: int = int(_level.get("max_mistakes", 3))
	if _mistakes >= mistake_limit:
		_fail("mistakes")
		return
	_busy = false
	_state = State.PLAYING
	_board_status.text = "翻开两张相同的秘术牌"
	_update_timer()


func _win() -> void:
	if _state == State.ENDED:
		return
	_state = State.ENDED
	_busy = true
	_set_cards_interactive(false)
	_board_status.text = "所有秘术牌都已归位"
	_update_timer()
	_finish_game(true, "cleared")


func _fail(reason: String) -> void:
	if _state == State.ENDED:
		return
	_state = State.ENDED
	_busy = true
	_set_cards_interactive(false)
	if reason == "timeout":
		_time_left = 0.0
		_board_status.text = "时间耗尽 · 牌阵沉入黑暗"
	else:
		_board_status.text = "失误超限 · 牌阵崩解"
	_update_timer()
	_finish_game(false, reason)


func _finish_game(success: bool, reason: String) -> void:
	if _finish_started:
		return
	_finish_started = true
	var rid := _run_id
	var time_limit: float = float(_level.get("time_limit", 45.0))
	var time_used: float = clampf(time_limit - _time_left, 0.0, time_limit)
	var stats := {
		"level": _level_id,
		"time_limit": time_limit,
		"time_left": _time_left,
		"time_used": time_used,
		"mistakes": _mistakes,
		"max_mistakes": int(_level.get("max_mistakes", 3)),
		"pairs": _pairs_found,
		"pairs_total": int(_level.get("pairs", 3)),
		"reason": reason
	}
	var polarity: String = "positive" if success else "negative"
	var buff := BUFF_CATALOG.create_memory_buff(polarity, _level_id, reason, stats)
	_current_buff = buff
	var bridge := _bridge()
	if bridge != null:
		var stored: Variant = bridge.queue_buff(buff)
		if stored is Dictionary:
			_current_buff = stored
	_refresh_fate_ui()
	_buff_status_label.text = "已写入跑酷命运池"
	_buff_sigil.ink = GOOD if success else Color("#d98a84")
	run_finished.emit({
		"success": success,
		"reason": reason,
		"stats": stats.duplicate(true),
		"buff": _current_buff.duplicate(true)
	})
	await get_tree().create_timer(0.48).timeout
	if _run_id != rid:
		return
	_show_result(success, reason, stats)


func _spawn_match_sparks(first: MemoryCard, second: MemoryCard) -> void:
	if _board_panel == null:
		return
	var a: Vector2 = first.get_global_rect().get_center()
	var b: Vector2 = second.get_global_rect().get_center()
	var local: Vector2 = (a + b) * 0.5 - _board_panel.get_global_rect().position
	var p := CPUParticles2D.new()
	p.position = local
	p.amount = 16
	p.lifetime = 0.85
	p.one_shot = true
	p.explosiveness = 0.92
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 24.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 150.0
	p.gravity = Vector2(0, 160)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.8
	p.color = Color(0.94, 0.82, 0.55, 0.95)
	p.texture = _dot_texture
	p.emitting = true
	p.z_index = 6
	_board_panel.add_child(p)
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


# ===========================================================================
# 被其他游戏触发 / 嵌入
# ===========================================================================

func _build_embedded_controls() -> void:
	_embedded_close = Button.new()
	_embedded_close.text = "×"
	_embedded_close.position = Vector2(956, 14)
	_embedded_close.size = Vector2(34, 32)
	_embedded_close.visible = false
	_embedded_close.z_index = 60
	_embedded_close.focus_mode = Control.FOCUS_NONE
	_embedded_close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_embedded_close.tooltip_text = "返回发出指令的游戏（Esc）"
	_embedded_close.add_theme_font_override("font", font_serif_bold)
	_embedded_close.add_theme_font_size_override("font_size", 19)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_embedded_close.add_theme_stylebox_override(state, _style(
			Color(0.035, 0.029, 0.045, 0.72),
			Color(0.58, 0.49, 0.35, 0.22),
			1, 6
		))
	var hover_style := _style(
		Color(0.09, 0.07, 0.10, 0.94),
		Color(_accent.r, _accent.g, _accent.b, 0.70),
		1, 6
	)
	_embedded_close.add_theme_stylebox_override("hover", hover_style)
	_embedded_close.add_theme_stylebox_override("pressed", hover_style)
	_embedded_close.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55, 0.90))
	_embedded_close.add_theme_color_override("font_hover_color", _accent.lightened(0.40))
	_embedded_close.add_theme_color_override("font_pressed_color", _accent.lightened(0.20))
	_embedded_close.pressed.connect(_on_embedded_close_pressed)
	add_child(_embedded_close)

	_embedded_hint = _place_label(
		self, "ESC  返回游戏", font_serif, 10,
		Color(0.66, 0.59, 0.48, 0.86), Vector2(720, 740), Vector2(278, 16),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	_embedded_hint.z_index = 60
	_embedded_hint.visible = false


## GameLink 打开本场景时调用；value=false 时隐藏嵌入式返回入口。
func set_embedded(value: bool) -> void:
	_embedded = value
	if _embedded_close != null:
		_embedded_close.visible = value
	if _embedded_hint != null:
		_embedded_hint.visible = value
	# 给右上角的关闭按钮让出空间
	if _pairs_label != null:
		_pairs_label.position.x = 744.0 if value else 740.0
		_pairs_label.size.x = 202.0 if value else 258.0
	if _fate_top_label != null:
		_fate_top_label.position.x = 744.0 if value else 740.0
		_fate_top_label.size.x = 202.0 if value else 258.0


## 指令入口：{"view":"menu"} 打开大厅；{"view":"level","level":"3x4"} 直接开局；
## {"view":"current"} 保留当前画面。由 GameLink 调用。
func open_from_command(options: Dictionary = {}) -> void:
	var view := String(options.get("view", "menu"))
	var level_id := String(options.get("level", ""))
	if bool(options.get("keep", false)) and view == "current" and _state != State.MENU:
		return
	if view == "level" and CONFIG.LEVELS.has(level_id):
		_start_level(level_id, true)
	elif view == "current":
		if _state == State.MENU:
			_show_menu(true)
	else:
		_show_menu(true)


func _on_embedded_close_pressed() -> void:
	if _embedded:
		close_requested.emit("button")


func _unhandled_input(event: InputEvent) -> void:
	if not _embedded:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit("escape")


# ===========================================================================
# 跑酷桥接 / 结算
# ===========================================================================

func _bridge() -> Node:
	return get_node_or_null("/root/RunBuffs")


func _connect_bridge() -> void:
	var bridge := _bridge()
	if bridge == null:
		push_warning("MemoryGame: 未找到 RunBuffs autoload，Buff 只会保留在内存里。")
		return
	var cb := Callable(self, "_on_pending_changed")
	if not bridge.pending_changed.is_connected(cb):
		bridge.pending_changed.connect(cb)


func _on_pending_changed(_pending: Array) -> void:
	_refresh_fate_ui()


func _refresh_fate_ui() -> void:
	var count: int = 0
	var bridge := _bridge()
	if bridge != null:
		count = int(bridge.pending_count())
	if _menu_fate_label != null:
		_menu_fate_label.text = "跑酷命运池 · %d 枚刻印待带入" % count
	if _fate_top_label != null:
		_fate_top_label.text = "跑酷命运池 · %d" % count
	if _buff_pending_label != null:
		_buff_pending_label.text = "已写入命运池 · 共 %d 枚待带入" % count if not _current_buff.is_empty() else "命运池 · %d 枚待带入" % count


func _show_result(success: bool, reason: String, stats: Dictionary) -> void:
	var palette: Color = GOOD if success else Color("#d47b7b")
	var muted_palette: Color = Color(0.62, 0.82, 0.66) if success else Color(0.83, 0.55, 0.55)
	_result_title.text = "记忆完整" if success else "记忆崩塌"
	_result_title.add_theme_color_override("font_color", Color("#f2e7cf") if success else Color("#f0d7d0"))
	_result_eyebrow.text = ("TRIAL COMPLETE · LEVEL %s" if success else "TRIAL FAILED · LEVEL %s") % String(_level.get("roman", "I"))
	_result_reason.text = _reason_text(success, reason)
	_result_reason.add_theme_color_override("font_color", muted_palette.lightened(0.12))

	if _result_stat_value_labels.size() >= 3:
		_result_stat_value_labels[0].text = _format_clock(float(stats.get("time_used", 0.0)))
		_result_stat_value_labels[1].text = "%d / %d" % [int(stats.get("mistakes", 0)), int(stats.get("max_mistakes", 0))]
		_result_stat_value_labels[2].text = "%d / %d" % [int(stats.get("pairs", 0)), int(stats.get("pairs_total", 0))]

	_result_sigil.ink = Color(palette.r, palette.g, palette.b, 0.95)
	if _result_panel_style != null:
		_result_panel_style.border_color = Color(palette.r, palette.g, palette.b, 0.50)
	if _result_buff_style != null:
		_result_buff_style.bg_color = Color(palette.r * 0.10, palette.g * 0.10, palette.b * 0.10, 0.92)
		_result_buff_style.border_color = Color(palette.r, palette.g, palette.b, 0.48)
	_result_buff_sigil.ink = Color(palette.r, palette.g, palette.b, 0.95)

	var configured: bool = bool(_current_buff.get("configured", false))
	var title: String = String(_current_buff.get("title", ""))
	var description: String = String(_current_buff.get("description", ""))
	var polarity: String = String(_current_buff.get("polarity", "negative"))
	_result_buff_kicker.text = "%s刻印 · %s" % [
		"正面" if polarity == "positive" else "负面",
		"POSITIVE" if polarity == "positive" else "NEGATIVE"
	]
	if not configured:
		_result_buff_kicker.text += "  ·  内容待配置"
	_result_buff_title.text = title if configured and title != "" else "未命名的刻印"
	_result_buff_desc.text = description if configured and description != "" else "效果尚未填写。接口与数据槽位已预留，等待后续内容接入。"
	_result_buff_meta.text = "目标：跑酷模式  ·  状态：已写入命运池，待消耗"
	if _result_buff_stamp != null:
		_result_buff_stamp.visible = not configured
		if _result_buff_stamp_style != null:
			_result_buff_stamp_style.border_color = Color(palette.r, palette.g, palette.b, 0.46)
		if _result_buff_stamp_label != null:
			_result_buff_stamp_label.add_theme_color_override("font_color", Color(palette.r, palette.g, palette.b, 0.78))

	var bridge := _bridge()
	_result_note.text = "命运刻印已封存  ·  下一次跑酷开始时读取" if bridge != null else "RunBuffs 未连接  ·  请检查 project.godot 的 Autoload"
	_result_note.add_theme_color_override("font_color", Color(0.62, 0.56, 0.46, 0.9) if bridge != null else DANGER)

	_result_primary.text = "再来一局" if success else "再试一次"
	_result_root.visible = true
	_result_panel.modulate.a = 0.0
	_result_panel.scale = Vector2(0.955, 0.955)
	var dim_alpha: float = _result_dim.color.a
	_result_dim.color.a = 0.0

	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	_result_tween = create_tween()
	_result_tween.tween_property(_result_panel, "modulate:a", 1.0, 0.30).set_ease(Tween.EASE_OUT)
	_result_tween.parallel().tween_property(_result_panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_result_tween.parallel().tween_property(_result_dim, "color:a", dim_alpha, 0.26).set_ease(Tween.EASE_OUT)

	_result_particles.color = Color(palette.r, palette.g, palette.b, 0.85)
	_result_particles.gravity = Vector2(0, 430) if success else Vector2(0, 540)
	_result_particles.emitting = false
	_result_particles.restart()
	_result_particles.emitting = true


func _reason_text(success: bool, reason: String) -> String:
	if success:
		return "所有秘术牌都已归位。女巫暂时取回了她的记忆。"
	match reason:
		"timeout":
			return "时间耗尽。最后一盏烛火熄灭，牌阵重新沉入黑暗。"
		"mistakes":
			return "失误超过限制。牌阵崩解，遗忘夺走了这一局。"
	return "试炼失败。"


func _retry_current_level() -> void:
	if _level_id == "":
		_show_menu(false)
		return
	_start_level(_level_id)


# ===========================================================================
# 可选：命令行截图，方便检查视觉
## godot --path . -- --capture=menu
## godot --path . -- --capture=game2x3
## godot --path . -- --capture=success
## godot --path . -- --capture=fail
# ===========================================================================

func _maybe_capture() -> void:
	# 只允许真正的当前场景做截图；被其他游戏预热的隐藏实例不要抢截图/退出。
	if get_tree().current_scene != self:
		return
	var target := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			target = arg.trim_prefix("--capture=")
	if target == "":
		return
	await get_tree().create_timer(0.9).timeout
	match target:
		"menu":
			pass
		"preview":
			await _capture_preview("3x4")
		"game2x3":
			await _capture_game("2x3")
		"game3x4":
			await _capture_game("3x4")
		"game4x5":
			await _capture_game("4x5")
		"success":
			await _capture_result(true)
		"fail":
			await _capture_result(false)
		_:
			pass
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "/tmp/memory_%s.png" % target
	var err := image.save_png(path)
	print("CAPTURE ", path, " err=", err)
	get_tree().quit()


func _capture_preview(level_id: String) -> void:
	_start_level(level_id)
	await get_tree().create_timer(0.85).timeout


func _capture_game(level_id: String) -> void:
	_start_level(level_id)
	await get_tree().create_timer(0.75).timeout
	if _state == State.PREVIEW:
		_state = State.PLAYING
		_time_left = float(_level.get("time_limit", 45.0)) * 0.62
		_preview_left = 0.0
		for card in _cards:
			if is_instance_valid(card):
				card.set_face_up(false, false)
		_busy = false
		_set_cards_interactive(true)
		_board_status.text = "翻开两张相同的秘术牌"
		_update_timer()
	await get_tree().create_timer(0.25).timeout


func _capture_result(success: bool) -> void:
	_start_level("3x4")
	await get_tree().create_timer(0.55).timeout
	_state = State.PLAYING
	_time_left = float(_level.get("time_limit", 75.0)) - 41.0
	if success:
		_pairs_found = int(_level.get("pairs", 6))
	else:
		_pairs_found = 3
		_mistakes = int(_level.get("max_mistakes", 4))
		for card in _cards:
			if is_instance_valid(card):
				card.set_face_up(false, false)
	_update_hud()
	_finish_game(success, "cleared" if success else "mistakes")
	await get_tree().create_timer(1.15).timeout
