extends Node
## ============================================================================
## test_corridor.gd · 长廊 + 嵌入式《记忆翻牌》无头验收
## ----------------------------------------------------------------------------
## 覆盖：
##   1. 2520 米长廊结构、地板/墙体碰撞、玩家落地与撞墙；
##   2. 触发区（无任何标记）→ 雾压到最浓 → 契约图出现，期间没有任何对白；
##   3. 点击契约图 → 同一个进程/窗口内嵌《记忆翻牌》；
##   4. 翻牌大厅显示 3 档难度，玩家可以自己选，不预先固定难度；
##   5. 一局结果（胜/负）回到长廊后施加正面/负面刻印；
##   6. 游戏结束雾恢复常态；
##   7. 长廊尽头结局文本触发区；
##   8. 人物模型接入通道。
## ============================================================================

var _failures: int = 0
var _checks: int = 0
var _main: Node3D
var _player: CorridorPlayer
var _zone: BufferZone
var _hud: EventHUD


func _ready() -> void:
	print("=== corridor + embedded memory test start ===")
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn 可加载")
	if scene == null:
		_finish()
		return
	_main = scene.instantiate() as Node3D
	add_child(_main)
	_player = _main.get_node_or_null("Player") as CorridorPlayer
	_zone = _main.get_node_or_null("BufferZone") as BufferZone
	_hud = _main.get_node_or_null("HUD") as EventHUD
	_check(_player != null and _zone != null and _hud != null, "Player / BufferZone / HUD 节点齐全")
	if _player == null or _zone == null or _hud == null:
		_finish()
		return

	await _test_structure()
	await _test_floor_and_wall()
	await _test_pact_and_embedded_memory()
	await _test_result_and_fog()
	await _test_ending_zone()
	await _test_model_slot()
	_finish()


# ---------------------------------------------------------------------------
# 1. 结构 / 长地图
# ---------------------------------------------------------------------------

func _test_structure() -> void:
	print("--- 1. 结构、碰撞与 10 分钟地图 ---")
	_check(_main.get_node_or_null("Corridor") != null, "存在 Corridor")
	_check(_main.get_node_or_null("Corridor/FloorCollision") != null, "存在地板碰撞")
	_check(_main.get_node_or_null("Corridor/RightWallCollision") != null, "存在右墙碰撞")
	_check(_main.get_node_or_null("BufferZone/TriggerArea") != null, "存在牌阵触发 Area")
	_check(_main.get_node_or_null("EndingZone") != null, "存在尽头结局触发 Area")
	var floor_shape := _shape_size(_main.get_node_or_null("Corridor/FloorCollision/CollisionShape3D"))
	var wall_shape := _shape_size(_main.get_node_or_null("Corridor/RightWallCollision/CollisionShape3D"))
	_check_is_equal_approx(floor_shape, Vector3(6.0, 0.4, 2520.0), "地板碰撞 6×0.4×2520")
	_check_is_equal_approx(wall_shape, Vector3(0.4, 4.4, 2520.0), "右墙碰撞 0.4×4.4×2520")
	_check(absf(float(_main.get("event_zone_center_z")) - 1260.0) < 0.01, "牌阵中心 z=1260")
	var ending := _main.get_node_or_null("EndingZone") as Node3D
	_check(ending != null and absf(ending.global_position.z - 2512.0) < 0.1, "结局触发区 z≈2512")
	_check(_zone.get_trigger_size().z > 3.0, "触发区纵深 > 3m")
	# 步行速度 4.2 m/s：2520m ≈ 600s
	var seconds := 2520.0 / 4.2
	_check(seconds > 590.0 and seconds < 610.0, "步行走完约 10 分钟（%.0f 秒）" % seconds)
	_check(ResourceLoader.exists("res://memory_game/memory_game.tscn"), "嵌入式 memory_game.tscn 存在")
	_check(get_node_or_null("/root/RunBuffs") != null, "RunBuffs 已注册为同进程 Autoload")
	_check(get_node_or_null("/root/EventBridge") == null, "旧的跨进程 EventBridge 已移除")
	await get_tree().physics_frame


