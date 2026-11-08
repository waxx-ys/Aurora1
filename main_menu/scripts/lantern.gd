extends Node3D
## 主界面左前景的旧提灯：轻微摇摆 + 火光闪烁。
## 结构与照片里的提灯一致：顶盖、四根铁骨、四面暖玻璃、底锥、吊链与点光。

@export var sway_amount: float = 0.035
@export var flicker_amount: float = 0.22
@onready var _light: OmniLight3D = $FlameLight
@onready var _glass_root: Node3D = $GlassRoot
var _time: float = 0.0
var _base_energy: float = 3.2
var _base_rotation: Vector3

func _ready() -> void:
	_time = randf() * 10.0
	_base_energy = _light.light_energy
	_base_rotation = rotation
	add_to_group("menu_lantern")

func _process(delta: float) -> void:
	_time += delta
	# 不规则“将熄”脉冲，避免机械正弦
	var slow := sin(_time * 1.3) * 0.5 + 0.5
	var fast := sin(_time * 9.7 + 1.2) * 0.5 + 0.5
	var pulse := 0.82 + 0.14 * slow + 0.04 * fast
	_light.light_energy = _base_energy * pulse
	rotation = _base_rotation + Vector3(
		sin(_time * 0.75) * sway_amount,
		0.0,
		cos(_time * 0.58) * sway_amount * 0.8
	)
	_glass_root.scale = Vector3.ONE * (0.985 + 0.03 * pulse)
