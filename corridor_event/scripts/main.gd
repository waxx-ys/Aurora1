extends Node3D
## ============================================================================
## main.gd · 记忆回廊（长廊 + 嵌入式《记忆翻牌》）
## ----------------------------------------------------------------------------
## 流程（全部在同一个 Godot 进程 / 同一个窗口里）：
##   IDLE
##     └─玩家走进中段触发区 → PACT：雾压到最浓，画面淡出，弹出女巫契约图
##          └─玩家点击图片 → 淡出，把《记忆翻牌》场景嵌进同一个窗口
##               └─MEMORY：玩家在翻牌游戏大厅自己选难度
##                    └─关闭翻牌（Esc / ×）→ RETURNING：淡出、回到长廊、雾恢复
##                         └─IDLE：按结果施加正面/负面刻印
##
## 关键点：
##   * 不再 spawn 第二个 Godot 进程，也没有 UDP / 窗口最小化；
##   * 触发区没有任何地面标记或 HUD 提示，走进去就自动开始；
##   * 触发前没有任何女巫对话/倒计时，只有一张契约图；
##   * 翻牌游戏嵌在 SubViewport 里，用同一套鼠标/窗口，玩家自己选难度；
##   * 长廊长 2520 米，步行 4.2 m/s 约 600 秒（10 分钟）走完。
## ============================================================================

enum EventState { IDLE, PACT, MEMORY, RETURNING }

const MEMORY_SCENE_PATH := "res://memory_game/memory_game.tscn"
const PACT_TEXTURE_PATH := "res://assets/ui/witch_pact.png"
const TRIAL_BLESSING_MULTIPLIER := 1.18
const TRIAL_CURSE_MULTIPLIER := 0.82
const TRIAL_EFFECT_DURATION := 45.0

## 牌阵中心 Z；生成器会写入 1260。
@export var event_zone_center_z: float = 1260.0

@export_group("动态雾")
## 从哪个 Z 开始起雾；生成器按 “牌阵中心 - 16” 写入
@export var fog_ramp_start_z: float = 1244.0
## 走路阶段雾最浓的位置；生成器按 “牌阵中心 - 1” 写入
@export var fog_peak_z: float = 1259.0
## 峰值保持到哪；生成器按 “牌阵中心 + 2” 写入
@export var fog_hold_end_z: float = 1262.0
## 到哪恢复到常态；生成器按 “牌阵中心 + 12” 写入
@export var fog_clear_end_z: float = 1272.0
## 走路阶段峰值密度（门柱只剩轮廓）
@export var fog_dense_density: float = 0.22
## 触发/进入契约瞬间的密度（几乎看不清路）
@export var fog_event_density: float = 0.38
@export var fog_follow_speed: float = 1.8
@export var fog_relief_speed: float = 1.1
@export var fog_relief_duration_sec: float = 60.0

var _state: EventState = EventState.IDLE

var _environment: Environment = null
var _base_fog_density: float = 0.038
var _fog_relief: bool = false
var _fog_relief_until_msec: int = 0

var _trial_result: Dictionary = {}
var _trial_result_received: bool = false

var _pact_layer: CanvasLayer
var _pact_root: Control
var _pact_texture: TextureRect
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _memory_layer: CanvasLayer
var _memory_game: Control = null
var _memory_viewport: SubViewport = null
var _memory_container: SubViewportContainer = null
var _memory_bg_art: TextureRect = null

@onready var player: CorridorPlayer = $Player
@onready var zone: BufferZone = $BufferZone
@onready var hud: EventHUD = $HUD
var ending_zone: EndingZone = null


