class_name Effects
extends Node2D
## Lightweight particle + floating-text system drawn in a single canvas item:
## muzzle flashes, cannon smoke, splashes, splinters, fire, debris, bubbles.

class P:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var size: float
	var grow: float
	var color: Color
	var kind: int
	var drag: float
	var rot: float

enum K { SMOKE, FLASH, SPLASH_RING, DROPLET, SPLINTER, FIRE, EMBER, DEBRIS, BUBBLE, FOAM, SPARK }

class FloatText:
	var pos: Vector2
	var text: String
	var color: Color
	var life: float
	var max_life: float
	var size: int

const MAX_PARTICLES := 2600

var _parts: Array[P] = []
var _texts: Array[FloatText] = []
var _rng := RandomNumberGenerator.new()
var _font: Font
var wind := Vector2(6.0, -3.0)


func _ready() -> void:
	z_index = 8
	_rng.randomize()
	_font = ThemeDB.fallback_font


func _add(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, grow: float, color: Color, drag: float = 0.0) -> void:
	if _parts.size() >= MAX_PARTICLES:
		return
	var p := P.new()
	p.kind = kind
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.size = size
	p.grow = grow
	p.color = color
	p.drag = drag
	p.rot = _rng.randf_range(0.0, TAU)
	_parts.append(p)


func _rand_dir() -> Vector2:
	return Vector2.from_angle(_rng.randf_range(0.0, TAU))


# --- Emitters ----------------------------------------------------------------------------

func muzzle(pos: Vector2, dir: Vector2, ship_vel: Vector2) -> void:
	_add(K.FLASH, pos + dir * 6.0, ship_vel, 0.09, 13.0, 40.0, Color(1.0, 0.85, 0.4, 1.0))
	for i in 7:
		var v := dir * _rng.randf_range(40.0, 120.0) + _rand_dir() * 18.0 + ship_vel * 0.8
		_add(K.SMOKE, pos + dir * 8.0, v, _rng.randf_range(1.2, 2.2), _rng.randf_range(6.0, 10.0), 16.0,
			Color(0.92, 0.9, 0.86, 0.55), 1.6)
	for i in 4:
		_add(K.SPARK, pos, dir * _rng.randf_range(160.0, 260.0) + _rand_dir() * 40.0, 0.18, 2.0, 0.0, Color(1, 0.7, 0.2), 3.0)


func splash(pos: Vector2, big: bool = false) -> void:
	var s := 1.6 if big else 1.0
	_add(K.SPLASH_RING, pos, Vector2.ZERO, 0.8 * s, 4.0, 34.0 * s, Color(0.9, 0.97, 1.0, 0.8))
	for i in int(9 * s):
		_add(K.DROPLET, pos, _rand_dir() * _rng.randf_range(20.0, 70.0) * s, _rng.randf_range(0.35, 0.7), _rng.randf_range(2.0, 4.0) * s, -2.0, Color(0.95, 1, 1, 0.9), 2.5)
	_add(K.FOAM, pos, Vector2.ZERO, 2.5 * s, 8.0 * s, 6.0, Color(1, 1, 1, 0.35))


func hit(pos: Vector2, normal: Vector2) -> void:
	_add(K.FLASH, pos, Vector2.ZERO, 0.08, 10.0, 30.0, Color(1, 0.8, 0.45))
	for i in 10:
		var v := (normal * _rng.randf_range(30.0, 130.0) + _rand_dir() * 60.0)
		_add(K.SPLINTER, pos, v, _rng.randf_range(0.5, 1.1), _rng.randf_range(2.0, 4.5), 0.0, Color("8a5a32"), 2.2)
	for i in 3:
		_add(K.SMOKE, pos, _rand_dir() * 20.0, _rng.randf_range(0.8, 1.5), 7.0, 12.0, Color(0.35, 0.33, 0.3, 0.5), 1.5)


func fire(pos: Vector2, intensity: float = 1.0) -> void:
	_add(K.FIRE, pos + _rand_dir() * 4.0, wind * 2.0 + _rand_dir() * 8.0, _rng.randf_range(0.35, 0.7), _rng.randf_range(4.0, 7.0) * intensity, -4.0, Color(1.0, 0.55, 0.15, 0.9), 1.0)
	if _rng.randf() < 0.5:
		_add(K.SMOKE, pos, wind * 4.0 + _rand_dir() * 10.0, _rng.randf_range(1.5, 2.8), 6.0 * intensity, 18.0, Color(0.18, 0.17, 0.17, 0.45), 0.6)
	if _rng.randf() < 0.2:
		_add(K.EMBER, pos, wind * 3.0 + _rand_dir() * 30.0, 0.8, 1.6, 0.0, Color(1, 0.6, 0.2), 1.0)


func smoke_trail(pos: Vector2) -> void:
	_add(K.SMOKE, pos, wind * 5.0 + _rand_dir() * 6.0, _rng.randf_range(1.8, 3.0), 7.0, 16.0, Color(0.3, 0.3, 0.3, 0.35), 0.5)


