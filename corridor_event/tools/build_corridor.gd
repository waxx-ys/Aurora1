extends SceneTree
## ============================================================================
## build_corridor.gd · 阴森长廊地图生成器（编辑器工具，非运行期脚本）
## ----------------------------------------------------------------------------
## 运行方式（改完尺寸/材质/氛围后重新生成 scenes/main.tscn）：
##   "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless \
##       --path "$HOME/地铁跑酷/corridor_event" \
##       --script res://tools/build_corridor.gd
##
## 为什么用脚本建图而不是手摆：
##   1. 长廊是规则重复结构（灯/梁/符纸按间距生成），参数化后不容易漏；
##   2. 尺寸改一个常量就能整体重建，碰撞体与视觉永远对齐；
##   3. 这份脚本本身就是“地图制作全过程”的可执行版本，详见 docs/01_地图制作全过程.md。
##
## 氛围设计（鬼怪跑酷）：
##   * 冷色月光 + 灰蓝环境光 + 中性灰蓝浓雾，能见度约 25–35 米；
##   * 石砖地面偏湿、原木墙褪色，踢脚线长苔藓；
##   * 沿途约 1 盏/28 米的破旧魂灯：昏暗暖黄自发光 + 铁笼 + 吊链，有的歪挂/断条/将熄，会缓慢摆动与闪烁；
##   * 墙上挂符纸、地上散落枯骨、天花板垂锁链、贴地飘雾；
##   * 中段（约 1260 m）是女巫牌阵，尽头（约 2512 m）是结局文本触发区。
##
## 生成内容：
##   Main
##   ├─ WorldEnvironment（冷雾/glow/调色）+ MoonLight
##   ├─ Corridor（地板、原木墙、天花板、横梁、苔藓、魂灯、符纸、枯骨、锁链、雾、封印门）
##   ├─ Atmosphere（flicker/sway 的统一驱动脚本）
##   ├─ BufferZone（中段女巫牌阵：符文石台 + 记忆之门 + 触发 Area3D + 浮空卡牌）
##   ├─ EndingZone（尽头结局文本触发区，中央预留空地/取景框）
##   ├─ Player（CharacterBody3D 角色 + 相机 + 模型插槽）
##   └─ HUD（暗角/刻印/尽头结局文本/调试）
##
## 只改生成的 main.tscn；不要在这个脚本之外手动改 main.tscn 再重跑，
## 否则手工修改会被覆盖（维护手册里写了“要留手改就不要再跑生成器”的约定）。
## ============================================================================

const OUT_PATH := "res://scenes/main.tscn"

# ---- 长廊尺寸（米）---------------------------------------------------------
const LENGTH: float = 2520.0     ## 长廊总长：步行 4.2 m/s 约 10 分钟
const WIDTH: float = 6.0         ## 内侧宽度（可走范围 x -3..3）
const HEIGHT: float = 4.4        ## 内侧净高
const HALF_W: float = WIDTH / 2.0
const Z_START: float = -2.0      ## 起点封墙的世界 Z
const Z_END: float = 2518.0      ## 尽头封墙的世界 Z（= Z_START + LENGTH）
const Z_CENTER: float = 1258.0   ## 几何中心
const ZONE_Z: float = 1260.0     ## 中段女巫牌阵中心 Z（约 5 分钟路程）
const PLAYER_Z: float = 1.6      ## 玩家出生点 Z
const ENDING_Z: float = 2512.0   ## 尽头结局文本触发区中心 Z

# ---- 装饰间距（米）----------------------------------------------------------
const LANTERN_STEP := 28
const BEAM_STEP := 24
const TALISMAN_STEP := 40
const MOSS_STEP := 50
const BONE_STEP := 37
const CHAIN_STEP := 110
const RAG_STEP := 96
const PLANK_STEP := 108


var _root: Node3D
var _mats: Dictionary = {}
var _node_count: int = 0
## 本次生成的节点列表（用于进入场景树后统一设置 owner，供 PackedScene 保存）
var _owned_nodes: Array[Node] = []


