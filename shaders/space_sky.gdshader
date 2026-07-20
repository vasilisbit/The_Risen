shader_type sky;

// Deep space seen from the hub: a dark gradient, a faint nebula wash and a
// dense procedural starfield. Replaces the default ProceduralSky, which drew a
// blue daytime horizon out of a starship window.
//
// Stars come from a hashed cell grid rather than a texture, so they are stable
// (a given direction always has the same star) and cost nothing to author.

// Deep navy fading to near-black. Kept dark on purpose: anything brighter and
// the window reads as a blue panel rather than an opening onto space.
uniform vec3 horizon_color : source_color = vec3(0.015, 0.022, 0.045);
uniform vec3 zenith_color : source_color = vec3(0.004, 0.005, 0.012);
uniform vec3 nebula_color : source_color = vec3(0.06, 0.04, 0.14);
uniform float nebula_strength = 0.35;
uniform float star_density = 0.965;   // higher = fewer stars
uniform float star_brightness = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += vnoise(p) * amp;
		p *= 2.11;
		amp *= 0.5;
	}
	return sum;
}

// One star per grid cell, jittered inside it, so they never sit on a lattice.
float stars(vec3 dir, float scale, float threshold, float size) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float pick = hash(cell);
	if (pick < threshold) {
		return 0.0;
	}
	vec3 jitter = vec3(hash(cell + 1.7), hash(cell + 3.3), hash(cell + 5.9));
	float d = length(fract(p) - jitter);
	float core = smoothstep(size, 0.0, d);
	// Twinkle: each star has its own phase so they don't pulse together.
	float twinkle = 0.75 + 0.25 * sin(TIME * 1.6 + pick * 40.0);
	return core * twinkle * (0.45 + 0.55 * hash(cell + 9.1));
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, up);

	// Nebula: a soft, patchy wash so the void isn't perfectly flat.
	float neb = fbm(dir * 2.4);
	neb = smoothstep(0.45, 0.85, neb);
	col += nebula_color * neb * nebula_strength;

	// Three passes at different scales: a few big stars, many small ones.
	float s = 0.0;
	s += stars(dir, 60.0, star_density, 0.16) * 1.0;
	s += stars(dir, 130.0, star_density + 0.015, 0.22) * 0.7;
	s += stars(dir, 260.0, star_density + 0.025, 0.30) * 0.45;
	col += vec3(0.85, 0.90, 1.0) * s * star_brightness;

	COLOR = col;
}
