class_name EventHUD
extends CanvasLayer
## ============================================================================
## EventHUD · 长廊事件的全部界面与文字叙事
## ----------------------------------------------------------------------------
## 这个脚本只负责“演”：淡入淡出、打字机叙事、倒计时、提示横幅。
## 什么时候演由 main.gd 的事件状态机决定，这里不做任何游戏逻辑判断。
##
## 文案为什么放在 main.gd 而不是这里：
##   叙事内容属于“关卡设计”，维护时经常改；界面布局属于“皮肤”，很少改。
##   分开后，改文案不用碰 UI 脚本。
##
## 常用 API（main.gd 调用）：
##   await hud.fade_from_black(1.2)
##   await hud.play_narration("回廊", lines)     # 打字机，E 键可加速/翻页
##   var ok := await hud.run_countdown(3)        # 3→2→1，Esc 取消，E 立即开始
##   hud.show_connecting("正在唤醒《记忆翻牌》…")
##   await hud.fade_to_black(0.6)
##   hud.show_return_banner("女巫的赐福", "……", 4.0, "positive")
##   hud.show_trial_mark(true, "正面刻印 · 疾行 45s", 45.0)
##   hud.play_ritual_pulse(1.2)                  # 入场时紫色雾光脉冲
##   hud.show_toast("……")
## ============================================================================

## 试炼结果横幅/刻印条用的绿色（赐福）与红色（诅咒）样式
const STYLE_TRIAL_SUCCESS: StyleBoxFlat = preload("res://ui/return_success.tres")
const STYLE_TRIAL_FAILURE: StyleBoxFlat = preload("res://ui/return_failure.tres")

@onready var root: Control = $Root
@onready var fade_rect: ColorRect = $Root/FadeRect
@onready var vignette: ColorRect = $Root/Vignette
@onready var ritual_pulse: ColorRect = $Root/RitualPulse
@onready var trial_mark: PanelContainer = $Root/TrialMark
@onready var trial_mark_label: Label = $Root/TrialMark/TrialMarkLabel
@onready var title_label: Label = $Root/TopLeft/Title
@onready var subtitle_label: Label = $Root/TopLeft/Subtitle
@onready var objective_label: Label = $Root/TopLeft/Objective
@onready var session_label: Label = $Root/SessionPanel/SessionLabel
@onready var debug_panel: PanelContainer = $Root/DebugPanel
@onready var debug_label: Label = $Root/DebugPanel/DebugLabel
@onready var zone_badge: PanelContainer = $Root/ZoneBadge
@onready var zone_badge_text: Label = $Root/ZoneBadge/BadgeText
@onready var countdown_label: Label = $Root/Countdown
@onready var connecting_panel: PanelContainer = $Root/ConnectingPanel
@onready var connecting_title: Label = $Root/ConnectingPanel/VBox/ConnectingTitle
@onready var connecting_status: Label = $Root/ConnectingPanel/VBox/ConnectingStatus
@onready var connecting_hint: Label = $Root/ConnectingPanel/VBox/ConnectingHint
@onready var narration_panel: PanelContainer = $Root/NarrationPanel
@onready var speaker_label: Label = $Root/NarrationPanel/VBox/Header/Speaker
@onready var page_label: Label = $Root/NarrationPanel/VBox/Header/PageLabel
@onready var narration_text: RichTextLabel = $Root/NarrationPanel/VBox/NarrationText
@onready var narration_hint: Label = $Root/NarrationPanel/VBox/Hint
@onready var return_banner: PanelContainer = $Root/ReturnBanner
@onready var return_title: Label = $Root/ReturnBanner/VBox/ReturnTitle
@onready var return_subtitle: Label = $Root/ReturnBanner/VBox/ReturnSubtitle
@onready var ending_panel: PanelContainer = $Root/EndingPanel
@onready var ending_kicker: Label = $Root/EndingPanel/VBox/EndingKicker
@onready var ending_title: Label = $Root/EndingPanel/VBox/EndingTitle
@onready var ending_body: Label = $Root/EndingPanel/VBox/EndingBody
@onready var ending_hint: Label = $Root/EndingPanel/VBox/EndingHint
@onready var toast_panel: PanelContainer = $Root/ToastPanel
@onready var toast_label: Label = $Root/ToastPanel/Toast
@onready var controls_label: Label = $Root/Controls

