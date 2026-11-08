extends Node3D
## ============================================================================
## 主界面 · Helltown 鬼屋视角（独立工程，仅主界面）
## ----------------------------------------------------------------------------
## 本场景只做三件事：
##   1. 用 zip 里的 3D 模型 + 自建旧提灯复刻参考照片的室内视角；
##   2. 循环播放 bad_day.wav；
##   3. 点击主界面任意位置 → 发出 start_requested 信号 / 可选的 game_scene_path。
##
## 没有加载任何游戏本体场景；集成方式见 docs/INTEGRATION.md。
## ============================================================================

signal start_requested

## 接入游戏本体时，在检查器里填游戏主场景路径（例如 res://scenes/main.tscn）。
## 留空 = 只发出信号 + 显示“接口已触发”的短提示，用于单独验收主界面。
@export_file("*.tscn") var game_scene_path: String = ""
@export_range(-40.0, 6.0, 0.5) var music_volume_db: float = -9.0
@export var enable_camera_sway: bool = true
## 主界面标题；暂定“幽灵廊”，直接改这里即可替换。
@export var title_text: String = "幽魂廊"
## 标题字体：最初使用的 hakidame.TTF；灵用系统宋体补字（最初版方案）。
@export_file("*.ttf") var title_font_path: String = "res://assets/fonts/hakidame.TTF"

const CAMERA_POSITION := Vector3(0.5, 1.7, 0.5)
const CAMERA_TARGET := Vector3(0.0, 1.15, -2.4)
const LANTERN_OFFSET := Vector3(-0.58, -0.12, -1.12)

@onready var camera: Camera3D = $Camera3D
@onready var music: AudioStreamPlayer = $Music
@onready var fade_rect: ColorRect = $UI/Root/FadeRect
@onready var click_catcher: Control = $UI/Root/ClickCatcher
@onready var title_root: Control = $UI/Root/TitleRoot
@onready var title_main_row: HBoxContainer = $UI/Root/TitleRoot/MainWrap/MainRow
@onready var title_main_wrap: Control = $UI/Root/TitleRoot/MainWrap

var _starting: bool = false
var _time: float = 0.0
var _camera_base_rot: Vector3
var _camera_base_pos: Vector3
var _lantern: Node3D
var _title_font: Font
var _title_fallback_font: Font
var _main_labels: Array[Label] = []
## 合并字体已经包含“灵”，一般不需要 fallback；保留手动补充机制。
const TITLE_FALLBACK_CHARS := ""


func _ready() -> void:
	randomize()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_environment()
	_setup_camera()
	_setup_lantern()
	_setup_music()
	click_catcher.gui_input.connect(_on_click_catcher_gui_input)
	_setup_title_font()
	_apply_title()
	title_root.modulate.a = 0.0
	await get_tree().create_timer(0.15).timeout
	title_root.pivot_offset = title_root.size * 0.5
	_fade_in()
	var title_tween := create_tween()
	title_tween.tween_property(title_root, "modulate:a", 1.0, 2.2).set_delay(0.8)
	print("[MainMenu] ready · Helltown interior · click anywhere to start")


func _process(delta: float) -> void:
	_time += delta
	if enable_camera_sway:
		camera.position = _camera_base_pos + Vector3(
			sin(_time * 0.23) * 0.006,
			sin(_time * 0.17 + 1.1) * 0.004,
			0.0
		)
		camera.rotation = _camera_base_rot + Vector3(
			sin(_time * 0.19) * 0.0018,
			sin(_time * 0.13 + 0.8) * 0.0012,
			sin(_time * 0.11) * 0.0012
		)
	# 右上角标题保留非常轻微的摇晃；不再有幽灵副本/阴影层。
	if title_root != null:
		title_main_wrap.position = Vector2(sin(_time * 0.83) * 1.4, cos(_time * 1.05) * 1.8)
		title_root.rotation = sin(_time * 0.52) * 0.008


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.004, 0.003, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.29, 0.19, 1)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.09, 0.05, 1)
	env.fog_light_energy = 0.8
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.92
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	_add_omni(Vector3(-1.2, 2.2, -1.6), Color(1.0, 0.42, 0.15), 1.35, 8.0)
	_add_omni(Vector3(2.0, 2.0, 1.4), Color(1.0, 0.55, 0.26), 0.85, 7.0)
	_add_omni(Vector3(0.0, 2.6, -3.0), Color(0.85, 0.30, 0.10), 0.55, 6.0)


