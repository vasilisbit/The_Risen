shader_type canvas_item;

// Fold warp overlay (P1): a full-screen starfield that streaks radially outward
// from the centre as the ship folds. Driven by a single `warp` uniform the travel
// state machine ramps 0 -> 1 over ~1 s during the FOLD beat, then back to 0 as the
// arrival cinematic is revealed. At warp 0 the overlay is fully transparent (the
// normal cockpit view shows through); as warp rises the screen fills with space and
// the stars stretch into rushing light-streaks.
//
// Everything is procedural (hashed angular bins), matching the project's
// generated-in-code policy - no textures, stable per-direction stars.

uniform float warp : hint_range(0.0, 1.0) = 0.0;
uniform vec4 streak_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
// Screen aspect used to keep the streaks radial (not egg-shaped) on a wide window.
uniform float aspect = 1.777;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// Centre-relative, aspect-corrected so radius is circular.
	vec2 uv = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(uv);
	float ang = atan(uv.y, uv.x);
	float a = ang * 0.15915494 + 0.5;         // angle -> 0..1

	// One star per angular bin, each with a random radial phase rushing outward.
	// Faster and longer-tailed the harder we are folding.
	float bins = 240.0;
	float bin = floor(a * bins);
	float seed = hash(vec2(bin, 1.0));
	float exists = step(0.34, hash(vec2(bin, 7.3)));

	float speed = 0.25 + warp * 2.4;
	float head = fract(seed + TIME * speed);   // radial position of the streak head
	float d = head - r;                        // >0: fragment lies on the inward tail
	float tail = 0.03 + warp * 0.5;

	float trail = exp(-max(d, 0.0) / tail) * step(-0.012, d);
	float glow = exp(-abs(d) / 0.014);         // bright head
	float line = (trail + glow) * exists;
	line *= smoothstep(0.02, 0.16, r);         // keep the very centre clear

	float fill = clamp(warp * 1.7, 0.0, 1.0);
	vec3 col = streak_color.rgb * line * (0.55 + warp);
	col += vec3(0.006, 0.011, 0.024) * fill;   // faint space wash so it isn't pure black

	float alpha = max(fill * 0.9, clamp(line, 0.0, 1.0) * fill);
	COLOR = vec4(col, alpha);
}
