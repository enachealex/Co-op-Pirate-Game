class_name Ship
extends Node2D
## Base ship: naval kinematics (spec 4), hull hit-testing, damage, sinking,
## gun batteries and procedural top-down rendering. PlayerShip and EnemyShip
## add control on top.

const SINK_TIME := 4.0

var world: Node
var team: int = U.Team.PLAYER
var player_idx := -1                   # >= 0 for player ships
var stats: Dictionary = {}
var hp := 100.0
var crew := 10
var velocity := Vector2.ZERO
var angular_velocity := 0.0
var sail_index := 1
var steer_input := 0.0
var thrust_mult := 1.0
var reload_mult := 1.0                 # >1 = slower reload (e.g. crew losses)
var sinking := false
var sink_t := 0.0
var removed := false
var display_name := ""
var batteries := {}
var last_hit_by: Array[float] = [-100.0, -100.0]
var aim_error := 0.0                   # AI inaccuracy (radians)

# Appearance
var hull_color := Color("6e4526")
var deck_color := Color("b88a55")
var sail_color := Color("efe9dc")
var stripe_color := Color("2f4f8f")
var flag_color := Color("c0392b")
var show_bar := true
var white_flag := false

var _time := 0.0
var _sail_visual := 0.0
var _hit_flash := 0.0
var _smoke_t := 0.0
var _holes: Array = []
var _hull_pts := PackedVector2Array()
var _deck_pts := PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _font: Font
var _ram_cooldown := {}


func _init() -> void:
	_rng.randomize()
	_font = ThemeDB.fallback_font


func setup_stats(p_stats: Dictionary, keep_hp_ratio: bool = false) -> void:
	var ratio := hp / float(stats["max_hp"]) if keep_hp_ratio and not stats.is_empty() else 1.0
	stats = p_stats
	hp = float(stats["max_hp"]) * ratio
	crew = int(stats["crew"])
	for side in ["port", "starboard", "bow"]:
		if not batteries.has(side):
			batteries[side] = Battery.new(self, side)
	batteries["port"].configure(stats["cannons"], stats["reload"], stats["damage"], stats["range"], stats["muzzle_speed"])
	batteries["starboard"].configure(stats["cannons"], stats["reload"], stats["damage"], stats["range"], stats["muzzle_speed"])
	batteries["bow"].configure(int(stats["chasers"]), stats["chaser_reload"], stats["chaser_damage"], stats["chaser_range"], stats["muzzle_speed"] * 1.1)
	_build_hull_shape()
	_holes.clear()


# --- Geometry --------------------------------------------------------------------------

func forward() -> Vector2:
	return Vector2(cos(rotation), sin(rotation))


func starboard_dir() -> Vector2:
	return Vector2(-sin(rotation), cos(rotation))


func length() -> float:
	return float(stats["length"])


func beam() -> float:
	return float(stats["beam"])


func mass() -> float:
	return float(stats["mass"])


func bound_radius() -> float:
	return length() * 0.5 + 4.0


## Three circles along the keel used for ship/ship and ship/island collisions.
func hull_circles() -> Array:
	var f := forward()
	var r := beam() * 0.5
	var L := length()
	return [
		[global_position + f * (L * 0.3), r],
		[global_position, r],
		[global_position - f * (L * 0.3), r],
	]


func is_active() -> bool:
	return not removed and visible


func is_hittable() -> bool:
	return is_active() and not sinking


## Projectile test: inside the hull ellipse and below the freeboard height.
func hit_test(p: Vector2, z: float) -> bool:
	if z > float(stats["freeboard"]):
		return false
	var d := p - global_position
	if d.length_squared() > pow(bound_radius(), 2):
		return false
	var l := d.rotated(-rotation)
	var a := length() * 0.5
	var b := beam() * 0.5 + 1.5
	return (l.x * l.x) / (a * a) + (l.y * l.y) / (b * b) <= 1.0