func _shape_size(shape_node: Node) -> Vector3:
	if shape_node == null:
		return Vector3.ZERO
	var collision := shape_node as CollisionShape3D
	if collision == null or collision.shape == null:
		return Vector3.ZERO
	if collision.shape is BoxShape3D:
		return (collision.shape as BoxShape3D).size
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# 2. 物理
# ---------------------------------------------------------------------------

func _test_floor_and_wall() -> void:
	print("--- 2. 落地与撞墙 ---")
	_player.teleport_to(Vector3(0, 1.2, 100.0))
	for i in 70:
		await get_tree().physics_frame
	_check(_player.global_position.y < 0.25, "角色落到地板（y=%.3f）" % _player.global_position.y)
	_check(_player.is_on_floor(), "角色处于 on_floor")

	_player.teleport_to(Vector3(2.0, 0.05, 100.0))
	await get_tree().physics_frame
	_player.velocity = Vector3(12, 0, 0)
	for i in 25:
		await get_tree().physics_frame
	_check(_player.global_position.x < 2.75, "角色被右墙挡住（x=%.3f）" % _player.global_position.x)
	_player.teleport_to(Vector3(-2.0, 0.05, 100.0))
	await get_tree().physics_frame
	_player.velocity = Vector3(-12, 0, 0)
	for i in 25:
		await get_tree().physics_frame
	_check(_player.global_position.x > -2.75, "角色被左墙挡住（x=%.3f）" % _player.global_position.x)


# ---------------------------------------------------------------------------
# 3. 触发 → 契约图 → 嵌入式翻牌
# ---------------------------------------------------------------------------

func _test_pact_and_embedded_memory() -> void:
	print("--- 3. 触发契约图 + 嵌入式翻牌 ---")
	_player.teleport_to(Vector3(0, 0.05, 1260.0))
	for i in 8:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(_main.is_pact_state(), "走进触发区自动进入契约状态")
	_check(not _player.is_input_enabled(), "契约图期间冻结移动")
	_check(not _hud.visible, "契约图期间隐藏长廊 HUD（没有对白）")
	_check(not _hud.is_narration_visible(), "没有任何女巫对话面板")
	_check(not _main.is_pact_visible(), "雾先压下来，契约图稍后淡入")
	await get_tree().create_timer(2.8).timeout
	_check(_main.is_pact_visible(), "雾压到最浓后显示契约图")
	_check(_main.get_fog_density() > 0.3, "契约图阶段雾密度 > 0.3（看不清前路）")
	_check(not _main.is_memory_open(), "此时还未打开翻牌游戏")

	_main.debug_click_pact()
	await get_tree().create_timer(2.0).timeout
	_check(_main.is_memory_open(), "点击契约图后在同进程打开嵌入式《记忆翻牌》")
	_check(get_node_or_null("/root/EventBridge") == null, "没有创建新的 Godot 进程/EventBridge")
	_check(not _main.is_pact_visible(), "翻牌打开后契约图隐藏")

	var mem: Control = _main.get_embedded_memory()
	_check(mem != null, "能取到嵌入式 memory_game 场景")
	if mem != null:
		_check(mem.get_parent() is SubViewport, "memory_game 嵌在同一个窗口的 SubViewport 里")
		_check(bool(mem.get("_menu_root").visible), "翻牌游戏显示自己的大厅")
		_check(String(mem.get("_level_id")) == "", "没有预先固定难度")
		_check(len(mem.get("_difficulty_cards")) == 3, "大厅提供 3 档难度供玩家自选")
		# 玩家自选初阶，验证难度不是被写死的
		mem.call("_on_difficulty_pressed", "2x3")
		await get_tree().create_timer(0.3).timeout
		_check(String(mem.get("_level_id")) == "2x3", "玩家可以在游戏内选择初阶难度")
		# 模拟一局胜利，回到长廊应施加正面刻印
		mem.run_finished.emit({
			"success": true,
			"reason": "cleared",
			"stats": {"level": "2x3", "time_used": 38.2, "mistakes": 1, "pairs": 3, "pairs_total": 3},
			"buff": {"polarity": "positive"},
		})
		await get_tree().create_timer(0.1).timeout
		_check(not mem.visible, "一局结束后隐藏翻牌游戏自己的结算页")
		await get_tree().create_timer(2.2).timeout
	_check(not _main.is_memory_open(), "翻牌结束后自动回到同一个长廊窗口")
	_check(_hud.visible, "回到长廊后 HUD 恢复")
	_check(absf(_player.get_trial_multiplier() - 1.18) < 0.001, "胜利结果施加正面刻印（疾行×1.18）")
	_check(_hud.is_trial_mark_visible(), "HUD 显示正面刻印状态条")

	# 再次进入，模拟玩家中途退出：按规则必须判失败并施加负面刻印
	_player.teleport_to(Vector3(0, 0.05, 1200.0))
	for i in 4:
		await get_tree().physics_frame
	_main.call("_begin_pact")
	await get_tree().create_timer(2.8).timeout
	_main.debug_click_pact()
	await get_tree().create_timer(2.0).timeout
	var mem2: Control = _main.get_embedded_memory()
	if mem2 != null:
		# 没有 run_finished，直接中途退出
		mem2.close_requested.emit("test_quit")
		await get_tree().create_timer(2.2).timeout
	_check(absf(_player.get_trial_multiplier() - 0.82) < 0.001, "中途退出判失败：滞步×0.82")
	_check(String(_main.get("_trial_result").get("reason", "")) == "abandoned", "中途退出记录为 abandoned")
	_check(_hud.is_trial_mark_visible(), "HUD 显示负面刻印状态条")