## 打字机速度（字/秒）
@export var typewriter_speed: float = 42.0
## 每段文字打完后的停留秒数
@export var line_hold_seconds: float = 1.35

var _narration_generation: int = 0
var _advance_requested: bool = false
var _countdown_generation: int = 0
var _countdown_cancelled: bool = false
var _countdown_skip: bool = false
var _debug_visible: bool = false
var _toast_generation: int = 0
var _trial_mark_generation: int = 0
var _ending_generation: int = 0
var _neutral_return_style: StyleBoxFlat = null


func _ready() -> void:
	# 初始全黑，main.gd 在开场调用 fade_from_black() 让画面亮起。
	fade_rect.color = Color(0, 0, 0, 1)
	narration_panel.visible = false
	connecting_panel.visible = false
	return_banner.visible = false
	toast_panel.visible = false
	zone_badge.visible = false
	countdown_label.visible = false
	debug_panel.visible = false
	trial_mark.visible = false
	ending_panel.visible = false
	ritual_pulse.color.a = 0.0
	_neutral_return_style = return_banner.get_theme_stylebox("panel") as StyleBoxFlat
	title_label.text = "记忆回廊"
	subtitle_label.text = "MEMORY CORRIDOR · 雾中牌阵"
	objective_label.text = "雾贴着火把爬上来。长廊深处，有牌面翻动的声音。\n沿着长廊走下去，直到雾把你带到牌阵前。"
	controls_label.text = "WASD 移动   ·   鼠标 视角   ·   Shift 疾跑   ·   Space 跳跃   ·   V 切换镜头   ·   Esc 释放鼠标   ·   F3 调试"
	session_label.text = "前段 · 雾中长廊"


# ============================================================================
# 淡入淡出
# ============================================================================

## 画面淡到全黑（用于进入另一款游戏前）。
func fade_to_black(duration: float = 0.8) -> void:
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, duration)
	await tween.finished


## 从全黑恢复（开场 / 从试炼归来）。
func fade_from_black(duration: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 0.0, duration)
	await tween.finished


func set_fade_alpha(alpha: float) -> void:
	fade_rect.color.a = clampf(alpha, 0.0, 1.0)


# ============================================================================
# 阴森仪式效果
# ============================================================================

## 踏入牌阵时的“雾光脉冲”：紫色半透明罩层 + 暗角短暂加重。
## main.gd 在叙事前 await 它，让触发不要那么突兀。
func play_ritual_pulse(duration: float = 1.2) -> void:
	ritual_pulse.color.a = 0.0
	var pulse_tween := create_tween()
	pulse_tween.tween_property(ritual_pulse, "color:a", 0.22, duration * 0.35)
	pulse_tween.tween_property(ritual_pulse, "color:a", 0.0, duration * 0.65)
	_set_vignette_strength(0.82)
	var vignette_tween := create_tween()
	vignette_tween.tween_method(_set_vignette_strength, 0.82, 0.62, duration)
	await pulse_tween.finished


func _set_vignette_strength(value: float) -> void:
	var material := vignette.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("vignette_strength", value)


# ============================================================================
# 文字叙事（打字机）
# ============================================================================

## 播放一组叙事文字。调用方 await 它会等全部段落播完。
## 玩家按 E 会立即打完当前行并翻到下一段（request_advance）。
## 玩家按 Esc 时调用 cancel_narration()，协程会提前返回。
func play_narration(speaker: String, lines: PackedStringArray) -> void:
	_narration_generation += 1
	var generation := _narration_generation
	_advance_requested = false
	speaker_label.text = speaker
	if speaker.contains("女巫"):
		speaker_label.add_theme_color_override("font_color", Color(0.78, 0.66, 1, 1))
	else:
		speaker_label.add_theme_color_override("font_color", Color(0.72, 0.62, 1, 1))
	narration_panel.visible = true
	narration_hint.text = "E 继续   ·   Esc 暂不进入"
	for index in lines.size():
		if generation != _narration_generation:
			return
		page_label.text = "%d / %d" % [index + 1, lines.size()]
		await _type_line(lines[index], generation)
		if generation != _narration_generation:
			return
		var keep_going := await _hold_or_advance(line_hold_seconds, generation)
		if not keep_going:
			return
	narration_panel.visible = false


