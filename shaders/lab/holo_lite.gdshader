shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// "Light" hologram for the 3D minion models: the model keeps its own
// painted colors and lighting, with only a soft rim of the class color,
// faint moving scanlines and a gentle flicker. The summon / death / glitch
// effects are the same as the full hologram (holo.gdshader).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool use_normal = false;
uniform bool use_orm = false;
uniform vec4 tint : source_color = vec4(0.65, 0.4, 1.0, 1.0);
uniform float rim_strength = 0.45;  // class-color rim light
uniform float scan_strength = 0.05; // how visible the scanlines are
uniform float flicker = 0.03;
uniform float brightness = 1.12;
uniform float self_light = 0.14;   // a little of the painted color glows, so models read in dark arenas
uniform float flash = 0.0;          // white hit flash
uniform float voxel = 0.075;        // cube size for digitize effects
uniform float build_y = 1000.0;     // summon: only voxels below this world height exist
uniform float dissolve = 0.0;       // death: cubes blink out
uniform float glitch = 0.0;         // 0..1 digital tearing before death

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (glitch > 0.0) {
		float row = floor(world_pos.y * 9.0);
		float j = hash(vec2(row, floor(TIME * 18.0))) - 0.5;
		VERTEX.x += j * glitch * 0.35 * step(0.55, hash(vec2(row * 3.1, floor(TIME * 9.0))));
	}
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * brightness;
	float scan = 1.0 - scan_strength + scan_strength * sin(world_pos.y * 90.0 - TIME * 6.0);
	float flick = 1.0 - flicker + flicker * hash(vec2(floor(TIME * 24.0), 1.0));
	ALBEDO = mix(base * scan * flick, vec3(1.0), flash);
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		AO = orm.r;
		ROUGHNESS = clamp(orm.g, 0.35, 1.0);
		METALLIC = orm.b * 0.6;
	} else {
		ROUGHNESS = 0.7;
	}
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	vec3 emit = tint.rgb * rim * rim_strength;
	// Voxel space: summon builds the figure bottom-up in cubes, death
	// blinks random cubes out (same as the full hologram).
	vec3 cell = floor(world_pos / voxel);
	float n = hash3(cell);
	float layer_y = (cell.y + 0.5) * voxel;
	if (layer_y > build_y) { discard; }
	float build_edge = 1.0 - smoothstep(0.0, voxel * 2.5, build_y - layer_y);
	emit += tint.rgb * build_edge * 2.2 * step(build_y, 999.0);
	if (n < dissolve) { discard; }
	float edge = 1.0 - smoothstep(0.0, 0.12, n - dissolve);
	emit += mix(tint.rgb, vec3(1.0), 0.5) * edge * 2.0 * step(0.001, dissolve);
	vec3 f = abs(fract(world_pos / voxel) - 0.5);
	float grid = step(0.42, max(max(f.x, f.y), f.z));
	emit += tint.rgb * grid * 0.8 * clamp(dissolve * 3.0 + build_edge + glitch, 0.0, 1.0);
	emit += vec3(0.25, 0.6, 0.8) * glitch * 0.4;
	EMISSION = emit + ALBEDO * self_light + vec3(1.0) * flash * 0.6;
}
