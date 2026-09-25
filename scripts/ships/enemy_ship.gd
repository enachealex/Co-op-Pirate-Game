class_name EnemyShip
extends Ship
## Hostile AI ship driven by a finite state machine (spec 7):
##   PATROL           - cruise trade-lane waypoints in convoy formation
##   ALERT            - target inside the 75 m detection radius, close to firing range
##   BROADSIDE_ENGAGE - lead the target, turn the beam onto it, fire inside +-25 deg,
##                      tack away while both batteries reload
##   FLEE / SURRENDER - hull < 15%: limp away while allies live, otherwise strike colours
##   PRIZE            - captured by boarding; sails off under the players' flag

enum AI { PATROL, ALERT, BROADSIDE_ENGAGE, FLEE, SURRENDER, PRIZE }

const THINK_INTERVAL := 0.35
const STATE_NAMES := ["PATROL", "ALERT", "ENGAGE", "FLEE", "SURRENDER", "PRIZE"]

var template_id := "cutter"
var role := "escort"               # "escort", "merchant", "bounty", "hunter"
var group = null                   # SpawnDirector.Group (untyped: inner class)
var lane: Array[Vector2] = []
var wp := 0
var formation := Vector2.ZERO      # x = along lane (behind leader), y = lateral offset
var loop_lane := false
var state: int = AI.PATROL
var target: Ship = null
var threat := {}                   # player idx -> accumulated threat
var gold_reward := 50
var crate_count := 1
var rich := false
var is_bounty := false
var disabled := false
var surrendered := false
var escaped := false
var _think := 0.0
var _lost_t := 0.0
var _side := 1.0                   # +1 = keep target on starboard, -1 = port
var _avoid_bias := 1.0
var _prize_t := 0.0
var _desired := 0.0
var _abandon_t := 0.0


func setup_enemy(p_template: String, notoriety: int, p_world: Node, hp_bonus: float = 1.0) -> void:
	template_id = p_template
	world = p_world
	team = U.Team.ENEMY
	var t: Dictionary = ShipDB.ENEMIES[template_id]
	role = t["role"]
	gold_reward = int(round(float(t["gold"]) * (1.0 + 0.1 * notoriety)))
	crate_count = int(t["crates"])
	rich = bool(t.get("cargo_rich", false))
	setup_stats(ShipDB.build_enemy_stats(template_id, notoriety, hp_bonus))
	display_name = String(stats["name"])
	aim_error = maxf(0.03, 0.1 - 0.008 * notoriety)
	if role == "merchant":
		sail_color = Color("dccaa4")
		stripe_color = Color("8a6a40")
		hull_color = Color("7b5a3a")
		flag_color = Color("e0b040")
	else:
		sail_color = Color("f1ece0")
		stripe_color = Color("2f4f8f")
		hull_color = Color("4f3726")
		flag_color = Color("2f4f8f")
	sail_index = 3


func make_bounty(captain: String, ship_name: String) -> void:
	is_bounty = true
	role = "bounty"
	display_name = "%s (%s)" % [ship_name, captain]
	sail_color = Color("2b2b30")
	stripe_color = Color("c02a2a")
	hull_color = Color("2e2320")
	flag_color = Color("c02a2a")
	aim_error *= 0.7


func is_hittable() -> bool:
	return is_active() and not sinking and state != AI.PRIZE


# --- AI tick ------------------------------------------------------------------------------

func ai_tick(dt: float) -> void:
	if sinking:
		return
	if state == AI.PRIZE:
		_prize_tick(dt)
		return
	for k in threat.keys():
		threat[k] *= maxf(0.0, 1.0 - 0.08 * dt)
	_think -= dt
	if _think <= 0.0:
		_think = THINK_INTERVAL + randf() * 0.1
		_decide()
	match state:
		AI.PATROL:
			_patrol(dt)
		AI.ALERT:
			_alert(dt)
		AI.BROADSIDE_ENGAGE:
			_engage(dt)
		AI.FLEE:
			_flee(dt)
		AI.SURRENDER:
			sail_index = 1
			thrust_mult = 0.0
			steer_input = 0.0
	if disabled:
		_abandon_tick(dt)