func _ready() -> void:
	if Engine.has_meta("corridor_build"):
		return
	# 读取场景里的常态雾密度，并以它作为动态雾的基准
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		_environment = world_env.environment
		_base_fog_density = _environment.fog_density

	zone.player_entered.connect(_on_zone_entered)
	zone.player_exited.connect(_on_zone_exited)
	ending_zone = get_node_or_null("EndingZone") as EndingZone
	if ending_zone != null:
		ending_zone.player_entered.connect(_on_ending_zone_entered)
		ending_zone.player_exited.connect(_on_ending_zone_exited)

	hud.set_fade_alpha(0.0)  # HUD 自带的全屏遮罩默认是黑的，单窗口版由 main 自己控制淡入
	_build_pact_overlay()
	_build_fade_overlay()
	_build_memory_layer_stub()

	# 开场：先冻结移动，淡入后交还控制权
	player.set_input_enabled(false)
	await _fade_from_black(1.2)
	player.set_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[CorridorMain] ready · witch gate z=%.1f · embedded memory · length=2520" % event_zone_center_z)


func _process(delta: float) -> void:
	_update_session_label()
	_update_fog(delta)
	if hud.is_debug_visible():
		hud.set_debug_text(_build_debug_text())


func _unhandled_input(event: InputEvent) -> void:
	# 契约图阶段：整张图都是可点击的（不依赖 Control 的 GUI 命中，
	# 这样鼠标点在图片任意位置/窗口缩放下都能进入翻牌）。
	if _state == EventState.PACT:
		if event is InputEventMouseButton:
			var pact_mb := event as InputEventMouseButton
			if pact_mb.pressed and pact_mb.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				_open_memory_game()
				return
		if event is InputEventKey:
			var pact_key := event as InputEventKey
			if pact_key.pressed and not pact_key.echo and pact_key.physical_keycode in [KEY_ENTER, KEY_SPACE]:
				get_viewport().set_input_as_handled()
				_open_memory_game()
				return
		return
	# 翻牌游戏期间：宿主也监听 Esc，保证无论 SubViewport 是否拿到键盘都能返回长廊。
	if _state == EventState.MEMORY:
		if event is InputEventKey:
			var mem_key := event as InputEventKey
			if mem_key.pressed and not mem_key.echo and mem_key.physical_keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_on_memory_close_requested("host_escape")
		return
	if _state == EventState.RETURNING:
		return
	if not (event is InputEventKey) or not event.pressed or (event as InputEventKey).echo:
		return
	var key_event := event as InputEventKey
	match key_event.physical_keycode:
		KEY_F3:
			hud.toggle_debug()
		KEY_E:
			# 只为调试/截图保留：站在触发区按 E 可再次弹出契约图
			if _state == EventState.IDLE and player.is_in_buffer_zone():
				_begin_pact()


# ============================================================================
# 触发 → 契约图 → 嵌入式翻牌
# ============================================================================

func _on_zone_entered(body: Node3D) -> void:
	if body != player:
		return
	player.set_buffer_zone(true)
	zone.set_active(true)
	if _state != EventState.IDLE:
		return
	# 触发区没有任何提示：走进去就自动开始
	_begin_pact()


func _on_zone_exited(body: Node3D) -> void:
	if body != player:
		return
	player.set_buffer_zone(false)
	zone.set_active(false)


func _begin_pact() -> void:
	if _state != EventState.IDLE:
		return
	_state = EventState.PACT
	_trial_result = {}
	_trial_result_received = false
	_fog_relief = false
	player.set_input_enabled(false)
	player.set_look_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide_trial_mark()
	hud.visible = false
	print("[CorridorMain] pact image · zone entered · fog will peak")

	# 先让雾压到最浓，再淡出到契约图（没有文字/倒计时）
	await get_tree().create_timer(0.9).timeout
	if _state != EventState.PACT:
		return
	await _fade_to_black(0.55)
	if _state != EventState.PACT:
		return
	_pact_layer.visible = true
	_pact_root.visible = true
	await _fade_from_black(0.7)


func _on_pact_gui_input(event: InputEvent) -> void:
	if _state != EventState.PACT:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_memory_game()


