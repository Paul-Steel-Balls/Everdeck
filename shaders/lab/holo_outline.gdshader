shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
// A thin dark ink line around the 3D Crew models (inverted hull, constant
// width in screen pixels), so they read against bright arena floors. Runs
// as the next pass of holo_lite and follows its summon / death / glitch
// effects, so the outline builds and breaks up with the model.

uniform vec4 line_color : source_color = vec4(0.04, 0.03, 0.07, 1.0);
uniform float width_px = 1.25;  // at 720p; scales with the screen height
uniform float voxel = 0.075;
uniform float build_y = 1000.0;
uniform float dissolve = 0.0;
uniform float glitch = 0.0;
uniform float flash = 0.0;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = VERTEX;
	if (glitch > 0.0) {
		float row = floor(world_pos.y * 9.0);
		float j = hash(vec2(row, floor(TIME * 18.0))) - 0.5;
		v.x += j * glitch * 0.35 * step(0.55, hash(vec2(row * 3.1, floor(TIME * 9.0))));
	}
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(v, 1.0));
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	float l = length(dir);
	if (l > 1e-5) {
		clip.xy += dir / l * (width_px * VIEWPORT_SIZE.y / 720.0) * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 cell = floor(world_pos / voxel);
	if ((cell.y + 0.5) * voxel > build_y) { discard; }
	if (hash3(cell) < dissolve) { discard; }
	if (glitch > 0.6) { discard; }
	ALBEDO = mix(line_color.rgb, vec3(1.0), flash);
}
