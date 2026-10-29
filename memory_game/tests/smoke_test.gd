extends Node

## 无界面冒烟测试：
## godot --headless --path . --audio-driver Dummy res://memory_game/tests/smoke_test.tscn
## 验证：发牌 -> 配对成功 -> 配对失误 -> 失误失败 -> 重新开局 -> 全配对胜利 -> Buff 入池。

var game: Control
var failures: Array[String] = []
var pending_before: int = 0


func _ready() -> void:
	game = load("res://memory_game/memory_game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	RunBuffs.clear_pending()
	await _test_menu_difficulty_click()
	await _test_match_and_mistake()
	await _test_failure_by_mistakes()
	await _test_win_and_positive_buff()
	await _test_timeout()

	print("\n========== SMOKE TEST ==========")
	if failures.is_empty():
		print("SMOKE_TEST: PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("SMOKE_TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  [FAIL] ", message)
	else:
		print("  [ok] ", message)


func _wait_until(predicate: Callable, timeout: float, tick: float = 0.04) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if bool(predicate.call()):
			return true
		await get_tree().create_timer(tick).timeout
		elapsed += tick
	return false


func _click(card: Node) -> void:
	# 有显示环境时走真实的 viewport 命中测试，验证牌阵没有被父节点挡住；
	# --headless 下 Godot 不派发 GUI 指针事件，退回直接调用。
	if DisplayServer.get_name() != "headless":
		var center: Vector2 = card.get_global_rect().get_center()
		var ev := InputEventMouseButton.new()
		ev.position = center
		ev.global_position = center
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		ev.pressed = true
		get_viewport().push_input(ev)
		var up := InputEventMouseButton.new()
		up.position = center
		up.global_position = center
		up.button_index = MOUSE_BUTTON_LEFT
		up.button_mask = 0
		up.pressed = false
		get_viewport().push_input(up)
		return
	var direct := InputEventMouseButton.new()
	direct.button_index = MOUSE_BUTTON_LEFT
	direct.pressed = true
	card._gui_input(direct)


func _start_and_deal(level: String) -> bool:
	game._start_level(level)
	await get_tree().process_frame
	game._begin_deal()
	var ok: bool = await _wait_until(func() -> bool: return int(game._state) == int(game.State.PLAYING), 5.0)
	await get_tree().create_timer(0.35).timeout
	return ok


func _find_pairs() -> Array:
	var groups: Dictionary = {}
	for card in game._cards:
		if card.matched:
			continue
		var key := String(card.pair_id)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(card)
	var result: Array = []
	for key in groups:
		if groups[key].size() >= 2:
			result.append(groups[key])
	return result


func _press_button(button: Button) -> void:
	if DisplayServer.get_name() != "headless":
		var center: Vector2 = button.get_global_rect().get_center()
		var ev := InputEventMouseButton.new()
		ev.position = center
		ev.global_position = center
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		ev.pressed = true
		get_viewport().push_input(ev)
		var up := InputEventMouseButton.new()
		up.position = center
		up.global_position = center
		up.button_index = MOUSE_BUTTON_LEFT
		up.button_mask = 0
		up.pressed = false
		get_viewport().push_input(up)
		return
	button.pressed.emit()


func _test_menu_difficulty_click() -> void:
	print("\n[0] 大厅难度卡点击")
	await get_tree().create_timer(0.9).timeout
	_check(game._difficulty_cards.size() == 3, "大厅有 3 张难度卡")
	var target: Button = game._difficulty_cards[1]
	_press_button(target)
	var entered: bool = await _wait_until(func() -> bool: return String(game._level_id) == "3x4" and int(game._state) == int(game.State.PREVIEW), 2.0)
	_check(entered, "点击 3×4 难度卡后进入对应牌局")
	game._return_to_menu()
	await get_tree().create_timer(0.4).timeout
	_check(int(game._state) == int(game.State.MENU), "返回厅堂后状态回到 MENU")


func _test_match_and_mistake() -> void:
	print("\n[1] 发牌 / 配对 / 失误")
	var started: bool = await _start_and_deal("2x3")
	_check(started, "2x3 完成发牌并进入 PLAYING")
	_check(game._cards.size() == 6, "牌数为 6（实际 %d）" % game._cards.size())
	var down := true
	for c in game._cards:
		if c.face_up:
			down = false
	_check(down, "发牌结束后所有牌面朝下")

	var pairs: Array = _find_pairs()
	_check(pairs.size() >= 1, "至少找到一对牌")
	var pair: Array = pairs[0]
	var first = pair[0]
	var second = pair[1]
	_click(first)
	_click(second)
	var resolved: bool = await _wait_until(func() -> bool: return int(game._state) == int(game.State.PLAYING) or int(game._state) == int(game.State.ENDED), 4.0)
	_check(resolved, "配对判定在 4 秒内结束")
	_check(int(game._pairs_found) == 1, "配对成功后 pairs_found = 1（实际 %d）" % int(game._pairs_found))
	_check(first.matched and second.matched, "配对成功的两张牌已标记消失")

	# 找到两张不同配对的牌，制造一次失误
	var unmatched: Array = []
	for c in game._cards:
		if not c.matched:
			unmatched.append(c)
	var a = null
	var b = null
	for i in range(unmatched.size()):
		for j in range(i + 1, unmatched.size()):
			if unmatched[i].pair_id != unmatched[j].pair_id:
				a = unmatched[i]
				b = unmatched[j]
				break
		if a != null:
			break
	if a != null and b != null:
		_click(a)
		_click(b)
		await _wait_until(func() -> bool: return int(game._mistakes) >= 1, 4.0)
		await _wait_until(func() -> bool: return int(game._state) == int(game.State.PLAYING) or int(game._state) == int(game.State.ENDED), 4.0)
		_check(int(game._mistakes) == 1, "不同牌配对后 mistakes = 1（实际 %d）" % int(game._mistakes))
		_check(not a.face_up and not b.face_up, "失误后两张牌重新翻回背面")
	else:
		_check(false, "找不到可用于制造失误的两张不同牌")


func _test_failure_by_mistakes() -> void:
	print("\n[2] 失误超限 -> 负面刻印")
	RunBuffs.clear_pending()
	var started: bool = await _start_and_deal("2x3")
	_check(started, "第二局进入 PLAYING")
	game._mistakes = int(game._level.get("max_mistakes", 3)) - 1
	game._update_hud()
	var unmatched: Array = []
	for c in game._cards:
		unmatched.append(c)
	var a = null
	var b = null
	for i in range(unmatched.size()):
		for j in range(i + 1, unmatched.size()):
			if unmatched[i].pair_id != unmatched[j].pair_id:
				a = unmatched[i]
				b = unmatched[j]
				break
		if a != null:
			break
	_click(a)
	_click(b)
	var ended: bool = await _wait_until(func() -> bool: return int(game._state) == int(game.State.ENDED), 5.0)
	_check(ended, "失误超限后进入 ENDED")
	var overlay: bool = await _wait_until(func() -> bool: return game._result_root.visible, 3.0)
	_check(overlay, "失败结算面板显示")
	_check(not game._current_buff.is_empty(), "失败生成了 Buff 数据")
	_check(String(game._current_buff.get("polarity", "")) == "negative", "失败 Buff 的 polarity = negative")
	_check(int(RunBuffs.pending_count()) == 1, "负面 Buff 已写入 RunBuffs（实际 %d）" % int(RunBuffs.pending_count()))


func _test_win_and_positive_buff() -> void:
	print("\n[3] 全部配对 -> 正面刻印")
	RunBuffs.clear_pending()
	var started: bool = await _start_and_deal("2x3")
	_check(started, "第三局进入 PLAYING")
	var safety := 0
	while int(game._state) != int(game.State.ENDED) and safety < 8:
		safety += 1
		var pairs: Array = _find_pairs()
		if pairs.is_empty():
			break
		var pair: Array = pairs[0]
		_click(pair[0])
		_click(pair[1])
		await get_tree().create_timer(0.15).timeout
		await _wait_until(func() -> bool: return int(game._state) == int(game.State.PLAYING) or int(game._state) == int(game.State.ENDED), 4.0)
	_check(int(game._state) == int(game.State.ENDED), "全部配对后进入 ENDED")
	_check(int(game._pairs_found) == int(game._level.get("pairs", 3)), "pairs_found 等于总对数（实际 %d）" % int(game._pairs_found))
	var overlay: bool = await _wait_until(func() -> bool: return game._result_root.visible, 3.0)
	_check(overlay, "胜利结算面板显示")
	_check(String(game._current_buff.get("polarity", "")) == "positive", "胜利 Buff 的 polarity = positive")
	_check(int(RunBuffs.pending_count()) == 1, "正面 Buff 已写入 RunBuffs（实际 %d）" % int(RunBuffs.pending_count()))
	var taken: Array = RunBuffs.consume_pending()
	_check(taken.size() == 1, "跑酷端接口 consume_pending() 可消费该 Buff")


func _test_timeout() -> void:
	print("\n[4] 倒计时归零 -> 负面刻印")
	RunBuffs.clear_pending()
	var started: bool = await _start_and_deal("2x3")
	_check(started, "第四局进入 PLAYING")
	game._time_left = 0.05
	game._update_timer()
	var ended: bool = await _wait_until(func() -> bool: return int(game._state) == int(game.State.ENDED), 2.0)
	_check(ended, "倒计时归零后进入 ENDED")
	var overlay: bool = await _wait_until(func() -> bool: return game._result_root.visible, 3.0)
	_check(overlay, "超时结算面板显示")
	_check(String(game._current_buff.get("polarity", "")) == "negative", "超时生成负面 Buff")
	_check(int(RunBuffs.pending_count()) == 1, "超时负面 Buff 已写入 RunBuffs")
	RunBuffs.clear_pending()
