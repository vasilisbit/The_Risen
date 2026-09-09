shader_type canvas_item;
// Black-and-white cinematic look for the intro cinematic, applied at PLAYBACK over the colour
// video (the video is shipped in colour so Godot's Theora decoder stays clean - a grayscale-
// encoded .ogv macroblocks in-engine). Replicates the old ffmpeg grade: luminance desaturation,
// a gentle S-curve contrast, and a soft vignette.
uniform float contrast = 1.18;
uniform float brightness = -0.02;
uniform float vignette_strength = 0.35;   // how dark the corners get (0 = none)

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Rec.709 luminance -> pure monochrome.
	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Contrast around mid-grey, plus a small brightness trim.
	l = clamp((l - 0.5) * contrast + 0.5 + brightness, 0.0, 1.0);
	// Soft vignette: 1.0 at centre, darkening toward the edges.
	vec2 d = UV - vec2(0.5);
	float vig = 1.0 - smoothstep(0.32, 0.85, length(d));
	l *= mix(1.0 - vignette_strength, 1.0, vig);
	COLOR = vec4(vec3(l), c.a);
}
