shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// A Bouncer's guard: a low ring-wall of ice-blue hexagon light around the
// model's feet, brightest at the base, fading upward, with a slow sweep
// so the eye catches it from across the table.
uniform vec4 col : source_color = vec4(0.42, 0.72, 1.0, 1.0);
uniform float strength = 1.0;

float hexgrid(vec2 p) {
	p *= vec2(1.0, 1.1547);
	vec2 a = mod(p, vec2(1.0, 1.732)) - vec2(0.5, 0.866);
	vec2 b = mod(p - vec2(0.5, 0.866), vec2(1.0, 1.732)) - vec2(0.5, 0.866);
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	float d = max(q.x * 0.866 + q.y * 0.5, q.y);
	return smoothstep(0.38, 0.47, d);
}

void fragment() {
	float h = 1.0 - UV.y;                 // 0 at the bottom edge, 1 at top
	float fade = pow(1.0 - h, 1.2);
	float hex = hexgrid(vec2(UV.x * 26.0, h * 4.0 - TIME * 0.35));
	float sweep = smoothstep(0.92, 1.0, sin(UV.x * 6.2831 - TIME * 2.2) * 0.5 + 0.5);
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	float base_line = smoothstep(0.16, 0.0, h);
	float v = (hex * 0.8 + 0.75 + sweep * 1.0) * fade * pulse + base_line * 1.5;
	// Mixed, not added, so it holds its amber on bright floors.
	ALBEDO = mix(col.rgb, vec3(0.92, 0.97, 1.0), clamp(v - 0.8, 0.0, 0.6));
	ALPHA = clamp(v * 1.15 * strength, 0.0, 0.95);
}
