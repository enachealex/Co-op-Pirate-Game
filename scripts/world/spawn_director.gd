class_name SpawnDirector
extends Node
## Wave / spawn manager (spec 7 + step 4). Keeps convoys moving along the trade
## lanes, sends roaming hunter squadrons as notoriety grows, and fields the
## current bounty captain with escorts.

class Group:
	extends RefCounted
	var kind := "convoy"             # "convoy", "hunters", "bounty"
	var ships: Array = []
	var leader: Node = null
	var alerted := false

	func alert(t: Node, _from: Node) -> void:
		alerted = true
		for s in ships:
			if is_instance_valid(s):
				s.on_group_alert(t)

	func on_member_lost(s: Node) -> void:
		if kind == "bounty" and s.is_bounty:
			# The captain is gone: the escorts break off and run for the sector edge.
			for o in ships:
				if is_instance_valid(o) and o != s and not o.sinking:
					o.retreat()
		if s == leader:
			leader = null
			for o in ships:
				if is_instance_valid(o) and o != s and not o.sinking and not o.disabled:
					leader = o
					break

	func on_member_disabled(s: Node) -> void:
		if s == leader:
			for o in ships:
				if is_instance_valid(o) and o != s and not o.sinking and not o.disabled:
					leader = o
					return

	func all_close(ldr: Node) -> bool:
		for s in ships:
			if is_instance_valid(s) and s != ldr and not s.sinking and not s.disabled:
				if s.global_position.distance_to(ldr.global_position) > 70.0 * U.M:
					return false
		return true

	func alive_count() -> int:
		var n := 0
		for s in ships:
			if is_instance_valid(s) and not s.removed and not s.sinking:
				n += 1
		return n

var world: Node
var groups: Array[Group] = []
var bounty_ship: EnemyShip = null
var _convoy_timer := 6.0
var _hunter_timer := 90.0
var _bounty_timer := 25.0
var _rng := RandomNumberGenerator.new()


func setup(p_world: Node) -> void:
	world = p_world
	_rng.randomize()


func max_convoys() -> int:
	return mini(2 + int(GameManager.notoriety / 2), 4)


func tick(dt: float) -> void:
	# Drop finished groups / escaped ships
	for g in groups.duplicate():
		for s in g.ships.duplicate():
			if not is_instance_valid(s) or s.removed:
				g.ships.erase(s)
			elif s.escaped:
				s.removed = true
				world.remove_ship(s)
				g.ships.erase(s)
		if g.ships.is_empty():
			groups.erase(g)
	var convoys := 0
	for g in groups:
		if g.kind == "convoy":
			convoys += 1
	_convoy_timer -= dt
	if convoys < max_convoys() and _convoy_timer <= 0.0:
		spawn_convoy()
		_convoy_timer = _rng.randf_range(10.0, 20.0)
	var hunter_groups := 0
	for g in groups:
		if g.kind == "hunters":
			hunter_groups += 1
	if GameManager.notoriety >= 2 and hunter_groups < 1 + int(GameManager.notoriety / 3):
		_hunter_timer -= dt
		if _hunter_timer <= 0.0:
			_hunter_timer = maxf(60.0, 150.0 - 15.0 * GameManager.notoriety)
			spawn_hunters()
	if bounty_ship == null or not is_instance_valid(bounty_ship) or bounty_ship.removed or bounty_ship.sinking or bounty_ship.state == EnemyShip.AI.PRIZE:
		bounty_ship = null
		_bounty_timer -= dt
		if _bounty_timer <= 0.0:
			_bounty_timer = 30.0
			spawn_bounty()


func _make_ship(template: String, pos: Vector2, rot: float, hp_bonus: float = 1.0) -> EnemyShip:
	var s := EnemyShip.new()
	s.setup_enemy(template, GameManager.notoriety, world, hp_bonus)
	s.position = pos
	s.rotation = rot
	s.velocity = Vector2.from_angle(rot) * float(s.stats["max_speed"]) * 0.6
	world.add_ship(s)
	return s