func explosion(pos: Vector2, scale_f: float = 1.0) -> void:
	_add(K.FLASH, pos, Vector2.ZERO, 0.25, 30.0 * scale_f, 140.0 * scale_f, Color(1, 0.75, 0.35))
	for i in int(24 * scale_f):
		_add(K.FIRE, pos + _rand_dir() * 10.0, _rand_dir() * _rng.randf_range(30.0, 140.0) * scale_f, _rng.randf_range(0.4, 0.9), _rng.randf_range(6.0, 12.0) * scale_f, 6.0, Color(1, 0.55, 0.15, 0.95), 2.2)
	for i in int(16 * scale_f):
		_add(K.SMOKE, pos + _rand_dir() * 16.0, _rand_dir() * _rng.randf_range(20.0, 80.0) * scale_f + wind * 3.0, _rng.randf_range(1.6, 3.2), 12.0 * scale_f, 26.0, Color(0.16, 0.15, 0.15, 0.6), 1.2)
	for i in int(18 * scale_f):
		_add(K.SPLINTER, pos, _rand_dir() * _rng.randf_range(60.0, 220.0) * scale_f, _rng.randf_range(0.7, 1.4), _rng.randf_range(3.0, 6.0), 0.0, Color("7a4d2a"), 1.8)


func debris(pos: Vector2, count: int, spread: float) -> void:
	for i in count:
		_add(K.DEBRIS, pos + _rand_dir() * _rng.randf_range(0.0, spread), _rand_dir() * _rng.randf_range(5.0, 30.0), _rng.randf_range(6.0, 11.0), _rng.randf_range(4.0, 9.0), 0.0, Color("6e4a2c"), 0.4)


func bubbles(pos: Vector2, radius: float) -> void:
	_add(K.BUBBLE, pos + _rand_dir() * _rng.randf_range(0.0, radius), Vector2.ZERO, _rng.randf_range(0.5, 1.1), _rng.randf_range(2.0, 5.0), 6.0, Color(0.85, 0.95, 1.0, 0.7))


func ring(pos: Vector2, color: Color, radius: float = 40.0) -> void:
	_add(K.SPLASH_RING, pos, Vector2.ZERO, 0.6, 6.0, radius * 1.6, color)


func text(pos: Vector2, s: String, color: Color = Color.WHITE, size: int = 22, life: float = 1.4) -> void:
	var t := FloatText.new()
	t.pos = pos
	t.text = s
	t.color = color
	t.life = life
	t.max_life = life
	t.size = size
	_texts.append(t)


# --- Update / draw ----------------------------------------------------------------------

func tick(dt: float) -> void:
	var i := 0
	while i < _parts.size():
		var p := _parts[i]
		p.life -= dt
		if p.life <= 0.0:
			_parts[i] = _parts[_parts.size() - 1]
			_parts.pop_back()
			continue
		p.vel *= maxf(0.0, 1.0 - p.drag * dt)
		p.pos += p.vel * dt
		p.size = maxf(0.2, p.size + p.grow * dt)
		p.rot += dt * 3.0
		i += 1
	i = 0
	while i < _texts.size():
		var t := _texts[i]
		t.life -= dt
		t.pos.y -= 26.0 * dt
		if t.life <= 0.0:
			_texts.remove_at(i)
			continue
		i += 1
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var a := clampf(p.life / p.max_life, 0.0, 1.0)
		var c := p.color
		match p.kind:
			K.SMOKE, K.FOAM:
				c.a *= a
				draw_circle(p.pos, p.size, c)
			K.FLASH:
				c.a *= a
				draw_circle(p.pos, p.size, c)
				draw_circle(p.pos, p.size * 0.5, Color(1, 1, 0.85, c.a))
			K.SPLASH_RING:
				c.a *= a
				draw_arc(p.pos, p.size, 0.0, TAU, 28, c, 2.5, true)
			K.DROPLET, K.SPARK, K.EMBER, K.BUBBLE:
				c.a *= a
				if p.kind == K.BUBBLE:
					draw_arc(p.pos, p.size, 0.0, TAU, 10, c, 1.2, true)
				else:
					draw_circle(p.pos, p.size, c)
			K.FIRE:
				c = c.lerp(Color(1.0, 0.95, 0.5), a * 0.6)
				c.a *= a
				draw_circle(p.pos, p.size, c)
			K.SPLINTER, K.DEBRIS:
				c.a *= minf(1.0, a * 3.0)
				var d := Vector2.from_angle(p.rot) * p.size
				var w := Vector2(-d.y, d.x).normalized() * (1.4 if p.kind == K.SPLINTER else 2.4)
				draw_colored_polygon(PackedVector2Array([p.pos - d - w, p.pos + d - w, p.pos + d + w, p.pos - d + w]), c)
	for t in _texts:
		var a := clampf(t.life / t.max_life * 2.0, 0.0, 1.0)
		var sz := _font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.size)
		var at := t.pos - Vector2(sz.x * 0.5, 0)
		draw_string_outline(_font, at, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.size, 5, Color(0, 0, 0, 0.8 * a))
		draw_string(_font, at, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.size, Color(t.color, t.color.a * a))
