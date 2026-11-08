shader_type canvas_item;
// Hero showcase portrait: fades into the background on the left, top and
// bottom so the painting melts into the scene instead of sitting in a box.
// A rim of class-colored light flickers along the edge.

uniform float fade_left = 0.38;
uniform float fade_bottom = 0.22;
uniform float fade_top = 0.06;
uniform vec4 rim_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = smoothstep(0.0, fade_left, UV.x);
	a *= smoothstep(1.0, 1.0 - fade_bottom, UV.y);
	a *= smoothstep(0.0, fade_top, UV.y);
	float rim = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.12, fade_left, UV.x));
	float flicker = 0.75 + 0.25 * sin(TIME * 7.0 + UV.y * 20.0);
	c.rgb += rim_color.rgb * rim * 0.18 * flicker;
	COLOR = vec4(c.rgb, c.a * a * COLOR.a);
}
