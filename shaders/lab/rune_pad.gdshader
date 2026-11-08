shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Summoning circle under a unit: two rings with rotating tick marks.
uniform vec4 col : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float intensity = 1.0;

float ring(float r, float at, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fwidth(r) * 1.5, abs(r - at));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float v = ring(r, 0.92, 0.05) + ring(r, 0.72, 0.03) * 0.8;
	float ticks = step(0.75, fract((a + TIME * 0.4) / 6.2831 * 24.0)) * step(0.76, r) * step(r, 0.88);
	v += ticks * 0.7;
	v += (1.0 - smoothstep(0.0, 0.7, r)) * 0.12;
	ALBEDO = col.rgb * v * 2.0 * intensity;
	ALPHA = clamp(v, 0.0, 1.0);
}
