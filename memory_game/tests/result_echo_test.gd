extends Node
## ============================================================================
## result_echo_test.gd · 跨进程试炼结果回传测试（目标工程侧）
## ----------------------------------------------------------------------------
## 运行：
##   "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless \
##     --path "$HOME/subway-runner" --audio-driver Dummy \
##     res://memory_game/tests/result_echo_test.tscn
##
## 验证 GameLink 的新增行为：
##   1. 通过 UDP 收到 open_memory_game 后，记住调用方地址；
##   2. 一局结束（run_finished）时，向该地址回发
##      {"event":"memory_run_finished","success":...,"reason":...,"stats":...,"buff":...}；
##   3. 关闭指令与原有握手不受影响。
## ============================================================================

var _failures: int = 0
var _checks: int = 0
var _client: PacketPeerUDP


func _ready() -> void:
	print("=== result echo test start ===")
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	var game_link := get_node_or_null("/root/GameLink")
	_check(game_link != null, "GameLink autoload 存在")
	if game_link == null:
		_finish()
		return

	_client = PacketPeerUDP.new()
	var err := _client.bind(0, "127.0.0.1")
	_check(err == OK, "测试客户端绑定回环端口")
	if err != OK:
		_finish()
		return
	_client.set_dest_address("127.0.0.1", 45910)

	# open 时关闭 pause_host，避免测试场景被暂停
	_send({"command": "open_memory_game", "view": "menu", "pause_host": false})
	var open_reply := await _wait_for_key("overlay", 5.0)
	_check(not open_reply.is_empty(), "收到 open_memory_game 回复")

	# 模拟一局结束：直接触发 GameLink 的 run_finished 处理
	game_link.call("_on_memory_run_finished", {
		"success": true,
		"reason": "cleared",
		"stats": {"level": "3x4", "time_used": 38.2, "mistakes": 1, "pairs": 6, "pairs_total": 6},
		"buff": {"id": "buff_test", "polarity": "positive", "title": "疾行刻印", "effects": {"speed": 1.18}},
	})
	var event_packet := await _wait_for_key("event", 5.0)
	_check(not event_packet.is_empty(), "收到 memory_run_finished 事件回传")
	if not event_packet.is_empty():
		_check(String(event_packet.get("event", "")) == "memory_run_finished", "事件名为 memory_run_finished")
		_check(bool(event_packet.get("success", false)), "事件携带 success=true")
		_check(String(event_packet.get("reason", "")) == "cleared", "事件携带 reason=cleared")
		var buff: Dictionary = {}
		var raw_buff: Variant = event_packet.get("buff", {})
		if raw_buff is Dictionary:
			buff = raw_buff as Dictionary
		_check(String(buff.get("polarity", "")) == "positive", "事件携带正面刻印 polarity")

	# 关闭，保持目标工程状态干净
	_send({"command": "close_memory_game", "reason": "result_echo_test"})
	await _wait_for_key("reason", 3.0)
	_finish()


func _send(payload: Dictionary) -> void:
	_client.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _wait_for_key(key: String, timeout_sec: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		while _client.get_available_packet_count() > 0:
			var text := _client.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and (parsed as Dictionary).has(key):
				return parsed as Dictionary
		await get_tree().process_frame
	return {}


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS ✓ %s" % description)
	else:
		_failures += 1
		printerr("  FAIL ✗ %s" % description)


func _finish() -> void:
	if _client != null:
		_client.close()
	print("=== result echo result: %d checks, %d failed ===" % [_checks, _failures])
	print("TEST_RESULT_%s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(0 if _failures == 0 else 1)
