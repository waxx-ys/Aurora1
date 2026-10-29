class_name CorridorPlayer
extends CharacterBody3D
## ============================================================================
## CorridorPlayer · 长廊角色控制器
## ----------------------------------------------------------------------------
## 功能：
##   * WASD 相机相对移动、Shift 疾跑、Space 跳跃、鼠标视角、V 切换第一/第三人称；
##   * 进入“缓冲区”后移动速度平滑降低（缓冲感），离开后恢复；
##   * 支持外部人物模型（见 player_model_slot.gd），并自动把 idle/run/jump 动画名
##     转发给模型；没有动画的占位小人也能正常运行；
##   * 事件/对话期间可由调度器调用 set_input_enabled(false) 冻结移动，但重力与
##     相机仍然工作，避免角色悬空或镜头卡死。
##
## 依赖节点结构（见 scenes/player.tscn）：
##   Player(CharacterBody3D, layer=player, mask=world)
##   ├─ Collision(CapsuleShape3D)
##   ├─ ModelRoot(Node3D + player_model_slot.gd)
##   │   └─ PlaceholderModel（程序化占位小人，接入外部模型后隐藏）
##   └─ CameraPivot
##       └─ SpringArm3D（第三人称弹簧臂，带碰撞）
##           └─ Camera3D
## ============================================================================

## 第一/第三人称切换时发出，HUD 可以据此换提示
signal camera_mode_changed(first_person: bool)
## 进入/离开缓冲区时发出（true=进入）
signal buffer_state_changed(in_buffer: bool)

@export_group("出生朝向")
## 角色身体初始朝向（度）。180 表示面朝 +Z（长廊深处方向）。
## 之所以用导出变量而不是直接改场景 Transform：避免手写 .tscn 时旋转矩阵写错。
@export var initial_yaw_deg: float = 180.0
## 相机初始朝向（度）。180 表示看向 +Z（长廊深处），相机自动落在角色身后。
## 说明：SpringArm3D 的子相机会被放到臂的 +Z 端，并看向臂的 -Z 方向；
## 因此 pivot yaw=180 时，相机在角色 -Z 侧、看向 +Z。
@export var initial_camera_yaw_deg: float = 180.0

@export_group("移动")
## 正常步行速度（米/秒）
@export var walk_speed: float = 4.2
## 疾跑速度
@export var sprint_speed: float = 6.8
## 缓冲区内的速度倍率（越小越“黏”，用来制造缓冲/减速感）
@export var buffer_speed_multiplier: float = 0.42
## 水平速度趋近目标值的加速度
@export var acceleration: float = 16.0
## 缓冲区减速/恢复的平滑速度
@export var buffer_transition_speed: float = 1.6
## 重力加速度
@export var gravity: float = 20.0
## 起跳初速度
@export var jump_velocity: float = 5.4
## 离开地面后仍允许起跳的宽限时间（土狼时间，提升手感）
@export var coyote_time: float = 0.12
## 落地前提前按跳跃的缓冲时间（跳跃缓冲）
@export var jump_buffer_time: float = 0.12

@export_group("相机")
## 鼠标灵敏度（弧度/像素）
@export var mouse_sensitivity: float = 0.0022
## 俯仰角限制
@export var pitch_min_deg: float = -62.0
@export var pitch_max_deg: float = 68.0
## 第三人称弹簧臂长度
@export var third_person_distance: float = 3.4
## 第一人称时弹簧臂长度（贴近眼睛）
@export var first_person_distance: float = 0.02
## 第三人称相机高度（相对脚底）
@export var third_person_pivot_height: float = 1.55
## 第一人称相机高度（相对脚底，约眼睛高度）
@export var first_person_pivot_height: float = 1.62
## 疾跑时相机 FOV 增量
@export var sprint_fov_boost: float = 5.0
## 基础 FOV
@export var base_fov: float = 70.0

var _yaw: float = 0.0         ## 相机 yaw（0 = 看向 +Z，长廊纵深方向）
var _pitch: float = -3.0
var _first_person: bool = false
var _input_enabled: bool = true
var _look_enabled: bool = true
var _in_buffer: bool = false
var _speed_scale: float = 1.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _facing_angle: float = PI
var _animation_state: StringName = &"idle"
## 女巫试炼刻印：正面=疾行，负面=滞步。乘在普通速度上，与缓冲区减速叠加。
var _trial_multiplier: float = 1.0
var _trial_remaining: float = 0.0

