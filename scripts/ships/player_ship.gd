class_name PlayerShip
extends Ship
## A player-controlled ship. Reads only its own PlayerInput device.
## Handles sail gears, broadsides, the bow chaser, mouse-aimed fire (P1 KB/M),
## context actions (boarding, tow-line, depot, field repair), dismasting,
## sinking and respawning at the allied port.

const DISMAST_TIME := 40.0
const RESPAWN_DELAY := 3.0
const TOW_ATTACH_RADIUS := 16.0 * U.M
const BOARD_TIME := 2.6
const FIELD_REPAIR_TIME := 3.0

var idx := 0
var input: PlayerInput
var profile                      # GameManager.PlayerProfile
var view: Node                   # PlayerView (camera shake, mouse picking)
var dismasted := false
var dismast_timer := 0.0
var respawn_timer := -1.0
var in_safe_zone := false
var docked := false
var shop_open := false
var tow_target: PlayerShip = null
var towed_by: PlayerShip = null
var boarding_target: Ship = null
var boarding_t := 0.0
var repair_t := 0.0
var prompts: Array[String] = []
## Set when the depot closes or the game resumes: the key that confirmed a menu
## choice may double as a fire key, so guns stay silent until fire keys are released.
var fire_lock := false
var _hold_full_warned := 0.0
var _no_chaser_warned := 0.0


func setup(p_idx: int, p_input: PlayerInput, p_profile, p_world: Node) -> void:
	idx = p_idx
	player_idx = p_idx
	input = p_input
	profile = p_profile
	world = p_world
	team = U.Team.PLAYER
	var col: Color = U.PLAYER_COLORS[idx]
	sail_color = col
	stripe_color = col.darkened(0.45)
	flag_color = col
	hull_color = Color("6a4226") if idx == 0 else Color("5b4030")
	display_name = U.PLAYER_NAMES[idx]
	setup_stats(profile.stats())
	crew = int(stats["crew"])


## Re-apply the profile after a depot purchase.
func apply_profile(full_heal: bool = false) -> void:
	var missing := float(stats["max_hp"]) - hp
	var crew_ratio := float(crew) / maxf(1.0, float(stats["crew"]))
	setup_stats(profile.stats())
	hp = float(stats["max_hp"]) if full_heal else clampf(float(stats["max_hp"]) - missing, 1.0, float(stats["max_hp"]))
	crew = int(round(float(stats["crew"]) * crew_ratio))


func is_active() -> bool:
	return visible and respawn_timer < 0.0


func is_hittable() -> bool:
	return is_active() and not sinking


func can_collect() -> bool:
	return is_active() and not sinking


func max_crew() -> int:
	return int(stats["crew"])


# --- Per-frame control -----------------------------------------------------------------------

func control_tick(dt: float) -> void:
	prompts.clear()
	_hold_full_warned = maxf(0.0, _hold_full_warned - dt)
	_no_chaser_warned = maxf(0.0, _no_chaser_warned - dt)
	if respawn_timer >= 0.0:
		respawn_timer -= dt
		if respawn_timer < 0.0:
			respawn()
		return
	if sinking:
		steer_input = 0.0
		return
	if shop_open:
		steer_input = 0.0
		sail_index = 1
		fire_lock = true
		return
	if boarding_target != null:
		steer_input = 0.0
		_boarding_tick(dt)
		return
	steer_input = input.steer()
	if fire_lock and not (input.held("fire_port") or input.held("fire_starboard") \
			or input.held("fire_bow") or input.held("fire_aim")):
		fire_lock = false
	if not dismasted:
		if input.just_pressed("sail_up"):
			sail_index = mini(3, sail_index + 1)
		if input.just_pressed("sail_down"):
			sail_index = maxi(0, sail_index - 1)
	if not dismasted and not fire_lock:
		if input.held("fire_port"):
			_fire("port")
		if input.held("fire_starboard"):
			_fire("starboard")
		if input.just_pressed("fire_bow") or (input.held("fire_bow") and batteries["bow"].count > 0):
			_fire("bow")
		if input.held("fire_aim"):
			_fire_aimed()
	if dismasted:
		sail_index = 1
	_context_actions()
	if repair_t > 0.0:
		repair_t -= dt
		hp = minf(float(stats["max_hp"]), hp + float(stats["max_hp"]) * 0.35 / FIELD_REPAIR_TIME * dt)
		if _rng.randf() < 0.1:
			world.effects.ring(global_position, Color(0.4, 1, 0.5, 0.5), length() * 0.4)


