shader_type canvas_item;
// Slowly churning dark smoke with an ember glow from below and a purple
// haze from above. Cheap value-noise fbm; runs full-screen behind menus.

uniform vec4 base_color : source_color = vec4(0.035, 0.012, 0.06, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.24, 0.08, 0.36, 1.0);
uniform vec4 ember_color : source_color = vec4(0.75, 0.24, 0.04, 1.0);
uniform float speed = 0.035;
uniform float ember_strength = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float aspect = 1.0 / max(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 0.0001);
	vec2 p = vec2(uv.x * 1.78, uv.y) * 2.4;
	float t = TIME * speed;
	float q = fbm(p + vec2(t, -t * 0.6));
	float r = fbm(p + 1.8 * q + vec2(-t * 0.8, t * 0.3));
	vec3 col = base_color.rgb;
	col = mix(col, smoke_color.rgb, smoothstep(0.35, 0.95, r) * (0.35 + 0.65 * (1.0 - uv.y)));
	float ember = smoothstep(0.45, 1.0, uv.y) * smoothstep(0.4, 0.85, r) * ember_strength;
	col += ember_color.rgb * ember;
	// Vignette.
	vec2 d = uv - vec2(0.5);
	col *= 1.0 - dot(d, d) * 1.1;
	COLOR = vec4(col, 1.0);
}
