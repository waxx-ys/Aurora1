shader_type canvas_item;
// ============================================================================
// eerie_vignette.gdshader · 阴森氛围的屏幕暗角 + 细微噪点
// ----------------------------------------------------------------------------
// 铺在 HUD 最底层（3D 之上、所有文字之下），不会阻挡输入。
// uniform 暴露给 event_hud.gd：
//   vignette_strength  暗角强度（0~1），仪式时可临时拉高
//   vignette_softness  暗角过渡宽度
//   grain_strength     胶片噪点强度（0~0.2）
//   tint_color         暗角颜色（默认偏冷的墨绿黑）
// ============================================================================

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.62;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.5;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.035;
uniform vec4 tint_color : source_color = vec4(0.015, 0.035, 0.028, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.5));
	float vig = smoothstep(0.5 - vignette_softness * 0.5, 0.8, dist) * vignette_strength;
	float grain = (hash12(uv * vec2(1920.0, 1080.0) + floor(TIME * 24.0)) - 0.5) * grain_strength;
	float alpha = clamp(vig + grain, 0.0, 0.92);
	COLOR = vec4(tint_color.rgb, alpha);
}
