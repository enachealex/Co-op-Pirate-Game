class_name World
extends Node2D
## World (spec 3): ocean, islands, Haven, forts, ships, projectiles, loot and
## effects. Owns the per-frame simulation order and all collision handling.
## It lives in its own hidden SubViewport; both player SubViewports share its World2D.

const LANE_MARGIN := 280.0
const FORT_NAMES: Array[String] = ["Fort Grimhold", "Fort Saltmarsh", "Fort Blackrock", "Fort Gallowspoint"]

var time := 0.0
var rng := RandomNumberGenerator.new()
var ocean: Ocean
var wakes: Wakes
var loot: Loot
var projectiles: Projectiles
var effects: Effects
var entity_layer: Node2D
var islands: Array[Island] = []
var forts: Array[Fort] = []
var port: Port
var lanes: Array = []                 # Array of Array[Vector2]
var ships: Array[Ship] = []
var players: Array[PlayerShip] = []
var enemies: Array[EnemyShip] = []
var targets: Array = []
var director: SpawnDirector
var _ram_cd := {}


func build(seed_value: int) -> void:
	rng.seed = seed_value
	ocean = Ocean.new()
	add_child(ocean)
	wakes = Wakes.new()
	wakes.world = self
	add_child(wakes)
	var island_layer := Node2D.new()
	island_layer.name = "Islands"
	add_child(island_layer)
	loot = Loot.new()
	loot.world = self
	add_child(loot)
	entity_layer = Node2D.new()
	entity_layer.name = "Entities"
	add_child(entity_layer)
	projectiles = Projectiles.new()
	projectiles.world = self
	add_child(projectiles)
	effects = Effects.new()
	add_child(effects)

	_make_lanes()
	# Haven, the allied port
	port = Port.new()
	port.setup(self, U.WORLD_SIZE * Vector2(0.44, 0.56), rng)
	island_layer.add_child(port.island)
	islands.append(port.island)
	island_layer.add_child(port)
	# Armada forts
	var fort_count := 3
	var attempts := 0
	while forts.size() < fort_count and attempts < 400:
		attempts += 1
		var r := rng.randf_range(24.0, 29.0) * U.M
		var p := Vector2(rng.randf_range(700.0, U.WORLD_SIZE.x - 700.0), rng.randf_range(700.0, U.WORLD_SIZE.y - 700.0))
		if not _site_ok(p, r, 2400.0, 320.0):
			continue
		var fort_ok := true
		for f in forts:
			if f.global_position.distance_to(p) < 2600.0:
				fort_ok = false
		if not fort_ok:
			continue
		var isl := Island.new()
		isl.setup(p, r, rng, "fort", 0.5)
		island_layer.add_child(isl)
		islands.append(isl)
		var fort := Fort.new()
		fort.setup(self, isl, FORT_NAMES[forts.size()])
		island_layer.add_child(fort)
		forts.append(fort)
	# Wild islands
	attempts = 0
	var wild := 0
	while wild < 15 and attempts < 1200:
		attempts += 1
		var r := rng.randf_range(11.0, 32.0) * U.M
		var p := Vector2(rng.randf_range(400.0, U.WORLD_SIZE.x - 400.0), rng.randf_range(400.0, U.WORLD_SIZE.y - 400.0))
		if not _site_ok(p, r, 1250.0, 260.0):
			continue
		var isl := Island.new()
		isl.setup(p, r, rng, "wild", 1.0)
		island_layer.add_child(isl)
		islands.append(isl)
		wild += 1
	director = SpawnDirector.new()
	director.name = "SpawnDirector"
	director.setup(self)


func _site_ok(p: Vector2, r: float, port_clear: float, gap: float) -> bool:
	if p.distance_to(port.global_position) < Port.SAFE_RADIUS + r + port_clear * 0.25 + 200.0:
		return false
	for isl in islands:
		if isl.position.distance_to(p) < isl.max_radius + r * 1.3 + gap:
			return false
	for lane in lanes:
		for i in lane.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, lane[i], lane[i + 1])
			if q.distance_to(p) < r * 1.3 + 300.0:
				return false
	return true


