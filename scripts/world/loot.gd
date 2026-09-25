class_name Loot
extends Node2D
## Floating debris / loot crates (spec 6: "Sunken ships drop floating crates with a
## buoyancy bob effect; either player sailing through them picks them up").

enum Kind { GOLD, CARGO, KIT }

class Crate:
	var pos: Vector2
	var vel: Vector2
	var kind: int
	var value: int
	var t: float
	var life: float
	var phase: float

const LIFETIME := 100.0
const PICKUP_EXTRA := 3.0 * U.M
const MAGNET_RADIUS := 9.0 * U.M

var world: Node
var crates: Array[Crate] = []
var _rng := RandomNumberGenerator.new()
var _font: Font


func _ready() -> void:
	z_index = -2
	_rng.randomize()
	_font = ThemeDB.fallback_font


func spawn(pos: Vector2, kind: int, value: int, burst: float = 60.0) -> void:
	var c := Crate.new()
	c.pos = pos
	c.vel = Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(burst * 0.3, burst)
	c.kind = kind
	c.value = value
	c.t = 0.0
	c.life = LIFETIME
	c.phase = _rng.randf_range(0.0, TAU)
	crates.append(c)


## Scatter the loot of a sunk ship.
func drop_for(pos: Vector2, crate_count: int, gold_value: int, rich: bool) -> void:
	spawn(pos, Kind.GOLD, gold_value, 50.0)
	for i in crate_count:
		var v := _rng.randi_range(35, 70) * (2 if rich else 1)
		spawn(pos, Kind.CARGO, v, 90.0)
	if _rng.randf() < 0.35:
		spawn(pos, Kind.KIT, 1, 70.0)


func tick(dt: float) -> void:
	var i := 0
	while i < crates.size():
		var c := crates[i]
		c.t += dt
		c.life -= dt
		c.vel *= maxf(0.0, 1.0 - 1.4 * dt)
		c.pos += (c.vel + world.effects.wind * 0.6) * dt
		var consumed := false
		if c.life <= 0.0:
			consumed = true
		else:
			for s in world.players:
				if not is_instance_valid(s) or not s.can_collect():
					continue
				var d: float = c.pos.distance_to(s.global_position)
				var reach: float = float(s.stats["length"]) * 0.5 + PICKUP_EXTRA
				if d < reach and c.t > 0.6:
					if s.collect(c.kind, c.value, c.pos):
						consumed = true
						break
				elif d < reach + MAGNET_RADIUS and c.t > 0.6:
					c.vel += (s.global_position - c.pos).normalized() * 140.0 * dt
		if consumed:
			crates[i] = crates[crates.size() - 1]
			crates.pop_back()
			continue
		i += 1
	queue_redraw()


func _draw() -> void:
	for c in crates:
		var bob := sin(c.t * 2.6 + c.phase)
		var s := 1.0 + 0.08 * bob
		var fade := clampf(c.life / 8.0, 0.0, 1.0)
		var rot := c.phase + sin(c.t * 1.3 + c.phase) * 0.35
		draw_set_transform(c.pos, rot, Vector2(s, s))
		draw_circle(Vector2(2, 3), 10.0, Color(0, 0, 0, 0.18 * fade))
		draw_arc(Vector2.ZERO, 13.0 + 2.0 * bob, 0, TAU, 20, Color(1, 1, 1, 0.25 * fade), 1.5, true)
		match c.kind:
			Kind.GOLD:
				draw_rect(Rect2(-9, -6, 18, 12), Color(0.45, 0.28, 0.12, fade))
				draw_rect(Rect2(-9, -6, 18, 5), Color(0.55, 0.35, 0.16, fade))
				draw_rect(Rect2(-9, -6, 18, 12), Color(0.95, 0.78, 0.25, fade), false, 1.5)
				draw_circle(Vector2(0, -1), 2.2, Color(1, 0.85, 0.3, fade))
			Kind.CARGO:
				draw_rect(Rect2(-8, -8, 16, 16), Color(0.62, 0.45, 0.27, fade))
				draw_rect(Rect2(-8, -8, 16, 16), Color(0.35, 0.23, 0.12, fade), false, 1.5)
				draw_line(Vector2(-8, -8), Vector2(8, 8), Color(0.35, 0.23, 0.12, fade), 1.5)
				draw_line(Vector2(8, -8), Vector2(-8, 8), Color(0.35, 0.23, 0.12, fade), 1.5)
			Kind.KIT:
				draw_circle(Vector2.ZERO, 8.5, Color(0.5, 0.33, 0.18, fade))
				draw_arc(Vector2.ZERO, 8.5, 0, TAU, 16, Color(0.25, 0.25, 0.28, fade), 1.5)
				draw_rect(Rect2(-5, -1.6, 10, 3.2), Color(0.3, 0.9, 0.45, fade))
				draw_rect(Rect2(-1.6, -5, 3.2, 10), Color(0.3, 0.9, 0.45, fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
