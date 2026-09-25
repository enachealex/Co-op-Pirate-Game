class_name Port
extends Node2D
## Haven, the allied port (spec step 5): a circular island safe zone with
## docking detection. Enemy AI steers clear of the safe zone and drops targets
## inside it; shore batteries fire on anything hostile that intrudes.

const ISLAND_RADIUS := 26.0 * U.M
const DOCK_RADIUS := 50.0 * U.M
const SAFE_RADIUS := 100.0 * U.M
const DOCK_MAX_SPEED := 6.0 * U.M
const GUN_RANGE := SAFE_RADIUS + 20.0 * U.M

var world: Node
var island: Island
var display_name := "Haven"
var team: int = U.Team.PLAYER
var _towers: Array = []          # [local pos, reload timer, aim angle]
var _t := 0.0
var _font: Font


func setup(p_world: Node, pos: Vector2, rng: RandomNumberGenerator) -> void:
	world = p_world
	position = pos
	z_index = -4
	_font = ThemeDB.fallback_font
	island = Island.new()
	island.setup(pos, ISLAND_RADIUS, rng, "port", 0.25)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		_towers.append([Vector2.from_angle(a) * ISLAND_RADIUS * 0.72, randf() * 2.0, a])


func in_safe_zone(p: Vector2, margin: float = 0.0) -> bool:
	return p.distance_to(global_position) < SAFE_RADIUS + margin


func spawn_transform(idx: int) -> Array:
	var a := PI * 0.5 + (0.35 if idx == 0 else -0.35)
	var p := global_position + Vector2.from_angle(a) * (ISLAND_RADIUS + 16.0 * U.M)
	return [p, a + PI * 0.5]


func tick(dt: float) -> void:
	_t += dt
	for p in world.players:
		if not is_instance_valid(p) or not p.is_active() or p.sinking:
			continue
		var d: float = p.global_position.distance_to(global_position)
		p.in_safe_zone = d < SAFE_RADIUS
		var was: bool = p.docked
		p.docked = d < DOCK_RADIUS and (p.shop_open or p.velocity.length() < DOCK_MAX_SPEED)
		if p.dismasted and p.in_safe_zone:
			p.on_docked()
		if p.docked and not was:
			p.on_docked()
			Sfx.at("bell", global_position, -6.0)
		if not p.docked:
			p.shop_open = false
	# Shore batteries
	for t in _towers:
		t[1] -= dt
		var tp: Vector2 = global_position + t[0]
		var target: Ship = null
		var best := GUN_RANGE
		for e in world.enemies:
			if is_instance_valid(e) and e.is_hittable():
				var d := tp.distance_to(e.global_position)
				if d < best:
					best = d
					target = e
		if target != null:
			var tof := best / (60.0 * U.M)
			var lead: Vector2 = target.global_position + target.velocity * tof
			t[2] = lerp_angle(t[2], (lead - tp).angle(), 1.0 - exp(-6.0 * dt))
			if t[1] <= 0.0:
				t[1] = 2.2
				var dir := Vector2.from_angle(t[2])
				world.projectiles.spawn(tp + dir * 14.0, dir, Vector2.ZERO, 60.0 * U.M, tp.distance_to(lead),
					22.0, U.Team.PLAYER, self, -1, GUN_RANGE)
				world.effects.muzzle(tp + dir * 14.0, dir, Vector2.ZERO)
				Sfx.at("cannon", tp, -6.0)
	if int(_t * 8.0) != int((_t - dt) * 8.0):
		queue_redraw()


func _draw() -> void:
	# Safe-zone ring (dashed) and docking ring
	var n := 64
	for i in n:
		if i % 2 == 0:
			var a0 := TAU * i / n + _t * 0.02
			var a1 := TAU * (i + 1) / n + _t * 0.02
			draw_arc(Vector2.ZERO, SAFE_RADIUS, a0, a1, 4, Color(0.55, 1.0, 0.7, 0.35), 3.0, true)
	draw_arc(Vector2.ZERO, DOCK_RADIUS, 0, TAU, 64, Color(1.0, 0.95, 0.6, 0.18 + 0.08 * sin(_t * 2.0)), 5.0, true)
	# Piers
	for a in [PI * 0.5 + 0.35, PI * 0.5 - 0.35, -PI * 0.5]:
		var d := Vector2.from_angle(a)
		var s := Vector2(-d.y, d.x)
		var p0 := d * ISLAND_RADIUS * 0.85
		var p1 := d * (ISLAND_RADIUS + 11.0 * U.M)
		draw_colored_polygon(PackedVector2Array([p0 - s * 7, p1 - s * 7, p1 + s * 7, p0 + s * 7]), Color("8a6a45"))
		for k in 6:
			var q := p0.lerp(p1, k / 5.0)
			draw_line(q - s * 7, q + s * 7, Color("5f4630"), 1.5)
	# Town (drawn on top of the island node, which renders beneath)
	var roofs := [Color("b5523b"), Color("c8743f"), Color("9c4a3a"), Color("d08a4a")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 16:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.2, 0.62) * ISLAND_RADIUS
		var c := Vector2.from_angle(a) * r
		var w := rng.randf_range(14.0, 22.0)
		var h := rng.randf_range(10.0, 16.0)
		draw_rect(Rect2(c - Vector2(w, h) * 0.5 + Vector2(3, 3), Vector2(w, h)), Color(0, 0, 0, 0.2))
		draw_rect(Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), roofs[i % roofs.size()])
		draw_line(c - Vector2(w * 0.5, 0), c + Vector2(w * 0.5, 0), Color(0, 0, 0, 0.25), 1.5)
	# Lighthouse
	draw_circle(Vector2(0, -ISLAND_RADIUS * 0.1), 13.0, Color("e8e2d0"))
	draw_circle(Vector2(0, -ISLAND_RADIUS * 0.1), 7.0, Color("c0392b"))
	var beam_a := _t * 1.2
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -ISLAND_RADIUS * 0.1),
		Vector2(0, -ISLAND_RADIUS * 0.1) + Vector2.from_angle(beam_a - 0.12) * 260.0,
		Vector2(0, -ISLAND_RADIUS * 0.1) + Vector2.from_angle(beam_a + 0.12) * 260.0]), Color(1, 0.95, 0.6, 0.10))
	# Shore battery towers
	for t in _towers:
		var p: Vector2 = t[0]
		draw_circle(p, 15.0, Color("7d7a72"))
		draw_circle(p, 11.0, Color("9a968c"))
		draw_line(p, p + Vector2.from_angle(t[2]) * 18.0, Color(0.12, 0.12, 0.13), 6.0)
	# Name
	var label := "HAVEN - Depot & Repairs"
	var sz := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string_outline(_font, Vector2(-sz.x * 0.5, ISLAND_RADIUS + 34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.7))
	draw_string(_font, Vector2(-sz.x * 0.5, ISLAND_RADIUS + 34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("fff3c4"))
