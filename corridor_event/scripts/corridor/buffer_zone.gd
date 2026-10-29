class_name BufferZone
extends Node3D
## ============================================================================
## BufferZone · 长廊中段缓冲区（事件触发区）
## ----------------------------------------------------------------------------
## 场景 scenes/buffer_zone.tscn 的根节点脚本。它由三部分组成：
##   1. TriggerArea（Area3D）：玩家（碰撞层 2）进入/离开时发信号；
##      —— 注意：Area 只负责“检测”，真正的剧情/跳转由 main.gd 状态机决定。
##   2. 视觉：记忆之门（木柱 + 横梁 + 半透明帷幕 + 浮空卡），地面**没有**符文圈/紫色触发标记；
##   3. 光效：低亮度紫色点光源、漂浮符文、卡牌、女巫之眼，脚本里做缓慢脉动。
##
## 为什么叫“缓冲区”：
##   * 玩法上，玩家进入后角色移动速度被 player_controller 平滑降到 42%，
##     同时冻结输入，进入契约图流程；触发区本身没有地面标记/提示；
##   * 进入后长廊只做一件事：把雾压到最浓，然后弹出契约图；没有任何对白/倒计时。
##   * 技术上，这里只发 player_entered/player_exited 信号，由 main.gd 决定
##     是否显示契约图、是否嵌入翻牌；离开后重新武装，允许再次体验。
##
## 维护提示：
##   * 调整触发范围：改本场景 TriggerArea 的 BoxShape3D size / 根节点 position.z；
##   * 调整减速幅度：改 scenes/player.tscn 上 Player 的 buffer_speed_multiplier；
##   * 想再次体验：离开触发区后再走回来，或在区内按 E（main.gd 调试入口）。
## ============================================================================

## 玩家进入缓冲区
signal player_entered(player: Node3D)
## 玩家离开缓冲区
signal player_exited(player: Node3D)

@export_group("动画")
## 漂浮符文的上下浮动幅度（米）
@export var float_amplitude: float = 0.08
## 漂浮符文的浮动速度
@export var float_speed: float = 1.3
## 玩家进入后光效增强倍率
@export var active_glow_multiplier: float = 1.9

@onready var trigger_area: Area3D = $TriggerArea
@onready var rune_light: OmniLight3D = $RuneLight
@onready var rift: MeshInstance3D = $MemoryGate/Rift
@onready var witch_cards_root: Node3D = $WitchCards
@onready var left_eye: MeshInstance3D = $WitchEyes/LeftEye
@onready var right_eye: MeshInstance3D = $WitchEyes/RightEye

var _active: bool = false
var _time: float = 0.0
var _base_light_energy: float = 0.0
var _floating_runes: Array[Node3D] = []
var _float_origins: Array[Vector3] = []
## 女巫浮空牌：记录初始位置/相位，做轻微上下浮动与自转
var _witch_cards: Array[MeshInstance3D] = []
var _witch_card_origins: Array[Vector3] = []
var _witch_card_phases: Array[float] = []


func _ready() -> void:
	add_to_group("buffer_zone")
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)
	_base_light_energy = rune_light.light_energy
	for child in $FloatingRunes.get_children():
		if child is Node3D:
			_floating_runes.append(child as Node3D)
			_float_origins.append((child as Node3D).position)
	for child in witch_cards_root.get_children():
		if child is MeshInstance3D:
			_witch_cards.append(child as MeshInstance3D)
			_witch_card_origins.append((child as MeshInstance3D).position)
			_witch_card_phases.append(_witch_phase(child.get_instance_id()))


func _process(delta: float) -> void:
	_time += delta
	# 触发区刻意保持“隐形”：地面上没有任何符文圈/紫色标记，
	# 玩家只是走进这块空气，Area3D 自动触发。
	# 光源呼吸：进入缓冲区后更亮，提示“这里不一样”
	var glow := 0.88 + 0.12 * sin(_time * 1.7)
	if _active:
		glow *= active_glow_multiplier
	rune_light.light_energy = _base_light_energy * glow
	# 漂浮符文：轻微上下浮动 + 自转
	for index in _floating_runes.size():
		var rune := _floating_runes[index]
		var origin := _float_origins[index]
		rune.position.y = origin.y + sin(_time * float_speed + index * 1.3) * float_amplitude
		rune.rotation.y += delta * (0.4 + 0.15 * index)
	# 帷幕微微呼吸，避免死板
	if rift != null:
		var pulse := 1.0 + 0.015 * sin(_time * 1.1)
		rift.scale = Vector3(pulse, pulse, 1.0)
	# 女巫的浮空牌：上下浮动 + 自转；玩家进入后幅度略微加大
	var card_boost := 1.6 if _active else 1.0
	for index in _witch_cards.size():
		var card := _witch_cards[index]
		var origin := _witch_card_origins[index]
		var phase := _witch_card_phases[index]
		card.position.y = origin.y + sin(_time * 0.8 + phase) * 0.055 * card_boost
		card.rotation.y += delta * (0.22 + 0.05 * index) * card_boost
	# 门楣上的“女巫之眼”：偶尔眨一下，别用固定节奏，免得像节拍器
	if left_eye != null and right_eye != null:
		var blink := sin(_time * 0.73) + sin(_time * 1.91 + 1.3) + sin(_time * 0.23 + 2.1)
		var eyes_open := blink > -2.35
		left_eye.visible = eyes_open
		right_eye.visible = eyes_open


func _witch_phase(seed_value: int) -> float:
	return fmod(float(seed_value) * 0.61803398875, 1.0) * TAU


## 玩家进入/离开时由 main.gd 调用，增强/恢复光效与“事件是否武装”状态。
func set_active(active: bool) -> void:
	_active = active


func is_active() -> bool:
	return _active


## 供测试/维护面板读取触发区世界尺寸。
func get_trigger_size() -> Vector3:
	var collision := trigger_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		return (collision.shape as BoxShape3D).size
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# Area3D 回调
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	set_active(true)
	player_entered.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	set_active(false)
	player_exited.emit(body)
