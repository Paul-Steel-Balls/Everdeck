shader_type canvas_item;
// Soft glossy highlight for buttons: brightest at the top, fading down.
void fragment() {
	float a = (1.0 - UV.y) * 0.28;
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	COLOR = vec4(1.0, 1.0, 1.0, a * edge);
}
