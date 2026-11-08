shader_type spatial;
render_mode unshaded;
// Projection-table surface: dark glass with a glowing grid and soft
// pulse rings radiating from the center.
uniform vec4 base_col : source_color = vec4(0.03, 0.01, 0.07, 1.0);
uniform vec4 line_col : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform vec4 near_col : source_color = vec4(0.25, 0.55, 1.0, 1.0); // my half
uniform vec4 far_col : source_color = vec4(1.0, 0.3, 0.35, 1.0);  // enemy half
uniform float halves = 0.0; // 1 = tint each half in its side's color
uniform vec2 size = vec2(10.0, 7.0);
uniform float cell = 0.5;

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) / fwidth(p / cell);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float r = length(p);
	float ring = 0.0;  // ripple rings removed (Ian: no rippling)
	float fade = 1.0 - smoothstep(size.x * 0.3, size.x * 0.62, r);
	vec3 lc = line_col.rgb;
	vec3 half_col = p.y > 0.0 ? near_col.rgb : far_col.rgb;
	lc = mix(lc, half_col, halves);
	vec3 col = base_col.rgb + lc * (line * 0.55 * fade + ring * 0.12 * fade);
	col += half_col * halves * 0.06 * fade;
	// Center divider glow.
	col += line_col.rgb * smoothstep(0.06, 0.0, abs(p.y)) * 0.8;
	ALBEDO = col;
}
