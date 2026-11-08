shader_type sky;
// Nebula with stars. The colors are set per arena theme (defaults: the
// purple nebula of the floating disc).
uniform vec3 deep = vec3(0.02, 0.0, 0.05);
uniform vec3 cloud = vec3(0.35, 0.08, 0.55);
uniform vec3 accent = vec3(0.9, 0.3, 0.1);
uniform float accent_amt = 0.4;
uniform float stars = 1.0;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void sky() {
	vec3 d = EYEDIR;
	float n = noise(d * 3.0 + TIME * 0.01) * 0.6 + noise(d * 7.0) * 0.4;
	vec3 col = mix(deep, cloud, smoothstep(0.45, 0.95, n));
	col += accent * smoothstep(0.75, 1.0, noise(d * 4.0 + 3.0)) * accent_amt;
	float s = step(0.9975, hash(floor(d * 300.0)));
	col += vec3(s) * stars;
	COLOR = col;
}
