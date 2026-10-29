class_name ParkourBuffReceiver
extends Node

## ---------------------------------------------------------------------------
## 跑酷端接入示例（可选组件）
##
## 用法：把本节点加到跑酷场景根节点下；在"开始跑酷 / 重置一局"时调用
## collect_and_apply()。它会一次性消费记忆翻牌写入 RunBuffs 的刻印。
##
## apply_buff() 里目前只打印，后续把 effects 字典接到跑酷的玩家属性、
## 视野、速度、障碍生成等系统即可。记忆翻牌端不需要改动。
## ---------------------------------------------------------------------------

signal buffs_collected(buffs: Array)
signal buff_applied(buff: Dictionary)

@export var auto_collect_on_ready := false

func _ready() -> void:
	if auto_collect_on_ready:
		collect_and_apply()


func collect_and_apply() -> Array:
	var bridge := get_node_or_null("/root/RunBuffs")
	if bridge == null:
		push_warning("ParkourBuffReceiver: 找不到 RunBuffs autoload。")
		return []
	var buffs: Array = bridge.consume_pending()
	buffs_collected.emit(buffs)
	for buff in buffs:
		if buff is Dictionary:
			apply_buff(buff)
	return buffs


## 把以下 TODO 接到跑酷系统。buff.effects 由 BuffCatalog / 策划填写。
func apply_buff(buff: Dictionary) -> void:
	var effects: Dictionary = buff.get("effects", {})
	var polarity := String(buff.get("polarity", "neutral"))
	var title := String(buff.get("title", "未配置刻印"))
	print("[ParkourBuff] %s · %s effects=%s" % [polarity, title, effects])
	# TODO: 例：
	# if effects.has("screen_fog"):
	#     %PlayerCamera.fog_strength = effects["screen_fog"]
	# if effects.has("speed_mult"):
	#     %Player.speed_multiplier *= effects["speed_mult"]
	buff_applied.emit(buff)