@onready var model_root: PlayerModelSlot = $ModelRoot as PlayerModelSlot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	# 让 Area3D 通过碰撞层识别玩家：玩家在 layer 2（player），触发器 mask 2。
	collision_layer = 1 << 1
	collision_mask = 1 << 0
	add_to_group("player")
	# 关键：只旋转「模型」，不旋转 CharacterBody3D 本体。
	# 原因：CameraPivot 是 Player 的子节点，如果旋转 Player，相机 yaw 会被叠加两次
	#（世界 yaw = 身体 yaw + pivot yaw），镜头就会乱飘。
	# 身体碰撞是胶囊体，本身不需要转向；视觉朝向交给 ModelRoot。
	model_root.rotation.y = deg_to_rad(initial_yaw_deg)
	_facing_angle = model_root.rotation.y
	_yaw = deg_to_rad(initial_camera_yaw_deg)
	camera_pivot.rotation.y = _yaw
	spring_arm.rotation.x = _pitch
	spring_arm.spring_length = third_person_distance
	camera.fov = base_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 外部模型接入/替换后，立刻按当前动作状态补播一次动画
	model_root.model_attached.connect(_on_model_attached)


func _physics_process(delta: float) -> void:
	_update_coyote(delta)
	_apply_gravity(delta)
	_update_buffer_scale(delta)
	_update_trial_effect(delta)

	var target_speed := _current_target_speed()
	var wish_dir := Vector3.ZERO
	if _input_enabled:
		var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# 相机视线方向 = pivot 局部 -Z 绕 Y 旋转：
		#   forward = (-sin(yaw), 0, -cos(yaw))，yaw=180° 时是 +Z（长廊深处）
		#   right   = ( cos(yaw), 0, -sin(yaw))，屏幕上“右”的方向
		var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		wish_dir = (right * input_vector.x + forward * -input_vector.y)
		if wish_dir.length() > 1.0:
			wish_dir = wish_dir.normalized()
		_handle_jump(delta)

	var desired := wish_dir * target_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)

	var was_on_floor := is_on_floor()
	move_and_slide()
	if not was_on_floor and is_on_floor():
		_on_landed()

	_update_facing(delta, wish_dir)
	_update_fov(delta)
	_update_animation_state()


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		# 鼠标下移 → pitch 减小 → 视线向下（标准 FPS 手感）
		_pitch = clampf(
			_pitch - motion.relative.y * mouse_sensitivity,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg)
		)
		camera_pivot.rotation.y = _yaw
		spring_arm.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_V:
			toggle_camera()
		elif key_event.physical_keycode == KEY_ESCAPE:
			# 只负责释放鼠标；剧情取消逻辑由 main.gd 处理
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------
# 对外 API（main.gd / HUD / 测试调用）
# ---------------------------------------------------------------------------

## 冻结/恢复玩家移动输入（剧情、进入试炼、返回动画时用）。
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		velocity.x = 0.0
		velocity.z = 0.0


func is_input_enabled() -> bool:
	return _input_enabled


## 开启/关闭鼠标视角（截图工具、过场镜头、无鼠标设备时用）。
func set_look_enabled(enabled: bool) -> void:
	_look_enabled = enabled


## 女巫刻印：给角色加一个限时的速度倍率（success=1.18 疾行；fail=0.82 滞步）。
## HUD 的刻印条由 main.gd 负责显示，这里只管数值。
func apply_trial_effect(multiplier: float, duration: float) -> void:
	_trial_multiplier = clampf(multiplier, 0.5, 1.6)
	_trial_remaining = maxf(duration, 0.0)
	if _trial_remaining <= 0.0:
		_trial_multiplier = 1.0


func clear_trial_effect() -> void:
	_trial_multiplier = 1.0
	_trial_remaining = 0.0


func get_trial_multiplier() -> float:
	return _trial_multiplier


func get_trial_remaining() -> float:
	return _trial_remaining


## 进入/离开缓冲区：会平滑降低/恢复移动速度。
func set_buffer_zone(active: bool) -> void:
	if _in_buffer == active:
		return
	_in_buffer = active
	buffer_state_changed.emit(active)


func is_in_buffer_zone() -> bool:
	return _in_buffer


