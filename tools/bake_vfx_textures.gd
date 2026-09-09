extends SceneTree

## Godot-baked shared VFX texture kit (no external tool — uses Godot's own
## FastNoiseLite + Image). Reconciled from the YouTube VFX study (planning-repo
## docs/VFX_FAL_RESEARCH.md §11): every tutorial authors these shape/pattern masks
## in Material Maker / Godot built-ins, NOT AI — for tileable, controllable masks
## that beats a raster generator. This bakes the ~9 masks the effect shaders /
## GPUParticles3D consume.
##
## Run:  godot --headless --path <proj> --script res://tools/bake_vfx_textures.gd -- [only]
##   [only] optional single texture name (validate one before batching).
##
## Output: res://assets/generated/vfx/tex/<name>.png
## Convention:
##   - Particle SPRITES (flare/flare_cross/spark/shock_ring): RGB=white, A=mask,
##     so an unshaded quad tints per-particle (ability colour) and keys transparency.
##   - Shader PATTERNS (noise/voronoi/hex/distortion/gradient): grayscale in RGB,
##     A=1 — the VisualShader samples a single channel. Tileable where it scrolls.

const SIZE := 256
const OUT_DIR := "res://assets/generated/vfx/tex"


func _initialize() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = String(args[0]).strip_edges()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var jobs := {
		"flare": _bake_flare,
		"flare_cross": _bake_flare_cross,
		"spark": _bake_spark,
		"shock_ring": _bake_shock_ring,
		"muzzle": _bake_muzzle,
		"noise_fbm": _bake_noise_fbm,
		"voronoi": _bake_voronoi,
		"hex_dots": _bake_hex_dots,
		"distortion": _bake_distortion,
		"gradient_v": _bake_gradient_v,
	}

	for name in jobs:
		if only != "" and name != only:
			continue
		var img: Image = (jobs[name] as Callable).call()
		var path := "%s/%s.png" % [OUT_DIR, name]
		var err := img.save_png(path)
		print("[bake] %s -> %s (%s)" % [name, path, "OK" if err == OK else "ERR %d" % err])

	quit()


# --- particle sprites (white RGB, alpha = mask) ---------------------------------

## Soft radial glow — the workhorse: sparks core, flash, fire, smoke, trails.
func _bake_flare() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := SIZE * 0.5
	var r := SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length() / r
			var a := _falloff(d, 1.6)              # smooth, glowy tail
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## 4-point cross-flare (radial core + soft horizontal/vertical streaks). Impact/muzzle.
func _bake_flare_cross() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := SIZE * 0.5
	var r := SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var nx := (x - c + 0.5) / r
			var ny := (y - c + 0.5) / r
			var core := _falloff(Vector2(nx, ny).length(), 2.2)
			# streaks: bright along an axis, thin across it
			var h := _falloff(absf(nx), 1.1) * _thin(absf(ny), 0.045)
			var v := _falloff(absf(ny), 1.1) * _thin(absf(nx), 0.045)
			var a := clampf(maxf(core, maxf(h, v)), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## Tight little dot for stretched sparks / embers (flare, but harder falloff).
func _bake_spark() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := SIZE * 0.5
	var r := SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length() / r
			var a := _falloff(d, 3.4)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## Thin bright expanding ring (shockwave). Difference of two radial edges.
func _bake_shock_ring() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := SIZE * 0.5
	var r := SIZE * 0.5
	var r0 := 0.72          # ring radius (0..1)
	var w := 0.14           # ring thickness
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length() / r
			var a := clampf(1.0 - absf(d - r0) / w, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)       # smoothstep
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## Spiky muzzle-flash star: a bright core with irregular radiating spikes of varying
## length/width (white-on-black, alpha-keyed). Reads as a real muzzle flash, not a soft dot.
func _bake_muzzle() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := SIZE * 0.5
	var r := SIZE * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9182
	var spikes: Array = []
	for i in 13:
		spikes.append({"a": rng.randf() * TAU, "len": rng.randf_range(0.55, 1.0), "w": rng.randf_range(0.035, 0.11)})
	for y in SIZE:
		for x in SIZE:
			var dx := (x - c + 0.5) / r
			var dy := (y - c + 0.5) / r
			var rad := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var v := _falloff(rad, 3.2)                    # bright core
			for s in spikes:
				var da: float = absf(fmod(ang - float(s["a"]) + PI, TAU) - PI)
				if da < float(s["w"]) and rad < float(s["len"]):
					var f := (1.0 - da / float(s["w"])) * (1.0 - rad / float(s["len"]))
					v = maxf(v, f * f)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(v, 0.0, 1.0)))
	return img


