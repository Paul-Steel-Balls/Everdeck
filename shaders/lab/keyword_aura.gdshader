shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Mechanics pass, wave 1: one see-through shell around a Crew model for
// the keyword states that change how it plays:
//   Stunt Double: a bright gold bubble (the first hit pops it)
//   Stage Fright: a pale ice block, frosty at the base
//   Backstage: a deep velvet-curtain haze
// Edges glow (fresnel), the middle stays clear so the model reads.
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float base_alpha = 0.06;
uniform float rim_alpha = 0.75;
uniform float rim_power = 2.2;
uniform float frost = 0.0;      // >0: frosty bottom (ice)
uniform float shimmer = 0.6;    // slow moving bands

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	float band = 0.5 + 0.5 * sin(UV.y * 18.0 - TIME * 1.6 + UV.x * 6.2831);
	float a = base_alpha + fres * rim_alpha + band * 0.05 * shimmer;
	float bottom = smoothstep(0.55, 1.0, UV.y);
	a += bottom * frost * 0.45;
	ALBEDO = mix(col.rgb, vec3(1.0), clamp(fres * 0.5 + bottom * frost * 0.4, 0.0, 0.7));
	ALPHA = clamp(a, 0.0, 0.9);
}
