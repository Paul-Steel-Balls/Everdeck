shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Soft contact shadow under a model: a dark radial pool that grounds it
// on the floor (real shadows from 30k-triangle models are too costly).
uniform float strength = 0.55;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.25, 1.0, r)) * strength;
	ALBEDO = vec3(0.02, 0.01, 0.03);
	ALPHA = a;
}