func _open_memory_game() -> void:
	if _state != EventState.PACT:
		return
	_state = EventState.MEMORY
	await _fade_to_black(0.5)
	_pact_root.visible = false
	_pact_layer.visible = false
	_remove_pact_ui()
	_build_memory_overlay()
	# 翻牌画面完全遮住 3D 时暂停长廊渲染，保证嵌套游戏的帧率与观感
	_set_corridor_world_visible(false)
	await _fade_from_black(0.7)
	print("[CorridorMain] embedded memory opened · same window/process")


func _build_memory_overlay() -> void:
	_memory_layer = CanvasLayer.new()
	_memory_layer.name = "EmbeddedMemoryLayer"
	_memory_layer.layer = 100
	add_child(_memory_layer)

	var root := Control.new()
	root.name = "MemoryRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_memory_layer.add_child(root)

	# 左右留白用契约图做暗色底，避免出现“另一个程序”的黑边
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.012, 0.018, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	_memory_bg_art = TextureRect.new()
	_memory_bg_art.texture = load(PACT_TEXTURE_PATH)
	_memory_bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_memory_bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_memory_bg_art.modulate = Color(1, 1, 1, 0.22)
	_memory_bg_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_memory_bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_memory_bg_art)

	# 《记忆翻牌》原本按 1024×768 排布；用 SubViewport 原尺寸渲染，
	# 再等比缩放进 1280×720 窗口，左右用契约图做暗色边，保持同一视觉世界。
	var vp_size := get_viewport().get_visible_rect().size
	var scale := vp_size.y / 768.0
	var view_w := 1024.0 * scale
	var view_h := 768.0 * scale

	_memory_container = SubViewportContainer.new()
	_memory_container.name = "MemoryViewportContainer"
	_memory_container.stretch = true
	_memory_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_memory_container.position = Vector2((vp_size.x - view_w) * 0.5, 0)
	_memory_container.size = Vector2(view_w, view_h)

	# 给嵌入画面加一圈很细的紫黑边框，让它看起来像长廊里的一面“女巫之镜”，
	# 而不是两个程序硬拼在一起。
	var frame := Panel.new()
	frame.name = "MemoryFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = _memory_container.position - Vector2(3, 0)
	frame.size = _memory_container.size + Vector2(6, 0)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = Color(0.46, 0.34, 0.7, 0.55)
	frame_style.set_border_width_all(2)
	frame_style.corner_radius_top_left = 6
	frame_style.corner_radius_top_right = 6
	frame_style.corner_radius_bottom_left = 6
	frame_style.corner_radius_bottom_right = 6
	frame.add_theme_stylebox_override("panel", frame_style)
	root.add_child(frame)
	root.add_child(_memory_container)

	_memory_viewport = SubViewport.new()
	_memory_viewport.name = "MemoryViewport"
	_memory_viewport.size = Vector2i(1024, 768)
	_memory_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_memory_viewport.handle_input_locally = true
	_memory_viewport.gui_disable_input = false
	_memory_container.add_child(_memory_viewport)

	var scene: PackedScene = load(MEMORY_SCENE_PATH)
	if scene == null:
		push_error("[CorridorMain] 找不到 memory_game.tscn")
		return
	_memory_game = scene.instantiate()
	_memory_viewport.add_child(_memory_game)
	_memory_game.set_embedded(true)
	_memory_game.close_requested.connect(_on_memory_close_requested)
	_memory_game.run_finished.connect(_on_memory_run_finished)
	# 不指定难度：打开大厅，让玩家自己选 2×3 / 3×4 / 4×5
	_memory_game.open_from_command({"view": "menu"})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_corridor_world_visible(visible: bool) -> void:
	for node_path in ["Corridor", "Player", "BufferZone", "EndingZone", "Atmosphere", "MoonLight"]:
		var node := get_node_or_null(node_path)
		if node is Node3D:
			(node as Node3D).visible = visible