## 跳过当前打字动画/提前翻页（E 键）。
func request_advance() -> void:
	_advance_requested = true


## 取消叙事（Esc / 玩家离开）。返回后 main.gd 负责恢复输入。
func cancel_narration() -> void:
	_narration_generation += 1
	_advance_requested = false
	narration_panel.visible = false


func is_narration_visible() -> bool:
	return narration_panel.visible


func _type_line(text: String, generation: int) -> void:
	narration_text.text = text
	narration_text.visible_characters = 0
	var total := narration_text.get_total_character_count()
	var shown := 0.0
	while shown < float(total):
		if generation != _narration_generation:
			return
		if _advance_requested:
			_advance_requested = false
			narration_text.visible_characters = -1
			return
		shown += typewriter_speed * get_process_delta_time()
		narration_text.visible_characters = int(shown)
		await get_tree().process_frame
	narration_text.visible_characters = -1


func _hold_or_advance(seconds: float, generation: int) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		if generation != _narration_generation:
			return false
		if _advance_requested:
			_advance_requested = false
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return true


# ============================================================================
# 倒计时
# ============================================================================

## 显示 3 → 2 → 1，然后自动结束。
## 返回 true = 正常结束（进入试炼）；false = 被 Esc 取消。
## 期间按 E 会立即结束倒计时（skip_countdown）。
func run_countdown(seconds: int = 3) -> bool:
	_countdown_generation += 1
	var generation := _countdown_generation
	_countdown_cancelled = false
	_countdown_skip = false
	countdown_label.visible = true
	narration_panel.visible = false
	for value in range(seconds, 0, -1):
		if generation != _countdown_generation:
			countdown_label.visible = false
			return false
		countdown_label.text = str(value)
		countdown_label.modulate = Color(1, 1, 1, 1)
		var elapsed := 0.0
		while elapsed < 0.78:
			if generation != _countdown_generation:
				countdown_label.visible = false
				return false
			if _countdown_skip:
				break
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		if _countdown_skip:
			break
	if not _countdown_cancelled and generation == _countdown_generation:
		countdown_label.text = "牌阵开启"
		var hold := 0.0
		while hold < 0.32:
			if generation != _countdown_generation:
				countdown_label.visible = false
				return false
			await get_tree().process_frame
			hold += get_process_delta_time()
	countdown_label.visible = false
	return not _countdown_cancelled


## 取消倒计时（Esc）。
func cancel_countdown() -> void:
	_countdown_cancelled = true
	_countdown_generation += 1
	countdown_label.visible = false


## 立即完成倒计时（E）。
func skip_countdown() -> void:
	_countdown_skip = true


func is_countdown_visible() -> bool:
	return countdown_label.visible


# ============================================================================
# 连接 / 返回 / 提示
# ============================================================================

## 显示“正在唤醒《记忆翻牌》”面板。
func show_connecting(status: String = "正在把你的影子押上牌桌……") -> void:
	connecting_panel.visible = true
	connecting_title.text = "牌阵正在开启"
	connecting_status.text = status
	connecting_hint.text = "雾会替你记住这一步   ·   首次唤醒需要数秒"


func set_connecting_status(status: String) -> void:
	connecting_status.text = status


func hide_connecting() -> void:
	connecting_panel.visible = false