func _fire(side: String) -> void:
	var bat: Battery = batteries[side]
	if bat.count == 0:
		if side == "bow" and _no_chaser_warned <= 0.0:
			_no_chaser_warned = 4.0
			GameManager.notify(idx, "No bow chaser - buy one at the Depot", Color("c8c8c8"))
		return
	if fire_battery(side):
		_on_salvo(bat)


## Keyboard+mouse: left click fires the broadside facing the cursor (or the chaser if ahead).
func _fire_aimed() -> void:
	if view == null:
		return
	var target: Vector2 = view.mouse_world()
	var to := target - global_position
	if to.length() < 8.0:
		return
	var fwd := forward()
	var ang := absf(fwd.angle_to(to))
	var side := "starboard" if fwd.cross(to) > 0.0 else "port"
	if ang < deg_to_rad(25.0) and batteries["bow"].count > 0:
		side = "bow"
	var bat: Battery = batteries[side]
	if not bat.is_ready():
		return
	var off := U.angle_diff(bat.world_angle(), to.angle())
	if bat.fire(off, to.length()):
		_on_salvo(bat)


func _on_salvo(bat: Battery) -> void:
	if view:
		view.shake(2.5 + bat.count * 0.9)
	input.rumble(0.25 + bat.count * 0.06, 0.35 + bat.count * 0.08, 0.18 + bat.count * U.SALVO_STAGGER)


func _context_actions() -> void:
	var mate: PlayerShip = world.teammate_of(self)
	# Tow-line / boarding share the Boarding_Action button.
	if tow_target != null:
		prompts.append("[%s] Cut tow-line" % input.glyph("board"))
		if input.just_pressed("board"):
			release_tow()
	elif mate != null and mate.dismasted and mate.towed_by == null and not dismasted \
			and hull_distance_to(mate) < TOW_ATTACH_RADIUS:
		prompts.append("[%s] Throw tow-line to %s" % [input.glyph("board"), mate.display_name])
		if input.just_pressed("board"):
			attach_tow(mate)
	elif not dismasted:
		var target: Ship = world.find_boardable(self)
		if target != null:
			prompts.append("[%s] Board the %s" % [input.glyph("board"), target.display_name])
			if input.just_pressed("board"):
				start_boarding(target)
	# Interact_Port: depot when docked, repair kit otherwise.
	var kits: int = profile.repair_kits
	if docked:
		prompts.append("[%s] Open the Depot" % input.glyph("interact"))
		if input.just_pressed("interact") and not dismasted:
			shop_open = true
			Sfx.ui("bell", -8.0)
	elif in_safe_zone:
		prompts.append("Sail closer to the harbor to dock")
	elif dismasted:
		if kits > 0:
			prompts.append("[%s] Patch hull with a repair kit (%d)" % [input.glyph("interact"), kits])
			if input.just_pressed("interact"):
				profile.repair_kits -= 1
				restore_from_dismast(0.3, "patched the hull")
	elif hp < float(stats["max_hp"]) * 0.9 and kits > 0 and repair_t <= 0.0:
		prompts.append("[%s] Field repair (%d kit%s)" % [input.glyph("interact"), kits, "" if kits == 1 else "s"])
		if input.just_pressed("interact"):
			profile.repair_kits -= 1
			repair_t = FIELD_REPAIR_TIME
			Sfx.at("repair", global_position, -2.0)


# --- Boarding ----------------------------------------------------------------------------------

func start_boarding(target: Ship) -> void:
	boarding_target = target
	boarding_t = 0.0
	sail_index = 1
	Sfx.at("rope", global_position, -2.0)
	Sfx.at("clash", target.global_position, -3.0)
	GameManager.notify(idx, "Grapples away! Boarding the %s..." % target.display_name, Color("ffd34d"))


func cancel_boarding(reason: String = "") -> void:
	if boarding_target != null and reason != "":
		GameManager.notify(idx, reason, Color("c8c8c8"))
	boarding_target = null
	boarding_t = 0.0


