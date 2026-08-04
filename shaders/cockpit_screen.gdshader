shader_type spatial;
// Cockpit console screen: a SUBTLE self-lit readout - a dim dark-glass panel with a
// soft moving telemetry waveform, a couple of quiet readout lines and gentle
// scanlines. Deliberately understated (the loud full-panel equaliser it replaced
// read as "horrible"); this just gives the console a hint of life. Purely cosmetic.
render_mode unshaded, cull_disabled;

uniform vec3 tint : source_color = vec3(0.35, 0.78, 0.95);
uniform float brightness = 0.9;

void fragment() {
	vec2 uv = UV;
	vec3 col = tint * 0.03;                        // near-black glass

	// soft central waveform line
	float wave = 0.5 + 0.10 * sin(uv.x * 22.0 + TIME * 2.5) + 0.05 * sin(uv.x * 7.0 - TIME);
	float d = abs(uv.y - wave);
	col += tint * brightness * smoothstep(0.05, 0.0, d) * 0.7;

	// two quiet readout ticks that drift
	float ticks = step(0.86, fract(uv.x * 6.0 - TIME * 0.15)) * step(0.12, uv.y) * step(uv.y, 0.28);
	col += tint * brightness * ticks * 0.35;

	// faint scanlines + a slow brightness breathe
	col *= 0.9 + 0.1 * sin(uv.y * 90.0 - TIME * 3.0);
	col *= 0.75 + 0.25 * sin(TIME * 0.8);
	ALBEDO = col;
	EMISSION = col;
}