func _remove_pact_ui() -> void:
	# 不销毁，只隐藏：允许玩家取消/再次入局时复用同一张契约图，避免重建。
	if _pact_root != null:
		_pact_root.visible = false
	if _pact_layer != null:
		_pact_layer.visible = false


func _on_memory_run_finished(result: Dictionary) -> void:
	_trial_result = result.duplicate(true)
	_trial_result_received = true
	print("[CorridorMain] memory run finished · success=%s reason=%s" % [
		str(result.get("success", false)), String(result.get("reason", "?"))
	])
	# 关键：一局结束（无论成功/失败）直接回长廊，不进入翻牌游戏自己的
	# “TRIAL COMPLETE / TRIAL FAILED”结算停留页。
	# 先把嵌入层藏掉，再淡出回长廊；结果只通过长廊的刻印条/短提示表达。
	if _state == EventState.MEMORY:
		if is_instance_valid(_memory_game):
			_memory_game.visible = false
		_return_from_memory()


func _on_memory_close_requested(reason: String) -> void:
	if _state != EventState.MEMORY:
		return
	# 中途退出 = 试炼失败：没有完整记忆，按失败结算负面刻印。
	if not _trial_result_received:
		_trial_result = {
			"success": false,
			"reason": "abandoned",
			"stats": {},
			"buff": {"polarity": "negative"},
		}
		_trial_result_received = true
		print("[CorridorMain] trial abandoned mid-game · treated as failure")
	print("[CorridorMain] memory close requested · %s" % reason)
	await _return_from_memory()


func _return_from_memory() -> void:
	if _state != EventState.MEMORY:
		return
	_state = EventState.RETURNING
	await _fade_to_black(0.4)
	if is_instance_valid(_memory_game):
		_memory_game.queue_free()
		_memory_game = null
	if is_instance_valid(_memory_layer):
		_memory_layer.queue_free()
		_memory_layer = null
	_memory_viewport = null
	_memory_container = null
	_memory_bg_art = null

	# 同一个窗口：显示回廊 HUD 与 3D，雾恢复到常态，按结果给刻印
	_set_corridor_world_visible(true)
	hud.visible = true
	_set_fog_relief()
	_apply_trial_result()
	player.set_look_enabled(true)
	player.set_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _fade_from_black(0.8)
	_state = EventState.IDLE
	if _trial_result_received:
		var success := bool(_trial_result.get("success", false))
		var toast := "试炼失败 · 负面刻印已生效，回到长廊。"
		if success:
			toast = "试炼完成 · 正面刻印已生效，回到长廊。"
		elif String(_trial_result.get("reason", "")) == "abandoned":
			toast = "中途退出 · 负面刻印已生效，回到长廊。"
		hud.show_toast(toast, 3.2)
	print("[CorridorMain] returned to corridor · same window")


# ============================================================================
# 结果 / 刻印
# ============================================================================

func _apply_trial_result() -> void:
	if not _trial_result_received:
		return
	var success := bool(_trial_result.get("success", false))
	var stats: Dictionary = _trial_result.get("stats", {}) if _trial_result.get("stats", {}) is Dictionary else {}
	var stats_text := _format_trial_stats(stats)
	if success:
		player.apply_trial_effect(TRIAL_BLESSING_MULTIPLIER, TRIAL_EFFECT_DURATION)
		hud.show_trial_mark(true, "正面刻印 · 疾行 45 秒　%s" % stats_text, TRIAL_EFFECT_DURATION)
	else:
		player.apply_trial_effect(TRIAL_CURSE_MULTIPLIER, TRIAL_EFFECT_DURATION)
		hud.show_trial_mark(false, "负面刻印 · 滞步 45 秒　%s" % stats_text, TRIAL_EFFECT_DURATION)


