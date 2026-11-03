shader_type canvas_item;
// 冲天光柱
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float intensity = 1.0;
uniform float width = 5.0;

void fragment() {
	float x = (UV.x - 0.5) * width;
	float side = exp(-x * x * 3.0);
	float vert = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	float flicker = 0.85 + 0.15 * sin(TIME * 18.0 + UV.y * 24.0);
	COLOR = vec4(color.rgb, clamp(side * vert * flicker * intensity, 0.0, 1.0) * color.a);
}
