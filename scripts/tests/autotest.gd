extends Node
## Automated smoke test / demo driver.
##   godot --path . -- --autotest [--duration=90] [--shots=res://screenshots]
## Starts a 2-player voyage, swaps both players' devices for bot inputs,
## exercises docking, the depot, layout toggling, pause, combat, boarding and
## towing, saves screenshots (when rendering) and prints a summary.

class BotInput:
	extends PlayerInput
	var ship: PlayerShip
	var world: Node
	var idle_until := 0.0
	var _frame := 0

	func _init() -> void:
		super(PlayerInput.Scheme.KB_IJKL, 0)

	func describe() -> String:
		return "Bot"

	func poll() -> void:
		_frame += 1
		for a in ACTIONS:
			_prev[a] = _now[a]
			_now[a] = false
		_steer_axis = 0.0
		if ship == null or not is_instance_valid(ship) or not ship.is_active() or world == null:
			return
		if world.time < idle_until:
			return
		if ship.dismasted:
			if ship.profile.repair_kits > 0 and _frame % 30 == 0:
				_now["interact"] = true
			return
		# Pick a target: boardable > nearest hostile > Haven
		var target: Node2D = world.find_boardable(ship)
		if target != null:
			if _frame % 20 == 0:
				_now["board"] = true
			return
		var best: Node2D = null
		var bd := INF
		for e in world.enemies:
			if is_instance_valid(e) and e.is_hittable():
				var d: float = e.global_position.distance_to(ship.global_position)
				if d < bd:
					bd = d
					best = e
		var mate: PlayerShip = world.teammate_of(ship)
		if mate != null and mate.dismasted and mate.towed_by == null:
			best = mate
			bd = mate.global_position.distance_to(ship.global_position)
			if _frame % 20 == 0:
				_now["board"] = true
		if ship.tow_target != null:
			best = world.port
			bd = world.port.global_position.distance_to(ship.global_position)
		if best == null:
			return
		var to: Vector2 = best.global_position - ship.global_position
		var rel := U.angle_diff(ship.rotation, to.angle())
		var desired := 0.0
		if best is EnemyShip:
			var s := signf(rel) if rel != 0.0 else 1.0
			if bd > 420.0:
				desired = s * deg_to_rad(30.0)
			elif bd < 220.0:
				desired = s * deg_to_rad(125.0)
			else:
				desired = s * deg_to_rad(90.0)
			if best.get("disabled"):
				desired = 0.0
			if bd < float(ship.stats["range"]) and _frame % 2 == 0:
				_now["fire_port"] = true
				_now["fire_starboard"] = true
				_now["fire_bow"] = true
		_steer_axis = clampf((rel - desired) * 2.0, -1.0, 1.0)
		var want := 3 if bd > 250.0 else 2
		if ship.sail_index < want and _frame % 12 == 0:
			_now["sail_up"] = true
		elif ship.sail_index > want and _frame % 12 == 0:
			_now["sail_down"] = true


var main: Node
var duration := 90.0
var shots_dir := ""
var _t := 0.0
var _step := 0
var _bots: Array = []
var _rendering := true
var _log: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rendering = DisplayServer.get_name() != "headless"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duration="):
			duration = float(a.split("=")[1])
		elif a.begins_with("--shots="):
			shots_dir = a.split("=")[1]
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots_dir))
	print("[autotest] start (rendering=%s, duration=%.0fs)" % [_rendering, duration])


func _shot(name: String) -> void:
	if not _rendering or shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shots_dir.path_join(name + ".png")
	img.save_png(path)
	print("[autotest] screenshot ", path)


