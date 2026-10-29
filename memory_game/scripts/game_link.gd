extends Node

## ===========================================================================
## GameLink · 游戏间快速触发接口（Autoload）
## ---------------------------------------------------------------------------
## 目标：不重新启动 Godot 进程，由另一个游戏 / 调度器发一条指令，
##       在已预热的进程里立即打开记忆翻牌。
##
## 两种触发通道：
##   1. 同进程（最快）：任意场景直接调用 GameLink.send_command("open_memory_game", {...})
##   2. 跨进程（本地 UDP）：另一个游戏向 127.0.0.1:45910 发 JSON 数据包
##
## 启动时会把记忆翻牌场景预加载，并在“当前场景不是记忆翻牌”时预实例化一份隐藏实例；
## 收到指令后只做显示 + 解暂停，不再重载资源，响应通常在一帧内。
##
## 指令：
##   open_memory_game    {"view":"menu"} / {"view":"level","level":"3x4"} / {"view":"current"}
##   close_memory_game   {"reason":"caller"}
##   ping                返回监听端口、是否已打开、是否已预热
##
## 外部进程预热启动（由另一个游戏在它启动时调用，非手动）：
##   Godot --path <项目> -- --warm
## 关闭预热（默认开启预热）：
##   Godot --path <项目> -- --no-prewarm
## 自定义端口：
##   MEMORY_TRIGGER_PORT=45911 Godot ...
## ===========================================================================

signal command_received(command: String, payload: Dictionary, source: String)
signal command_handled(command: String, result: Dictionary, source: String)
signal memory_game_opened(options: Dictionary, latency_ms: float)
signal memory_game_closed(reason: String)
signal memory_run_finished(result: Dictionary)
signal ready_for_commands()

const MEMORY_SCENE: PackedScene = preload("res://memory_game/memory_game.tscn")
const DEFAULT_TRIGGER_PORT := 45910
const CMD_OPEN := "open_memory_game"
const CMD_CLOSE := "close_memory_game"
const CMD_PING := "ping"

var _memory: Control
var _overlay_layer: CanvasLayer
var _udp: PacketPeerUDP
var _trigger_port: int = DEFAULT_TRIGGER_PORT
var _is_open: bool = false
var _did_pause_host: bool = false
var _tree_paused_before: bool = false
var _warm_mode: bool = false
var _prewarm_enabled: bool = true
var _prewarmed: bool = false
## 最近一次通过 UDP 发来指令的调用方地址（长廊进程）。
## 一局结束时用它把“试炼结果”回传，让跑酷侧知道是正面刻印还是负面刻印。
var _last_udp_peer_ip: String = ""
var _last_udp_peer_port: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	_warm_mode = "--warm" in args
	_prewarm_enabled = not ("--no-prewarm" in args)
	_trigger_port = _resolve_port()
	_setup_udp()
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	# 等主场景进入树，避免给“本身就是记忆翻牌”的场景再创建一份隐藏副本。
	await get_tree().process_frame
	await get_tree().process_frame
	_resolve_existing_memory()
	if _memory != null:
		print("[GameLink] using existing memory scene: %s" % _memory.get_path())
	elif _prewarm_enabled:
		_ensure_overlay_memory()
		print("[GameLink] prewarmed hidden overlay: %s" % _memory.get_path())
	_prewarmed = is_instance_valid(_memory)
	print("[GameLink] ready · prewarmed=%s · udp=%s:%d · warm=%s" % [
		str(_prewarmed), str(_udp != null), _trigger_port, str(_warm_mode)
	])
	ready_for_commands.emit()
	if _warm_mode:
		await get_tree().create_timer(0.15).timeout
		if not _is_open:
			_minimize_window()


# ---------------------------------------------------------------------------
# 公开指令 API（同进程直接调用）
# ---------------------------------------------------------------------------

