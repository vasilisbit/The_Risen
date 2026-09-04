shader_type canvas_item;
// SCREEN-READ variant of intro_bw.gdshader, for the GoZen playback path.
//
// GoZen renders the video through its own internal yuv->rgb shader on a child TextureRect, so the
// B&W cinematic grade cannot be a material on the video node (that node has no plain TEXTURE to
// sample). Instead this runs on a full-screen ColorRect drawn ON TOP of the video: it samples the
// already-composited frame from the screen texture and regrades it. Same look as intro_bw: Rec.709
// luminance desaturation, a gentle S-curve contrast, and a soft vignette. The mp4 is colour-
// encoded but its content is monochrome, so this only deepens contrast + adds the vignette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float contrast = 1.18;
uniform float brightness = -0.02;
uniform float vignette_strength = 0.35;   // how dark the corners get (0 = none)

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	// Rec.709 luminance -> pure monochrome.
	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Contrast around mid-grey, plus a small brightness trim.
	l = clamp((l - 0.5) * contrast + 0.5 + brightness, 0.0, 1.0);
	// Soft vignette: 1.0 at centre, darkening toward the edges.
	vec2 d = SCREEN_UV - vec2(0.5);
	float vig = 1.0 - smoothstep(0.32, 0.85, length(d));
	l *= mix(1.0 - vignette_strength, 1.0, vig);
	COLOR = vec4(vec3(l), 1.0);
}
