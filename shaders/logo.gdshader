shader_type canvas_item;
// Gold logo lettering: vertical gold gradient across the whole label (not
// per glyph) plus a bright shine band that sweeps across every few seconds.

uniform vec4 top_color : source_color = vec4(1.0, 0.95, 0.62, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.72, 0.16, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.80, 0.30, 0.03, 1.0);
uniform vec2 label_size = vec2(800.0, 160.0);
uniform float sweep_period = 4.5;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	vec2 p = local_pos / label_size;
	float y = clamp(p.y, 0.0, 1.0);
	vec3 g = y < 0.5 ? mix(top_color.rgb, mid_color.rgb, y * 2.0) : mix(mid_color.rgb, bottom_color.rgb, (y - 0.5) * 2.0);
	// Keep dark outline/shade pixels dark: only tint bright glyph pixels.
	float lum = dot(tex.rgb, vec3(0.333));
	vec3 col = mix(tex.rgb, g, smoothstep(0.35, 0.9, lum));
	float phase = fract(TIME / sweep_period) * 2.4 - 0.7;
	float band = 1.0 - smoothstep(0.0, 0.06, abs((p.x - phase) + (p.y - 0.5) * 0.35));
	col += vec3(1.0, 0.96, 0.8) * band * 0.85 * smoothstep(0.35, 0.9, lum);
	COLOR = vec4(col, tex.a);
}