func _initialize() -> void:
	print("[build_corridor] start · length=%.1f width=%.1f height=%.1f" % [LENGTH, WIDTH, HEIGHT])
	# 告诉 main.gd：现在是“建图模式”，不要在 _ready 里跑游戏逻辑。
	Engine.set_meta("corridor_build", true)
	_load_materials()

	# 先在“游离状态”搭完整棵树，再整体挂进场景树，这样 owner 才合法。
	_root = Node3D.new()
	_root.name = "Main"
	_root.set_script(load("res://scripts/main.gd"))
	_root.set("event_zone_center_z", ZONE_Z)
	_root.set("fog_ramp_start_z", ZONE_Z - 16.0)
	_root.set("fog_peak_z", ZONE_Z - 1.0)
	_root.set("fog_hold_end_z", ZONE_Z + 2.0)
	_root.set("fog_clear_end_z", ZONE_Z + 12.0)

	_build_environment()
	_build_corridor()
	_build_atmosphere()
	_build_buffer_zone()
	_build_ending_zone()
	_build_player()
	_build_hud()

	# 挂进当前场景树（SceneTree.root），然后统一设置 owner 并保存。
	get_root().add_child(_root)
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.owner = _root
	_save_scene()

	# 清理临时树，避免退出时一堆 “Leaked instance dependency”。
	get_root().remove_child(_root)
	_root.free()
	Engine.remove_meta("corridor_build")
	quit(0)


# ============================================================================
# 材质
# ============================================================================

func _load_materials() -> void:
	_mats["floor"] = load("res://materials/floor_stone.tres")
	_mats["wall"] = load("res://materials/wall_log.tres")
	_mats["wall_end"] = load("res://materials/wall_log_end.tres")
	_mats["ceiling"] = load("res://materials/ceiling_wood.tres")
	_mats["trim"] = load("res://materials/wood_trim.tres")
	_mats["iron"] = load("res://materials/iron_dark.tres")
	_mats["moss"] = load("res://materials/moss_dark.tres")
	_mats["bone"] = load("res://materials/bone_pale.tres")
	_mats["rune"] = load("res://materials/rune_glow.tres")
	_mats["flame"] = load("res://materials/lamp_glow.tres")
	_mats["talisman"] = load("res://materials/talisman_paper.tres")
	_mats["card"] = load("res://materials/card_back.tres")
	_mats["fog"] = load("res://materials/fog_mist.tres")
	_mats["rag"] = load("res://materials/rag_cloth.tres")
	_mats["dust"] = load("res://materials/dust_mote.tres")
	for key in _mats.keys():
		if _mats[key] == null:
			push_error("[build_corridor] 材质加载失败: %s" % key)


# ============================================================================
# 环境：阴森、冷雾、可见但压抑
# ============================================================================

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.011, 0.013, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.37, 1)
	env.ambient_light_energy = 0.92
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.15
	# 浓雾：近处仍能看清脚下与 10–15 米，20 米开始发灰，35 米外只剩轮廓。
	# 雾色是冷灰偏蓝，和“破旧暖灯”形成脏冷的对比。
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.2, 0.22, 1)
	env.fog_light_energy = 1.5
	env.fog_density = 0.038
	env.fog_aerial_perspective = 0.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.72
	env.adjustment_brightness = 1.0

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_attach(_root, world_env)

	# 冷色平行光只提供极弱的轮廓，主光来自破旧魂灯与牌阵
	var moon := DirectionalLight3D.new()
	moon.name = "MoonLight"
	moon.light_color = Color(0.42, 0.52, 0.62, 1)
	moon.light_energy = 0.36
	moon.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(38.0), 0.0)
	moon.shadow_enabled = false
	_attach(_root, moon)


# ============================================================================
# 长廊主体
# ============================================================================