func _boarding_tick(dt: float) -> void:
	var t := boarding_target
	if not is_instance_valid(t) or not t.is_hittable() or not t.get("disabled"):
		cancel_boarding("Boarding called off.")
		return
	velocity *= maxf(0.0, 1.0 - 2.5 * dt)
	t.velocity *= maxf(0.0, 1.0 - 2.5 * dt)
	if hull_distance_to(t) > U.BOARDING_RADIUS * 1.8:
		cancel_boarding("The grapple lines snapped!")
		return
	boarding_t += dt
	if int(boarding_t * 3.0) != int((boarding_t - dt) * 3.0):
		Sfx.at("clash", t.global_position, -8.0)
	prompts.append("Boarding... %d%%" % int(boarding_t / BOARD_TIME * 100.0))
	if boarding_t >= BOARD_TIME:
		world.resolve_boarding(t)


# --- Towing ------------------------------------------------------------------------------------

func attach_tow(mate: PlayerShip) -> void:
	tow_target = mate
	mate.towed_by = self
	Sfx.at("rope", global_position, 0.0)
	GameManager.notify(-1, "%s has %s in tow! Head for Haven." % [display_name, mate.display_name], Color("8fe3ff"))


func release_tow() -> void:
	if tow_target != null and is_instance_valid(tow_target):
		tow_target.towed_by = null
	tow_target = null


# --- Damage / dismasting / respawn -------------------------------------------------------------

func take_damage(amount: float, info: Dictionary) -> void:
	if not is_hittable():
		return
	if dismasted:
		dismast_timer -= 2.5
		_hit_flash = 1.0
		world.effects.hit(info.get("pos", global_position), -(info.get("dir", Vector2.ZERO) as Vector2))
		Sfx.at("hit", global_position, -4.0)
		return
	super.take_damage(amount, info)


func _on_damaged(dmg: float, _info: Dictionary, _crit: bool) -> void:
	if view:
		view.shake(minf(14.0, 3.0 + dmg * 0.35))
	input.rumble(0.4, minf(1.0, 0.3 + dmg * 0.03), 0.25)
	if repair_t > 0.0:
		repair_t = 0.0


func _on_hull_breached(_info: Dictionary) -> void:
	if dismasted:
		return
	dismasted = true
	dismast_timer = DISMAST_TIME
	sail_index = 1
	hp = 0.0
	repair_t = 0.0
	release_tow()
	cancel_boarding()
	for b in batteries.values():
		b.cancel()
	world.effects.explosion(global_position, 0.5)
	Sfx.at("explosion", global_position, -4.0)
	if view:
		view.shake(16.0)
	input.rumble(1.0, 1.0, 0.6)
	var mate: PlayerShip = world.teammate_of(self)
	if mate != null:
		GameManager.notify(-1, "%s is DISMASTED! Tow them to Haven or patch with a repair kit." % display_name, Color("ff6b5b"))
	else:
		GameManager.notify(idx, "DISMASTED! Patch with a repair kit or drift home.", Color("ff6b5b"))


func restore_from_dismast(ratio: float, how: String) -> void:
	if not dismasted:
		return
	dismasted = false
	hp = float(stats["max_hp"]) * ratio
	if towed_by != null and is_instance_valid(towed_by):
		towed_by.release_tow()
	towed_by = null
	Sfx.at("repair", global_position, 0.0)
	GameManager.notify(-1, "%s %s - back under sail!" % [display_name, how], Color("7dff9a"))


func physics_tick(dt: float) -> void:
	if not is_active():
		return
	thrust_mult = 1.0
	if dismasted:
		thrust_mult = 0.0
		dismast_timer -= dt
		if dismast_timer <= 0.0 and not sinking:
			sink({})
	elif shop_open:
		thrust_mult = 0.0
		velocity *= maxf(0.0, 1.0 - 3.0 * dt)
	elif tow_target != null:
		thrust_mult = 0.8
	reload_mult = 1.0 + 0.6 * (1.0 - clampf(float(crew) / maxf(1.0, float(stats["crew"])), 0.0, 1.0))
	for side in ["port", "starboard", "bow"]:
		batteries[side].enabled = not dismasted
	super.physics_tick(dt)