## A disabled ship nobody comes back for eventually limps out of the sector,
## so it stops holding a convoy slot.
func _abandon_tick(dt: float) -> void:
	var near := false
	for p in world.players:
		if is_instance_valid(p) and p.is_active() and p.global_position.distance_to(global_position) < U.DETECTION_RADIUS * 2.0:
			near = true
			break
	_abandon_t = 0.0 if near else _abandon_t + dt
	if _abandon_t > 25.0:
		escaped = true


func _decide() -> void:
	if state == AI.PRIZE:
		return
	# Disabled below 15% hull (spec 5 boarding + spec 7 FLEE / SURRENDER)
	if hull_ratio() < U.DISABLE_THRESHOLD:
		if not disabled:
			disabled = true
			for b in batteries.values():
				b.cancel()
				b.enabled = false
			world.effects.text(global_position + Vector2(0, -40), "DISABLED", Color("d0d0d0"), 18)
			if group != null:
				group.on_member_disabled(self)
		if _allies_fighting():
			state = AI.FLEE
		else:
			if state != AI.SURRENDER:
				white_flag = true
				surrendered = true
				world.effects.text(global_position + Vector2(0, -60), "STRUCK COLOURS", Color.WHITE, 20)
			state = AI.SURRENDER
		return
	var best := _pick_target()
	if best != null:
		_lost_t = 0.0
		if target != best:
			target = best
			if group != null:
				group.alert(best, self)
		if state == AI.PATROL:
			state = AI.ALERT
	elif target != null:
		var keep := is_instance_valid(target) and target.is_hittable() and not _target_in_safe_zone(target)
		if keep and global_position.distance_to(target.global_position) < U.DETECTION_RADIUS * 1.7:
			_lost_t = 0.0
		else:
			_lost_t += THINK_INTERVAL
			if _lost_t > 5.0 or not keep:
				_drop_target()
	if state == AI.ALERT and target != null and role != "merchant":
		var d := global_position.distance_to(target.global_position)
		if d < float(stats["range"]) * 1.05:
			state = AI.BROADSIDE_ENGAGE
	elif state == AI.BROADSIDE_ENGAGE and target != null:
		var d := global_position.distance_to(target.global_position)
		if d > float(stats["range"]) * 1.5:
			state = AI.ALERT


func _drop_target() -> void:
	target = null
	_lost_t = 0.0
	state = AI.PATROL
	_rejoin_lane()


## Threat-weighted target selection (spec 6: distraction / aggro).
func _pick_target() -> Ship:
	var best: Ship = null
	var best_score := -INF
	for p in world.players:
		if not is_instance_valid(p) or not p.is_hittable() or _target_in_safe_zone(p):
			continue
		var d: float = global_position.distance_to(p.global_position)
		var th: float = float(threat.get(p.idx, 0.0))
		var detect := U.DETECTION_RADIUS
		if d > detect and not (th > 1.0 and d < detect * 1.8):
			continue
		var score: float = th * 1.0 + (1.0 - d / (detect * 1.8)) * 20.0 + float(p.stats["threat"]) * 12.0
		if p.dismasted:
			score -= 60.0
		if p == target:
			score += 8.0     # hysteresis
		if score > best_score:
			best_score = score
			best = p
	return best


func _target_in_safe_zone(t: Ship) -> bool:
	return world.port != null and world.port.in_safe_zone(t.global_position)


func _allies_fighting() -> bool:
	if group == null:
		return false
	for s in group.ships:
		if s != self and is_instance_valid(s) and not s.sinking and not s.disabled and s.state != AI.PRIZE:
			return true
	return false