func _make_lanes() -> void:
	var W := U.WORLD_SIZE.x
	var H := U.WORLD_SIZE.y
	var m := LANE_MARGIN
	var jitter := func(v: Vector2) -> Vector2: return v + Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
	lanes = [
		[Vector2(m, H * 0.2), jitter.call(Vector2(W * 0.3, H * 0.16)), jitter.call(Vector2(W * 0.62, H * 0.3)), Vector2(W - m, H * 0.22)],
		[Vector2(W * 0.8, m), jitter.call(Vector2(W * 0.74, H * 0.38)), jitter.call(Vector2(W * 0.84, H * 0.66)), Vector2(W * 0.72, H - m)],
		[Vector2(m, H * 0.82), jitter.call(Vector2(W * 0.3, H * 0.9)), jitter.call(Vector2(W * 0.6, H * 0.78)), Vector2(W - m, H * 0.88)],
		[Vector2(W * 0.14, m), jitter.call(Vector2(W * 0.2, H * 0.45)), jitter.call(Vector2(W * 0.12, H * 0.7)), Vector2(W * 0.24, H - m)],
	]


func start(n_players: int) -> void:
	for i in n_players:
		var p := PlayerShip.new()
		p.setup(i, InputRouter.get_player(i), GameManager.profile(i), self)
		var sp: Array = port.spawn_transform(i)
		p.position = sp[0]
		p.rotation = sp[1]
		entity_layer.add_child(p)
		ships.append(p)
		players.append(p)
		var ov := AimOverlay.new()
		ov.setup(self, p)
		add_child(ov)
	for i in 2:
		director.spawn_convoy()


# --- Registry & queries --------------------------------------------------------------------

func add_ship(s: Ship) -> void:
	s.world = self
	entity_layer.add_child(s)
	ships.append(s)
	if s is EnemyShip:
		enemies.append(s)


func remove_ship(s: Ship) -> void:
	ships.erase(s)
	if s is EnemyShip:
		enemies.erase(s)
	if not (s is PlayerShip):
		s.queue_free()


func teammate_of(p: PlayerShip) -> PlayerShip:
	for o in players:
		if o != p and is_instance_valid(o) and o.is_active():
			return o
	return null


func island_at(p: Vector2, margin: float = 0.0) -> Island:
	for isl in islands:
		if isl.contains(p, margin):
			return isl
	return null


func find_boardable(p: PlayerShip) -> Ship:
	var best: Ship = null
	var best_d := U.BOARDING_RADIUS
	for e in enemies:
		if not is_instance_valid(e) or not e.is_hittable() or not e.disabled:
			continue
		if e.global_position.distance_to(p.global_position) > e.bound_radius() + p.bound_radius() + U.BOARDING_RADIUS:
			continue
		var d := p.hull_distance_to(e)
		if d <= best_d:
			best_d = d
			best = e
	return best


## Contested crew check odds for everyone currently boarding (or about to board) target.
func boarding_odds(target: Ship, extra: PlayerShip = null) -> float:
	var boarders: Array = []
	for p in players:
		if p.boarding_target == target or p == extra:
			boarders.append(p)
	var power := 0.0
	for p in boarders:
		power += float(p.crew) * (0.6 + 0.4 * p.hull_ratio())
	if boarders.size() > 1:
		power *= 1.25
	var enemy_power := float(target.crew) * (0.35 if target.get("surrendered") else 1.0)
	return power / maxf(1.0, power + enemy_power)


func resolve_boarding(target: Ship) -> void:
	var boarders: Array[PlayerShip] = []
	for p in players:
		if p.boarding_target == target:
			boarders.append(p)
	if boarders.is_empty():
		return
	var chance := boarding_odds(target)
	for p in boarders:
		p.boarding_target = null
		p.boarding_t = 0.0
	if rng.randf() < chance:
		_capture(target as EnemyShip, boarders)
	else:
		for p in boarders:
			var lost := int(ceil(p.crew * 0.3))
			p.crew = maxi(1, p.crew - lost)
			p.hp = maxf(1.0, p.hp - float(p.stats["max_hp"]) * 0.05)
			GameManager.notify(p.idx, "Boarders repelled! Lost %d crew (odds were %d%%). Try again!" % [lost, int(chance * 100.0)], Color("ff8a7a"))
		target.crew = maxi(1, int(target.crew * 0.65))
		Sfx.at("clash", target.global_position, 0.0)