func _process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			if _t > 0.3:
				_shot("00_title")
				_step = 1
		1:
			if _t > 0.6:
				main.menus.show_lobby()
				_step = 2
		2:
			if _t > 0.9:
				_shot("01_lobby")
				_step = 3
		3:
			if _t > 1.2:
				main.start_voyage(2, false)
				for i in 2:
					var b := BotInput.new()
					b.ship = main.world.players[i]
					b.world = main.world
					b.idle_until = 4.0
					InputRouter.players[i] = b
					main.world.players[i].input = b
					_bots.append(b)
				_step = 4
				_t = 0.0
		4:
			if _t > 1.0:
				_check("players docked at spawn", main.world.players[1].docked)
				main.world.players[1].shop_open = true
				_step = 5
		5:
			if _t > 1.6:
				_shot("02_spawn_and_depot")
				main.world.players[1].shop_open = false
				_step = 6
		6:
			if _t > 3.0:
				_stage_combat()
				_step = 7
		7:
			if _t > 9.0:
				_shot("03_engagement")
				_step = 70
		70:
			if _t > 9.3:
				main.toggle_layout()
				_step = 8
		8:
			if _t > 10.0:
				_check("stacked layout active", main.split is VSplitContainer)
				_shot("04_stacked_layout")
				_step = 80
		80:
			if _t > 10.3:
				main.toggle_layout()
				_step = 9
		9:
			if _t > 11.0:
				main.pause()
				_step = 10
		10:
			if _t > 11.5:
				_check("tree paused", get_tree().paused)
				_shot("05_pause_menu")
				_step = 100
		100:
			if _t > 11.8:
				main.resume()
				_step = 11
		11:
			if _t > 24.0:
				_shot("06_battle")
				_step = 12
		12:
			if _t > 26.0:
				_test_dismast_and_tow()
				_step = 13
		13:
			if _t > 30.0:
				_shot("07_tow_line")
				_step = 14
		14:
			if _t > duration:
				_shot("08_final")
				_step = 15
		15:
			if _t > duration + 0.5:
				var failed := _summary()
				get_tree().quit(1 if failed > 0 else 0)


func _check(what: String, ok: bool) -> void:
	var line := "[autotest] %s: %s" % ["PASS" if ok else "FAIL", what]
	_log.append(line)
	print(line)


## Put both players next to the nearest convoy so combat starts quickly.
func _stage_combat() -> void:
	var w: World = main.world
	var target: EnemyShip = null
	for e in w.enemies:
		if is_instance_valid(e) and e.role == "merchant":
			target = e
			break
	if target == null and not w.enemies.is_empty():
		target = w.enemies[0]
	if target == null:
		_check("enemy convoy spawned", false)
		return
	_check("enemy convoy spawned", true)
	var f := target.forward()
	var side := Vector2(-f.y, f.x)
	for i in 2:
		var p: PlayerShip = w.players[i]
		p.global_position = target.global_position + side * (330.0 if i == 0 else -330.0) - f * 120.0
		p.rotation = target.rotation
		p.velocity = f * 60.0
		p.sail_index = 3
		main.views[i].camera.snap()


## Force P2 dismasted near P1 to exercise the tow-line.
func _test_dismast_and_tow() -> void:
	var w: World = main.world
	var p1: PlayerShip = w.players[0]
	var p2: PlayerShip = w.players[1]
	if not p1.is_active() or not p2.is_active():
		_check("tow test skipped (a player is respawning)", true)
		return
	p2.profile.repair_kits = 0
	p2.global_position = p1.global_position - p1.forward() * (p1.length() + 60.0)
	p2.rotation = p1.rotation
	p2.hp = 1.0
	p2.take_damage(999.0, {"kind": "ball", "pos": p2.global_position})
	_check("P2 dismasted", p2.dismasted)
	p1.attach_tow(p2)
	_check("tow-line attached", p1.tow_target == p2 and p2.towed_by == p1)


## Prints the run summary and returns the number of failed checks.
func _summary() -> int:
	var w: World = main.world
	print("[autotest] ---- summary ----")
	print("[autotest] game time %.1fs, treasury %d, total sunk %d, notoriety %d" % [w.time, GameManager.treasury, GameManager.total_sunk, GameManager.notoriety])
	for p in GameManager.profiles:
		print("[autotest] P%d hull=%s sunk=%d captured=%d dmg=%d deaths=%d cargo=%d kits=%d" % [p.idx + 1, p.hull_id, p.sunk, p.captured, int(p.damage_dealt), p.deaths, p.cargo.size(), p.repair_kits])
	print("[autotest] ships=%d enemies=%d balls=%d crates=%d groups=%d forts=%d islands=%d" % [w.ships.size(), w.enemies.size(), w.projectiles.balls.size(), w.loot.crates.size(), w.director.groups.size(), w.forts.size(), w.islands.size()])
	var dealt := 0.0
	for p in GameManager.profiles:
		dealt += p.damage_dealt
	_check("players dealt damage", dealt > 0.0)
	var fails := 0
	for l in _log:
		if l.contains("FAIL"):
			fails += 1
	print("[autotest] result: %s (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", _log.size(), fails])
	return fails
