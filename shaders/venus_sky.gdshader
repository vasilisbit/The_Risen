shader_type sky;
// Venus surface sky: an oppressive, near-total sulfuric-acid cloud overcast. No blue,
// no crisp sun disk (direct sunlight never reaches the Venusian surface) - just a
// churning ochre/sulfur-orange cloud deck bathed in a dim diffuse glow, darkening
// toward a hazy zenith. Adapts the Earth cloud fbm to a heavy toxic palette with
// near-full cover. sun_dir is set from the scene's DirectionalLight (venus_level.gd).

uniform vec3 zenith_color : source_color = vec3(0.34, 0.20, 0.09);   // murky ochre overhead
uniform vec3 horizon_color : source_color = vec3(0.86, 0.52, 0.18);  // sulfur-orange horizon glow
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.34);      // diffuse sun-through-haze
uniform vec3 cloud_lit : source_color = vec3(0.95, 0.66, 0.30);      // sunlit sulfur cloud tops
uniform vec3 cloud_dark : source_color = vec3(0.32, 0.18, 0.10);     // shadowed cloud undersides
uniform vec3 sun_dir = vec3(0.3, 0.5, -0.8);
uniform float cloud_cover = 0.72;      // 0..1, high = thick overcast
uniform float cloud_sharpness = 1.4;   // soft billows, not crisp puffs
uniform float cloud_scale = 0.7;       // spatial frequency of the churning deck
uniform float cloud_speed = 0.006;     // drift speed

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * vnoise(p);
		p = p * 2.02 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, 0.0, 1.0);
	// base gradient: bright sulfur haze at the horizon darkening to a murky zenith
	vec3 col = mix(horizon_color, zenith_color, pow(h, 0.6));

	// diffuse sun: NO crisp disk on Venus - only a broad glow bleeding through the deck
	float sd = max(dot(dir, normalize(sun_dir)), 0.0);
	col += glow_color * pow(sd, 3.0) * 0.35;    // broad hazy glow, no hard edge

	// thick churning cloud deck: threshold an fbm field, shade tops toward the glow
	if (dir.y > 0.01) {
		vec2 uv = dir.xz / max(dir.y, 0.05);            // perspective plane projection
		uv = uv * cloud_scale + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.7);
		float base = fbm(uv);
		float detail = fbm(uv * 3.3 + 5.0);             // finer churn
		float field = base * 0.7 + detail * 0.3;
		float thr = 1.0 - cloud_cover;                  // higher cover -> lower threshold
		float density = smoothstep(thr, thr + 0.22 / cloud_sharpness, field);
		density *= smoothstep(0.01, 0.22, dir.y);       // fade into the horizon haze
		// sunlit tops brighter on the sun side, murky undersides elsewhere
		float lit = smoothstep(thr + 0.02, thr + 0.24, field);
		lit = mix(lit, min(lit + 0.5 * sd, 1.0), 0.5);
		vec3 cloud = mix(cloud_dark, cloud_lit, lit);
		col = mix(col, cloud, density * 0.92);
	}
	COLOR = col;
}
