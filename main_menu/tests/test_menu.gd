extends Node
## 主界面独立验收：模型/相机/提灯/音乐循环/全屏点击接口。
var _checks := 0
var _fails := 0
func _ready() -> void:
	await get_tree().process_frame
	var menu: Node3D = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.5).timeout
	_check(menu.get_node_or_null("Helltown") != null, "3D 鬼屋模型已加载")
	var mesh: Mesh = menu.get_node("Helltown").mesh
	_check(mesh != null and mesh.get_surface_count() > 10, "模型材质面已导入")
	_check(menu.get_node_or_null("Camera3D").current, "相机已启用")
	_check(menu.get_node_or_null("ForegroundLantern") != null, "左前景提灯已生成")
	var music: AudioStreamPlayer = menu.get_node("Music")
	_check(music.stream is AudioStreamWAV, "音乐是 WAV")
	_check(music.playing, "音乐正在播放")
	if music.stream is AudioStreamWAV:
		_check((music.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "音乐循环模式已开启")
	var catcher: Control = menu.get_node("UI/Root/ClickCatcher")
	_check(catcher.mouse_filter == Control.MOUSE_FILTER_STOP, "全屏点击层拦截鼠标")
	var labels: Array = menu.get_node("UI/Root").find_children("*", "Label", true, false)
	_check(labels.size() == 3, "标题是 3 个字，没有额外阴影副本")
	_check(String(menu.get("title_text")) == "幽魂廊", "标题为《幽魂廊》")
	_check(_labels_text(labels) == "幽魂廊", "标题三字完整")
	var title_font := (labels[0] as Label).get_theme_font("font")
	_check(title_font != null and title_font.resource_path.contains("hakidame"), "标题使用最初版 hakidame 字体")
	_check(menu.get_node_or_null("UI/Root/TitleRoot/GhostWrap") == null, "已删除幽灵阴影层")
	var title_root: Control = menu.get_node("UI/Root/TitleRoot")
	_check(title_root.anchor_left == 1.0 and (title_root.global_position.x + title_root.size.x * 0.5) > 640.0, "标题位于画面右上角")
	var main_wrap: Control = menu.get_node("UI/Root/TitleRoot/MainWrap")
	var sway_before := main_wrap.position
	await get_tree().create_timer(0.3).timeout
	_check(main_wrap.position != sway_before, "标题仍有轻微摇晃")
	menu.call("set_title", "测试名字")
	_check(String(menu.get("title_text")) == "测试名字", "set_title 可以替换标题")
	menu.call("set_title", "幽魂廊")
	var fired := [false]
	menu.start_requested.connect(func() -> void: fired[0] = true)
	menu.call("_start_game")
	await get_tree().process_frame
	_check(fired[0], "点击/开始会发出 start_requested 信号")
	_check(String(menu.get("game_scene_path")) == "", "默认没有接入游戏本体")
	print("=== result: %d checks, %d failed ===" % [_checks, _fails])
	print("TEST_RESULT_PASS" if _fails == 0 else "TEST_RESULT_FAIL")
	get_tree().quit(0 if _fails == 0 else 1)
func _labels_text(labels: Array) -> String:
	var out := ""
	for label in labels:
		out += (label as Label).text
	return out


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok: print("  PASS ✓ ", label)
	else:
		_fails += 1; print("  FAIL ✗ ", label)
