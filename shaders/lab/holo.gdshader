shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;
// Hologram: tinted, scanlined, flickering, rim-lit. Works on textured
// quads (card art) and on untextured meshes (figurines). `dissolve`
// 0..1 eats the hologram away with a bright edge (summon / death).

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool use_tex = false;
uniform vec4 tint : source_color = vec4(0.65, 0.4, 1.0, 1.0);
uniform float strength = 1.0;
uniform float tex_color_mix = 0.75; // 1 = full painting colors, 0 = mono tint
uniform float dissolve = 0.0;
uniform float oval_mask = 0.0; // 1 = fade to an oval (busts)
uniform float flash = 0.0;     // white hit flash
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0); // crop of the texture
uniform float voxel = 0.075;        // cube size for digitize effects
uniform float build_y = 1000.0;     // summon: only voxels below this world height exist
uniform float glitch = 0.0;         // 0..1 digital tearing before death

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Glitch: slices of the hologram jump sideways.
	if (glitch > 0.0) {
		float row = floor(world_pos.y * 9.0);
		float j = hash(vec2(row, floor(TIME * 18.0))) - 0.5;
		VERTEX.x += j * glitch * 0.35 * step(0.55, hash(vec2(row * 3.1, floor(TIME * 9.0))));
	}
}

void fragment() {
	vec3 base = tint.rgb * 0.55;
	float a = 0.78;
	if (use_tex) {
		vec2 uv = uv_rect.xy + UV * uv_rect.zw;
		vec4 t = texture(tex, uv);
		float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		base = mix(tint.rgb * (0.35 + lum * 1.4), t.rgb * 1.1, tex_color_mix);
		a = t.a * 0.92;
	}
	// Rim glow: from the view angle on meshes, from the edges on quads.
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	if (use_tex) {
		vec2 d = abs(UV - 0.5) * 2.0;
		rim = max(rim * 0.3, pow(max(d.x, d.y), 6.0));
	}
	float scan = 0.82 + 0.18 * sin(world_pos.y * 90.0 - TIME * 6.0);
	float band = smoothstep(0.0, 0.04, abs(fract(world_pos.y * 0.9 - TIME * 0.45) - 0.5)) * 0.25 + 0.75;
	float flick = 0.92 + 0.08 * hash(vec2(floor(TIME * 24.0), 1.0));
	vec3 col = base * scan * band * flick + tint.rgb * rim * 0.9;
	col = mix(col, vec3(1.0), flash);
	if (oval_mask > 0.0) {
		vec2 o = (UV - vec2(0.5, 0.45)) / vec2(0.5, 0.55);
		a *= 1.0 - smoothstep(0.75, 1.0, length(o)) * oval_mask;
	}
	// Voxel space: everything below happens in whole cubes.
	vec3 cell = floor(world_pos / voxel);
	float n = hash3(cell);
	// Summon: the figure is built bottom-up, one layer of cubes at a time.
	float layer_y = (cell.y + 0.5) * voxel;
	if (layer_y > build_y) { discard; }
	float build_edge = 1.0 - smoothstep(0.0, voxel * 2.5, build_y - layer_y);
	col += tint.rgb * build_edge * 2.2 * step(build_y, 999.0);
	// Death: random cubes blink out, with a bright edge on the survivors.
	if (n < dissolve) { discard; }
	float edge = 1.0 - smoothstep(0.0, 0.12, n - dissolve);
	col += mix(tint.rgb, vec3(1.0), 0.5) * edge * 2.0 * step(0.001, dissolve);
	// Cube grid lines show while digitizing.
	vec3 f = abs(fract(world_pos / voxel) - 0.5);
	float grid = step(0.42, max(max(f.x, f.y), f.z));
	col += tint.rgb * grid * 0.8 * clamp(dissolve * 3.0 + build_edge + glitch, 0.0, 1.0);
	col = mix(col, col * vec3(0.6, 1.2, 1.4), glitch * 0.5);
	ALBEDO = col;
	ALPHA = clamp(a * strength * (0.85 + rim * 0.3), 0.0, 1.0);
}
