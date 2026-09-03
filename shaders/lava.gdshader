shader_type spatial;
render_mode cull_disabled;
// Flowing molten magma: a dark basalt crust broken by glowing molten channels that
// slowly flow and shift, sampled in WORLD space so it tiles seamlessly across big
// lava surfaces (river / moat / pit / vents) without UVs. Emissive so it lights the
// caverns. Drive `flow_dir` per-surface if you want the current to run a certain way.

uniform vec3 crust_color : source_color = vec3(0.10, 0.03, 0.02);   // cooled black crust
uniform vec3 hot_color : source_color = vec3(0.95, 0.35, 0.05);     // glowing magma
uniform vec3 bright_color : source_color = vec3(1.0, 0.92, 0.5);    // white-hot cores
uniform float emission_strength = 3.2;
uniform float tex_scale = 0.14;      // world-units frequency of the magma cells
uniform float flow_speed = 0.05;     // how fast the molten field drifts
uniform vec2 flow_dir = vec2(0.4, 1.0);

varying vec3 world_pos;

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(7.3, 1.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * tex_scale;
	vec2 drift = normalize(flow_dir) * TIME * flow_speed;
	// Domain warp: push the sample point around by its own noise so the molten field
	// reads as organic FLOWING channels instead of chunky cellular blobs that look like
	// blocks. This is what turns the lava from "glowing rectangles" into continuous flow.
	vec2 warp = vec2(fbm(uv + drift + vec2(1.3, 4.7)), fbm(uv - drift * 0.8 + vec2(8.1, 2.4)));
	uv += (warp - 0.5) * 1.7;
	// three layers scrolling at different rates -> churning, not a rigid slide; the fine
	// layer adds continuous small detail so the surface never reads as flat blocks.
	float base = fbm(uv + drift);
	float detail = fbm(uv * 2.4 - drift * 1.7 + 5.0);
	float fine = fbm(uv * 5.3 + drift * 0.6 + 11.0);
	float field = base * 0.58 + detail * 0.30 + fine * 0.12;
	// crust vs molten: threshold the field, then a hotter core inside the molten veins.
	// Softer/lower molten threshold -> the glowing channels connect across the surface
	// rather than breaking into isolated cells.
	float molten = smoothstep(0.36, 0.60, field);
	float core = smoothstep(0.58, 0.82, field);
	vec3 col = mix(crust_color, hot_color, molten);
	col = mix(col, bright_color, core * 0.9);
	ALBEDO = col * 0.12;
	EMISSION = col * emission_strength * (0.25 + molten * 1.2 + core * 0.8);
	ROUGHNESS = mix(0.92, 0.55, molten);
	METALLIC = 0.0;
}