## Approximate distance between two hulls (edge to edge) using keel circles.
func hull_distance_to(other: Ship) -> float:
	var best := INF
	for ca in hull_circles():
		for cb in other.hull_circles():
			var d: float = (ca[0] as Vector2).distance_to(cb[0]) - float(ca[1]) - float(cb[1])
			best = minf(best, d)
	return best


## Extra splash distance past the target centre so shots straddle the hull.
func aim_radius() -> float:
	return beam() * 0.6


func hull_ratio() -> float:
	return clampf(hp / float(stats["max_hp"]), 0.0, 1.0)


func forward_speed() -> float:
	return forward().dot(velocity)


# --- Kinematics (spec 4 pseudo-implementation) --------------------------------------------

func physics_tick(dt: float) -> void:
	_time += dt
	_hit_flash = maxf(0.0, _hit_flash - dt * 4.0)
	for b in batteries.values():
		b.tick(dt, reload_mult)
	if sinking:
		_sink_tick(dt)
		return
	var max_speed: float = stats["max_speed"]
	var fwd_speed := forward_speed()
	# Rudder effectiveness scales with water flowing past it
	var speed_factor := clampf(absf(fwd_speed) / max_speed, float(stats["min_rudder"]), 1.0)
	var steer := steer_input * (-1.0 if fwd_speed < -4.0 else 1.0)
	var angular_accel := steer * float(stats["turn_rate"]) * speed_factor
	angular_velocity += angular_accel * dt
	angular_velocity *= (1.0 - float(stats["angular_drag"]) * dt)
	rotation += angular_velocity * dt

	# Propulsion
	var target_thrust: float = U.SAIL_STATES[sail_index] * float(stats["thrust"]) * thrust_mult
	var forward_dir := forward()
	var lateral_dir := starboard_dir()
	# Decompose velocity
	var forward_vel := forward_dir * forward_dir.dot(velocity)
	var lateral_vel := lateral_dir * lateral_dir.dot(velocity)
	# Keel cancels most lateral slip, allowing slight drift
	lateral_vel *= (1.0 - float(stats["keel_grip"]) * dt)
	forward_vel += forward_dir * target_thrust * dt
	forward_vel *= (1.0 - float(stats["linear_drag"]) * dt)
	velocity = forward_vel + lateral_vel
	position += velocity * dt

	_sail_visual = move_toward(_sail_visual, U.SAIL_STATES[sail_index] * (1.0 if thrust_mult > 0.05 else 0.0), dt * 1.5)
	_damage_fx(dt)


func _damage_fx(dt: float) -> void:
	var r := hull_ratio()
	if r > 0.6 or not world:
		return
	_smoke_t -= dt
	if _smoke_t <= 0.0:
		_smoke_t = 0.07 if r < 0.35 else 0.18
		var spot := Vector2(_rng.randf_range(-0.3, 0.3) * length(), _rng.randf_range(-0.25, 0.25) * beam())
		var wp := global_position + spot.rotated(rotation)
		if r < 0.35:
			world.effects.fire(wp, 1.0 + (0.35 - r) * 2.0)
		else:
			world.effects.smoke_trail(wp)


# --- Combat ---------------------------------------------------------------------------------

## Called by Battery for each cannon in the staggered salvo.
func discharge_cannon(bat: Battery, slot: int, aim_offset: float, aim_range: float) -> void:
	if sinking or not world:
		return
	var local := bat.muzzle_local(slot)
	var muzzle := global_position + local.rotated(rotation)
	var ang := bat.world_angle() + aim_offset + _rng.randf_range(-0.035, 0.035) + _rng.randf_range(-aim_error, aim_error)
	var dir := Vector2.from_angle(ang)
	var r := aim_range * _rng.randf_range(0.95, 1.05) * (1.0 + _rng.randf_range(-aim_error, aim_error))
	world.projectiles.spawn(muzzle, dir, velocity, bat.muzzle_speed, r, bat.damage, team, self, player_idx, bat.max_range, bat.side == "bow")
	world.effects.muzzle(muzzle, dir, velocity)
	Sfx.at("chaser" if bat.side == "bow" else "cannon", muzzle, -3.0 if bat.side != "bow" else -5.0)
	_on_cannon_fired(bat)


