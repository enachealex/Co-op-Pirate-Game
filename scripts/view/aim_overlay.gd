class_name AimOverlay
extends Node2D
## Per-player world overlay: broadside firing arcs with reload fill, the
## auto-aim lead reticle, mouse aim line and boardable-target highlight.
## Its visibility_layer is private to its player, so the other split-screen
## view never renders it.

var world: Node
var ship: PlayerShip
var _t := 0.0


func setup(p_world: Node, p_ship: PlayerShip) -> void:
	world = p_world
	ship = p_ship
	visibility_layer = 2 << ship.idx
	z_index = -1
	name = "AimOverlay_P%d" % (ship.idx + 1)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if ship == null or not is_instance_valid(ship) or not ship.is_active() or ship.sinking or ship.dismasted:
		return
	if not GameManager.settings.get("show_arcs", true):
		return
	var col: Color = U.PLAYER_COLORS[ship.idx]
	var pos := ship.global_position
	for side in ["port", "starboard", "bow"]:
		var bat: Battery = ship.batteries[side]
		if bat.count == 0:
			continue
		var facing := bat.world_angle()
		var r := bat.max_range
		var prog := bat.progress()
		var ready := bat.is_ready()
		var a0 := facing - bat.arc
		var a1 := facing + bat.arc
		# Faint wedge, brighter when loaded
		var fill_r := r * prog
		if fill_r > 4.0:
			var fan := PackedVector2Array([pos])
			for i in 17:
				fan.append(pos + Vector2.from_angle(lerpf(a0, a1, i / 16.0)) * fill_r)
			draw_colored_polygon(fan, Color(col, 0.055 if ready else 0.03))
		draw_arc(pos, r, a0, a1, 24, Color(col, 0.5 if ready else 0.16), 2.0, true)
		draw_line(pos + Vector2.from_angle(a0) * ship.beam() * 0.6, pos + Vector2.from_angle(a0) * r, Color(col, 0.16), 1.0, true)
		draw_line(pos + Vector2.from_angle(a1) * ship.beam() * 0.6, pos + Vector2.from_angle(a1) * r, Color(col, 0.16), 1.0, true)
		if ready:
			var aim := ship.auto_aim(bat)
			if absf(float(aim[0])) > 0.0001 or float(aim[1]) < r - 1.0:
				var p: Vector2 = pos + Vector2.from_angle(facing + float(aim[0])) * float(aim[1])
				var pulse := 1.0 + 0.15 * sin(_t * 8.0)
				draw_arc(p, 14.0 * pulse, 0, TAU, 20, Color(col, 0.9), 2.0, true)
				draw_line(p - Vector2(20, 0), p - Vector2(8, 0), Color(col, 0.9), 2.0)
				draw_line(p + Vector2(8, 0), p + Vector2(20, 0), Color(col, 0.9), 2.0)
				draw_line(p - Vector2(0, 20), p - Vector2(0, 8), Color(col, 0.9), 2.0)
				draw_line(p + Vector2(0, 8), p + Vector2(0, 20), Color(col, 0.9), 2.0)
	# Mouse aim line (keyboard + mouse player only)
	if ship.input and ship.input.uses_mouse and ship.view:
		var m: Vector2 = ship.view.mouse_world()
		var d := m - pos
		if d.length() > 30.0:
			var n := int(d.length() / 24.0)
			for i in n:
				if i % 2 == 0:
					draw_line(pos + d * (float(i) / n), pos + d * (float(i + 1) / n), Color(1, 1, 1, 0.25), 1.5)
			draw_arc(m, 9.0, 0, TAU, 16, Color(1, 1, 1, 0.5), 1.5, true)
	# Boardable highlight
	var b: Ship = world.find_boardable(ship)
	if b != null:
		var pr := b.length() * 0.6 + 8.0 * sin(_t * 6.0)
		draw_arc(b.global_position, pr, 0, TAU, 32, Color(1, 0.85, 0.3, 0.8), 3.0, true)
	# Tow hint for a dismasted teammate
	var mate: PlayerShip = world.teammate_of(ship)
	if mate != null and mate.dismasted and mate.towed_by == null:
		draw_arc(mate.global_position, mate.length() * 0.7 + 6.0 * sin(_t * 5.0), 0, TAU, 32, Color(0.55, 0.9, 1.0, 0.8), 3.0, true)