func _capture(target: EnemyShip, boarders: Array[PlayerShip]) -> void:
	var lead := boarders[0]
	var gold := target.gold_reward * 2
	GameManager.add_gold(gold, lead.idx, "- captured the %s!" % target.display_name)
	# Immediate cargo loot, shared across the boarding crews' holds
	var goods := target.crate_count + (2 if target.rich else 0)
	var k := 0
	for i in goods:
		var value := rng.randi_range(35, 70) * (2 if target.rich else 1)
		var placed := false
		for j in boarders.size():
			var b: PlayerShip = boarders[(k + j) % boarders.size()]
			if b.profile.cargo.size() < int(b.stats["hold"]):
				b.profile.cargo.append(value)
				placed = true
				break
		k += 1
		if not placed:
			loot.spawn(target.global_position, Loot.Kind.CARGO, value, 60.0)
	# Consumable repair materials
	var kits := 1 + (1 if target.rich or target.is_bounty else 0)
	lead.profile.repair_kits = mini(ShipDB.MAX_REPAIR_KITS, lead.profile.repair_kits + kits)
	lead.profile.captured += 1
	for b in boarders:
		b.crew = maxi(1, b.crew - int(b.crew * 0.1))
	effects.text(target.global_position + Vector2(0, -40), "CAPTURED!", Color("7dff9a"), 30, 2.0)
	GameManager.notify(-1, "%s captured the %s! +%d cargo, +%d repair kit%s" % [lead.display_name, target.display_name, goods, kits, "" if kits == 1 else "s"], Color("7dff9a"))
	Sfx.at("bell", target.global_position, 0.0)
	GameManager.register_capture(lead.idx)
	if target.is_bounty:
		GameManager.bounty_claimed(lead.idx, true)
	if target.group != null:
		target.group.on_member_lost(target)
	target.become_prize(lead.idx)


# --- Simulation ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	time += dt
	for p in players:
		p.control_tick(dt)
	for e in enemies.duplicate():
		if is_instance_valid(e) and not e.removed:
			e.ai_tick(dt)
	for s in ships.duplicate():
		if is_instance_valid(s) and s.is_active():
			s.physics_tick(dt)
	_collisions()
	_tow_constraints(dt)
	_bounds(dt)
	port.tick(dt)
	for f in forts:
		f.tick(dt)
	targets.clear()
	for s in ships:
		if is_instance_valid(s) and s.is_active():
			targets.append(s)
	for f in forts:
		targets.append(f)
	projectiles.tick(dt)
	loot.tick(dt)
	effects.tick(dt)
	wakes.tick(dt)
	director.tick(dt)


func _collidable(s: Ship) -> bool:
	return is_instance_valid(s) and s.is_active() and not s.sinking


func _collisions() -> void:
	var n := ships.size()
	for i in n:
		var a := ships[i]
		if not _collidable(a):
			continue
		# Ship vs island
		for c in a.hull_circles():
			for isl in islands:
				var pen := isl.penetration(c[0], c[1])
				if pen.is_empty():
					continue
				var nrm: Vector2 = pen["normal"]
				a.position += nrm * float(pen["depth"])
				var vn := a.velocity.dot(nrm)
				if vn < 0.0:
					a.velocity -= nrm * vn * 1.3
					if -vn > 4.5 * U.M and a is PlayerShip:
						a.take_damage(-vn / U.M * 1.5, {"kind": "ram", "pos": c[0], "dir": nrm})
		# Ship vs ship
		for j in range(i + 1, n):
			var b := ships[j]
			if not _collidable(b):
				continue
			if a.global_position.distance_squared_to(b.global_position) > pow(a.bound_radius() + b.bound_radius(), 2):
				continue
			var best_ov := 0.0
			var best_n := Vector2.RIGHT
			var contact := Vector2.ZERO
			for ca in a.hull_circles():
				for cb in b.hull_circles():
					var d: Vector2 = (cb[0] as Vector2) - (ca[0] as Vector2)
					var dist := d.length()
					var ov: float = float(ca[1]) + float(cb[1]) - dist
					if ov > best_ov:
						best_ov = ov
						best_n = d / dist if dist > 0.01 else Vector2.RIGHT
						contact = (ca[0] as Vector2) + best_n * float(ca[1])
			if best_ov <= 0.0:
				continue
			var ma := a.mass()
			var mb := b.mass()
			a.position -= best_n * best_ov * (mb / (ma + mb))
			b.position += best_n * best_ov * (ma / (ma + mb))
			var rel := (b.velocity - a.velocity).dot(best_n)
			if rel < 0.0:
				var jimp := -(1.25) * rel / (1.0 / ma + 1.0 / mb)
				a.velocity -= best_n * jimp / ma
				b.velocity += best_n * jimp / mb
				_ram(a, b, -rel, best_n, contact)


