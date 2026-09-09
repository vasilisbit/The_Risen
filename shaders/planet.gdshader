shader_type spatial;
render_mode unshaded, cull_back;

// Procedural planet for the hub viewport (T-0028). Unshaded and self-lit: it
// is meant to be a distant world lit by a star that isn't in the scene, so it
// must not depend on the hub's interior lighting reaching 20 m out the window.
//
// Rotation is done here against TIME rather than by spinning the node, so it
// is frame-rate independent and cannot stutter with the physics tick - and the
// terminator stays put while the surface turns under it, as it should.
//
// No textures: the surface is fbm noise, matching the project's
// everything-generated-in-code policy.

uniform vec3 ocean_color : source_color = vec3(0.05, 0.22, 0.55);
uniform vec3 land_color : source_color = vec3(0.16, 0.42, 0.18);
uniform vec3 atmo_color : source_color = vec3(0.40, 0.65, 1.00);
uniform vec3 sun_dir = vec3(0.6, 0.35, 0.7);
uniform float land_threshold = 0.52;
uniform float band_strength = 0.0;      // latitude banding (Mars/Venus)
uniform float cloud_amount = 0.40;
uniform float rot_speed = 0.0166667;    // revolutions per second = 1 per 60 s
uniform float night_level = 0.06;       // how dark the unlit side goes

// TAU is a Godot shader builtin - declaring it here is a redefinition error.

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
	float n000 = hash(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
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

	// Spin the sample point about the pole; the surface turns, the light does not.
	float ang = TIME * rot_speed * TAU;
	float c = cos(ang);
	float s = sin(ang);
	vec3 rp = vec3(c * n.x + s * n.z, n.y, -s * n.x + c * n.z);

	float continents = fbm(rp * 2.2);
	float land = smoothstep(land_threshold - 0.05, land_threshold + 0.05, continents);
	vec3 surface = mix(ocean_color, land_color, land);

	// Latitude bands, weak on Earth and heavy on the gas-hazed worlds.
	float bands = sin(rp.y * 13.0 + fbm(rp * 3.0) * 3.5) * 0.5 + 0.5;
	surface = mix(surface, land_color * 1.25, bands * band_strength);

	// Clouds drift a little faster than the ground.
	float clouds = smoothstep(0.54, 0.76, fbm(rp * 3.4 + vec3(ang * 0.35, 0.0, 0.0)));
	surface = mix(surface, vec3(1.0), clouds * cloud_amount);

	// Day/night with a soft terminator.
	float lambert = clamp(dot(n, normalize(sun_dir)), 0.0, 1.0);
	float day = smoothstep(0.0, 0.32, lambert);
	vec3 lit = surface * mix(night_level, 1.0, day);

	// Atmospheric rim, brightest where it catches the light.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	lit += atmo_color * rim * 0.55 * mix(0.12, 1.0, day);

	ALBEDO = lit;
}
