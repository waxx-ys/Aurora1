extends Node

## ---------------------------------------------------------------------------
## RunBuffs · 记忆翻牌 <-> 跑酷 的唯一跨场景接口（Autoload）
##
## 记忆翻牌结束后调用 queue_buff() 把刻印放进"跑酷命运池"，
## 跑酷场景在开局时调用 consume_pending() 取走并应用。
## 数据同时写入 user://memory_run_buffs.json，因此重启游戏也不会丢失。
## ---------------------------------------------------------------------------

signal buff_queued(buff: Dictionary)
signal pending_changed(pending: Array)

const SAVE_PATH := "user://memory_run_buffs.json"
const MAX_PENDING := 12

var _pending: Array[Dictionary] = []
var _history: Array[Dictionary] = []


func _ready() -> void:
	_load()


## 入池。返回带 id / 时间戳的完整 buff 字典。
func queue_buff(buff: Dictionary) -> Dictionary:
	var entry: Dictionary = buff.duplicate(true)
	entry["id"] = String(entry.get("id", "buff_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]))
	entry["created_at"] = int(Time.get_unix_time_from_system())
	entry["created_at_text"] = Time.get_datetime_string_from_system(false, true)
	entry["consumed"] = false
	entry["target"] = String(entry.get("target", "parkour"))
	entry["source"] = String(entry.get("source", "memory_card_game"))

	_pending.append(entry)
	while _pending.size() > MAX_PENDING:
		_pending.pop_front()

	_save()
	buff_queued.emit(entry.duplicate(true))
	pending_changed.emit(peek_pending())
	return entry.duplicate(true)


## 跑酷端读取：取走全部待生效刻印，并清空池子。接口语义 = 一次性消费。
func consume_pending() -> Array:
	var taken: Array = _pending.duplicate(true)
	if taken.is_empty():
		return []
	for entry in taken:
		entry["consumed"] = true
		entry["consumed_at"] = int(Time.get_unix_time_from_system())
		_history.append(entry)
	while _history.size() > 32:
		_history.pop_front()
	_pending.clear()
	_save()
	pending_changed.emit([])
	return taken


## 只读预览，不消费。用于菜单 HUD / 跑酷准备界面。
func peek_pending() -> Array:
	return _pending.duplicate(true)


func has_pending() -> bool:
	return not _pending.is_empty()


func pending_count() -> int:
	return _pending.size()


## 清空待生效刻印（调试或新开一轮时使用）。
func clear_pending() -> void:
	_pending.clear()
	_save()
	pending_changed.emit([])


func history() -> Array:
	return _history.duplicate(true)


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("RunBuffs: 无法写入 %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"pending": _pending,
		"history": _history
	}, "\t"))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	var pending_data: Variant = data.get("pending", [])
	if pending_data is Array:
		for item in pending_data:
			if item is Dictionary:
				_pending.append((item as Dictionary).duplicate(true))
	var history_data: Variant = data.get("history", [])
	if history_data is Array:
		for item in history_data:
			if item is Dictionary:
				_history.append((item as Dictionary).duplicate(true))
