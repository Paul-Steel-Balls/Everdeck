shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Spark streak: a thin bright line, brighter than white so the glow picks it
// up, with a hot core along its length.
uniform float boost = 3.0;
void fragment() {
	float core = 1.0 - abs(UV.x - 0.5) * 2.0;
	float tip = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	ALBEDO = COLOR.rgb * boost * (0.4 + core * 0.8);
	ALPHA = COLOR.a * core * tip;
}
