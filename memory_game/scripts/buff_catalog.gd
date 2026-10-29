class_name MemoryBuffCatalog
extends RefCounted

## ---------------------------------------------------------------------------
## 跑酷 Buff 内容池 —— 刻意留空。
##
## 记忆翻牌只负责"产生"一枚刻印并把它的 schema 写进 RunBuffs；
## 具体效果内容由这里（以及之后的跑酷模式）补充。
##
## 以后新增内容时，按下面结构往池子里追加字典即可：
## {
##     "id": "negative_blur",
##     "title": "雾蚀之眼",
##     "description": "下一场跑酷中，视野边缘被雾气侵蚀。",
##     "effects": {"screen_fog": 0.45, "duration": 20.0}   # effects 完全由跑酷端解释
## }
## ---------------------------------------------------------------------------

const NEGATIVE_POOL: Array[Dictionary] = []
const POSITIVE_POOL: Array[Dictionary] = []


static func create_memory_buff(polarity: String, level_id: String, reason: String, stats: Dictionary) -> Dictionary:
	var pool: Array[Dictionary] = NEGATIVE_POOL if polarity == "negative" else POSITIVE_POOL
	var template: Dictionary = {}
	if not pool.is_empty():
		template = pool.pick_random().duplicate(true)

	var effects_value: Variant = template.get("effects", {})
	var effects: Dictionary = {}
	if effects_value is Dictionary:
		effects = (effects_value as Dictionary).duplicate(true)

	return {
		"polarity": polarity,
		"source": "memory_card_game",
		"target": "parkour",
		"template_id": String(template.get("id", "")),
		"title": String(template.get("title", "")),
		"description": String(template.get("description", "")),
		"effects": effects,
		"configured": not template.is_empty(),
		"context": {
			"level": level_id,
			"reason": reason,
			"stats": stats.duplicate(true),
			"created_by": "memory_game"
		}
	}
