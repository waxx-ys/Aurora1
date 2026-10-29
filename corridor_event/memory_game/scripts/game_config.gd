class_name MemoryGameConfig
extends RefCounted

## ---------------------------------------------------------------------------
## 记忆翻牌 · 数值与卡片配置
##
## 想调整倒计时 / 失误上限 / 记忆预览时长，只需要改 LEVELS 里对应难度的字段。
## 想更换卡面，改 CARD_POOL 的 art 路径即可；牌阵会自动从卡池里随机抽取。
## ---------------------------------------------------------------------------

const LEVEL_ORDER: Array[String] = ["2x3", "3x4", "4x5"]

const LEVELS: Dictionary = {
	"2x3": {
		"name": "初阶",
		"title": "轻试记忆",
		"roman": "I",
		"columns": 3,
		"rows": 2,
		"pairs": 3,
		"time_limit": 45.0,      # 倒计时秒数，后续可直接修改
		"max_mistakes": 3,       # 允许的配对失误次数
		"preview_time": 3.0,     # 开局展示牌面的记忆时间
		"card_size": [176, 238],
		"gap": 16,
		"accent": "#7fbf95",
		"accent_dim": "#2f5945",
		"difficulty": 1,
		"hint": "第一次推开女巫牌阵的门。"
	},
	"3x4": {
		"name": "中阶",
		"title": "迷雾牌局",
		"roman": "II",
		"columns": 4,
		"rows": 3,
		"pairs": 6,
		"time_limit": 75.0,
		"max_mistakes": 4,
		"preview_time": 8.0,
		"card_size": [136, 184],
		"gap": 13,
		"accent": "#c9a86a",
		"accent_dim": "#5e4a2b",
		"difficulty": 2,
		"hint": "迷雾开始吞没熟悉的牌面。"
	},
	"4x5": {
		"name": "高阶",
		"title": "深渊回响",
		"roman": "III",
		"columns": 5,
		"rows": 4,
		"pairs": 10,
		"time_limit": 120.0,
		"max_mistakes": 5,
		"preview_time": 10.0,
		"card_size": [102, 138],
		"gap": 10,
		"accent": "#cf7d95",
		"accent_dim": "#642f43",
		"difficulty": 3,
		"hint": "深渊记得每一张牌，也记得你的失误。"
	}
}

const CARD_POOL: Array[Dictionary] = [
	{
		"id": "night_bat",
		"name": "夜蝠",
		"full_name": "夜巡之蝠",
		"art": "res://memory_game/art/cards/night_bat.png",
		"lore": "它替女巫数着没有月亮的夜。"
	},
	{
		"id": "grave",
		"name": "墓碑",
		"full_name": "无名之碑",
		"art": "res://memory_game/art/cards/grave.png",
		"lore": "碑上没有名字，只有被抹去的日期。"
	},
	{
		"id": "skull",
		"name": "颅骨",
		"full_name": "猩红颅骨",
		"art": "res://memory_game/art/cards/skull.png",
		"lore": "它仍记得最后一次说谎的人。"
	},
	{
		"id": "scythe",
		"name": "魂镰",
		"full_name": "缚魂之镰",
		"art": "res://memory_game/art/cards/scythe.png",
		"lore": "刃口映出的，从来不是使用者。"
	},
	{
		"id": "ancient_tree",
		"name": "古树",
		"full_name": "月蚀古树",
		"art": "res://memory_game/art/cards/ancient_tree.png",
		"lore": "它的年轮里藏着一整座森林的记忆。"
	},
	{
		"id": "mushrooms",
		"name": "菌菇",
		"full_name": "幽光菌菇",
		"art": "res://memory_game/art/cards/mushrooms.png",
		"lore": "据说吃下它，会记起从未发生的事。"
	},
	{
		"id": "lantern",
		"name": "魂灯",
		"full_name": "引魂灯",
		"art": "res://memory_game/art/cards/lantern.png",
		"lore": "灯芯燃烧的不是油，是亡者的名字。"
	},
	{
		"id": "potions",
		"name": "魔药",
		"full_name": "三色魔药",
		"art": "res://memory_game/art/cards/potions.png",
		"lore": "红的是遗忘，绿的是记忆，蓝的是代价。"
	},
	{
		"id": "spellbook",
		"name": "禁书",
		"full_name": "禁术之书",
		"art": "res://memory_game/art/cards/spellbook.png",
		"lore": "书页会自己翻动，直到你想起那一页。"
	},
	{
		"id": "cauldron",
		"name": "药釜",
		"full_name": "翠焰药釜",
		"art": "res://memory_game/art/cards/cauldron.png",
		"lore": "沸腾的绿焰里，浮着未说完的誓言。"
	},
	{
		"id": "moon_window",
		"name": "月窗",
		"full_name": "囚月之窗",
		"art": "res://memory_game/art/cards/moon_window.png",
		"lore": "女巫把月亮锁在石窗里，只为借一点光。"
	}
]


static func get_level(level_id: String) -> Dictionary:
	return LEVELS.get(level_id, {})


static func accent_of(level: Dictionary) -> Color:
	return Color(String(level.get("accent", "#c9a86a")))


static func accent_dim_of(level: Dictionary) -> Color:
	return Color(String(level.get("accent_dim", "#5e4a2b")))