func _format_trial_stats(stats: Dictionary) -> String:
	if stats.is_empty():
		return ""
	var level := String(stats.get("level", ""))
	var time_used := float(stats.get("time_used", 0.0))
	var pairs := int(stats.get("pairs", 0))
	var pairs_total := int(stats.get("pairs_total", 0))
	return "（%s · %.1f 秒 · 配对 %d/%d）" % [level, time_used, pairs, pairs_total]


# ============================================================================
# 契约图 / 淡入淡出
# ============================================================================

func _build_pact_overlay() -> void:
	_pact_layer = CanvasLayer.new()
	_pact_layer.name = "PactLayer"
	_pact_layer.layer = 120
	_pact_layer.visible = false
	add_child(_pact_layer)

	_pact_root = Control.new()
	_pact_root.name = "PactRoot"
	_pact_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pact_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pact_root.visible = false
	_pact_root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pact_root.gui_input.connect(_on_pact_gui_input)
	_pact_layer.add_child(_pact_root)

	_pact_texture = TextureRect.new()
	_pact_texture.texture = load(PACT_TEXTURE_PATH)
	_pact_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pact_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pact_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pact_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pact_root.add_child(_pact_texture)


func _build_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 200
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_layer.add_child(_fade_rect)


func _build_memory_layer_stub() -> void:
	# 契约图显示时 PactLayer 可见；翻牌层在点击后才创建
	pass


func _fade_to_black(duration: float) -> void:
	_fade_rect.visible = true
	_fade_rect.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, duration)
	await tween.finished


func _fade_from_black(duration: float) -> void:
	_fade_rect.visible = true
	_fade_rect.modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, duration)
	await tween.finished
	_fade_rect.visible = false


# ============================================================================
# 动态雾（同上一版：越接近触发区越浓，事件结束后恢复）
# ============================================================================

func _update_fog(delta: float) -> void:
	if _environment == null:
		return
	var now := Time.get_ticks_msec()
	var pz := player.global_position.z
	# relief：到时间后，只有离开牌阵雾区才恢复按 Z 起雾；
	# 玩家站在触发区里看结算/发呆时，雾保持常态，不会 60 秒后又埋住他。
	if _fog_relief and (pz < 8.0 or (now > _fog_relief_until_msec and (pz < fog_ramp_start_z or pz > fog_clear_end_z))):
		_fog_relief = false
	var target := _base_fog_density
	if _state in [EventState.PACT, EventState.MEMORY]:
		target = fog_event_density
	elif _fog_relief:
		target = _base_fog_density
	else:
		target = _fog_target_for_z(player.global_position.z)
	var speed := fog_follow_speed if target >= _environment.fog_density else fog_relief_speed
	_environment.fog_density = lerpf(
		_environment.fog_density,
		target,
		clampf(speed * delta, 0.0, 1.0)
	)


func _fog_target_for_z(z: float) -> float:
	return lerpf(_base_fog_density, fog_dense_density, _fog_ratio_for_z(z))


func _fog_ratio_for_z(z: float) -> float:
	if z <= fog_ramp_start_z:
		return 0.0
	if z < fog_peak_z:
		var t := (z - fog_ramp_start_z) / (fog_peak_z - fog_ramp_start_z)
		return t * t * (3.0 - 2.0 * t)
	if z <= fog_hold_end_z:
		return 1.0
	if z < fog_clear_end_z:
		var t := (z - fog_hold_end_z) / (fog_clear_end_z - fog_hold_end_z)
		return 1.0 - t * t * (3.0 - 2.0 * t)
	return 0.0


func _set_fog_relief(seconds: float = -1.0) -> void:
	_fog_relief = true
	var duration := seconds if seconds > 0.0 else fog_relief_duration_sec
	_fog_relief_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)


func get_fog_density() -> float:
	return _environment.fog_density if _environment != null else 0.0


func get_fog_threat_ratio() -> float:
	return _fog_ratio_for_z(player.global_position.z)


func is_fog_relief_active() -> bool:
	return _fog_relief


# ============================================================================
# 长廊尽头 · 游戏结束文本触发区（继续保留）
# ============================================================================