# --- shader patterns (grayscale RGB, alpha = 1, tileable) ------------------------

## Seamless fbm noise — dissolve masks, fire distortion, shield break-up, smoke.
func _bake_noise_fbm() -> Image:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.02
	n.seed = 1337
	return _grayscale_from(func(x, y): return _tile(n, x, y), 0.0)


## Seamless cellular (voronoi) — fireball body, energy cores, crackle.
func _bake_voronoi() -> Image:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.frequency = 0.03
	n.seed = 707
	return _grayscale_from(func(x, y): return _tile(n, x, y), 0.0)


## Hex/dot lattice — the Guardian Dome shield pattern (energy-shield read).
## Dots on a hex grid, tileable by construction.
func _bake_hex_dots() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var cols := 8.0
	var cw := SIZE / cols                    # cell width
	var ch := cw * sqrt(3.0) / 2.0           # hex row height (kept for offset look)
	var dot := cw * 0.30                      # dot radius
	for y in SIZE:
		for x in SIZE:
			var row := floori(y / ch)
			var ox := 0.0 if (row % 2 == 0) else cw * 0.5   # brick/hex offset
			var gx := fposmod(x - ox, cw) - cw * 0.5
			var gy := fposmod(float(y), ch) - ch * 0.5
			var d := Vector2(gx, gy).length() / dot
			var v := 1.0 - clampf(d, 0.0, 1.0)
			v = v * v * (3.0 - 2.0 * v)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return img


## Seamless low-freq 2-octave noise for UV heat-haze distortion (Le Lu fire).
func _bake_distortion() -> Image:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 2
	n.frequency = 0.015
	n.seed = 42
	return _grayscale_from(func(x, y): return _tile(n, x, y), 0.0)


## Vertical linear gradient (black bottom -> white top) — masks distortion base,
## clips trail tails, softens ring edges.
func _bake_gradient_v() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var v := 1.0 - float(y) / float(SIZE - 1)   # top bright
		for x in SIZE:
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return img


# --- helpers --------------------------------------------------------------------

## Radial falloff in [0..1], d=0 -> 1 (bright), d>=1 -> 0. `p` shapes the tail.
func _falloff(d: float, p: float) -> float:
	var a := clampf(1.0 - d, 0.0, 1.0)
	return pow(a, p)


## Thin band around 0: |t| small -> 1, fading to 0 at width `w`.
func _thin(t: float, w: float) -> float:
	return clampf(1.0 - t / w, 0.0, 1.0)


## Seamless wrap of any FastNoiseLite: blends the 4 toroidal corners -> tileable,
## remapped to [0..1].
func _tile(n: FastNoiseLite, x: int, y: int) -> float:
	var w := float(SIZE)
	var a := n.get_noise_2d(x, y)
	var b := n.get_noise_2d(x - w, y)
	var c := n.get_noise_2d(x, y - w)
	var d := n.get_noise_2d(x - w, y - w)
	var wx := float(x) / w
	var wy := float(y) / w
	var v: float = lerp(lerp(a, b, wx), lerp(c, d, wx), wy)
	return clampf(v * 0.5 + 0.5, 0.0, 1.0)


## Fill a grayscale RGBA image from a per-pixel value func (value in [0..1]).
func _grayscale_from(f: Callable, _unused: float) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var v: float = clampf(f.call(x, y), 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return img
