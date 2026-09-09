shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

// Holographic version of the hub viewport planet (planet.gdshader), for the
// mission-table spheres. Same fbm surface so a planet reads as the same world
// in both places, then projected as light: additive blending, a bright fresnel
// limb, travelling scanlines and a faint flicker.
//
// The noise block is duplicated from planet.gdshader rather than #include'd -
// the two shaders differ in render_mode and lighting model, and a shared
// include for ~25 lines would couple them for little gain.

uniform vec3 base_color : source_color = vec3(0.20, 0.55, 1.00);
uniform vec3 land_color : source_color = vec3(0.55, 0.85, 1.00);
uniform float land_threshold = 0.52;
uniform float band_strength = 0.0;
uniform float rot_speed = 0.05;        // faster than the real planet: it's a display
uniform float scan_speed = 0.35;
uniform float scan_density = 90.0;
uniform float brightness = 1.0;
uniform float flicker_amount = 0.06;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
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
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(local_pos);
	float ang = TIME * rot_speed * TAU;
	float c = cos(ang);
	float s = sin(ang);
	vec3 rp = vec3(c * n.x + s * n.z, n.y, -s * n.x + c * n.z);

	// Same surface definition as the real planet, flattened to two tones.
	float continents = fbm(rp * 2.2);
	float land = smoothstep(land_threshold - 0.05, land_threshold + 0.05, continents);
	float bands = sin(rp.y * 13.0 + fbm(rp * 3.0) * 3.5) * 0.5 + 0.5;
	vec3 surface = mix(base_color, land_color, land);
	surface = mix(surface, land_color, bands * band_strength);

	// Limb glow: a hologram is brightest where you see it edge-on.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 2.2);
	float body = 0.20 + 0.55 * land;

	// Scanlines travelling up the projection, plus a slow overall flicker.
	float scan = 0.75 + 0.25 * sin((local_pos.y * scan_density) - TIME * scan_speed * 40.0);
	float flicker = 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * 37.0));
	// A rolling band, brighter, that sweeps the sphere.
	float sweep = smoothstep(0.85, 1.0, sin(local_pos.y * 6.0 - TIME * 1.4));

	float intensity = (body + fresnel * 1.4 + sweep * 0.5) * scan * flicker * brightness;
	ALBEDO = surface * intensity;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