func _build_corridor() -> void:
	var corridor := Node3D.new()
	corridor.name = "Corridor"
	_attach(_root, corridor)
	_build_floor(corridor)
	_build_walls(corridor)
	_build_ceiling(corridor)
	_build_trim_and_beams(corridor)
	_build_lanterns(corridor)
	_build_talismans(corridor)
	_build_rags_and_planks(corridor)
	_build_moss(corridor)
	_build_bones(corridor)
	_build_chains(corridor)
	_build_dust(corridor)
	_build_mist(corridor)
	_build_fog_sheets(corridor)
	_build_end_door(corridor)


func _build_floor(parent: Node) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(WIDTH, LENGTH)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	floor.mesh = plane
	floor.material_override = _mats["floor"]
	floor.position = Vector3(0, 0, Z_CENTER)
	_attach(parent, floor)

	_static_box(parent, "FloorCollision", Vector3(WIDTH, 0.4, LENGTH), Vector3(0, -0.2, Z_CENTER))


func _build_walls(parent: Node) -> void:
	# 左右墙用 QuadMesh（单面朝内，省一半面数）；UV 由材质 uv1_scale 控制，
	# 4 米一个褪色原木循环，与 4.4 米净高形成 1.1 次纵向重复。
	var right := _quad_mesh("RightWall", Vector2(LENGTH, HEIGHT), _mats["wall"],
		Vector3(HALF_W, HEIGHT / 2.0, Z_CENTER), Vector3(0, -PI / 2.0, 0))
	_attach(parent, right)
	var left := _quad_mesh("LeftWall", Vector2(LENGTH, HEIGHT), _mats["wall"],
		Vector3(-HALF_W, HEIGHT / 2.0, Z_CENTER), Vector3(0, PI / 2.0, 0))
	_attach(parent, left)

	# 墙体碰撞体积：厚 0.4m 的盒子，内表面正好落在 x=±3.0 的视觉墙面上。
	_static_box(parent, "RightWallCollision", Vector3(0.4, HEIGHT, LENGTH),
		Vector3(HALF_W + 0.2, HEIGHT / 2.0, Z_CENTER))
	_static_box(parent, "LeftWallCollision", Vector3(0.4, HEIGHT, LENGTH),
		Vector3(-HALF_W - 0.2, HEIGHT / 2.0, Z_CENTER))

	# 起点/尽头封墙（视觉 + 碰撞）
	var back := _quad_mesh("BackWall", Vector2(WIDTH, HEIGHT), _mats["wall_end"],
		Vector3(0, HEIGHT / 2.0, Z_START), Vector3.ZERO)
	_attach(parent, back)
	var front := _quad_mesh("FrontWall", Vector2(WIDTH, HEIGHT), _mats["wall_end"],
		Vector3(0, HEIGHT / 2.0, Z_END), Vector3(0, PI, 0))
	_attach(parent, front)
	_static_box(parent, "BackWallCollision", Vector3(WIDTH, HEIGHT, 0.4),
		Vector3(0, HEIGHT / 2.0, Z_START - 0.2))
	_static_box(parent, "FrontWallCollision", Vector3(WIDTH, HEIGHT, 0.4),
		Vector3(0, HEIGHT / 2.0, Z_END + 0.2))


func _build_ceiling(parent: Node) -> void:
	var ceiling := _quad_mesh("Ceiling", Vector2(WIDTH, LENGTH), _mats["ceiling"],
		Vector3(0, HEIGHT, Z_CENTER), Vector3(PI / 2.0, 0, 0))
	_attach(parent, ceiling)
	_static_box(parent, "CeilingCollision", Vector3(WIDTH, 0.3, LENGTH),
		Vector3(0, HEIGHT + 0.15, Z_CENTER))


