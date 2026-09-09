shader_type spatial;
// Ember Tyrant phase-B energy dome. An additive, fresnel-rimmed honeycomb shield in the boss's
// ember palette: bright at grazing angles, animated hex cells, rising scan bands and a flicker,
// so the invulnerable phase reads clearly as an energy barrier (not a flat blue bubble).
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

uniform vec3 shield_color : source_color = vec3(1.0, 0.48, 0.12);
uniform vec3 hot_color : source_color = vec3(1.0, 0.86, 0.45);
uniform float rim_power = 2.2;
uniform float hex_scale = 9.0;
uniform float flicker_speed = 6.0;
uniform float base_alpha = 0.08;

// Offset of the nearest hex-cell centre (its length is ~0 at centre, ~0.5 at an edge).
vec2 hex_cell(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	return dot(a, a) < dot(b, b) ? a : b;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec2 huv = UV * hex_scale;
	huv.y += TIME * 0.15;
	float edge = smoothstep(0.40, 0.5, length(hex_cell(huv)));      // bright cell borders
	float scan = 0.5 + 0.5 * sin(UV.y * 24.0 - TIME * flicker_speed); // rising energy bands
	float flick = 0.85 + 0.15 * sin(TIME * flicker_speed * 1.7);
	float intensity = (fres * 1.8 + edge * 0.6 + scan * 0.12) * flick;
	vec3 col = mix(shield_color, hot_color, clamp(fres + edge * 0.4, 0.0, 1.0));
	ALBEDO = col * intensity * 2.0;
	ALPHA = clamp(base_alpha + fres * 0.9 + edge * 0.3 + scan * 0.05, 0.0, 0.95);
}
