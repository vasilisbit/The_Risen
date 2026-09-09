shader_type sky;
// Afternoon ruined-Earth sky with drifting volumetric-look clouds. Base gradient
// (warm hazy horizon -> afternoon blue) + a sun disk/glow + fbm cloud layer
// projected onto a virtual plane above, scrolling slowly and sunlit from the sun
// direction. sun_dir is set from the scene's DirectionalLight (earth_level.gd).

uniform vec3 top_color : source_color = vec3(0.17, 0.37, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.82, 0.78, 0.66);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_dark : source_color = vec3(0.48, 0.49, 0.55);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform float cloud_cover = 0.38;      // 0..1, higher = more sky covered
uniform float cloud_sharpness = 2.2;   // edge contrast of the clouds
uniform float cloud_scale = 0.85;       // spatial frequency of the cloud field
uniform float cloud_speed = 0.004;     // drift speed

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
	// base gradient (brighten toward the horizon haze)
	float h = clamp(dir.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.55));

	// sun disk + broad glow
	float sd = max(dot(dir, normalize(sun_dir)), 0.0);
	col += sun_color * pow(sd, 350.0) * 10.0;   // crisp disk
	col += sun_color * pow(sd, 6.0) * 0.30;     // hazy glow around it

	// cloud layer: project the view onto a plane overhead, scroll it, shade by fbm.
	// Distinct puffs against blue gaps: threshold the field, then shade tops brighter.
	if (dir.y > 0.015) {
		vec2 uv = dir.xz / max(dir.y, 0.05);            // perspective plane projection
		uv = uv * cloud_scale + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.6);
		float base = fbm(uv);
		float detail = fbm(uv * 3.1 + 7.0);             // finer billows
		float field = base * 0.72 + detail * 0.28;
		float thr = 1.0 - cloud_cover;                  // higher cover -> lower threshold
		float density = smoothstep(thr, thr + 0.20 / cloud_sharpness, field);
		density *= smoothstep(0.02, 0.30, dir.y);       // fade into the horizon haze
		// sunlit tops (denser core = brighter), grey shaded undersides
		float lit = smoothstep(thr + 0.02, thr + 0.22, field);
		lit = mix(lit, min(lit + 0.4 * sd, 1.0), 0.5);  // extra glow on the sun side
		vec3 cloud = mix(cloud_dark, cloud_lit, lit);
		col = mix(col, cloud, density);
	}
	COLOR = col;
}