func _build_trim_and_beams(parent: Node) -> void:
	# 踢脚线：压住墙脚与地板的接缝，阴森版本改用发黑的朽木
	for side in [-1.0, 1.0]:
		var trim := MeshInstance3D.new()
		trim.name = "Baseboard%s" % ("L" if side < 0 else "R")
		trim.mesh = _box_mesh(Vector3(0.14, 0.32, LENGTH))
		trim.material_override = _mats["trim"]
		trim.position = Vector3(side * (HALF_W - 0.08), 0.16, Z_CENTER)
		_attach(parent, trim)

	# 横梁：每隔 BEAM_STEP 米一根；牌阵/结局区附近留空
	var z := 10
	while z < int(Z_END) - 8:
		if absf(float(z) - ZONE_Z) > 8.0 and absf(float(z) - ENDING_Z) > 10.0:
			var beam := MeshInstance3D.new()
			beam.name = "Beam_%d" % z
			beam.mesh = _box_mesh(Vector3(WIDTH + 0.2, 0.2, 0.3))
			beam.material_override = _mats["trim"]
			beam.position = Vector3(0, HEIGHT - 0.12, float(z))
			_attach(parent, beam)
			for side in [-1.0, 1.0]:
				var bracket := MeshInstance3D.new()
				bracket.name = "BeamBracket_%d_%s" % [z, "L" if side < 0 else "R"]
				bracket.mesh = _box_mesh(Vector3(0.1, 0.5, 0.1))
				bracket.material_override = _mats["iron"]
				bracket.position = Vector3(side * (HALF_W - 0.05), HEIGHT - 0.45, float(z))
				_attach(parent, bracket)
		z += BEAM_STEP

func _build_lanterns(parent: Node) -> void:
	# 破旧魂灯：一根吊链 + 铁笼 + 昏暗暖黄火球 + OmniLight。
	# 整盏灯挂在 pivot 上，atmosphere.gd 通过 "sway_pivot" 组让它缓慢摇晃；
	# 光源通过 "flicker_light" 组做不规律闪烁。
	# 沿 2520 米长廊每隔约 28 米一盏；牌阵与结局区附近留空。
	var energy_cycle := [0.85, 0.65, 1.0, 0.9, 0.7, 0.8, 0.55, 0.95]
	var range_cycle := [7.0, 6.2, 7.5, 7.0, 6.4, 6.8, 6.0, 7.2]
	var z := 14
	var index := 0
	while z < int(Z_END) - 14:
		if absf(float(z) - ZONE_Z) > 8.0 and absf(float(z) - ENDING_Z) > 10.0:
			var side := -1.0 if index % 2 == 0 else 1.0
			var x := side * (HALF_W - 0.45)
			var pivot := Node3D.new()
			pivot.name = "LanternRig_%d" % index
			pivot.position = Vector3(x, HEIGHT - 0.05, float(z))
			var broken := index % 17 == 5
			var tilt := 0.12 * sin(float(index) * 2.1)
			pivot.rotation = Vector3(0.02 * cos(float(index) * 1.4), 0, tilt + (0.16 if broken else 0.0))
			pivot.add_to_group("sway_pivot")
			_attach(parent, pivot)

			var chain := MeshInstance3D.new()
			chain.name = "Chain"
			chain.mesh = _box_mesh(Vector3(0.018, 1.05, 0.018))
			chain.material_override = _mats["iron"]
			chain.position = Vector3(0, -0.55, 0)
			_attach(pivot, chain)

			var crown := MeshInstance3D.new()
			crown.name = "Crown"
			var crown_mesh := TorusMesh.new()
			crown_mesh.inner_radius = 0.09
			crown_mesh.outer_radius = 0.13
			crown_mesh.rings = 16
			crown_mesh.ring_segments = 6
			crown.mesh = crown_mesh
			crown.material_override = _mats["iron"]
			crown.position = Vector3(0, -1.02, 0)
			_attach(pivot, crown)

			var bottom := MeshInstance3D.new()
			bottom.name = "BottomRing"
			bottom.mesh = crown_mesh
			bottom.material_override = _mats["iron"]
			bottom.position = Vector3(0, -1.34, 0)
			_attach(pivot, bottom)

			var missing_bars := (index % 11 == 1)
			for bar_index in 4:
				if missing_bars and bar_index == 1:
					continue
				var angle := TAU * float(bar_index) / 4.0
				var bar := MeshInstance3D.new()
				bar.name = "CageBar_%d" % bar_index
				bar.mesh = _box_mesh(Vector3(0.012, 0.32, 0.012))
				bar.material_override = _mats["iron"]
				bar.position = Vector3(cos(angle) * 0.115, -1.18, sin(angle) * 0.115)
				_attach(pivot, bar)

			var flame := MeshInstance3D.new()
			flame.name = "Flame"
			var sphere := SphereMesh.new()
			sphere.radius = 0.075
			sphere.height = 0.17
			sphere.radial_segments = 12
			sphere.rings = 6
			flame.mesh = sphere
			flame.material_override = _mats["flame"]
			flame.position = Vector3(0, -1.18, 0)
			if broken:
				flame.scale = Vector3(0.55, 0.55, 0.55)
			_attach(pivot, flame)

			var light := OmniLight3D.new()
			light.name = "FlameLight"
			light.light_color = Color(1.0, 0.68, 0.36, 1)
			light.light_energy = 0.2 if broken else float(energy_cycle[index % energy_cycle.size()])
			light.omni_range = 6.0 if broken else float(range_cycle[index % range_cycle.size()])
			light.omni_attenuation = 1.9
			light.shadow_enabled = false
			light.position = Vector3(0, -1.18, 0)
			light.add_to_group("flicker_light")
			_attach(pivot, light)
			index += 1
		z += LANTERN_STEP

