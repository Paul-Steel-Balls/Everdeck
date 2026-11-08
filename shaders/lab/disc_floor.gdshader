shader_type spatial;
// Floating-disc arena floor. Each half glows in its hero's color; a bright
// seam runs between them and the rim burns at the edge. The etched pattern
// follows the arena theme:
//   0 circuit traces (the original disc)   4 ship deck planks (high seas)
//   1 cracked rock (quarry)                5 castle flagstones
//   2 kitchen tiles + doily lace           6 casino felt diamonds
//   3 star map + rune rings (library)    (6 = green baize card table)

uniform vec4 near_col : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec4 far_col : source_color = vec4(0.1, 0.8, 0.78, 1.0);
uniform vec4 base_col : source_color = vec4(0.025, 0.012, 0.05, 1.0);
uniform float radius = 10.0;        // half-depth (toward the camera)
uniform float half_w = 10.0;        // half-width (left-right)
uniform float shape_n = 2.0;        // 2 = circle/ellipse, 4+ = rounded square
uniform int pattern = 0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return vec2(hash(p), hash(p + 17.3)); }

float line_aa(float d, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fwidth(d) * 1.5, abs(d));
}

// Circuit traces: in each cell, a horizontal or vertical trace with a pad.
float circuit(vec2 p) {
	vec2 c = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(c);
	float v = 0.0;
	if (h < 0.35) {
		v = line_aa(f.y, 0.04) * step(abs(f.x), 0.5);
	} else if (h < 0.6) {
		v = line_aa(f.x, 0.04) * step(abs(f.y), 0.5);
	} else if (h < 0.7) {
		v = 1.0 - smoothstep(0.07, 0.07 + fwidth(f.x) * 2.0, length(f));
	}
	return v;
}

// Voronoi edges (cracks between rock plates).
float cracks(vec2 p) {
	vec2 c = floor(p);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 q = c + o + hash2(c + o) * 0.85;
			float d = length(p - q);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return 1.0 - smoothstep(0.0, 0.05 + fwidth(p.x) * 1.5, d2 - d1);
}

