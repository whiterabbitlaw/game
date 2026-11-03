shader_type canvas_item;
// 全屏闪白 + 径向模糊感
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.85, 1.0);

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 1.6;
	float a = amount * (0.55 + 0.45 * (1.0 - r));
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0));
}