func _build_talismans(parent: Node) -> void:
	# 符纸：贴在墙上的旧黄纸，淡金符文微微发光；左右交替、略有倾斜。
	var index := 0
	var z := 8
	while z < int(Z_END) - 8:
		if absf(float(z) - ZONE_Z) > 6.0 and absf(float(z) - ENDING_Z) > 8.0:
			var side := -1.0 if index % 2 == 0 else 1.0
			var x := side * (HALF_W - 0.015)
			var talisman := MeshInstance3D.new()
			talisman.name = "Talisman_%d" % index
			var quad := QuadMesh.new()
			quad.size = Vector2(0.22, 0.5)
			talisman.mesh = quad
			talisman.material_override = _mats["talisman"]
			talisman.position = Vector3(x, 2.35 + 0.18 * sin(float(index) * 1.7), float(z))
			talisman.rotation = Vector3(0, -PI / 2.0 if side > 0 else PI / 2.0, 0.06 * sin(float(index)))
			_attach(parent, talisman)

			var pin := MeshInstance3D.new()
			pin.name = "Pin_%d" % index
			pin.mesh = _box_mesh(Vector3(0.02, 0.02, 0.02))
			pin.material_override = _mats["iron"]
			pin.position = Vector3(x, talisman.position.y + 0.25, float(z))
			_attach(parent, pin)
			index += 1
		z += TALISMAN_STEP

func _build_rags_and_planks(parent: Node) -> void:
	# 破烂的挂布 + 断木板：让长廊看起来真的年久失修
	var index := 0
	var z := 24
	while z < int(Z_END) - 20:
		if absf(float(z) - ZONE_Z) > 8.0 and absf(float(z) - ENDING_Z) > 12.0:
			var rag := MeshInstance3D.new()
			rag.name = "Rag_%d" % index
			var quad := QuadMesh.new()
			quad.size = Vector2(0.7, 1.3)
			rag.mesh = quad
			rag.material_override = _mats["rag"]
			var side := -1.0 if index % 2 == 0 else 1.0
			rag.position = Vector3(side * (1.7 + 0.2 * sin(float(index))), 3.15, float(z))
			rag.rotation = Vector3(0.04, 0.12 * sin(float(index)), 0.03 * float(index))
			_attach(parent, rag)
			index += 1
		z += RAG_STEP

	index = 0
	z = 40
	while z < int(Z_END) - 24:
		if absf(float(z) - ZONE_Z) > 8.0 and absf(float(z) - ENDING_Z) > 12.0:
			var side := -1.0 if index % 2 == 0 else 1.0
			var plank := MeshInstance3D.new()
			plank.name = "BrokenPlank_%d" % index
			plank.mesh = _box_mesh(Vector3(0.12, 0.08, 2.2))
			plank.material_override = _mats["trim"]
			plank.position = Vector3(side * 2.65, 0.5, float(z))
			plank.rotation = Vector3(0.42 * side, 0, 0.35 * (-1.0 if side > 0 else 1.0))
			_attach(parent, plank)
			index += 1
		z += PLANK_STEP

