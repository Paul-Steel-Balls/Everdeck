shader_type spatial;
render_mode unshaded;

// The disc's glowing edge band: the near half (toward the camera, +Z)
// burns in the near hero's color, the far half in the far hero's, with a
// white-hot blend where the two meet (matching the floor's seam).

uniform vec4 near_col : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec4 far_col : source_color = vec4(0.1, 0.8, 0.78, 1.0);
uniform float energy = 1.0;

varying float z_local;

void vertex() {
	z_local = VERTEX.z;
}

void fragment() {
	float near = smoothstep(-0.25, 0.25, z_local);
	vec3 side = mix(far_col.rgb, near_col.rgb, near);
	float seam = 1.0 - smoothstep(0.0, 0.35, abs(z_local));
	ALBEDO = mix(side, vec3(1.0), seam * 0.45) * energy;
}
