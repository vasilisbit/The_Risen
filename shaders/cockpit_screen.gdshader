shader_type spatial;
// Cockpit console screen: an unshaded, self-lit readout that reads as a live panel
// out of the corner of the eye - a dark glass with an animated bar-graph band, a
// header strip and rolling scanlines. Purely cosmetic (the helm's real state is on
// the HUD); this just makes the deploying console feel alive.
render_mode unshaded, cull_disabled;

uniform vec3 tint : source_color = vec3(0.30, 0.80, 1.00);
uniform float bars = 9.0;        // number of equaliser columns
uniform float brightness = 1.6;  // >1 so the panel blooms

// cheap per-column hash so each bar has its own height + rhythm
float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec3 col = tint * 0.05;                       // dark glass base

	// header strip along the top
	if (uv.y > 0.86) {
		col = tint * (uv.x < 0.55 ? 1.3 : 0.25);
	} else {
		// equaliser band in the lower ~70%
		float region = clamp((0.78 - uv.y) / 0.78, 0.0, 1.0);
		float bx = floor(uv.x * bars);
		float gap = fract(uv.x * bars);
		float h = 0.25 + 0.7 * hash(bx);
		h *= 0.6 + 0.4 * sin(TIME * 2.2 + bx * 1.7);   // pulse
		if (region < h && gap > 0.16 && gap < 0.84) {
			col = tint * brightness;
		}
	}

	// rolling scanlines over everything
	col *= 0.82 + 0.18 * sin(uv.y * 140.0 - TIME * 4.0);
	ALBEDO = col;
	EMISSION = col;
}