func _on_cannon_fired(_bat: Battery) -> void:
	pass


## Pick the best target inside a battery's arc and return [aim_offset, aim_range].
## Uses a lead vector (target position + velocity * time of flight).
func auto_aim(bat: Battery) -> Array:
	var facing := bat.world_angle()
	var best_score := INF
	var result := [0.0, bat.max_range]
	for t in world.targets:
		if not is_instance_valid(t) or t == self or not t.is_hittable() or t.team == team or t.team == U.Team.NEUTRAL:
			continue
		var to: Vector2 = t.global_position - global_position
		var dist := to.length()
		if dist > bat.max_range * 1.12:
			continue
		var tof := dist / maxf(1.0, bat.muzzle_speed)
		var tv: Vector2 = t.velocity
		var lead: Vector2 = t.global_position + (tv - velocity) * tof
		var to_lead := lead - global_position
		var off := U.angle_diff(facing, to_lead.angle())
		if absf(off) > bat.arc + 0.12:
			continue
		var score := absf(off) * 400.0 + dist
		if score < best_score:
			best_score = score
			result = [clampf(off, -bat.arc, bat.arc), minf(to_lead.length() + float(t.aim_radius()), bat.max_range)]
	return result


func fire_battery(side: String) -> bool:
	var bat: Battery = batteries[side]
	if not bat.is_ready():
		return false
	var aim := auto_aim(bat)
	return bat.fire(aim[0], aim[1])


func take_damage(amount: float, info: Dictionary) -> void:
	if not is_hittable():
		return
	var armor := float(stats["armor"])
	if info.get("kind", "") == "ram":
		armor *= 0.5
	var dmg := amount * float(info.get("falloff", 1.0)) * (1.0 - armor)
	var pidx := int(info.get("player_idx", -1))
	var crit := false
	if pidx >= 0 and team == U.Team.ENEMY and world:
		last_hit_by[pidx] = world.time
		var other := 1 - pidx
		if GameManager.player_count > 1 and world.time - last_hit_by[other] <= U.PINCER_WINDOW:
			dmg *= U.PINCER_MULT
			crit = true
	hp -= dmg
	_hit_flash = 1.0
	var pos: Vector2 = info.get("pos", global_position)
	if world:
		var n: Vector2 = -(info.get("dir", Vector2.ZERO) as Vector2)
		world.effects.hit(pos, n)
		if _holes.size() < 10 and _rng.randf() < 0.6:
			_holes.append((pos - global_position).rotated(-rotation) * 0.85)
		var col := Color("ffd34d") if team == U.Team.ENEMY else Color("ff6b5b")
		if crit:
			world.effects.text(pos + Vector2(0, -30), "PINCER BARRAGE!", Color("ff9f1c"), 20, 1.3)
			col = Color("ff9f1c")
		world.effects.text(pos, str(int(round(dmg))), col, 18 if not crit else 24, 1.0)
	Sfx.at("hit", pos, -4.0)
	if pidx >= 0:
		var prof = GameManager.profile(pidx)
		if prof:
			prof.damage_dealt += dmg
	_on_damaged(dmg, info, crit)
	if hp <= 0.0:
		hp = 0.0
		_on_hull_breached(info)


func _on_damaged(_dmg: float, _info: Dictionary, _crit: bool) -> void:
	pass


func _on_hull_breached(info: Dictionary) -> void:
	sink(info)


func sink(_info: Dictionary = {}) -> void:
	if sinking:
		return
	sinking = true
	sink_t = 0.0
	hp = 0.0
	for b in batteries.values():
		b.cancel()
	if world:
		world.effects.explosion(global_position, 0.6 + length() / 250.0)
		world.effects.debris(global_position, 8 + int(length() / 20.0), length() * 0.4)
	Sfx.at("sink", global_position, 0.0)
	Sfx.at("explosion", global_position, -6.0)
	_on_sunk(_info)


func _on_sunk(_info: Dictionary) -> void:
	pass


