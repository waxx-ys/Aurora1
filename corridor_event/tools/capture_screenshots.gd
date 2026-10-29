extends Node
## ============================================================================
## capture_screenshots.gd · 单窗口嵌套版文档截图（窗口模式运行）
## ----------------------------------------------------------------------------
## 生成：
##   01_corridor_start     长廊起点
##   02_floor_walls        地板/墙/长走廊
##   03_wall_closeup       墙材近景
##   04_approach_fog       接近牌阵时雾变浓
##   05_pact_image         触发区弹出的女巫契约图（无对白）
##   06_memory_menu        同窗口嵌入的翻牌游戏大厅（玩家自选难度）
##   07_memory_game        翻牌游戏中（3×4）
##   08_return_corridor    关闭翻牌后回到长廊（雾恢复 + 刻印状态）
##   09_deep_corridor      长廊深处
##   10_ending_text        尽头结局文本触发区
##   11_first_person       第一人称
##   12_debug_overlay      F3 调试
## ============================================================================

const OUT_DIR := "res://docs/images"
var _main: Node3D
var _player: CorridorPlayer
var _hud: EventHUD


func _ready() -> void:
	print("[capture] start")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_position(Vector2i(40, 40))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate() as Node3D
	add_child(_main)
	_player = _main.get_node("Player") as CorridorPlayer
	_hud = _main.get_node("HUD") as EventHUD
	_player.set_look_enabled(false)
	await get_tree().create_timer(3.5).timeout

	print("[capture] fade visible=", _main.get("_fade_rect").visible, " alpha=", _main.get("_fade_rect").modulate.a, " pact=", _main.get("_pact_layer").visible)
	_aim(Vector3(0, 0.02, 5.0), 180.0, -3.0, false)
	await _settle()
	await _capture("01_corridor_start.png")

	_aim(Vector3(0, 0.02, 120.0), 172.0, -11.0, false)
	await _settle()
	await _capture("02_floor_walls.png")

	_aim(Vector3(0.8, 0.02, 200.0), 215.0, -6.0, true)
	await _settle()
	await _capture("03_wall_closeup.png")

	# 牌阵前（z=1248），雾已明显变浓
	_aim(Vector3(0, 0.02, 1248.0), 180.0, -2.0, false)
	await get_tree().create_timer(2.2).timeout
	await _capture("04_approach_fog.png")

	# 走进触发区：自动压雾并弹出契约图；没有 HUD/对白
	_aim(Vector3(0, 0.02, 1260.0), 180.0, -2.0, false)
	await get_tree().create_timer(3.1).timeout
	await _capture("05_pact_image.png")

	# 点击契约图 → 同一窗口嵌入翻牌游戏大厅
	_main.debug_click_pact()
	await get_tree().create_timer(2.2).timeout
	await _capture("06_memory_menu.png")

	# 玩家自己选难度：3×4
	var mem: Control = _main.get_embedded_memory()
	if mem != null:
		mem.call("_on_difficulty_pressed", "3x4")
		await get_tree().create_timer(4.0).timeout
		await _capture("07_memory_game.png")
		# 模拟一局胜利，然后关闭回廊
		mem.run_finished.emit({
			"success": true,
			"reason": "cleared",
			"stats": {"level": "3x4", "time_used": 38.2, "mistakes": 1, "pairs": 6, "pairs_total": 6},
			"buff": {"polarity": "positive"},
		})
		await get_tree().create_timer(0.3).timeout
		mem.close_requested.emit("capture")
		await get_tree().create_timer(2.2).timeout
	await _capture("08_return_corridor.png")

	_aim(Vector3(0, 0.02, 2400.0), 180.0, -2.0, false)
	await _settle()
	await _capture("09_deep_corridor.png")

	_aim(Vector3(0, 0.02, 2512.0), 180.0, -2.0, false)
	await get_tree().create_timer(1.0).timeout
	await _capture("10_ending_text.png")

	_aim(Vector3(0, 0.02, 2300.0), 180.0, 0.0, true)
	await _settle()
	await _capture("11_first_person.png")

	_hud.toggle_debug()
	_aim(Vector3(0, 0.02, 1300.0), 180.0, -2.0, false)
	await _settle(0.8)
	await _capture("12_debug_overlay.png")

	print("[capture] done")
	get_tree().quit(0)


func _aim(position: Vector3, yaw_deg: float, pitch_deg: float, first_person: bool) -> void:
	_player.set_input_enabled(false)
	_player.teleport_to(position)
	_player.apply_camera_view(yaw_deg, pitch_deg, first_person)


func _settle(seconds: float = 0.45) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _capture(file_name: String) -> void:
	print("[capture] shot=%s player=%s" % [file_name, str(_player.global_position)])
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(OUT_DIR.path_join(file_name))
	var error := image.save_png(absolute_path)
	if error == OK:
		print("[capture] saved ", absolute_path, " (", image.get_width(), "x", image.get_height(), ")")
	else:
		push_error("[capture] save failed %s: %s" % [absolute_path, error_string(error)])