## 从试炼归来时显示的判词横幅，会自己消失；不必 await。
## polarity: "positive"（赐福/绿色）/ "negative"（诅咒/红色）/ "neutral"（中性）
func show_return_banner(title: String, subtitle: String, duration: float = 3.0,
		polarity: String = "neutral") -> void:
	match polarity:
		"positive":
			return_banner.add_theme_stylebox_override("panel", STYLE_TRIAL_SUCCESS)
			return_title.add_theme_color_override("font_color", Color(0.62, 1, 0.72, 1))
			return_subtitle.add_theme_color_override("font_color", Color(0.72, 0.94, 0.76, 1))
		"negative":
			return_banner.add_theme_stylebox_override("panel", STYLE_TRIAL_FAILURE)
			return_title.add_theme_color_override("font_color", Color(1, 0.64, 0.58, 1))
			return_subtitle.add_theme_color_override("font_color", Color(0.94, 0.74, 0.7, 1))
		_:
			if _neutral_return_style != null:
				return_banner.add_theme_stylebox_override("panel", _neutral_return_style)
			return_title.add_theme_color_override("font_color", Color(0.9, 0.86, 0.7, 1))
			return_subtitle.add_theme_color_override("font_color", Color(0.8, 0.84, 0.76, 1))
	return_title.text = title
	return_subtitle.text = subtitle
	return_banner.visible = true
	return_banner.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(return_banner, "modulate:a", 1.0, 0.35)
	await get_tree().create_timer(duration).timeout
	var fade_out := create_tween()
	fade_out.tween_property(return_banner, "modulate:a", 0.0, 0.45)
	await fade_out.finished
	return_banner.visible = false


## 屏幕上方常驻的“刻印”状态：成功=绿色，失败=红色；duration 秒后自动隐藏。
## 与 player_controller 的实际 buff 计时保持一致（main.gd 传 45 秒）。
func show_trial_mark(positive: bool, text: String, duration: float = 45.0) -> void:
	_trial_mark_generation += 1
	var generation := _trial_mark_generation
	trial_mark.add_theme_stylebox_override(
		"panel", STYLE_TRIAL_SUCCESS if positive else STYLE_TRIAL_FAILURE
	)
	trial_mark_label.add_theme_color_override(
		"font_color", Color(0.62, 1, 0.72, 1) if positive else Color(1, 0.64, 0.58, 1)
	)
	trial_mark_label.text = text
	trial_mark.visible = true
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if generation == _trial_mark_generation:
			trial_mark.visible = false


func hide_trial_mark() -> void:
	_trial_mark_generation += 1
	trial_mark.visible = false


func is_trial_mark_visible() -> bool:
	return trial_mark.visible


## 长廊尽头的结局文本面板（进入 EndingZone 时调用）。
func show_ending(title: String, body: String, hint: String = "离开此区域关闭 · 此处为游戏结束文本 / 制作名单预留空间") -> void:
	_ending_generation += 1
	ending_title.text = title
	ending_body.text = body
	ending_hint.text = hint
	ending_panel.visible = true
	ending_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(ending_panel, "modulate:a", 1.0, 0.35)


func hide_ending() -> void:
	_ending_generation += 1
	var generation := _ending_generation
	if not ending_panel.visible:
		return
	var tween := create_tween()
	tween.tween_property(ending_panel, "modulate:a", 0.0, 0.3)
	await tween.finished
	if generation == _ending_generation:
		ending_panel.visible = false


func is_ending_visible() -> bool:
	return ending_panel.visible


## 立即隐藏底部短提示（进入正式事件流程时避免和倒计时/叙事叠字）。
func hide_toast() -> void:
	_toast_generation += 1
	toast_panel.visible = false


## 底部短提示（连不上、正在连接等）。
func show_toast(text: String, duration: float = 2.6) -> void:
	_toast_generation += 1
	var generation := _toast_generation
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	await get_tree().create_timer(duration).timeout
	if generation != _toast_generation:
		return
	var fade_out := create_tween()
	fade_out.tween_property(toast_panel, "modulate:a", 0.0, 0.3)
	await fade_out.finished
	if generation == _toast_generation:
		toast_panel.visible = false


## 旧版缓冲区徽标接口：默认不显示（触发区不标示，走进去自动开始）。
func show_zone_badge(visible: bool, text: String = "⟡  女巫的牌阵 · 雾正在聚拢  ⟡") -> void:
	zone_badge_text.text = text
	zone_badge.visible = visible


# ============================================================================
# 调试
# ============================================================================

func toggle_debug() -> void:
	_debug_visible = not _debug_visible
	debug_panel.visible = _debug_visible


func is_debug_visible() -> bool:
	return _debug_visible


func set_debug_text(text: String) -> void:
	debug_label.text = text


func set_session_text(text: String) -> void:
	session_label.text = text
