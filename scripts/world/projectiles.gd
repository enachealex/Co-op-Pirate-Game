class_name Projectiles
extends Node2D
## Cannonball simulation (spec 5: Projectile Ballistics).
## Each ball carries a horizontal 2D velocity (ship velocity + muzzle velocity)
## plus a height z with vertical speed vz. Gravity (g = 9.8 m/s^2) pulls it
## into a parabolic arc. It hits a hull if it passes over the hull ellipse while
## lower than that ship's freeboard, stops on land, or splashes at z <= 0.

class Ball:
	var pos: Vector2
	var vel: Vector2
	var z: float
	var vz: float
	var damage: float
	var team: int
	var owner_ref: WeakRef
	var player_idx: int = -1
	var traveled := 0.0
	var max_range := 400.0
	var radius := 3.2
	var chaser := false

var world: Node
var balls: Array[Ball] = []


func _ready() -> void:
	z_index = 7


## Fire a ball. Elevation is solved so that a ball over flat water lands at `aim_range`.
func spawn(from: Vector2, horiz_dir: Vector2, ship_vel: Vector2, muzzle_speed: float, aim_range: float,
		damage: float, team: int, owner: Node, player_idx: int, max_range: float, chaser: bool = false) -> void:
	var r := clampf(aim_range, 60.0, max_range)
	# Relative to the gun: range = v^2 sin(2 theta) / g, launched from muzzle height h0.
	var s2 := clampf(r * U.GRAVITY / (muzzle_speed * muzzle_speed), 0.0, 1.0)
	var theta := 0.5 * asin(s2)
	var b := Ball.new()
	b.pos = from
	b.vel = ship_vel + horiz_dir.normalized() * muzzle_speed * cos(theta)
	b.vz = muzzle_speed * sin(theta)
	b.z = 1.2 * U.M
	b.damage = damage
	b.team = team
	b.owner_ref = weakref(owner)
	b.player_idx = player_idx
	b.max_range = max_range
	b.chaser = chaser
	b.radius = 2.6 if chaser else 3.2
	balls.append(b)


func tick(dt: float) -> void:
	var i := 0
	while i < balls.size():
		var b := balls[i]
		var step := b.vel * dt
		b.pos += step
		b.traveled += step.length()
		b.vz -= U.GRAVITY * dt
		b.z += b.vz * dt
		if _resolve(b):
			balls[i] = balls[balls.size() - 1]
			balls.pop_back()
			continue
		i += 1
	queue_redraw()


## Returns true when the ball is consumed.
func _resolve(b: Ball) -> bool:
	# Damage falls off from 100% (inside half range) to 70% at max range.
	var falloff := 1.0 - 0.3 * clampf((b.traveled / b.max_range - 0.5) * 2.0, 0.0, 1.0)
	for t in world.targets:
		if not is_instance_valid(t) or not t.is_hittable() or t.team == b.team:
			continue
		if t.hit_test(b.pos, b.z):
			var owner = b.owner_ref.get_ref()
			var info := {
				"source": owner, "player_idx": b.player_idx, "pos": b.pos,
				"dir": b.vel.normalized(), "kind": "ball", "falloff": falloff,
			}
			t.take_damage(b.damage, info)
			return true
	var isl: Island = world.island_at(b.pos)
	if isl != null and b.z < isl.land_height:
		world.effects.hit(b.pos, -b.vel.normalized())
		return true
	if b.z <= 0.0:
		world.effects.splash(b.pos)
		Sfx.at("splash", b.pos, -10.0)
		return true
	return false


func _draw() -> void:
	for b in balls:
		var h := maxf(b.z, 0.0)
		# Shadow on the water, ball offset "up" the screen by its height.
		draw_circle(b.pos, b.radius * 0.9, Color(0, 0, 0, 0.28))
		var up := b.pos + Vector2(0, -h * 0.9)
		draw_circle(up, b.radius + h * 0.02, Color(0.1, 0.1, 0.11))
		draw_circle(up + Vector2(-0.8, -0.8), b.radius * 0.4, Color(0.55, 0.55, 0.58))
