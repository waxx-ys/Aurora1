extends Node3D
## ============================================================================
## CorridorAtmosphere · 长廊“阴森氛围”的统一驱动
## ----------------------------------------------------------------------------
## 挂在 Main 下的 Atmosphere 节点上（由 tools/build_corridor.gd 生成）。
##
## 负责三件事，全部只看 group，不写死具体节点，方便后续加灯/加挂饰：
##   1. 旧灯闪烁：group "flicker_light" 里的 OmniLight3D 能量做低频抖动 +
##      偶发“将熄”暗脉冲；保留 15% 基线，避免玩家眼前一黑什么都看不见。
##   2. 吊灯/锁链摆动：group "sway_pivot" 里的 Node3D 做轻微 X/Z 旋转摆动。
##   3. 长廊“呼吸”：组 "breathing_prop" 的道具做极小幅度缩放/浮动（可选）。
##
## 视觉原则（维护时请保持）：
##   * 阴森 ≠ 全黑：雾和冷光要能看清前方 20~30 米，否则跑酷没法玩；
##   * 闪烁不能影响可读性：单灯最暗不低于基线的 55%，且不同灯相位错开；
##   * 所有动画用时间函数，无随机状态，便于测试/复现。
## ============================================================================

@export_group("旧灯闪烁")
## 是否启用灯光闪烁
@export var flicker_enabled: bool = true
## 闪烁频率
@export var flicker_speed: float = 1.0
## 闪烁幅度（0=稳定，1=大幅抖动）
@export var flicker_amount: float = 0.28
## 偶发暗脉冲的概率/强度（0=不出现）
@export var blackout_chance: float = 0.35
@export var blackout_strength: float = 0.3

@export_group("悬挂物")
## 吊灯/锁链摆动幅度（弧度）
@export var sway_amplitude: float = 0.035
## 摆动速度
@export var sway_speed: float = 0.55

@export_group("呼吸道具")
@export var breathing_amplitude: float = 0.015
@export var breathing_speed: float = 0.9

var _time: float = 0.0
var _lights: Array[OmniLight3D] = []
var _light_base_energy: Array[float] = []
var _light_phase: Array[float] = []
var _sway_pivots: Array[Node3D] = []
var _sway_base_rotation: Array[Vector3] = []
var _sway_phase: Array[float] = []
var _breathing_props: Array[Node3D] = []
var _breathing_base_scale: Array[Vector3] = []
var _breathing_phase: Array[float] = []
var _fog_sheets: Array[MeshInstance3D] = []
var _fog_sheet_origins: Array[Vector3] = []
var _fog_sheet_phases: Array[float] = []


func _ready() -> void:
	# 建图模式（tools/build_corridor.gd 把场景临时挂进树）不启动动画
	if Engine.has_meta("corridor_build"):
		return
	_collect_group_children(get_tree().root, "flicker_light", _lights)
	for light in _lights:
		_light_base_energy.append(light.light_energy)
		_light_phase.append(_hash_phase(light.get_instance_id()))
	_collect_group_children(get_tree().root, "sway_pivot", _sway_pivots)
	for pivot in _sway_pivots:
		_sway_base_rotation.append(pivot.rotation)
		_sway_phase.append(_hash_phase(pivot.get_instance_id()))
	_collect_group_children(get_tree().root, "breathing_prop", _breathing_props)
	for prop in _breathing_props:
		_breathing_base_scale.append(prop.scale)
		_breathing_phase.append(_hash_phase(prop.get_instance_id()))
	_collect_group_children(get_tree().root, "fog_sheet", _fog_sheets)
	for sheet in _fog_sheets:
		_fog_sheet_origins.append(sheet.position)
		_fog_sheet_phases.append(_hash_phase(sheet.get_instance_id()))


func _process(delta: float) -> void:
	_time += delta
	if flicker_enabled:
		_update_flicker()
	_update_sway()
	_update_breathing()
	_update_fog_sheets()


# ---------------------------------------------------------------------------
# 旧灯闪烁
# ---------------------------------------------------------------------------

func _update_flicker() -> void:
	var t := _time * flicker_speed
	for index in _lights.size():
		var light := _lights[index]
		if not is_instance_valid(light):
			continue
		var phase := _light_phase[index]
		# 三个不同频率的正弦叠加，形成不规律的“呼吸”
		var wobble := (
			sin(t * 7.3 + phase) * 0.5
			+ sin(t * 13.7 + phase * 1.7) * 0.3
			+ sin(t * 23.1 + phase * 0.4) * 0.2
		)
		var energy := _light_base_energy[index] * (1.0 - flicker_amount * 0.5 + flicker_amount * 0.5 * wobble)
		# 偶发“将熄”：由时间片哈希决定，每盏灯错开，持续 0.12~0.3 秒
		var slot: float = floorf(_time * 0.8 + phase * 3.0)
		var roll := _hash01(slot + phase)
		if roll < blackout_chance * 0.08:
			var dip := blackout_strength * (0.6 + 0.4 * sin(_time * 40.0 + phase))
			energy *= clampf(1.0 - dip, 0.15, 1.0)
		light.light_energy = maxf(energy, _light_base_energy[index] * 0.12)


# ---------------------------------------------------------------------------
# 吊灯/锁链摆动
# ---------------------------------------------------------------------------

func _update_sway() -> void:
	for index in _sway_pivots.size():
		var pivot := _sway_pivots[index]
		if not is_instance_valid(pivot):
			continue
		var phase := _sway_phase[index]
		var base := _sway_base_rotation[index]
		pivot.rotation = Vector3(
			base.x + sin(_time * sway_speed + phase) * sway_amplitude * 0.6,
			base.y,
			base.z + sin(_time * sway_speed * 0.73 + phase * 1.9) * sway_amplitude
		)


# ---------------------------------------------------------------------------
# 雾帘漂移
# ---------------------------------------------------------------------------

func _update_fog_sheets() -> void:
	for index in _fog_sheets.size():
		var sheet := _fog_sheets[index]
		if not is_instance_valid(sheet):
			continue
		var origin := _fog_sheet_origins[index]
		sheet.position.x = origin.x + sin(_time * 0.11 + _fog_sheet_phases[index]) * 0.55
		sheet.position.y = origin.y + sin(_time * 0.07 + _fog_sheet_phases[index] * 1.7) * 0.08


# ---------------------------------------------------------------------------
# 呼吸道具（可选）
# ---------------------------------------------------------------------------

func _update_breathing() -> void:
	for index in _breathing_props.size():
		var prop := _breathing_props[index]
		if not is_instance_valid(prop):
			continue
		var scale_value := 1.0 + sin(_time * breathing_speed + _breathing_phase[index]) * breathing_amplitude
		prop.scale = _breathing_base_scale[index] * scale_value


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _collect_group_children(root: Node, group_name: StringName, out: Array) -> void:
	for node in root.get_children():
		_collect_group_children(node, group_name, out)
	if root.is_in_group(group_name):
		out.append(root)


func _hash_phase(seed_value: int) -> float:
	return fmod(float(seed_value) * 0.61803398875, 1.0) * TAU


func _hash01(value: float) -> float:
	var x := sin(value * 127.1 + 311.7) * 43758.5453
	return x - floor(x)