func spawn_convoy() -> void:
	var lanes: Array = world.lanes
	if lanes.is_empty():
		return
	var lane: Array = lanes[_rng.randi() % lanes.size()].duplicate()
	if _rng.randf() < 0.5:
		lane.reverse()
	var start: Vector2 = lane[0]
	var dir: Vector2 = (lane[1] - lane[0]).normalized()
	var n := GameManager.notoriety
	var comp: Array = []
	# Merchants
	comp.append("treasure" if n >= 3 and _rng.randf() < 0.35 else "merchant")
	if _rng.randf() < 0.5 + 0.1 * n:
		comp.append("merchant")
	# Escorts scale with notoriety
	var escorts := 1 + int(n / 2) + (1 if _rng.randf() < 0.4 else 0)
	for i in mini(escorts, 4):
		var roll := _rng.randf() + 0.12 * n
		comp.append("frigate" if roll > 1.25 else ("brig" if roll > 0.7 else "cutter"))
	if n >= 5 and _rng.randf() < 0.3:
		comp.append("manowar")
	var g := Group.new()
	g.kind = "convoy"
	var offsets := [Vector2(0, 0), Vector2(26, -22), Vector2(26, 22), Vector2(52, 0), Vector2(-26, -26), Vector2(-26, 26), Vector2(78, 0)]
	var lane_typed: Array[Vector2] = []
	for p in lane:
		lane_typed.append(p)
	# Escorts lead and flank, merchants sail in the middle.
	comp.sort_custom(func(a, b): return ShipDB.ENEMIES[a]["role"] == "escort" and ShipDB.ENEMIES[b]["role"] != "escort")
	for i in comp.size():
		var off: Vector2 = offsets[mini(i, offsets.size() - 1)] * U.M
		var pos: Vector2 = start - dir * off.x + Vector2(-dir.y, dir.x) * off.y
		var s := _make_ship(comp[i], pos, dir.angle())
		s.group = g
		s.lane = lane_typed
		s.wp = 1
		s.formation = off
		g.ships.append(s)
	g.leader = g.ships[0]
	groups.append(g)


func spawn_hunters() -> void:
	var g := Group.new()
	g.kind = "hunters"
	var start := _edge_point()
	var target_pos: Vector2 = world.port.global_position
	for p in world.players:
		if is_instance_valid(p) and p.is_active():
			target_pos = p.global_position
			break
	var dir := (target_pos - start).normalized()
	var count := 2 + int(GameManager.notoriety / 3)
	var route: Array[Vector2] = world.random_route(start, 5)
	for i in mini(count, 4):
		var t := "frigate" if i == 0 and GameManager.notoriety >= 4 else ("brig" if i < 2 else "cutter")
		var off := Vector2(30.0 * i, (i % 2 * 2 - 1) * 20.0 * i) * U.M
		var pos := start - dir * off.x + Vector2(-dir.y, dir.x) * off.y
		var s := _make_ship(t, pos, dir.angle())
		s.role = "hunter"
		s.group = g
		s.lane = route
		s.loop_lane = true
		s.wp = 0
		s.formation = off
		g.ships.append(s)
	g.leader = g.ships[0]
	groups.append(g)
	GameManager.notify(-1, "An Armada hunter squadron has entered the sector!", Color("ff8a7a"))


func spawn_bounty() -> void:
	var b := GameManager.current_bounty()
	var g := Group.new()
	g.kind = "bounty"
	var start := _edge_point()
	var route: Array[Vector2] = world.random_route(start, 6)
	var dir := (route[0] - start).normalized()
	var boss := _make_ship(b["template"], start, dir.angle(), float(b["hp_mult"]))
	boss.make_bounty(b["captain"], b["ship"])
	boss.gold_reward = int(boss.gold_reward * 1.5)
	boss.crate_count += 2
	boss.group = g
	boss.lane = route
	boss.loop_lane = true
	g.ships.append(boss)
	var escorts: Array = b["escorts"]
	for i in escorts.size():
		var off := Vector2(28.0 + 14.0 * i, (22.0 if i % 2 == 0 else -22.0)) * U.M
		var pos := start - dir * off.x + Vector2(-dir.y, dir.x) * off.y
		var s := _make_ship(escorts[i], pos, dir.angle())
		s.group = g
		s.lane = route
		s.loop_lane = true
		s.formation = off
		g.ships.append(s)
	g.leader = boss
	groups.append(g)
	bounty_ship = boss
	GameManager.banner.emit("NEW BOUNTY", "%s aboard the %s  -  %s gold reward" % [b["captain"], b["ship"], U.fmt_gold(int(b["reward"]))])


func _edge_point() -> Vector2:
	var m := 300.0
	var sz := U.WORLD_SIZE
	for attempt in 20:
		var p: Vector2
		match _rng.randi() % 4:
			0: p = Vector2(_rng.randf_range(m, sz.x - m), m)
			1: p = Vector2(_rng.randf_range(m, sz.x - m), sz.y - m)
			2: p = Vector2(m, _rng.randf_range(m, sz.y - m))
			_: p = Vector2(sz.x - m, _rng.randf_range(m, sz.y - m))
		var far := true
		for pl in world.players:
			if is_instance_valid(pl) and pl.global_position.distance_to(p) < 110.0 * U.M:
				far = false
		if far and world.island_at(p, 200.0) == null:
			return p
	return Vector2(m, m)