func _sink_tick(dt: float) -> void:
	sink_t += dt
	velocity *= maxf(0.0, 1.0 - 1.5 * dt)
	position += velocity * dt
	rotation += angular_velocity * dt
	angular_velocity = angular_velocity * (1.0 - dt) + 0.12 * dt
	if world and _rng.randf() < 0.6:
		world.effects.bubbles(global_position, length() * 0.35 * (1.0 - sink_t / SINK_TIME))
	if sink_t >= SINK_TIME:
		_on_sink_finished()


func _on_sink_finished() -> void:
	removed = true
	if world:
		world.remove_ship(self)


# --- Rendering -------------------------------------------------------------------------------

func _build_hull_shape() -> void:
	_hull_pts = hull_polygon(length(), beam(), String(stats["style"]))
	_deck_pts = PackedVector2Array()
	for p in _hull_pts:
		_deck_pts.append(Vector2(p.x * 0.9 - 1.0, p.y * 0.74))


static func hull_polygon(L: float, B: float, style: String) -> PackedVector2Array:
	var n := 16
	var half := L * 0.5
	var stern_w := 0.72 if style != "fluyt" else 0.5
	var bow_start := 0.5 if style != "galley" else 0.62
	var starboard: Array[Vector2] = []
	for i in n + 1:
		var t := float(i) / n
		var x := lerpf(-half, half, t)
		var w: float
		if t < bow_start:
			var u := t / bow_start
			w = lerpf(stern_w, 1.0, sqrt(u))
		else:
			var u := (t - bow_start) / (1.0 - bow_start)
			w = sqrt(maxf(0.0, 1.0 - u * u))
			if style == "galley":
				w = maxf(w, 0.0)
		starboard.append(Vector2(x, w * B * 0.5))
	var pts := PackedVector2Array()
	for p in starboard:
		pts.append(p)
	for i in range(starboard.size() - 2, 0, -1):
		pts.append(Vector2(starboard[i].x, -starboard[i].y))
	return pts


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if stats.is_empty():
		return
	var L := length()
	var B := beam()
	var sink_f := clampf(sink_t / SINK_TIME, 0.0, 1.0) if sinking else 0.0
	var alpha := 1.0 - sink_f * 0.85
	var sc := 1.0 - sink_f * 0.2
	draw_set_transform(Vector2.ZERO, sink_f * 0.3, Vector2(sc, sc * (1.0 - sink_f * 0.35)))

	# Water shadow cast toward the lower right (world space)
	var sh := Vector2(5, 7).rotated(-rotation)
	var shadow := PackedVector2Array()
	for p in _hull_pts:
		shadow.append(p * 1.04 + sh)
	draw_colored_polygon(shadow, Color(0, 0.05, 0.1, 0.3 * alpha))
	# Bow wave foam
	var spd := clampf(absf(forward_speed()) / float(stats["max_speed"]), 0.0, 1.0)
	if spd > 0.15 and not sinking:
		var fw := Color(1, 1, 1, 0.45 * spd * alpha)
		draw_arc(Vector2(L * 0.42, 0), B * 0.55, -1.2, 1.2, 12, fw, 2.5 + spd * 2.0, true)

	# Oars for the war galley
	if stats["style"] == "galley":
		_draw_oars(L, B, alpha)

	# Hull
	draw_colored_polygon(_hull_pts, _mix_hit(hull_color.darkened(0.35), alpha))
	var inner := PackedVector2Array()
	for p in _hull_pts:
		inner.append(p * Vector2(0.97, 0.9))
	draw_colored_polygon(inner, _mix_hit(hull_color, alpha))
	# Paint stripe
	var stripe := PackedVector2Array()
	for p in _hull_pts:
		stripe.append(p * Vector2(0.95, 0.84))
	draw_polyline(PackedVector2Array(Array(stripe) + [stripe[0]]), Color(stripe_color, 0.9 * alpha), 2.0, true)
	# Deck + planks
	draw_colored_polygon(_deck_pts, _mix_hit(deck_color, alpha))
	var plank_c := Color(deck_color.darkened(0.25), 0.6 * alpha)
	for k in range(-2, 3):
		var y := k * B * 0.12
		draw_line(Vector2(-L * 0.42, y), Vector2(L * 0.3, y), plank_c, 1.0)
	# Iron armor plates for the galley
	if stats["style"] == "galley":
		for k in 5:
			var x := lerpf(-L * 0.35, L * 0.25, k / 4.0)
			draw_rect(Rect2(x - 5, -B * 0.46, 10, 5), Color(0.45, 0.47, 0.5, alpha))
			draw_rect(Rect2(x - 5, B * 0.46 - 5, 10, 5), Color(0.45, 0.47, 0.5, alpha))
		draw_colored_polygon(PackedVector2Array([Vector2(L * 0.5, 0), Vector2(L * 0.5 + 12, -3), Vector2(L * 0.5 + 16, 0), Vector2(L * 0.5 + 12, 3)]), Color(0.72, 0.5, 0.2, alpha))
	# Stern cabin
	draw_rect(Rect2(-L * 0.5 + 3, -B * 0.28, L * 0.13, B * 0.56), Color(hull_color.darkened(0.1), alpha))
	draw_rect(Rect2(-L * 0.5 + 3, -B * 0.28, L * 0.13, B * 0.56), Color(stripe_color, 0.8 * alpha), false, 1.5)
	# Hull damage
	for h in _holes:
		draw_circle(h, 3.2, Color(0.12, 0.07, 0.04, 0.85 * alpha))
	# Cannons
	for side in ["port", "starboard"]:
		var bat: Battery = batteries[side]
		for i in bat.count:
			var m := bat.muzzle_local(i)
			var out := bat.local_dir()
			var recoil := 0.0
			if bat.timer > bat.reload_time - 0.25:
				recoil = 2.5
			draw_line(m - out * (6.0 + recoil), m + out * (4.0 - recoil), Color(0.12, 0.12, 0.13, alpha), 4.5)
	var bow: Battery = batteries["bow"]
	for i in bow.count:
		var m := bow.muzzle_local(i)
		draw_line(m - Vector2(6, 0), m + Vector2(6, 0), Color(0.15, 0.15, 0.16, alpha), 4.0)
	# Bowsprit + jib
	if stats["style"] != "galley":
		var tip := Vector2(L * 0.5 + L * 0.16, 0)
		draw_line(Vector2(L * 0.42, 0), tip, Color("4a2f1a"), 3.0)
		var fore: float = _mast_positions(L)[0]
		if absf(_sail_visual) > 0.08:
			var bulge := B * 0.25 * _sail_visual
			draw_colored_polygon(PackedVector2Array([Vector2(fore, 0), tip, Vector2((fore + tip.x) * 0.5, bulge)]), Color(sail_color.lightened(0.15), 0.95 * alpha))
	# Masts and sails
	var masts := _mast_positions(L)
	for mx in masts:
		_draw_sail(mx, L, B, alpha)
	for mx in masts:
		draw_circle(Vector2(mx, 0), B * 0.11 + 1.0, Color("3b2414"))
		draw_circle(Vector2(mx, 0), B * 0.07, Color("5a3a20"))
	# Flag at the stern-most mast
	_draw_flag(Vector2(masts[masts.size() - 1] - 2.0, 0), alpha)
	# Hit flash
	if _hit_flash > 0.0:
		draw_colored_polygon(_hull_pts, Color(1, 0.9, 0.7, 0.35 * _hit_flash * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_overlay()


func _mix_hit(c: Color, alpha: float) -> Color:
	return Color(c, alpha)


func _mast_positions(L: float) -> Array:
	match int(stats["masts"]):
		1: return [L * 0.06]
		2: return [L * 0.2, -L * 0.14]
	return [L * 0.26, 0.0, -L * 0.25]


func _draw_sail(mx: float, L: float, B: float, alpha: float) -> void:
	var S := B * 1.55
	var yard := Color("4a2f1a")
	var fill := _sail_visual
	if absf(fill) < 0.05:
		# Furled sail on the yard
		draw_line(Vector2(mx, -S * 0.45), Vector2(mx, S * 0.45), Color(sail_color.darkened(0.1), alpha), 5.0)
		draw_line(Vector2(mx, -S * 0.5), Vector2(mx, S * 0.5), yard, 2.0)
		return
	var bulge := L * 0.12 * fill
	var depth := 9.0 + 7.0 * absf(fill)
	var steps := 10
	var front := PackedVector2Array()
	var back := PackedVector2Array()
	var sway := sin(_time * 2.2 + mx) * 0.6
	for i in steps + 1:
		var u := float(i) / steps * 2.0 - 1.0
		var y := u * S * 0.5
		var curve := 1.0 - u * u
		front.append(Vector2(mx + bulge * curve + sway, y))
		back.append(Vector2(mx + bulge * curve * 0.55 - depth * signf(fill + 0.001) * 0.4, y))
	var poly := PackedVector2Array()
	for p in front:
		poly.append(p)
	for i in range(back.size() - 1, -1, -1):
		poly.append(back[i])
	draw_colored_polygon(poly, Color(sail_color, 0.96 * alpha))
	draw_polyline(front, Color(stripe_color, 0.95 * alpha), 2.5, true)
	# Sail seams
	for k in [-0.5, 0.0, 0.5]:
		var y: float = k * S * 0.5
		var c: float = 1.0 - k * k
		draw_line(Vector2(mx + bulge * c * 0.55, y), Vector2(mx + bulge * c, y), Color(sail_color.darkened(0.2), 0.7 * alpha), 1.0)
	draw_line(Vector2(mx, -S * 0.5), Vector2(mx, S * 0.5), yard, 2.0)


func _draw_oars(L: float, B: float, alpha: float) -> void:
	var n := 7
	var sweep := sin(_time * (2.0 + absf(forward_speed()) * 0.03)) * 0.35
	if absf(forward_speed()) < 6.0 and absf(steer_input) < 0.1:
		sweep = 0.0
	for side in [-1.0, 1.0]:
		for i in n:
			var x := lerpf(-L * 0.3, L * 0.3, float(i) / (n - 1))
			var base := Vector2(x, side * B * 0.45)
			var tip := base + Vector2(sweep * 12.0, side * B * 0.55)
			draw_line(base, tip, Color(0.55, 0.38, 0.2, alpha), 2.0)
			draw_line(tip, tip + Vector2(sweep * 4.0, side * 5.0), Color(0.45, 0.3, 0.16, alpha), 4.0)


func _draw_flag(at: Vector2, alpha: float) -> void:
	var col := Color.WHITE if white_flag else flag_color
	var pts := PackedVector2Array()
	var flag_len := 18.0
	var steps := 6
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(at + Vector2(-t * flag_len, sin(_time * 7.0 - t * 4.0) * 2.5 * t - 5.0))
	for i in range(steps, -1, -1):
		var t := float(i) / steps
		pts.append(at + Vector2(-t * flag_len, sin(_time * 7.0 - t * 4.0) * 2.5 * t + 5.0 - t * 4.0))
	draw_colored_polygon(pts, Color(col, alpha))


## Unrotated overlay: health bar, name tags. Subclasses extend.
func _draw_overlay() -> void:
	if sinking or not show_bar:
		return
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var w := clampf(length() * 0.7, 50.0, 120.0)
	var y := -maxf(length(), beam()) * 0.55 - 14.0
	var r := hull_ratio()
	draw_rect(Rect2(-w * 0.5 - 1, y - 1, w + 2, 7), Color(0, 0, 0, 0.6))
	var col := Color("4cd964") if r > 0.5 else (Color("ffcc00") if r > 0.25 else Color("ff3b30"))
	if team == U.Team.ENEMY and r <= U.DISABLE_THRESHOLD:
		col = Color("b0b0b0")
	draw_rect(Rect2(-w * 0.5, y, w * r, 5), col)
	_draw_tags(y, w)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tags(_bar_y: float, _bar_w: float) -> void:
	pass


func draw_label(text: String, at: Vector2, size: int, color: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var p := at - Vector2(sz.x * 0.5, 0)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.75))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