func _on_ending_zone_entered(body: Node3D) -> void:
	if body != player:
		return
	if ending_zone != null:
		ending_zone.set_active(true)
	var text := _build_ending_text()
	hud.show_ending(String(text.get("title", "记忆回廊 · 尽头")), String(text.get("body", "")))


func _on_ending_zone_exited(body: Node3D) -> void:
	if body != player:
		return
	if ending_zone != null:
		ending_zone.set_active(false)
	hud.hide_ending()


func _build_ending_text() -> Dictionary:
	if _trial_result_received:
		var success := bool(_trial_result.get("success", false))
		var stats: Dictionary = _trial_result.get("stats", {}) if _trial_result.get("stats", {}) is Dictionary else {}
		var stats_text := _format_trial_stats(stats)
		if success:
			return {
				"title": "长廊尽头 · 试炼完成",
				"body": "你走完了记忆回廊。\n女巫的牌阵已经合上，正面刻印还在你的影子里发烫。\n命运池记下了这一笔——接下来，是下一段路。\n%s" % stats_text,
			}
		return {
			"title": "长廊尽头 · 试炼未竟",
			"body": "你走到了长廊尽头，但记忆没有完整归还。\n负面刻印还在拖慢脚步，女巫没有回头。\n下一次，她会记得你。\n%s" % stats_text,
		}
	return {
		"title": "长廊尽头 · 雾的源头",
		"body": "长廊在这里结束，但女巫的牌阵还在中段等你。\n回去，翻开那些牌，把记忆还给她，再走到这里。",
	}


# ============================================================================
# HUD / 调试
# ============================================================================

func _update_session_label() -> void:
	var z := player.global_position.z
	if z < event_zone_center_z - 30.0:
		hud.set_session_text("前段 · 雾中长廊")
	elif z < event_zone_center_z + 20.0:
		hud.set_session_text("中段 · 女巫牌阵")
	elif z < 2450.0:
		hud.set_session_text("深处 · 雾的尽头")
	else:
		hud.set_session_text("尽头 · 结局之地")


func _build_debug_text() -> String:
	var trial_text := "无"
	if _trial_result_received:
		trial_text = "%s/%s" % [
			"成功" if bool(_trial_result.get("success", false)) else "失败",
			String(_trial_result.get("reason", "?")),
		]
	return "\n".join(PackedStringArray([
		"[F3] 状态=%s  嵌入式翻牌=%s" % [EventState.keys()[_state], str(is_memory_open())],
		"玩家 xyz=(%.1f, %.1f, %.1f) 速度=%.2f 缓冲=%s 刻印×%.2f(%.0fs)" % [
			player.global_position.x, player.global_position.y, player.global_position.z,
			player.get_horizontal_speed(),
			"是" if player.is_in_buffer_zone() else "否",
			player.get_trial_multiplier(), player.get_trial_remaining(),
		],
		"雾密度=%.4f 雾压=%.2f relief=%s" % [get_fog_density(), get_fog_threat_ratio(), str(_fog_relief)],
		"试炼结果=%s  牌阵 z=%.1f  结局 z=2512" % [trial_text, event_zone_center_z],
		"记忆场景=%s" % str(ResourceLoader.exists(MEMORY_SCENE_PATH)),
	]))


# ============================================================================
# 对外查询（测试/截图用）
# ============================================================================

func is_pact_visible() -> bool:
	return _pact_layer != null and _pact_layer.visible and _pact_root != null and _pact_root.visible


func is_memory_open() -> bool:
	return _state == EventState.MEMORY and is_instance_valid(_memory_game)


func is_pact_state() -> bool:
	return _state == EventState.PACT


func debug_click_pact() -> void:
	if _state == EventState.PACT:
		_open_memory_game()


func get_embedded_memory() -> Control:
	return _memory_game


func is_returning() -> bool:
	return _state == EventState.RETURNING