func _build_moss(parent: Node) -> void:
	# 墙脚苔藓：断断续续的暗绿窄条，让墙根“发潮”。
	var index := 0
	var z := 12
	while z < int(Z_END) - 8:
		if absf(float(z) - ZONE_Z) > 6.0 and absf(float(z) - ENDING_Z) > 8.0:
			for side in [-1.0, 1.0]:
				var moss := MeshInstance3D.new()
				moss.name = "Moss_%d_%s" % [index, "L" if side < 0 else "R"]
				moss.mesh = _box_mesh(Vector3(0.03, 0.045, 4.0))
				moss.material_override = _mats["moss"]
				moss.position = Vector3(side * (HALF_W - 0.015), 0.035, float(z))
				_attach(parent, moss)
			index += 1
		z += MOSS_STEP

func _build_bones(parent: Node) -> void:
	# 枯骨/碎骨：只在墙脚与阴影里放少量，避免变成“骷髅主题乐园”。
	var index := 0
	var z := 18
	while z < int(Z_END) - 12:
		if absf(float(z) - ZONE_Z) > 6.0 and absf(float(z) - ENDING_Z) > 10.0:
			var side := -1.0 if index % 2 == 0 else 1.0
			var bone := MeshInstance3D.new()
			bone.name = "Bone_%d" % index
			bone.mesh = _box_mesh(Vector3(0.05, 0.045, 0.38))
			bone.material_override = _mats["bone"]
			bone.position = Vector3(side * (2.5 + 0.08 * sin(float(index))), 0.04, float(z))
			bone.rotation = Vector3(0, 0.8 * sin(float(index) * 1.9), 0.08)
			_attach(parent, bone)
			index += 1
		z += BONE_STEP

func _build_chains(parent: Node) -> void:
	# 天花板垂下的铁链，会轻摆；增加“这里死过很多人”的暗示
	var index := 0
	var z := 55
	while z < int(Z_END) - 20:
		if absf(float(z) - ZONE_Z) > 8.0 and absf(float(z) - ENDING_Z) > 12.0:
			var side := -1.0 if index % 2 == 0 else 1.0
			var pivot := Node3D.new()
			pivot.name = "HangingChain_%d" % index
			pivot.position = Vector3(side * (HALF_W - 0.35), HEIGHT - 0.02, float(z))
			pivot.add_to_group("sway_pivot")
			_attach(parent, pivot)

			var chain := MeshInstance3D.new()
			chain.name = "Chain"
			chain.mesh = _box_mesh(Vector3(0.022, 2.8, 0.022))
			chain.material_override = _mats["iron"]
			chain.position = Vector3(0, -1.4, 0)
			_attach(pivot, chain)

			var hook := MeshInstance3D.new()
			hook.name = "Hook"
			var torus := TorusMesh.new()
			torus.inner_radius = 0.055
			torus.outer_radius = 0.085
			torus.rings = 12
			torus.ring_segments = 6
			hook.mesh = torus
			hook.material_override = _mats["iron"]
			hook.position = Vector3(0, -2.82, 0)
			_attach(pivot, hook)
			index += 1
		z += CHAIN_STEP

