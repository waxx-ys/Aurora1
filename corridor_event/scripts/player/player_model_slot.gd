class_name PlayerModelSlot
extends Node3D
## ============================================================================
## PlayerModelSlot · 人物模型接入插槽
## ----------------------------------------------------------------------------
## 这是「外部人物模型」进入本项目的唯一官方通道：
##   * 场景 scenes/player.tscn 里 ModelRoot 节点挂的就是本脚本；
##   * 现在里面放的是程序化占位小人（PlaceholderModel），没有外部模型也能玩；
##   * 拿到真正的角色模型（.glb / .gltf / .blend 导入）后，走下面任一方式接入：
##
##   方式 A（推荐，零代码）：
##     Godot 编辑器打开 scenes/player.tscn → 选中 ModelRoot →
##     把导入后生成的模型场景（.glb 拖进来会生成 PackedScene）拖成 ModelRoot 的子节点 →
##     在检查器把本脚本的 `external_model` 指到这个子节点 →
##     把子节点缩放/旋转到与占位小人一致（脚底 y=0，朝向 -Z）→ 保存。
##
##   方式 B（代码/运行时换肤，适合多角色）：
##     var slot := player.get_node("ModelRoot") as PlayerModelSlot
##     slot.attach_model(load("res://characters/hero.glb"))
##
##   方式 C（在别处实例化后调用）：
##     slot.attach_model(existing_node)  # 直接传已实例化的 Node3D
##
## 约定与注意事项（接模型前务必看 docs/03_人物模型接入通道.md）：
##   1. 模型原点在脚底，面朝 -Z（Godot 的“前方”），这样不用额外旋转；
##   2. 身高建议 1.8 m 左右，与胶囊碰撞体（半径 0.34、高 1.8）对齐；
##   3. 如果模型带 AnimationPlayer，`play_animation()` 会按名字播放；
##      动画合法·非法都安全（找不到就只打印警告，不崩溃）；
##   4. 第一人称模式会隐藏模型（避免看到自己的后脑勺），由 set_first_person() 控制；
##   5. 占位小人在接入外部模型后会自动隐藏，但不会被删除，方便随时切回。
## ============================================================================

## 外部模型接入/替换时发出，UI 或剧情可以据此做换装提示
signal model_attached(model: Node3D)
## 请求播放某个动画（供动画状态机或接入方监听）
signal animation_requested(animation_name: StringName)

## 在编辑器里把外部模型节点拖到这里（方式 A）。
## 若为空，则运行时查找名为 external_model 的子节点。
@export var external_model: Node3D = null
## 占位模型节点名（在 ModelRoot 下），接入外部模型后会被隐藏
@export var placeholder_name: StringName = &"PlaceholderModel"

var _placeholder: Node3D = null
var _current_model: Node3D = null
var _first_person: bool = false
var _animation_player: AnimationPlayer = null


func _ready() -> void:
	_placeholder = get_node_or_null(NodePath(String(placeholder_name))) as Node3D
	if external_model != null:
		_apply_model(external_model)
	else:
		# 方式 A 的简化版：不设置导出变量，只要子节点叫 ExternalModel 也会自动接入。
		var auto_model := get_node_or_null("ExternalModel") as Node3D
		if auto_model != null:
			_apply_model(auto_model)
		elif _placeholder != null:
			_current_model = _placeholder


## 接入/替换外部人物模型。
## 参数 model 可以是：
##   * PackedScene（推荐）——会实例化后加入 ModelRoot；
##   * Node3D 实例——直接 reparent 到 ModelRoot 下。
## 返回实际使用的模型节点；失败返回 null。
func attach_model(model: Variant) -> Node3D:
	var instance: Node3D = null
	if model is PackedScene:
		instance = (model as PackedScene).instantiate() as Node3D
	elif model is Node3D:
		instance = model as Node3D
	if instance == null:
		push_warning("[PlayerModelSlot] attach_model 只接受 PackedScene 或 Node3D")
		return null
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	add_child(instance)
	# 新模型默认对齐到插槽原点（脚底）。如果美术资源原点不在脚底，
	# 请在这里或编辑器里调整 position，而不是改碰撞体。
	instance.position = Vector3.ZERO
	instance.rotation = Vector3.ZERO
	_apply_model(instance)
	return instance


## 切回程序化占位小人。
func use_placeholder() -> void:
	if _current_model != null and _current_model != _placeholder:
		_current_model.queue_free()
	_current_model = _placeholder
	if _placeholder != null:
		_placeholder.visible = not _first_person
	model_attached.emit(_placeholder)


## 播放模型自带的动画（若无 AnimationPlayer 或动画名不存在，安全忽略）。
## 动画名示例：&"idle"、&"run"、&"jump"。
func play_animation(animation_name: StringName) -> void:
	animation_requested.emit(animation_name)
	if _animation_player == null:
		return
	if not _animation_player.has_animation(animation_name):
		# 只提示一次，避免每帧刷屏
		if not _missing_animation_warned:
			_missing_animation_warned = true
			push_warning("[PlayerModelSlot] 模型没有动画：%s（忽略，不影响玩法）" % animation_name)
		return
	_animation_player.play(animation_name)


## 第一人称时隐藏自身模型。
func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if _current_model != null:
		_current_model.visible = not enabled


func is_first_person() -> bool:
	return _first_person


func get_current_model() -> Node3D:
	return _current_model


func has_external_model() -> bool:
	return _current_model != null and _current_model != _placeholder


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

var _missing_animation_warned: bool = false


func _apply_model(model: Node3D) -> void:
	if model == null:
		return
	# 移除上一个外部模型（保留占位小人）
	if _current_model != null and _current_model != _placeholder and is_instance_valid(_current_model):
		_current_model.queue_free()
	_current_model = model
	_current_model.visible = not _first_person
	if _placeholder != null and _current_model != _placeholder:
		_placeholder.visible = false
	_animation_player = _find_animation_player(_current_model)
	if _animation_player != null:
		print("[PlayerModelSlot] 发现 AnimationPlayer：%s（动画数：%d）" % [
			_animation_player.name, _animation_player.get_animation_list().size()
		])
	model_attached.emit(_current_model)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
