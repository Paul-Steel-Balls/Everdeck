shader_type canvas_item;
// Diagonal screen wipe with a glowing gold edge. progress 0 = clear,
// 1 = fully covered. The covered side is deep night purple.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cover : source_color = vec4(0.04, 0.015, 0.07, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.72, 0.2, 1.0);

void fragment() {
	float d = UV.x * 0.8 + (1.0 - UV.y) * 0.2;
	float p = progress * 1.3 - 0.15;
	float covered = 1.0 - smoothstep(p - 0.01, p + 0.01, d);
	float glow = exp(-abs(d - p) * 40.0) * step(0.001, progress) * step(progress, 0.999);
	vec3 col = mix(cover.rgb, edge.rgb, glow * 0.9);
	COLOR = vec4(col, clamp(covered + glow, 0.0, 1.0));
}