## Ramming damage: bow-on impacts hurt the other ship far more than the rammer.
func _ram(a: Ship, b: Ship, closing: float, n: Vector2, contact: Vector2) -> void:
	if closing < 2.5 * U.M or a.team == b.team or a.team == U.Team.NEUTRAL or b.team == U.Team.NEUTRAL:
		return
	var key := "%d_%d" % [a.get_instance_id(), b.get_instance_id()]
	if float(_ram_cd.get(key, -10.0)) > time - 0.7:
		return
	_ram_cd[key] = time
	var base := closing / U.M * 2.0
	var a_bow := a.forward().dot(n) > 0.55
	var b_bow := b.forward().dot(-n) > 0.55
	var to_b := base * sqrt(a.mass()) * (float(a.stats["ram_mult"]) if a_bow else 0.5)
	var to_a := base * sqrt(b.mass()) * (float(b.stats["ram_mult"]) if b_bow else 0.5)
	if a_bow:
		to_a *= 0.4 * (1.0 - float(a.stats["ram_resist"]))
	if b_bow:
		to_b *= 0.4 * (1.0 - float(b.stats["ram_resist"]))
	b.take_damage(to_b, {"kind": "ram", "source": a, "player_idx": a.player_idx, "pos": contact, "dir": n})
	a.take_damage(to_a, {"kind": "ram", "source": b, "player_idx": b.player_idx, "pos": contact, "dir": -n})
	if (a_bow and a is PlayerShip) or (b_bow and b is PlayerShip):
		effects.text(contact + Vector2(0, -24), "RAMMED!", Color("ffb347"), 24, 1.2)
	effects.explosion(contact, 0.35)
	Sfx.at("hit", contact, 2.0)


## Tow-line rope constraint (spec 6: Towing & Repair).
func _tow_constraints(dt: float) -> void:
	for p in players:
		var m := p.tow_target
		if m == null:
			continue
		if not is_instance_valid(m) or not m.is_active() or m.sinking or not m.dismasted or not p.is_active() or p.dismasted or p.sinking:
			p.release_tow()
			continue
		var a := p.global_position - p.forward() * p.length() * 0.5
		var b := m.global_position + m.forward() * m.length() * 0.5
		var d := a - b
		var dist := d.length()
		if dist > U.TOW_LENGTH * 3.5:
			p.release_tow()
			GameManager.notify(-1, "The tow-line snapped!", Color("ff8a7a"))
			continue
		if dist > U.TOW_LENGTH:
			var nrm := d / dist
			var excess := dist - U.TOW_LENGTH
			m.position += nrm * excess * 0.85
			p.position -= nrm * excess * 0.15
			var vrel := (m.velocity - p.velocity).dot(nrm)
			if vrel < 0.0:
				m.velocity -= nrm * vrel * 0.9
				p.velocity += nrm * vrel * 0.1
			m.angular_velocity += U.angle_diff(m.rotation, nrm.angle()) * 2.0 * dt


func _bounds(dt: float) -> void:
	var soft := U.WORLD_EDGE_SOFT
	for s in ships:
		if not _collidable(s):
			continue
		if s is EnemyShip and s.state == EnemyShip.AI.PATROL and not s.loop_lane:
			continue
		var p := s.position
		var push := Vector2.ZERO
		if p.x < soft: push.x += soft - p.x
		if p.y < soft: push.y += soft - p.y
		if p.x > U.WORLD_SIZE.x - soft: push.x -= p.x - (U.WORLD_SIZE.x - soft)
		if p.y > U.WORLD_SIZE.y - soft: push.y -= p.y - (U.WORLD_SIZE.y - soft)
		if push != Vector2.ZERO:
			s.velocity += push.normalized() * minf(push.length() * 1.6, 220.0) * dt
		s.position = s.position.clamp(Vector2(-120, -120), U.WORLD_SIZE + Vector2(120, 120))


## Random open-water route used by hunters and bounty captains.
func random_route(start: Vector2, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var tries := 0
	while out.size() < count and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(600.0, U.WORLD_SIZE.x - 600.0), rng.randf_range(600.0, U.WORLD_SIZE.y - 600.0))
		if island_at(p, 260.0) != null or port.in_safe_zone(p, 300.0):
			continue
		var prev: Vector2 = start if out.is_empty() else out[out.size() - 1]
		if prev.distance_to(p) < 1400.0:
			continue
		out.append(p)
	if out.is_empty():
		out.append(U.WORLD_SIZE * 0.5)
	return out