## 第一/第三人称切换。
func toggle_camera() -> void:
	_first_person = not _first_person
	if _first_person:
		spring_arm.spring_length = first_person_distance
		camera_pivot.position.y = first_person_pivot_height
		model_root.set_first_person(true)
	else:
		spring_arm.spring_length = third_person_distance
		camera_pivot.position.y = third_person_pivot_height
		model_root.set_first_person(false)
	camera_mode_changed.emit(_first_person)


func is_first_person() -> bool:
	return _first_person


## 瞬移（测试/检查点重调用）。
func teleport_to(target_position: Vector3) -> void:
	global_position = target_position
	velocity = Vector3.ZERO


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 让相机看向某个方向，并把身体也转向该方向（测试与“返回长廊”时使用）。
## yaw_radians：0 = 看向 +Z（长廊深处）。
func face_direction(yaw_radians: float) -> void:
	_yaw = yaw_radians
	camera_pivot.rotation.y = _yaw
	_facing_angle = _yaw
	model_root.rotation.y = _facing_angle


## 一次性设置视角（截图工具、过场动画、维护调试用）：
##   yaw_deg   180 = 看向 +Z（长廊深处），0 = 看向 -Z（入口）
##   pitch_deg 正数 = 视线向上，负数 = 视线向下
##   first_person 是否切到第一人称
func apply_camera_view(yaw_deg: float, pitch_deg: float, first_person: bool = false) -> void:
	_yaw = deg_to_rad(yaw_deg)
	camera_pivot.rotation.y = _yaw
	# 模型面向相机看的同一方向：模型默认朝 -Z，所以模型 rotation.y = 相机 yaw + PI
	_facing_angle = _yaw
	model_root.rotation.y = _facing_angle
	_pitch = clampf(deg_to_rad(pitch_deg), deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	spring_arm.rotation.x = _pitch
	if first_person and not _first_person:
		toggle_camera()
	elif not first_person and _first_person:
		toggle_camera()


# ---------------------------------------------------------------------------
# 内部实现
# ---------------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _update_coyote(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _handle_jump(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_play_animation(&"jump")


func _on_landed() -> void:
	# 预留：落地音效/灰尘粒子可以挂这里
	pass


func _current_target_speed() -> float:
	var base := sprint_speed if Input.is_action_pressed("sprint") and _input_enabled else walk_speed
	if not _input_enabled:
		base = 0.0
	return base * _speed_scale * _trial_multiplier


func _update_buffer_scale(delta: float) -> void:
	var target := buffer_speed_multiplier if _in_buffer else 1.0
	_speed_scale = move_toward(_speed_scale, target, buffer_transition_speed * delta)


func _update_trial_effect(delta: float) -> void:
	if _trial_remaining <= 0.0:
		return
	_trial_remaining = maxf(_trial_remaining - delta, 0.0)
	if _trial_remaining <= 0.0:
		_trial_multiplier = 1.0


func _update_facing(delta: float, wish_dir: Vector3) -> void:
	if wish_dir.length() < 0.05 or _first_person:
		return
	# 模型默认面朝 -Z：yaw = atan2(-x, -z)
	var target_angle := atan2(-wish_dir.x, -wish_dir.z)
	_facing_angle = lerp_angle(_facing_angle, target_angle, clampf(12.0 * delta, 0.0, 1.0))
	# 只转模型，不转玩家本体（否则相机 yaw 会被父节点叠加）
	model_root.rotation.y = _facing_angle


func _update_fov(delta: float) -> void:
	var target_fov := base_fov
	if not _first_person and Input.is_action_pressed("sprint") and get_horizontal_speed() > walk_speed:
		target_fov += sprint_fov_boost
	camera.fov = lerpf(camera.fov, target_fov, clampf(6.0 * delta, 0.0, 1.0))


func _on_model_attached(_model: Node) -> void:
	_animation_state = &""
	_update_animation_state()


func _update_animation_state() -> void:
	if model_root == null or not model_root.has_external_model():
		return
	var next_state: StringName = &"idle"
	if not is_on_floor():
		next_state = &"jump"
	elif get_horizontal_speed() > 0.4:
		next_state = &"run"
	if next_state != _animation_state:
		_animation_state = next_state
		_play_animation(next_state)


func _play_animation(animation_name: StringName) -> void:
	if model_root != null:
		model_root.play_animation(animation_name)