float grid_lines(vec2 p, float w) {
	vec2 g = abs(fract(p) - 0.5);
	return max(line_aa(g.x - 0.5, w), line_aa(g.y - 0.5, w));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.2;
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(half_w, radius) * 2.0;   // world units, x right, y toward camera
	// Distance in the platform's own shape (superellipse), scaled so the
	// edge is at r == radius whatever the shape.
	vec2 q = abs(p) / vec2(half_w, radius);
	float r = pow(pow(q.x, shape_n) + pow(q.y, shape_n), 1.0 / shape_n) * radius;
	if (r > radius) { discard; }
	float ang = atan(p.y, p.x);
	float near = smoothstep(-0.25, 0.25, p.y);
	vec3 side = mix(far_col.rgb, near_col.rgb, near);
	// `mat` is the surface itself (lit); `glow` is light-up detail in the
	// half's hero color (emission).
	vec3 mat = base_col.rgb;
	float glow = 0.0;
	float rough = 0.8;
	float rings = 0.5;
	if (pattern == 0) {
		glow += circuit(p * 1.6) * 0.35;
		glow += circuit(p * 3.7 + 13.0) * 0.18;
		vec2 g = abs(fract(p / 1.5) - 0.5) / fwidth(p / 1.5);
		glow += (1.0 - min(min(g.x, g.y), 1.0)) * 0.22;
	} else if (pattern == 1) {
		// Quarry rock: mottled plates, dark cracks with an ember glow deep in them.
		float c1 = cracks(p * 0.75);
		float c2 = cracks(p * 2.1 + 5.0);
		float n = fbm(p * 1.3);
		mat = mix(vec3(0.22, 0.16, 0.12), vec3(0.42, 0.33, 0.26), n);
		mat *= 1.0 - c1 * 0.75 - c2 * 0.3;
		glow += c1 * 0.5;
		rings = 0.0;
	} else if (pattern == 2) {
		// Kitchen: cream and duck-egg checkered tiles, white grout, a lace doily border.
		vec2 t = floor(p / 1.1);
		float chk = mod(t.x + t.y, 2.0);
		mat = mix(vec3(0.62, 0.57, 0.48), vec3(0.38, 0.52, 0.54), chk);
		mat *= 0.92 + hash(t) * 0.08;
		float grout = grid_lines(p / 1.1, 0.04);
		mat = mix(mat, vec3(0.7, 0.69, 0.66), grout);
		rough = 0.35;
		float sc = r - radius * 0.86 - sin(ang * 48.0) * 0.12;
		float lace = line_aa(sc, 0.06) + line_aa(r - radius * 0.8 - sin(ang * 24.0) * 0.18, 0.05) * 0.7;
		lace += line_aa(sin(ang * 48.0) * r, 0.04) * smoothstep(radius * 0.78, radius * 0.82, r) * (1.0 - smoothstep(radius * 0.86, radius * 0.9, r)) * 0.6;
		mat = mix(mat, vec3(0.8), clamp(lace, 0.0, 1.0) * 0.9);
		mat *= 0.72;  // darker so the Crew stand out
		rings = 0.0;
	} else if (pattern == 3) {
		// Library: deep blue marble with gold star-map inlay.
		float v = fbm(p * 0.8 + fbm(p * 1.7) * 2.0);
		mat = mix(vec3(0.04, 0.05, 0.14), vec3(0.14, 0.16, 0.32), v);
		rough = 0.25;
		vec2 c = floor(p * 1.3);
		vec2 o = hash2(c) - 0.5;
		float star = (1.0 - smoothstep(0.03, 0.06 + fwidth(p.x), length(fract(p * 1.3) - 0.5 - o * 0.6))) * step(0.6, hash(c));
		float inlay = 0.0;
		for (int i = 1; i <= 8; i++) {
			inlay += line_aa(r - float(i) * radius * 0.11, 0.025) * 0.6;
		}
		inlay += line_aa(sin(ang * 6.0) * r, 0.03) * 0.5 + line_aa(sin(ang * 6.0 + 1.05) * r, 0.03) * 0.5;
		mat = mix(mat, vec3(0.85, 0.66, 0.28), clamp(inlay, 0.0, 1.0));
		glow += star * 1.2;
		rings = 0.0;
	} else if (pattern == 4) {
		// Ship deck: warm planks, each its own shade, dark caulked seams, grain.
		float row = floor(p.y / 0.55);
		float seg = floor(p.x / 3.2 + hash(vec2(row, 3.0)));
		float seam_y = line_aa(abs(fract(p.y / 0.55) - 0.5) - 0.5, 0.05);
		float joint = line_aa(abs(fract(p.x / 3.2 + hash(vec2(row, 3.0))) - 0.5) - 0.5, 0.025);
		float grain = sin(p.x * 11.0 + hash(vec2(row, seg)) * 20.0 + fbm(p * vec2(0.6, 6.0)) * 6.0) * 0.5 + 0.5;
		mat = mix(vec3(0.33, 0.2, 0.1), vec3(0.52, 0.34, 0.18), hash(vec2(row, seg)) * 0.6 + grain * 0.4);
		mat *= 1.0 - (seam_y + joint) * 0.8;
		rough = 0.7;
		rings = 0.0;
	} else if (pattern == 5) {
		// Castle: grey flagstones of varied tone, dark mortar, worn edges.
		float row = floor(p.y / 1.1);
		vec2 fq = vec2(p.x / 1.6 + mod(row, 2.0) * 0.5, p.y / 1.1);
		float mortar = grid_lines(fq, 0.06);
		float n = fbm(p * 2.0);
		mat = mix(vec3(0.3, 0.3, 0.33), vec3(0.5, 0.49, 0.5), hash(floor(fq)) * 0.6 + n * 0.4);
		mat *= 1.0 - mortar * 0.7;
		mat *= 0.82;  // a tad darker so the Crew stand out
		rough = 0.9;
		rings = 0.0;
	} else {
		// Casino: deep green baize (a card table) with a soft nap, a faint
		// gold lattice and a gold pip border.
		float n = fbm(p * 3.0);
		mat = mix(vec3(0.02, 0.16, 0.07), vec3(0.05, 0.3, 0.14), n);
		float sheen = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		mat += vec3(0.04, 0.12, 0.06) * sheen;
		vec2 dq = vec2(p.x + p.y, p.x - p.y) / 1.4;
		float lat = grid_lines(dq, 0.02) * 0.45;
		float pip = 1.0 - smoothstep(0.08, 0.12 + fwidth(p.x), length(fract(vec2(ang * 7.64, r * 0.5)) - 0.5) * 2.0);
		pip *= smoothstep(radius * 0.8, radius * 0.82, r) * (1.0 - smoothstep(radius * 0.9, radius * 0.92, r));
		mat = mix(mat, vec3(0.85, 0.65, 0.25), clamp(lat * 0.7 + pip, 0.0, 1.0));
		rough = 0.95;
		rings = 0.0;
	}
	// Rune circles and spokes (the neon disc only).
	for (int i = 1; i <= 4; i++) {
		glow += line_aa(r - float(i) * radius * 0.22, 0.03) * rings;
	}
	glow += line_aa(sin(ang * 12.0) * r, 0.04) * smoothstep(radius * 0.9, radius * 0.5, r) * 0.15 * rings * 2.0;
	vec3 em = side * glow * 0.9;
	if (pattern == 0) {
		em += base_col.rgb + side * 0.05;
		mat = vec3(0.0);
	} else {
		// A light wash of each hero's color over their half of the real floor.
		mat = mix(mat, mat * (side * 1.4 + 0.3), 0.22);
		// Depth: broad light-and-dark patches, and a pool of light in the
		// middle that falls off toward the edge (the models stand in it).
		float big = fbm(p * 0.22 + 3.1);
		mat *= 0.8 + 0.34 * big;
		float pool = 1.0 - smoothstep(radius * 0.3, radius * 1.02, r);
		mat *= mix(0.62, 1.04, pool);
	}
	// Seam between the halves: white-hot center fading to both colors.
	float seam = 1.0 - smoothstep(0.0, 0.09, abs(p.y));
	em += mix(side, vec3(1.0), 0.35) * seam * 1.2;
	// Burning rim.
	float rim = smoothstep(radius * 0.93, radius * 0.985, r) * (1.0 - smoothstep(radius * 0.985, radius, r));
	em += side * rim * 1.6;
	ALBEDO = mat;
	ROUGHNESS = rough;
	EMISSION = em;
}
