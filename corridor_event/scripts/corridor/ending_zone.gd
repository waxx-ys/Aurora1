class_name EndingZone
extends Area3D
## ============================================================================
## EndingZone · 长廊尽头的“游戏结束文本”触发区（预留空间）
## ----------------------------------------------------------------------------
## 位置：主场景 z=59 左右（EndDoor 前面约 2.6 米），由 tools/build_corridor.gd
##       实例化到 Main 下。
##
## 作用：
##   1. 玩家走进来 → 发 player_entered，main.gd 让 HUD 显示“结局文本”面板；
##   2. 玩家走出去 → 发 player_exited，HUD 收起；
##   3. 灯柱/符文圈有轻微呼吸，告诉玩家“这里是一个舞台”。
##
## 为什么单独做一个场景：
##   * 这部分空间需要保持空旷（不摆符纸/苔藓/锁链/枯骨），以后要放
##     游戏结束文本、制作名单、结局 CG 或类似演出，直接替换 HUD 面板
##     或在此处放 3D 文本即可；
##   * 触发逻辑与女巫牌阵完全解耦，互不影响。
##
## 预留内容：
##   * 中央空地约 5.8 × 4.2 米（z≈56.9–61.1），没有地面符文/触发标记；
##   * 后侧祭坛前有 Marker3D "EndingTextAnchor"（可挂 3D 文本/贴图）；
##   * 左右铁柱 + 拱梁形成取景框；
##   * HUD 的 EndingPanel 目前显示结局文案，后续可替换为制作名单/结算。
## ============================================================================

signal player_entered(player: Node3D)
signal player_exited(player: Node3D)

@export var active_glow_multiplier: float = 1.5

@onready var left_lamp: MeshInstance3D = $Stage/LeftPillarLamp
@onready var right_lamp: MeshInstance3D = $Stage/RightPillarLamp

var _active: bool = false
var _time: float = 0.0


func _ready() -> void:
	add_to_group("ending_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta
	# 这里不做地面发光标记；只有两侧灯球轻微呼吸，保持空间纵深。
	var pulse := 0.9 + 0.1 * sin(_time * 1.3)
	if _active:
		pulse *= active_glow_multiplier
	if left_lamp != null:
		left_lamp.scale = Vector3.ONE * pulse
	if right_lamp != null:
		right_lamp.scale = Vector3.ONE * pulse


func set_active(active: bool) -> void:
	_active = active


func is_active() -> bool:
	return _active


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