func _add_omni(pos: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	add_child(light)


func _setup_camera() -> void:
	camera.fov = 66.0
	camera.position = CAMERA_POSITION
	camera.look_at(CAMERA_TARGET, Vector3.UP)
	camera.current = true
	_camera_base_pos = camera.position
	_camera_base_rot = camera.rotation


func _setup_lantern() -> void:
	var scene: PackedScene = load("res://scenes/lantern.tscn")
	if scene == null:
		push_error("[MainMenu] 缺少 lantern.tscn")
		return
	_lantern = scene.instantiate()
	_lantern.name = "ForegroundLantern"
	add_child(_lantern)
	var offset := camera.global_transform.basis * LANTERN_OFFSET
	_lantern.global_position = camera.global_position + offset
	_lantern.scale = Vector3.ONE * 0.88
	_lantern.rotation.y = camera.rotation.y + 0.15


func _setup_music() -> void:
	var stream := music.stream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(maxf(1.0, wav.get_length()) * float(wav.mix_rate))
	music.volume_db = music_volume_db
	music.finished.connect(_on_music_finished)
	music.play()


func _on_music_finished() -> void:
	music.play()


func _fade_in() -> void:
	fade_rect.visible = true
	fade_rect.modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, 2.6)
	tween.tween_callback(func() -> void: fade_rect.visible = false)


func _on_click_catcher_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_start_game()


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
			_start_game()


func _start_game() -> void:
	if _starting:
		return
	_starting = true
	print("[MainMenu] start_requested")
	start_requested.emit()

	var target := game_scene_path.strip_edges()
	if target.is_empty():
		# 还没接入游戏本体：只做一个黑场呼吸作为点击反馈，页面上不出现任何文字。
		await _pulse_black()
		_starting = false
		return

	if not ResourceLoader.exists(target):
		push_error("[MainMenu] game_scene_path 不存在：%s" % target)
		await _pulse_black()
		_starting = false
		return

	await _fade_to_black(0.8)
	get_tree().change_scene_to_file(target)


func _pulse_black() -> void:
	fade_rect.visible = true
	fade_rect.modulate = Color(1, 1, 1, 0)
	var t1 := create_tween()
	t1.tween_property(fade_rect, "modulate:a", 0.72, 0.28)
	await t1.finished
	var t2 := create_tween()
	t2.tween_property(fade_rect, "modulate:a", 0.0, 0.6)
	await t2.finished
	fade_rect.visible = false


func _fade_to_black(duration: float) -> void:
	fade_rect.visible = true
	fade_rect.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, duration)
	await tween.finished


func _setup_title_font() -> void:
	# 主字体：最初版 hakidame.TTF；灵用系统宋体补字。
	# 可通过 title_font_path 换成其他字体；字体文件与许可证均在 assets/fonts/。
	_title_font = load(title_font_path)
	if _title_font == null:
		_title_font = load("res://assets/fonts/hakidame.TTF")
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray([
		"Songti SC", "STSong", "Noto Serif CJK SC", "Source Han Serif SC",
		"PingFang SC", "SimSun", "Arial Unicode MS",
	])
	fallback.allow_system_fallback = true
	fallback.font_weight = 500
	_title_fallback_font = fallback


func _apply_title() -> void:
	_main_labels.clear()
	if title_main_row != null:
		for child in title_main_row.get_children():
			child.queue_free()
	for i in title_text.length():
		var ch := title_text.substr(i, 1)
		var use_fallback := TITLE_FALLBACK_CHARS.contains(ch)
		var f: Font = _title_fallback_font if use_fallback else _title_font
		var label := _make_title_char(ch, f)
		title_main_row.add_child(label)
		_main_labels.append(label)


func _make_title_char(ch: String, f: Font) -> Label:
	var label := Label.new()
	label.text = ch
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", f)
	label.add_theme_font_size_override("font_size", 108)
	# 去掉阴影：不设 font_shadow_color / shadow_offset，也没有幽灵副本。
	label.add_theme_color_override("font_color", Color(0.84, 0.65, 0.34, 1))
	label.add_theme_color_override("font_outline_color", Color(0.14, 0.055, 0.01, 0.9))
	label.add_theme_constant_override("outline_size", 1)
	return label


func set_title(value: String) -> void:
	title_text = value
	_apply_title()


func set_game_scene(path: String) -> void:
	game_scene_path = path


func is_starting() -> bool:
	return _starting


func get_lantern() -> Node3D:
	return _lantern