func _on_damaged(dmg: float, info: Dictionary, _crit: bool) -> void:
	var src = info.get("source")
	if src is PlayerShip:
		var p: PlayerShip = src
		threat[p.idx] = float(threat.get(p.idx, 0.0)) + dmg * float(p.stats["threat"])
		if target == null and not disabled:
			target = p
			state = AI.ALERT
			if group != null:
				group.alert(p, self)


## Group-wide alert from a convoy mate.
func on_group_alert(t: Ship) -> void:
	if disabled or state == AI.PRIZE or not is_instance_valid(t):
		return
	if target == null:
		target = t
		if state == AI.PATROL:
			state = AI.ALERT


# --- Behaviours -----------------------------------------------------------------------------

func _patrol(dt: float) -> void:
	if lane.is_empty():
		sail_index = 2
		_steer_to(rotation, dt)
		return
	var goal := _formation_point()
	if global_position.distance_to(goal) < 34.0 * U.M:
		wp += 1
		if wp >= lane.size():
			if loop_lane:
				wp = 0
			else:
				escaped = true
				return
		goal = _formation_point()
	# Keep formation: slow down when ahead of the slot, speed up when behind.
	var to_goal := goal - global_position
	sail_index = 3
	if group != null and group.leader != self and is_instance_valid(group.leader) \
			and not group.leader.disabled and not group.leader.sinking:
		var slot: Vector2 = group.leader.global_position + _formation_offset_world(group.leader.rotation)
		var ahead := forward().dot(global_position - slot)
		if ahead > 30.0:
			sail_index = 2
		to_goal = (slot + group.leader.forward() * 200.0) - global_position
	elif group != null and group.leader == self:
		sail_index = 3 if group.all_close(self) else 2
	_steer_to(_avoid(to_goal.angle()), dt)


func _formation_offset_world(lead_rot: float) -> Vector2:
	return Vector2(-formation.x, formation.y).rotated(lead_rot)


func _formation_point() -> Vector2:
	return lane[mini(wp, lane.size() - 1)]


func _rejoin_lane() -> void:
	if lane.is_empty():
		return
	var best := 0
	var best_d := INF
	for i in lane.size():
		var d := global_position.distance_to(lane[i])
		if d < best_d:
			best_d = d
			best = i
	wp = mini(best + 1, lane.size() - 1) if not loop_lane else (best + 1) % lane.size()


