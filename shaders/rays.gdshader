shader_type canvas_item;
// 放射光芒：用于突破爆发、打坐光环
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float intensity = 1.0;
uniform float rays = 14.0;
uniform float spin = 0.0;
uniform float core_size = 8.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x) + spin;
	float ray = 0.5 + 0.5 * sin(a * rays);
	ray = pow(ray, 3.0);
	float fall = smoothstep(1.0, 0.05, r);
	float core = exp(-r * r * core_size);
	float v = (ray * fall * 0.85 + core) * intensity;
	COLOR = vec4(color.rgb, clamp(v, 0.0, 1.0) * color.a);
}
