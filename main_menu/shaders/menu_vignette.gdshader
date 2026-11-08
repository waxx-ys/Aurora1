shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.05;
uniform float grain_amount : hint_range(0.0, 0.15) = 0.035;
uniform float warm_tint : hint_range(0.0, 1.0) = 0.10;

void fragment() {
	vec4 scene = texture(screen_texture, SCREEN_UV);
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p * vec2(1.0, 0.82));
	float v = smoothstep(0.30, 1.15, d) * vignette_strength;
	vec3 c = scene.rgb;
	c *= mix(vec3(1.0), vec3(1.06, 0.92, 0.78), warm_tint);
	c *= (1.0 - clamp(v, 0.0, 0.92));
	float g = fract(sin(dot(UV * vec2(127.1, 311.7) + TIME * 0.35, vec2(12.9898, 78.233))) * 43758.5453);
	c += (g - 0.5) * grain_amount;
	COLOR = vec4(c, 1.0);
}
