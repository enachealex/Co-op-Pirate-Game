class_name Fort
extends Node2D
## Armada coastal fort: raidable target on an island. Its towers lead-aim at
## players inside range. When destroyed it spills loot and is rebuilt later.

const RANGE := 66.0 * U.M
const REBUILD_TIME := 150.0

var world: Node
var island: Island
var team: int = U.Team.ENEMY
var display_name := "Armada Fort"
var max_hp := 600.0
var hp := 600.0
var destroyed := false
var velocity := Vector2.ZERO     # targets expose a velocity for lead aiming
var stats := {"beam": 60.0}
var _towers: Array = []          # [local pos, reload, aim]
var _rebuild_t := 0.0
var _t := 0.0
var _flash := 0.0
var _smoke_t := 0.0
var _font: Font
var _rng := RandomNumberGenerator.new()
var _wall_r := 90.0


func setup(p_world: Node, p_island: Island, fort_name: String) -> void:
	world = p_world
	island = p_island
	display_name = fort_name
	position = island.position
	z_index = -3
	_font = ThemeDB.fallback_font
	_rng.randomize()
	_wall_r = island.min_radius * 0.62
	var n := 4
	for i in n:
		var a := TAU * i / n + 0.4
		_towers.append([Vector2.from_angle(a) * _wall_r, _rng.randf_range(0.0, 3.0), a])
	_reset_hp()


func _reset_hp() -> void:
	max_hp = 650.0 + 120.0 * GameManager.notoriety
	hp = max_hp


func is_hittable() -> bool:
	return not destroyed


func aim_radius() -> float:
	return _wall_r * 0.5


func hit_test(p: Vector2, z: float) -> bool:
	return z < 9.0 * U.M and p.distance_to(global_position) < _wall_r + 14.0


func take_damage(amount: float, info: Dictionary) -> void:
	if destroyed:
		return
	var dmg := amount * float(info.get("falloff", 1.0)) * 0.85
	var pidx := int(info.get("player_idx", -1))
	hp -= dmg
	_flash = 1.0
	var pos: Vector2 = info.get("pos", global_position)
	world.effects.hit(pos, -(info.get("dir", Vector2.ZERO) as Vector2))
	world.effects.text(pos, str(int(round(dmg))), Color("ffd34d"), 18, 1.0)
	Sfx.at("hit", pos, -4.0)
	if pidx >= 0 and GameManager.profile(pidx):
		GameManager.profile(pidx).damage_dealt += dmg
	if hp <= 0.0:
		_destroy(pidx)


func _destroy(by: int) -> void:
	destroyed = true
	hp = 0.0
	_rebuild_t = REBUILD_TIME
	world.effects.explosion(global_position, 2.2)
	for t in _towers:
		world.effects.explosion(global_position + t[0], 1.0)
	Sfx.at("explosion", global_position, 2.0)
	var gold := 350 + 60 * GameManager.notoriety
	var drop_at := global_position + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * (island.max_radius + 40.0)
	world.loot.drop_for(drop_at, 4, 0, true)
	GameManager.add_gold(gold, by, "- %s razed!" % display_name)
	GameManager.banner.emit("FORT RAZED", "%s lies in ruins." % display_name)


func tick(dt: float) -> void:
	_t += dt
	_flash = maxf(0.0, _flash - dt * 4.0)
	if destroyed:
		_rebuild_t -= dt
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = 0.25
			world.effects.smoke_trail(global_position + Vector2.from_angle(_rng.randf_range(0, TAU)) * _rng.randf_range(0, _wall_r))
		if _rebuild_t <= 0.0:
			destroyed = false
			_reset_hp()
			GameManager.notify(-1, "The Armada has rebuilt %s." % display_name, Color("c8c8c8"))
		queue_redraw()
		return
	for t in _towers:
		t[1] -= dt
		var tp: Vector2 = global_position + t[0]
		var target: Ship = null
		var best := RANGE
		for p in world.players:
			if is_instance_valid(p) and p.is_hittable() and not p.dismasted:
				var d := tp.distance_to(p.global_position)
				if d < best:
					best = d
					target = p
		if target == null:
			continue
		var tof := best / (55.0 * U.M)
		var lead: Vector2 = target.global_position + target.velocity * tof
		t[2] = lerp_angle(t[2], (lead - tp).angle(), 1.0 - exp(-4.0 * dt))
		if t[1] <= 0.0 and absf(U.angle_diff(t[2], (lead - tp).angle())) < 0.2:
			t[1] = maxf(2.2, 3.6 - 0.15 * GameManager.notoriety) + _rng.randf_range(0.0, 0.8)
			var dir := Vector2.from_angle(t[2] + _rng.randf_range(-0.06, 0.06))
			var dmg := 13.0 + 1.5 * GameManager.notoriety
			world.projectiles.spawn(tp + dir * 16.0, dir, Vector2.ZERO, 55.0 * U.M, tp.distance_to(lead) * _rng.randf_range(0.92, 1.08),
				dmg, team, self, -1, RANGE)
			world.effects.muzzle(tp + dir * 16.0, dir, Vector2.ZERO)
			Sfx.at("cannon", tp, -4.0)
	queue_redraw()


func _draw() -> void:
	var wall := Color("8b877c") if not destroyed else Color("4a4642")
	var ring := PackedVector2Array()
	for i in 9:
		ring.append(Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * _wall_r)
	var fill := ring.slice(0, 8)
	draw_colored_polygon(fill, Color(0, 0, 0, 0.2))
	draw_polyline(ring, wall, 10.0, true)
	if not destroyed:
		draw_colored_polygon(fill, Color("a39b86").darkened(0.1))
		draw_rect(Rect2(-18, -14, 36, 28), Color("6f6a60"))
		draw_line(Vector2(0, -14), Vector2(0, -44), Color("3b2414"), 3.0)
		var flag := PackedVector2Array([Vector2(0, -44), Vector2(22 + sin(_t * 6.0) * 2.0, -38), Vector2(0, -32)])
		draw_colored_polygon(flag, Color("2f4f8f"))
	for t in _towers:
		var p: Vector2 = t[0]
		draw_circle(p, 17.0, wall.darkened(0.2))
		draw_circle(p, 13.0, wall)
		if not destroyed:
			draw_line(p, p + Vector2.from_angle(t[2]) * 20.0, Color(0.1, 0.1, 0.11), 7.0)
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, _wall_r, Color(1, 0.9, 0.7, 0.2 * _flash))
	# HP bar + label
	var y := -_wall_r - 40.0
	var label := display_name + (" (ruins - rebuilt in %ds)" % int(_rebuild_t) if destroyed else "")
	var sz := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string_outline(_font, Vector2(-sz.x * 0.5, y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.7))
	draw_string(_font, Vector2(-sz.x * 0.5, y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ff9a8a") if not destroyed else Color("aaaaaa"))
	if not destroyed:
		var w := 120.0
		draw_rect(Rect2(-w * 0.5 - 1, y - 1, w + 2, 7), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w * 0.5, y, w * hp / max_hp, 5), Color("ff3b30"))