func _on_sunk(_info: Dictionary) -> void:
	release_tow()
	if towed_by != null and is_instance_valid(towed_by):
		towed_by.release_tow()
	towed_by = null
	cancel_boarding()
	shop_open = false
	var lost_cargo: int = profile.cargo_value()
	profile.cargo.clear()
	profile.deaths += 1
	var fee := int(GameManager.treasury * 0.1)
	GameManager.notify(-1, "%s went down with %d gold of cargo!" % [display_name, lost_cargo], Color("ff6b5b"))
	if fee > 0:
		GameManager.add_gold(-fee, idx, "(salvage fee)")


func _on_sink_finished() -> void:
	visible = false
	respawn_timer = RESPAWN_DELAY


func respawn() -> void:
	respawn_timer = -1.0
	sinking = false
	sink_t = 0.0
	dismasted = false
	visible = true
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	sail_index = 1
	var sp: Array = world.port.spawn_transform(idx)
	global_position = sp[0]
	rotation = sp[1]
	setup_stats(profile.stats())
	hp = float(stats["max_hp"])
	crew = int(stats["crew"])
	GameManager.notify(idx, "A new ship awaits you at Haven.", Color("8fe3ff"))


## Called by the Port when this ship enters the docking ring.
func on_docked() -> void:
	crew = int(stats["crew"])
	var value: int = profile.cargo_value()
	if value > 0:
		GameManager.add_gold(value, idx, "(sold %d cargo)" % profile.cargo.size())
		profile.cargo.clear()
		Sfx.ui("coin", -2.0)
	if dismasted:
		restore_from_dismast(0.3, "received emergency repairs at Haven")


func collect(kind: int, value: int, pos: Vector2) -> bool:
	match kind:
		Loot.Kind.GOLD:
			GameManager.add_gold(value, idx)
			world.effects.text(pos, "+%d gold" % value, Color("ffd34d"), 18)
		Loot.Kind.CARGO:
			if profile.cargo.size() >= int(stats["hold"]):
				if _hold_full_warned <= 0.0:
					_hold_full_warned = 5.0
					GameManager.notify(idx, "Cargo hold full! Sell it at Haven.", Color("ffb347"))
				return false
			profile.cargo.append(value)
			world.effects.text(pos, "+cargo (%d)" % value, Color("e8c79a"), 18)
		Loot.Kind.KIT:
			if profile.repair_kits >= ShipDB.MAX_REPAIR_KITS:
				GameManager.add_gold(25, idx)
				world.effects.text(pos, "+25 gold", Color("ffd34d"), 18)
			else:
				profile.repair_kits += 1
				world.effects.text(pos, "+repair kit", Color("7dff9a"), 18)
	Sfx.at("coin", pos, -4.0)
	return true


# --- Rendering ---------------------------------------------------------------------------------

func _draw_tags(bar_y: float, _bar_w: float) -> void:
	var col: Color = U.PLAYER_COLORS[idx]
	draw_label("P%d" % (idx + 1), Vector2(0, bar_y - 6), 18, col)
	if dismasted:
		draw_label("DISMASTED %ds" % int(ceil(dismast_timer)), Vector2(0, -bar_y + 26), 16, Color("ff6b5b"))


func _draw_overlay() -> void:
	super._draw_overlay()
	if not is_active():
		return
	# Ropes are drawn in world space.
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	if tow_target != null and is_instance_valid(tow_target):
		var a := global_position - forward() * length() * 0.5
		var b := tow_target.global_position + tow_target.forward() * tow_target.length() * 0.5
		_draw_rope(a, b, Color("d8c39a"))
	if boarding_target != null and is_instance_valid(boarding_target):
		for k in 3:
			var off := forward() * length() * (0.25 * (k - 1))
			var toff := boarding_target.forward() * boarding_target.length() * (0.25 * (k - 1))
			_draw_rope(global_position + off, boarding_target.global_position + toff, Color("c9b38a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_rope(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var slack := clampf(1.0 - d.length() / U.TOW_LENGTH, 0.0, 1.0) * 14.0 + 2.0
	var n := Vector2(-d.y, d.x).normalized()
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(a + d * t + n * sin(t * PI) * slack)
	draw_polyline(pts, Color(0, 0, 0, 0.4), 4.0, true)
	draw_polyline(pts, col, 2.0, true)