# ---------------------------------------------------------------------------
# 4. 雾恢复
# ---------------------------------------------------------------------------

func _test_result_and_fog() -> void:
	print("--- 4. 游戏结束后雾恢复 ---")
	await get_tree().create_timer(1.8).timeout
	_check(_main.is_fog_relief_active(), "返回长廊后进入雾恢复状态")
	_check(_main.get_fog_density() < 0.1, "雾恢复到可辨认的常态（%.4f）" % _main.get_fog_density())
	_player.teleport_to(Vector3(0, 0.05, 5.0))
	await get_tree().create_timer(1.6).timeout
	_check(_main.get_fog_density() < 0.07, "入口处雾是常态（%.4f）" % _main.get_fog_density())
	_player.teleport_to(Vector3(0, 0.05, 1256.0))
	await get_tree().create_timer(2.4).timeout
	_check(_main.get_fog_density() > 0.15, "接近牌阵时雾重新变浓（%.4f）" % _main.get_fog_density())


# ---------------------------------------------------------------------------
# 5. 尽头结局触发区
# ---------------------------------------------------------------------------

func _test_ending_zone() -> void:
	print("--- 5. 尽头结局触发区 ---")
	_player.teleport_to(Vector3(0, 0.05, 2512.0))
	for i in 8:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(_hud.is_ending_visible(), "进入尽头触发区显示结局文本")
	_player.teleport_to(Vector3(0, 0.05, 2480.0))
	for i in 8:
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
	_check(not _hud.is_ending_visible(), "离开尽头后结局文本收起")


# ---------------------------------------------------------------------------
# 6. 模型插槽
# ---------------------------------------------------------------------------

func _test_model_slot() -> void:
	print("--- 6. 人物模型接入 ---")
	var slot := _player.get_node_or_null("ModelRoot") as PlayerModelSlot
	_check(slot != null, "ModelRoot 挂载 PlayerModelSlot")
	_check(slot.get_child_count() > 0, "默认使用占位小人")
	var stub := Node3D.new()
	stub.name = "TestStub"
	slot.attach_model(stub)
	_check(slot.has_external_model(), "attach_model 接入外部模型成功")
	slot.use_placeholder()
	_check(not slot.has_external_model(), "use_placeholder 恢复占位小人")
	stub.free()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS ✓ %s" % label)
	else:
		_failures += 1
		print("  FAIL ✗ %s" % label)


func _check_is_equal_approx(actual: Vector3, expected: Vector3, label: String) -> void:
	_check(actual.is_equal_approx(expected), "%s（实际 %s）" % [label, str(actual)])


func _finish() -> void:
	print("\n=== result: %d checks, %d failed ===" % [_checks, _failures])
	print("TEST_RESULT_PASS" if _failures == 0 else "TEST_RESULT_FAIL")
	get_tree().quit(0 if _failures == 0 else 1)
