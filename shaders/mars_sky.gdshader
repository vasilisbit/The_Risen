shader_type sky;
// Dusty Mars daytime sky: a low-contrast butterscotch/tan dome brightening to a
// hazy salmon horizon, with a soft pale sun disk diffused through suspended dust
// (no clouds - the Martian atmosphere reads as a uniform dusty haze). sun_dir is
// set from the scene's DirectionalLight (mars_level.gd).

uniform vec3 zenith_color : source_color = vec3(0.55, 0.42, 0.32);   // dusty tan overhead
uniform vec3 horizon_color : source_color = vec3(0.80, 0.60, 0.47);  // hazy salmon haze
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.68);
uniform vec3 sun_dir = vec3(0.4, 0.5, -0.7);
uniform float haze = 0.35;                                            // extra horizon dust lift

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, 0.0, 1.0);
	// dusty gradient - keep it low contrast so it reads as thick atmosphere
	vec3 col = mix(horizon_color, zenith_color, pow(h, 0.7));
	// lift a dust band near the horizon
	col += horizon_color * haze * pow(1.0 - h, 3.0);
	// soft diffuse sun through the dust (broad glow, faint disk)
	float sd = max(dot(dir, normalize(sun_dir)), 0.0);
	col += sun_color * pow(sd, 60.0) * 1.2;      // diffuse pale disk
	col += sun_color * pow(sd, 4.0) * 0.22;      // broad dusty glow
	COLOR = col;
}