func _alert(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		_drop_target()
		return
	var to := target.global_position - global_position
	if role == "merchant":
		# Merchants run: away from the threat, but keep heading roughly down the lane.
		var away := (-to).normalized()
		var lane_dir := forward()
		if not lane.is_empty():
			lane_dir = (_formation_point() - global_position).normalized()
		var h := (away * 1.4 + lane_dir).angle()
		sail_index = 3
		_steer_to(_avoid(h), dt)
		_opportunistic_fire()
		return
	sail_index = 3
	# Head for a point off the target's beam at optimal range
	var optimal := float(stats["range"]) * 0.7
	var desired := to.angle() + _side * deg_to_rad(35.0) * clampf(optimal / maxf(1.0, to.length()), 0.0, 1.0)
	_steer_to(_avoid(desired), dt)
	_opportunistic_fire()


func _engage(dt: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_hittable():
		_drop_target()
		return
	var dist := global_position.distance_to(target.global_position)
	var tof := dist / maxf(1.0, float(stats["muzzle_speed"]))
	var lead: Vector2 = target.global_position + (target.velocity - velocity) * tof
	var to_lead := lead - global_position
	var bearing := to_lead.angle()
	var port_b: Battery = batteries["port"]
	var star_b: Battery = batteries["starboard"]
	# Which beam currently points closer to the target?
	var rel := U.angle_diff(rotation, bearing)          # + = target on starboard
	var natural := 1.0 if rel > 0.0 else -1.0
	var ready_star := star_b.is_ready()
	var ready_port := port_b.is_ready()
	if ready_star and not ready_port:
		_side = 1.0
	elif ready_port and not ready_star:
		_side = -1.0
	elif ready_port and ready_star:
		_side = natural
	var optimal := float(stats["range"]) * 0.68
	var band := float(stats["range"]) * 0.22
	var h: float
	if not ready_port and not ready_star and dist < optimal * 1.15:
		# Both batteries reloading: tack away to open the range (spec 7).
		h = bearing + PI - _side * deg_to_rad(40.0)
		sail_index = 3
	else:
		# Turn perpendicular so the chosen battery bears; correct the range.
		var k := clampf((dist - optimal) / band, -1.0, 1.0)
		h = bearing - _side * PI * 0.5 + _side * k * deg_to_rad(38.0)
		sail_index = 3 if dist > optimal * 1.25 else 2
	_steer_to(_avoid(h), dt)
	# Fire inside the +-25 degree alignment window
	for side in ["port", "starboard"]:
		var bat: Battery = batteries[side]
		if not bat.is_ready():
			continue
		var off := U.angle_diff(bat.world_angle(), bearing)
		if absf(off) < U.AI_FIRE_WINDOW and dist < float(stats["range"]) * 1.05:
			bat.fire(off, to_lead.length() + target.aim_radius())
	if batteries["bow"].count > 0 and batteries["bow"].is_ready():
		var off2 := U.angle_diff(rotation, bearing)
		if absf(off2) < deg_to_rad(15.0) and dist < float(stats["chaser_range"]):
			batteries["bow"].fire(off2, to_lead.length())


func _opportunistic_fire() -> void:
	if target == null:
		return
	var dist := global_position.distance_to(target.global_position)
	if dist > float(stats["range"]) * 1.05:
		return
	for side in ["port", "starboard"]:
		var bat: Battery = batteries[side]
		if not bat.is_ready():
			continue
		var off := U.angle_diff(bat.world_angle(), (target.global_position - global_position).angle())
		if absf(off) < U.AI_FIRE_WINDOW:
			bat.fire(off, dist + target.aim_radius())


func _flee(dt: float) -> void:
	thrust_mult = 0.35
	sail_index = 2
	var threat_pos := global_position + forward() * 100.0
	var nearest := INF
	for p in world.players:
		if is_instance_valid(p) and p.is_hittable():
			var d: float = global_position.distance_to(p.global_position)
			if d < nearest:
				nearest = d
				threat_pos = p.global_position
	var away := (global_position - threat_pos).angle()
	_steer_to(_avoid(away), dt)
	if not _allies_fighting():
		_decide()


## Captured prize sails toward Haven, then disappears (crew takes it home).
func become_prize(by_idx: int) -> void:
	state = AI.PRIZE
	team = U.Team.NEUTRAL
	white_flag = false
	flag_color = U.PLAYER_COLORS[by_idx]
	sail_color = U.PLAYER_COLORS[by_idx].lerp(Color.WHITE, 0.5)
	thrust_mult = 0.6
	sail_index = 2
	hp = maxf(hp, 1.0)
	show_bar = false
	_prize_t = 0.0
	for b in batteries.values():
		b.cancel()
		b.enabled = false


func _prize_tick(dt: float) -> void:
	_prize_t += dt
	if world.port != null:
		_steer_to(_avoid((world.port.global_position - global_position).angle()), dt)
	modulate.a = clampf(1.0 - (_prize_t - 7.0) / 2.0, 0.0, 1.0)
	if _prize_t > 9.0 and not removed:
		removed = true
		world.remove_ship(self)


# --- Steering helpers -------------------------------------------------------------------------

func _steer_to(desired: float, _dt: float) -> void:
	desired = _separate(desired)
	_desired = desired
	var diff := U.angle_diff(rotation, desired)
	steer_input = clampf(diff * 2.4 - angular_velocity * 0.9, -1.0, 1.0)


## Separation: bend the heading away from ships that are crowding this one.
func _separate(desired: float) -> float:
	var push := Vector2.ZERO
	for s in world.ships:
		if s == self or not is_instance_valid(s) or not s.is_active() or s.sinking:
			continue
		var d: Vector2 = global_position - s.global_position
		var min_d: float = (bound_radius() + s.bound_radius()) * 1.1
		var dl := d.length()
		if dl < min_d and dl > 0.01:
			push += d / dl * (1.0 - dl / min_d)
	if push == Vector2.ZERO:
		return desired
	return (Vector2.from_angle(desired) + push * 1.8).angle()


## Obstacle avoidance: probe along the desired heading and swing it away from
## islands, the storm border and Haven's safe zone.
func _avoid(desired: float) -> float:
	var probes := [0.0, deg_to_rad(25.0), deg_to_rad(-25.0), deg_to_rad(50.0), deg_to_rad(-50.0),
		deg_to_rad(80.0), deg_to_rad(-80.0), deg_to_rad(115.0), deg_to_rad(-115.0), deg_to_rad(160.0)]
	var look: float = length() * 0.8 + maxf(0.0, forward_speed()) * 2.2 + 60.0
	for i in probes.size():
		var swing: float = float(probes[i]) * _avoid_bias
		var a: float = desired + swing
		if _clear_along(a, look):
			if i > 0:
				_avoid_bias = signf(swing)   # remember the side that worked (stops dithering)
			return a
	return desired + PI * 0.5


func _clear_along(angle: float, look: float) -> bool:
	var d := Vector2.from_angle(angle)
	var margin := beam() * 0.8 + 10.0
	for f in [0.35, 0.7, 1.0]:
		var p: Vector2 = global_position + d * look * float(f)
		if not U.in_world(p, 120.0) and not _heading_out_ok():
			return false
		if world.island_at(p, margin) != null:
			return false
		if world.port != null and state != AI.PRIZE and world.port.in_safe_zone(p, 60.0):
			return false
	return true


func _heading_out_ok() -> bool:
	# Convoys on their final waypoint are allowed to sail off the map edge.
	return state == AI.PATROL and not lane.is_empty() and wp >= lane.size() - 1 and not loop_lane


## Leave the sector via the nearest edge (used when a bounty captain falls).
func retreat() -> void:
	var p := global_position
	var sz := U.WORLD_SIZE
	var m := 280.0
	var options := [Vector2(p.x, m), Vector2(p.x, sz.y - m), Vector2(m, p.y), Vector2(sz.x - m, p.y)]
	var best: Vector2 = options[0]
	for o in options:
		if p.distance_to(o) < p.distance_to(best):
			best = o
	var route: Array[Vector2] = [best]
	lane = route
	wp = 0
	loop_lane = false
	role = "escort" if role != "merchant" else role
	if not disabled:
		target = null
		state = AI.PATROL


# --- Rewards --------------------------------------------------------------------------------

func _on_sunk(info: Dictionary) -> void:
	var by := int(info.get("player_idx", -1))
	if by < 0 and maxf(last_hit_by[0], last_hit_by[1]) >= 0.0:
		# Credit whoever dealt the most recent hit.
		by = 0 if last_hit_by[0] >= last_hit_by[1] else 1
		if by >= GameManager.player_count:
			by = 0
	world.loot.drop_for(global_position, crate_count, gold_reward, rich)
	GameManager.register_sink(by)
	if by >= 0:
		GameManager.notify(-1, "%s sunk the %s!" % [U.PLAYER_NAMES[by], display_name], Color("ffd34d"))
	else:
		GameManager.notify(-1, "Haven's shore batteries sank the %s!" % display_name, Color("ffd34d"))
	if is_bounty:
		GameManager.bounty_claimed(by, false)
	if group != null:
		group.on_member_lost(self)


func _draw_tags(bar_y: float, _bar_w: float) -> void:
	if is_bounty:
		draw_label("BOUNTY: " + display_name, Vector2(0, bar_y - 6), 16, Color("ff8a7a"))
	elif surrendered:
		draw_label("SURRENDERED - board her!", Vector2(0, bar_y - 6), 14, Color.WHITE)
	elif disabled:
		draw_label("DISABLED - board her!", Vector2(0, bar_y - 6), 14, Color("d0d0d0"))
