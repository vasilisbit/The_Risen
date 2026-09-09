shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled, depth_draw_opaque;

// Sci-fi energy-shield / aura shader (docs/VFX_FAL_RESEARCH.md §11.5, from the
// "Sci-Fi Barrier" tutorial recipe): a tiled dot/hex pattern broken up by a
// scrolling noise, plus a Fresnel rim so the silhouette glows, all additive so
// it reads as energy you can see through. `strength` dims it as the dome's pool
// is spent. Used by the Guardian Dome (hemisphere + hex) and Juggernaut Charge
// (sphere + voronoi crackle).

uniform sampler2D pattern_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 shield_color : source_color = vec4(0.35, 0.95, 0.6, 1.0);
uniform float pattern_scale = 3.0;
uniform float scroll_speed = 0.06;
uniform float fresnel_power = 2.4;
uniform float rim_boost = 1.4;
uniform float brightness = 2.2;
uniform float strength = 1.0;   // 0..1, driven from remaining shield pool

void fragment() {
	vec2 uv = UV * pattern_scale;
	float pat = texture(pattern_tex, uv).r;
	float n = texture(noise_tex, uv + vec2(0.0, TIME * scroll_speed)).r;
	pat *= mix(0.55, 1.0, n);                       // noise break-up
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndotv, fresnel_power) * rim_boost;
	float intensity = clamp((pat * 0.5 + fres) * strength, 0.0, 1.0);
	ALBEDO = shield_color.rgb * brightness;
	ALPHA = intensity;
}
