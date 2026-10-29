extends Node

## 游戏间触发接口测试（不需要记忆翻牌作为主场景）：
## 验证 GameLink 预热 → 同进程指令打开 → 暂停宿主 → 关闭恢复 → UDP 指令打开。

var failures: Array[String] = []
var udp_reply: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(0.4).timeout

	var link := get_node_or_null("/root/GameLink")
	if link == null:
		print("SMOKE_TEST: FAIL · GameLink autoload missing")
		get_tree().quit(1)
		return

	print("\n[1] 预热与 ping")
	var ping: Dictionary = link.send_command("ping")
	_check(bool(ping.get("ok", false)), "ping 返回 ok")
	_check(bool(ping.get("prewarmed", false)), "记忆翻牌已预热")
	_check(not bool(ping.get("open", false)), "初始状态未打开")

	print("\n[2] 同进程指令 open_memory_game（3×4）")
	var opened_at := Time.get_ticks_usec()
	var open_result: Dictionary = link.send_command("open_memory_game", {"view": "level", "level": "3x4"})
	var open_ms := float(Time.get_ticks_usec() - opened_at) / 1000.0
	_check(bool(open_result.get("ok", false)), "open_memory_game 返回 ok")
	_check(bool(link.is_memory_game_open()), "GameLink 标记为已打开")
	_check(get_tree().paused, "宿主树被暂停（记忆翻牌独占输入）")
	var memory := get_tree().get_first_node_in_group("memory_game") as Control
	_check(memory != null, "找到记忆翻牌实例")
	if memory != null:
		_check(memory.visible, "记忆翻牌实例可见")
		_check(String(memory.get("_level_id")) == "3x4", "直接进入 3×4 牌局（实际 %s）" % String(memory.get("_level_id")))
		_check(bool(memory.get("_embedded")), "嵌入式返回按钮已启用")
		if memory != null:
			var preview_before := float(memory.get("_preview_left"))
			await get_tree().create_timer(0.30).timeout
			var preview_after := float(memory.get("_preview_left"))
			_check(preview_after < preview_before, "宿主暂停时记忆翻牌的倒计时仍在推进（%.2f → %.2f）" % [preview_before, preview_after])
	print("  open latency: %.3f ms (signal: %.3f ms)" % [open_ms, float(open_result.get("latency_ms", 0.0))])
	_check(open_ms < 100.0, "同进程打开耗时 < 100ms")

	print("\n[3] 关闭并恢复宿主")
	var close_result: Dictionary = link.send_command("close_memory_game", {"reason": "test"})
	_check(bool(close_result.get("ok", false)), "close_memory_game 返回 ok")
	_check(not bool(link.is_memory_game_open()), "GameLink 标记为已关闭")
	_check(not get_tree().paused, "宿主树已解除暂停")
	if memory != null:
		_check(not memory.visible, "记忆翻牌实例已隐藏")

	print("\n[4] UDP 指令 open_memory_game（menu）")
	await _send_udp({
		"command": "open_memory_game",
		"view": "menu",
		"reply": true
	})
	await get_tree().create_timer(0.25).timeout
	_check(bool(link.is_memory_game_open()), "UDP 指令触发了记忆翻牌")
	_check(get_tree().paused, "UDP 打开后宿主暂停")
	_check(udp_reply != "", "UDP 返回了 JSON 响应")
	if udp_reply != "":
		var reply: Variant = JSON.parse_string(udp_reply)
		if reply is Dictionary:
			_check(bool(reply.get("ok", false)), "UDP 响应 ok=true")
			print("  udp reply: ", udp_reply)
		else:
			_check(false, "UDP 响应不是 JSON 字典")

	link.send_command("close_memory_game", {"reason": "test_end"})
	await get_tree().create_timer(0.1).timeout

	print("\n========== INTERGAME TEST ==========")
	if failures.is_empty():
		print("INTERGAME_TRIGGER_TEST: PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("INTERGAME_TRIGGER_TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [ok] ", message)
	else:
		failures.append(message)
		print("  [FAIL] ", message)


func _send_udp(payload: Dictionary) -> void:
	var sender := PacketPeerUDP.new()
	var bind_err := sender.bind(0, "127.0.0.1")
	if bind_err != OK:
		_check(false, "UDP 发送端无法绑定本地端口: %s" % error_string(bind_err))
		return
	var err := sender.set_dest_address("127.0.0.1", int(get_node("/root/GameLink").get_trigger_port()))
	if err != OK:
		_check(false, "UDP 发送端无法设置目标地址: %s" % error_string(err))
		return
	sender.put_packet(JSON.stringify(payload).to_utf8_buffer())
	# 等待 GameLink 的响应
	for i in range(40):
		await get_tree().create_timer(0.01).timeout
		if sender.get_available_packet_count() > 0:
			udp_reply = sender.get_packet().get_string_from_utf8()
			break