func _build_dust(parent: Node) -> void:
	# 冷灰尘埃：在旧灯附近能看出空气里的“灰”。2520 米用多组粒子覆盖几个区段。
	var mote := QuadMesh.new()
	mote.size = Vector2(0.03, 0.03)
	for center_z in [180.0, 760.0, 1260.0, 1760.0, 2340.0]:
		var dust := CPUParticles3D.new()
		dust.name = "ColdDust_%d" % int(center_z)
		dust.amount = 70
		dust.lifetime = 14.0
		dust.preprocess = 8.0
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(2.8, 1.9, 95.0)
		dust.direction = Vector3(0, 1, 0)
		dust.spread = 35.0
		dust.initial_velocity_min = 0.03
		dust.initial_velocity_max = 0.1
		dust.gravity = Vector3(0, -0.01, 0)
		dust.scale_amount_min = 0.4
		dust.scale_amount_max = 1.2
		dust.color = Color(0.74, 0.78, 0.8, 0.18)
		dust.mesh = mote
		dust.material_override = _mats["dust"]
		dust.position = Vector3(0, 2.1, center_z)
		_attach(parent, dust)

func _build_mist(parent: Node) -> void:
	# 贴地雾团：低透明度、大尺寸 billboard，慢慢向上/向前漂。
	var mist_quad := QuadMesh.new()
	mist_quad.size = Vector2(1.0, 1.0)
	for center_z in [180.0, 760.0, 1260.0, 1760.0, 2340.0]:
		var mist := CPUParticles3D.new()
		mist.name = "GroundMist_%d" % int(center_z)
		mist.amount = 46
		mist.lifetime = 22.0
		mist.preprocess = 10.0
		mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		mist.emission_box_extents = Vector3(2.7, 0.25, 80.0)
		mist.direction = Vector3(0, 0.4, 0.2)
		mist.spread = 55.0
		mist.initial_velocity_min = 0.015
		mist.initial_velocity_max = 0.08
		mist.gravity = Vector3(0, 0.008, 0)
		mist.scale_amount_min = 2.6
		mist.scale_amount_max = 5.2
		mist.color = Color(0.58, 0.86, 0.75, 0.55)
		mist.mesh = mist_quad
		mist.material_override = _mats["fog"]
		mist.position = Vector3(0, 0.35, center_z)
		_attach(parent, mist)

func _build_fog_sheets(parent: Node) -> void:
	# 缓慢漂移的“雾帘”：牌阵附近密一些，长走廊每 400 米左右补一层。
	var fog_material: Material = load("res://materials/fog_sheet.tres")
	var sheet_zs: Array[float] = []
	var z := 80.0
	while z < Z_END - 20.0:
		sheet_zs.append(z)
		z += 400.0
	for near in [ZONE_Z - 24.0, ZONE_Z - 12.0, ZONE_Z, ZONE_Z + 12.0, ZONE_Z + 24.0]:
		sheet_zs.append(near)
	sheet_zs.sort()
	var index := 0
	for sheet_z in sheet_zs:
		var sheet := MeshInstance3D.new()
		sheet.name = "FogSheet_%d" % index
		var quad := QuadMesh.new()
		quad.size = Vector2(5.6, 3.0)
		sheet.mesh = quad
		sheet.material_override = fog_material
		sheet.position = Vector3(0, 1.45, sheet_z)
		sheet.rotation = Vector3(0, 0.15 * sin(float(index) * 1.3), 0)
		sheet.add_to_group("fog_sheet")
		_attach(parent, sheet)
		index += 1

func _build_end_door(parent: Node) -> void:
	# 尽头“封印门”：冷青色符文 + 铁木门板，是 2520 米长廊的终点锚点。
	# 注意：它不是事件出口，真正的女巫牌阵在中段 z=34。
	var door_root := Node3D.new()
	door_root.name = "SealedEndDoor"
	_attach(parent, door_root)

	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	panel.mesh = _box_mesh(Vector3(5.2, 3.5, 0.25))
	panel.material_override = _mats["iron"]
	panel.position = Vector3(0, 1.75, Z_END - 0.35)
	_attach(door_root, panel)

	var frame_top := MeshInstance3D.new()
	frame_top.name = "RuneFrameTop"
	frame_top.mesh = _box_mesh(Vector3(4.7, 0.09, 0.06))
	frame_top.material_override = _mats["rune"]
	frame_top.position = Vector3(0, 3.25, Z_END - 0.49)
	_attach(door_root, frame_top)

	for i in [-1, 0, 1]:
		var strip := MeshInstance3D.new()
		strip.name = "RuneStrip_%d" % (i + 1)
		strip.mesh = _box_mesh(Vector3(0.09, 2.6, 0.06))
		strip.material_override = _mats["rune"]
		strip.position = Vector3(i * 1.55, 1.85, Z_END - 0.49)
		_attach(door_root, strip)

	var door_light := OmniLight3D.new()
	door_light.name = "DoorLight"
	door_light.light_color = Color(0.4, 0.9, 0.85, 1)
	door_light.light_energy = 1.0
	door_light.omni_range = 7.0
	door_light.omni_attenuation = 1.5
	door_light.position = Vector3(0, 2.2, Z_END - 1.0)
	door_light.add_to_group("flicker_light")
	_attach(door_root, door_light)

	_static_box(parent, "EndDoorCollision", Vector3(5.4, 3.6, 0.35),
		Vector3(0, 1.8, Z_END - 0.35))


