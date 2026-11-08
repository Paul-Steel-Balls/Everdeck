shader_type spatial;
// Night ocean under the High Seas arena: rolling swell with moonlit crests.
uniform vec3 deep = vec3(0.02, 0.16, 0.22);
uniform vec3 crest = vec3(0.5, 0.9, 0.95);

varying float h;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	h = sin(w.x * 0.35 + TIME * 0.9) * 0.35 + sin(w.z * 0.5 - TIME * 1.3) * 0.25 + sin((w.x + w.z) * 0.9 + TIME * 1.7) * 0.1;
	VERTEX.y += h;
}

void fragment() {
	float foam = smoothstep(0.35, 0.65, h);
	ALBEDO = mix(deep, crest, foam * 0.5);
	ROUGHNESS = 0.15;
	METALLIC = 0.3;
	EMISSION = deep * 0.35 + crest * foam * 0.35;
}
