class_name Island
extends Node2D
## Procedural island. The coastline is a polar function r(theta), which gives
## exact, cheap point-in-island tests for collision, AI avoidance and projectiles.

const SAMPLES := 72

var radius := 200.0          # nominal radius (px)
var radii := PackedFloat32Array()
var max_radius := 0.0
var min_radius := 0.0
var land_height := 3.0 * U.M # cannonballs below this height stop on land
var kind := "wild"           # "wild", "port", "fort"
var _palms: Array = []       # [Vector2 local, size, rot]
var _rocks: Array = []
var _coast := PackedVector2Array()
var _grass := PackedVector2Array()
var _shallow := PackedVector2Array()
var _shallow_colors := PackedColorArray()
var _foam := PackedVector2Array()
var _t := 0.0


func setup(p_pos: Vector2, p_radius: float, rng: RandomNumberGenerator, p_kind: String = "wild", roughness: float = 1.0) -> void:
	position = p_pos
	radius = p_radius
	kind = p_kind
	z_index = -5
	radii.resize(SAMPLES)
	var harmonics := []
	for k in range(2, 7):
		harmonics.append([k, rng.randf_range(0.0, TAU), rng.randf_range(0.02, 0.11) * roughness / (k * 0.5)])
	max_radius = 0.0
	min_radius = INF
	for i in SAMPLES:
		var a := TAU * i / SAMPLES
		var r := 1.0
		for h in harmonics:
			r += float(h[2]) * sin(float(h[0]) * a + float(h[1]))
		r = maxf(0.6, r) * radius
		radii[i] = r
		max_radius = maxf(max_radius, r)
		min_radius = minf(min_radius, r)
	_build_geometry(rng)


func radius_at(angle: float) -> float:
	var f := wrapf(angle, 0.0, TAU) / TAU * SAMPLES
	var i0 := int(floor(f)) % SAMPLES
	var i1 := (i0 + 1) % SAMPLES
	return lerpf(radii[i0], radii[i1], f - floor(f))


## True if a world point is on land (optionally inflated by margin px).
func contains(p: Vector2, margin: float = 0.0) -> bool:
	var d := p - position
	var dist := d.length()
	if dist > max_radius + margin:
		return false
	return dist < radius_at(d.angle()) + margin


## How deep a point is inside the (inflated) coastline, and the outward normal.
func penetration(p: Vector2, margin: float = 0.0) -> Dictionary:
	var d := p - position
	var dist := d.length()
	if dist > max_radius + margin:
		return {}
	var r := radius_at(d.angle()) + margin
	if dist >= r:
		return {}
	var n := d / dist if dist > 0.001 else Vector2.RIGHT
	return {"depth": r - dist, "normal": n}


func _build_geometry(rng: RandomNumberGenerator) -> void:
	_coast.clear()
	_grass.clear()
	_shallow.clear()
	_shallow_colors.clear()
	_foam.clear()
	var shallow_col := Color(0.35, 0.8, 0.85, 0.38)
	_shallow.append(Vector2.ZERO)
	_shallow_colors.append(shallow_col)
	for i in SAMPLES:
		var a := TAU * i / SAMPLES
		var r := radii[i]
		var dv := Vector2(cos(a), sin(a))
		_coast.append(dv * r)
		_grass.append(dv * (r * 0.78 - 10.0))
		_foam.append(dv * (r + 5.0))
	for i in SAMPLES + 1:
		var a := TAU * (i % SAMPLES) / SAMPLES
		var r := radii[i % SAMPLES]
		_shallow.append(Vector2(cos(a), sin(a)) * (r * 1.28 + 30.0))
		_shallow_colors.append(Color(0.3, 0.7, 0.8, 0.0))
	_foam.append(_foam[0])
	if kind == "wild":
		var n := int(radius / 18.0)
		for i in n:
			var a := rng.randf_range(0.0, TAU)
			var rr := rng.randf_range(0.0, 0.7) * radius_at(a)
			_palms.append([Vector2(cos(a), sin(a)) * rr, rng.randf_range(11.0, 18.0), rng.randf_range(0.0, TAU)])
		for i in int(radius / 40.0) + 2:
			var a := rng.randf_range(0.0, TAU)
			var rr := radius_at(a) * rng.randf_range(0.85, 1.02)
			_rocks.append([Vector2(cos(a), sin(a)) * rr, rng.randf_range(6.0, 14.0)])


func _process(delta: float) -> void:
	_t += delta
	if int(_t * 10.0) != int((_t - delta) * 10.0):
		queue_redraw()


func _draw() -> void:
	# Shallow water halo (triangle fan with vertex colors)
	for i in range(1, _shallow.size() - 1):
		draw_polygon(PackedVector2Array([_shallow[0], _shallow[i], _shallow[i + 1]]),
			PackedColorArray([_shallow_colors[0], _shallow_colors[i], _shallow_colors[i + 1]]))
	# Animated surf line
	var surf := 0.5 + 0.5 * sin(_t * 1.7)
	draw_polyline(_foam, Color(1, 1, 1, 0.35 + 0.25 * surf), 3.0 + 2.0 * surf, true)
	draw_colored_polygon(_coast, Color("e3cf94"))
	draw_colored_polygon(_grass, Color("4f8f3f") if kind != "fort" else Color("7c8a5a"))
	draw_polyline(PackedVector2Array(Array(_coast) + [_coast[0]]), Color("b89c62"), 2.0, true)
	for r in _rocks:
		draw_circle(r[0], r[1], Color("6f6a64"))
		draw_circle(r[0] + Vector2(-2, -2), float(r[1]) * 0.6, Color("8d877f"))
	for p in _palms:
		_draw_palm(p[0], p[1], p[2])


func _draw_palm(at: Vector2, size: float, rot: float) -> void:
	draw_circle(at + Vector2(4, 4), size * 0.7, Color(0, 0, 0, 0.18))
	for k in 5:
		var a := rot + TAU * k / 5.0
		var tip := at + Vector2(cos(a), sin(a)) * size
		var side := Vector2(-sin(a), cos(a)) * size * 0.28
		draw_colored_polygon(PackedVector2Array([at, tip + side, tip, tip - side]), Color("2f6b2a"))
	draw_circle(at, size * 0.22, Color("6b4a2b"))