func send_command(command: String, payload: Dictionary = {}, source: String = "in-process") -> Dictionary:
	var started := Time.get_ticks_usec()
	command_received.emit(command, payload, source)
	var result: Dictionary = {}
	match command:
		CMD_OPEN:
			result = open_memory_game(payload)
		CMD_CLOSE:
			result = close_memory_game(String(payload.get("reason", "caller")))
		CMD_PING:
			result = {
				"ok": true,
				"open": _is_open,
				"prewarmed": _prewarmed,
				"port": _trigger_port,
				"warm": _warm_mode
			}
		_:
			result = {"ok": false, "error": "unknown_command", "command": command}
	if not result.has("latency_ms"):
		result["latency_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	result["source"] = source
	command_handled.emit(command, result, source)
	return result


## 打开记忆翻牌。返回 {ok, latency_ms, overlay, views...}
func open_memory_game(options: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_usec()
	if not is_instance_valid(_memory):
		_resolve_existing_memory()
	if _memory == null:
		_ensure_overlay_memory()
	if not is_instance_valid(_memory):
		return {"ok": false, "error": "memory_scene_unavailable"}

	var overlay := _is_overlay_instance()
	var pause_host := bool(options.get("pause_host", true))
	if overlay:
		if not _is_open:
			_tree_paused_before = get_tree().paused
		_did_pause_host = pause_host
		get_tree().paused = _tree_paused_before if not pause_host else true
		_overlay_layer.visible = true
		_memory.process_mode = Node.PROCESS_MODE_ALWAYS
		_memory.visible = true
	else:
		_did_pause_host = false
	_memory.call("set_embedded", true)
	_bring_window_to_front()
	# 恢复窗口后立刻打开画面，再执行具体视图（大厅/关卡）。
	_memory.call("open_from_command", options)
	_is_open = true
	var latency := float(Time.get_ticks_usec() - started) / 1000.0
	memory_game_opened.emit(options, latency)
	return {
		"ok": true,
		"latency_ms": latency,
		"overlay": overlay,
		"prewarmed": _prewarmed,
		"paused_host": _did_pause_host,
		"open": true
	}


## 关闭记忆翻牌。嵌入模式下恢复被暂停的主机；独立进程则最小化窗口保持热启动。
func close_memory_game(reason: String = "caller") -> Dictionary:
	var started := Time.get_ticks_usec()
	if not is_instance_valid(_memory):
		return {"ok": false, "error": "memory_scene_unavailable"}
	if not _is_open:
		return {"ok": false, "error": "not_open", "latency_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	if _memory.has_method("set_embedded"):
		_memory.call("set_embedded", false)
	var overlay := _is_overlay_instance()
	if overlay:
		_memory.visible = false
		_memory.process_mode = Node.PROCESS_MODE_DISABLED
		if _overlay_layer != null:
			_overlay_layer.visible = false
		if _did_pause_host:
			get_tree().paused = _tree_paused_before
		_did_pause_host = false
	else:
		# 独立进程 + 被外部触发：最小化而不是退出，下一次 open 仍然快速。
		_minimize_window()
	_is_open = false
	memory_game_closed.emit(reason)
	return {
		"ok": true,
		"latency_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"reason": reason,
		"overlay": overlay
	}


func is_memory_game_open() -> bool:
	return _is_open


func is_prewarmed() -> bool:
	return _prewarmed


func get_trigger_port() -> int:
	return _trigger_port


# ---------------------------------------------------------------------------
# 内存场景管理
# ---------------------------------------------------------------------------

func _resolve_existing_memory() -> void:
	var existing := get_tree().get_first_node_in_group("memory_game") as Control
	if existing != null:
		_memory = existing
		_wire_memory(_memory)


func _ensure_overlay_memory() -> void:
	if is_instance_valid(_memory):
		return
	if _overlay_layer == null:
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.name = "GameLinkMemoryLayer"
		_overlay_layer.layer = 100
		_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_overlay_layer.visible = false
		add_child(_overlay_layer)
	_memory = MEMORY_SCENE.instantiate() as Control
	_memory.name = "MemoryGameOverlay"
	_memory.visible = false
	_memory.process_mode = Node.PROCESS_MODE_DISABLED
	_overlay_layer.add_child(_memory)
	_memory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wire_memory(_memory)


func _wire_memory(memory: Control) -> void:
	if memory == null:
		return
	var close_cb := Callable(self, "_on_memory_close_requested")
	if memory.has_signal("close_requested") and not memory.is_connected("close_requested", close_cb):
		memory.connect("close_requested", close_cb)
	var finish_cb := Callable(self, "_on_memory_run_finished")
	if memory.has_signal("run_finished") and not memory.is_connected("run_finished", finish_cb):
		memory.connect("run_finished", finish_cb)


func _is_overlay_instance() -> bool:
	return _overlay_layer != null and is_instance_valid(_memory) and _memory.get_parent() == _overlay_layer


func _on_memory_close_requested(reason: String) -> void:
	close_memory_game(reason)


func _on_memory_run_finished(result: Dictionary) -> void:
	memory_run_finished.emit(result)
	# 跨进程场景：把结果回报给最近的调用方（长廊）。
	# 同进程调用不会设置 _last_udp_peer_ip，因此走上面的信号即可。
	_notify_udp_run_finished(result)


## 向最近一次发来 UDP 指令的地址回传试炼结果。
## 这是“可选增强”事件：不依赖它的调用方仍可正常 close / ping。
## 消息形如：
##   {"event":"memory_run_finished","ok":true,"success":true,
##    "reason":"cleared","stats":{...},"buff":{...}}
func _notify_udp_run_finished(result: Dictionary) -> void:
	if _udp == null or _last_udp_peer_ip.is_empty() or _last_udp_peer_port <= 0:
		return
	var payload: Dictionary = result.duplicate(true)
	payload["event"] = "memory_run_finished"
	payload["ok"] = true
	payload["source"] = "memory_game"
	_udp.set_dest_address(_last_udp_peer_ip, _last_udp_peer_port)
	_udp.put_packet(JSON.stringify(payload).to_utf8_buffer())


# ---------------------------------------------------------------------------
# 窗口
# ---------------------------------------------------------------------------

func _bring_window_to_front() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()


func _minimize_window() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


# ---------------------------------------------------------------------------
# 本地 UDP 触发（跨进程）
# ---------------------------------------------------------------------------

func _resolve_port() -> int:
	var env := OS.get_environment("MEMORY_TRIGGER_PORT").strip_edges()
	if env.is_valid_int():
		var value := int(env)
		if value > 0 and value < 65536:
			return value
	return DEFAULT_TRIGGER_PORT


func _setup_udp() -> void:
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(_trigger_port, "127.0.0.1")
	if err != OK:
		push_warning("[GameLink] UDP bind 127.0.0.1:%d failed: %s（同进程 API 仍可用）" % [_trigger_port, error_string(err)])
		_udp = null
		return
	print("[GameLink] listening for trigger: udp://127.0.0.1:%d" % _trigger_port)


func _process(_delta: float) -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var from_ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var text := packet.get_string_from_utf8().strip_edges()
		if text.is_empty():
			continue
		var command := text
		var payload: Dictionary = {}
		if text.begins_with("{"):
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				payload = parsed
				command = String(payload.get("command", ""))
				payload.erase("command")
		var result := send_command(command, payload, "udp")
		if from_ip != "":
			# 记住调用方，供一局结束时回传 memory_run_finished 事件
			_last_udp_peer_ip = from_ip
			_last_udp_peer_port = from_port
			_udp.set_dest_address(from_ip, from_port)
			_udp.put_packet(JSON.stringify(result).to_utf8_buffer())