# ============================================================================
# 氛围驱动 / 缓冲区 / 玩家 / HUD
# ============================================================================

func _build_atmosphere() -> void:
	var atmosphere := Node3D.new()
	atmosphere.name = "Atmosphere"
	atmosphere.set_script(load("res://scripts/corridor/atmosphere.gd"))
	_attach(_root, atmosphere)


func _build_buffer_zone() -> void:
	var scene: PackedScene = load("res://scenes/buffer_zone.tscn")
	if scene == null:
		push_error("[build_corridor] 找不到 buffer_zone.tscn")
		return
	var zone := scene.instantiate()
	zone.name = "BufferZone"
	zone.position = Vector3(0, 0, ZONE_Z)
	_attach(_root, zone)


func _build_ending_zone() -> void:
	# 长廊尽头（EndDoor 前）预留的“游戏结束文本”舞台，保持中央空旷
	var scene: PackedScene = load("res://scenes/ending_zone.tscn")
	if scene == null:
		push_error("[build_corridor] 找不到 ending_zone.tscn")
		return
	var zone := scene.instantiate()
	zone.name = "EndingZone"
	zone.position = Vector3(0, 0, ENDING_Z)
	_attach(_root, zone)


func _build_player() -> void:
	var scene: PackedScene = load("res://scenes/player.tscn")
	if scene == null:
		push_error("[build_corridor] 找不到 player.tscn")
		return
	var player := scene.instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0.02, PLAYER_Z)
	_attach(_root, player)


func _build_hud() -> void:
	var scene: PackedScene = load("res://ui/event_hud.tscn")
	if scene == null:
		push_error("[build_corridor] 找不到 event_hud.tscn")
		return
	var hud := scene.instantiate()
	hud.name = "HUD"
	_attach(_root, hud)


# ============================================================================
# 工具函数
# ============================================================================

## 把节点挂到场景里。owner 在整棵树挂进场景树之后统一设置
## （PackedScene.pack 只保存 owner 指向 Main 的节点；实例化子场景的内部节点保持自己的 owner）。
func _attach(parent: Node, child: Node, node_name: String = "") -> void:
	if not node_name.is_empty():
		child.name = node_name
	parent.add_child(child)
	_owned_nodes.append(child)
	_node_count += 1


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _quad_mesh(node_name: String, size: Vector2, material: Material,
		position: Vector3, rotation: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = quad
	instance.material_override = material
	instance.position = position
	instance.rotation = rotation
	return instance


## 生成一个 StaticBody3D + BoxShape3D 碰撞体（世界层 layer 1）。
func _static_box(parent: Node, node_name: String, size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	body.add_child(shape)
	_owned_nodes.append(shape)
	_attach(parent, body)
	return body


func _save_scene() -> void:
	var packed := PackedScene.new()
	var pack_error := packed.pack(_root)
	if pack_error != OK:
		push_error("[build_corridor] pack 失败: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUT_PATH)
	if save_error != OK:
		push_error("[build_corridor] 保存失败: %s" % error_string(save_error))
		return
	print("[build_corridor] OK · nodes=%d · saved=%s" % [_node_count, OUT_PATH])
