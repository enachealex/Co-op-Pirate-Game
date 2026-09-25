class_name Battery
extends RefCounted
## One gun battery (port / starboard broadside or bow chasers).
## Broadsides discharge sequentially down the gun deck, U.SALVO_STAGGER seconds
## apart, and each battery keeps its own reload timer (spec 5).

var ship: Node            # owning Ship
var side := "port"        # "port", "starboard", "bow"
var count := 2
var reload_time := 3.0
var timer := 0.0          # remaining reload (s)
var arc := U.BROADSIDE_ARC
var damage := 10.0
var max_range := 400.0
var muzzle_speed := 400.0
var enabled := true
var _queue: Array = []    # [delay, slot, aim_offset, aim_range]


func _init(p_ship: Node, p_side: String) -> void:
	ship = p_ship
	side = p_side
	if side == "bow":
		arc = deg_to_rad(18.0)


func configure(p_count: int, p_reload: float, p_damage: float, p_range: float, p_muzzle: float) -> void:
	count = p_count
	reload_time = p_reload
	damage = p_damage
	max_range = p_range
	muzzle_speed = p_muzzle


func is_ready() -> bool:
	return enabled and count > 0 and timer <= 0.0 and _queue.is_empty()


func is_firing() -> bool:
	return not _queue.is_empty()


## 0 = just fired, 1 = loaded.
func progress() -> float:
	if count <= 0:
		return 0.0
	return 1.0 - clampf(timer / maxf(0.01, reload_time), 0.0, 1.0)


## Local-space direction the battery faces (ship forward = +X, starboard = +Y).
func local_dir() -> Vector2:
	match side:
		"port": return Vector2(0, -1)
		"starboard": return Vector2(0, 1)
	return Vector2(1, 0)


func world_angle() -> float:
	return ship.rotation + local_dir().angle()


## Local muzzle position of cannon `slot` (bow-first order down the gun deck).
func muzzle_local(slot: int) -> Vector2:
	var L: float = ship.stats["length"]
	var B: float = ship.stats["beam"]
	if side == "bow":
		var off := 0.0 if count == 1 else (-0.18 if slot == 0 else 0.18) * B
		return Vector2(L * 0.5 - 2.0, off)
	var t := 0.5 if count == 1 else float(slot) / float(count - 1)
	var x := lerpf(L * 0.28, -L * 0.3, t)
	return Vector2(x, (B * 0.5 + 1.0) * local_dir().y)


## Fire the battery. aim_offset: radians relative to the battery facing
## (clamped to the arc). aim_range: desired splash distance in px.
func fire(aim_offset: float = 0.0, aim_range: float = -1.0) -> bool:
	if not is_ready():
		return false
	var r := max_range if aim_range <= 0.0 else clampf(aim_range, 60.0, max_range)
	var off := clampf(aim_offset, -arc, arc)
	for i in count:
		_queue.append([float(i) * U.SALVO_STAGGER, i, off, r])
	timer = reload_time + float(count) * U.SALVO_STAGGER
	return true


func tick(dt: float, reload_mult: float = 1.0) -> void:
	if timer > 0.0:
		timer = maxf(0.0, timer - dt / maxf(0.2, reload_mult))
	var i := 0
	while i < _queue.size():
		var q: Array = _queue[i]
		q[0] -= dt
		if q[0] <= 0.0:
			ship.discharge_cannon(self, int(q[1]), float(q[2]), float(q[3]))
			_queue.remove_at(i)
			continue
		i += 1


func cancel() -> void:
	_queue.clear()
