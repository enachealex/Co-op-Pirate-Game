class_name Wakes
extends Node2D
## Draws V-shaped foam wakes behind every ship (below ships, above the ocean).

const SAMPLE_INTERVAL := 0.09
const MAX_AGE := 3.2

var world: Node
var _trails := {}    # ship instance id -> Array of [pos, lateral, width, age]
var _timer := 0.0


func _ready() -> void:
	z_index = -9


func tick(dt: float) -> void:
	_timer += dt
	var sample := _timer >= SAMPLE_INTERVAL
	if sample:
		_timer = 0.0
	var alive_ids := {}
	for s in world.ships:
		if not is_instance_valid(s):
			continue
		var id: int = s.get_instance_id()
		alive_ids[id] = true
		if not _trails.has(id):
			_trails[id] = []
		var tr: Array = _trails[id]
		for e in tr:
			e[3] += dt
		while tr.size() > 0 and tr[0][3] > MAX_AGE:
			tr.pop_front()
		if sample and not s.sinking:
			var spd: float = s.velocity.length()
			if spd > 8.0:
				var fwd: Vector2 = s.forward()
				var stern: Vector2 = s.global_position - fwd * float(s.stats["length"]) * 0.45
				tr.append([stern, Vector2(-fwd.y, fwd.x), float(s.stats["beam"]) * 0.4, 0.0, clampf(spd / float(s.stats["max_speed"]), 0.0, 1.0)])
	for id in _trails.keys():
		if not alive_ids.has(id):
			var tr: Array = _trails[id]
			for e in tr:
				e[3] += dt
			while tr.size() > 0 and tr[0][3] > MAX_AGE:
				tr.pop_front()
			if tr.is_empty():
				_trails.erase(id)
	queue_redraw()


func _draw() -> void:
	for id in _trails:
		var tr: Array = _trails[id]
		if tr.size() < 2:
			continue
		for i in range(tr.size() - 1):
			var a: Array = tr[i]
			var b: Array = tr[i + 1]
			var age_a: float = a[3]
			var alpha := clampf(1.0 - age_a / MAX_AGE, 0.0, 1.0) * float(a[4])
			if alpha <= 0.01:
				continue
			var spread_a: float = a[2] + age_a * 22.0
			var spread_b: float = b[2] + float(b[3]) * 22.0
			var la: Vector2 = a[1]
			var lb: Vector2 = b[1]
			var pa: Vector2 = a[0]
			var pb: Vector2 = b[0]
			var c := Color(1, 1, 1, 0.42 * alpha)
			draw_line(pa + la * spread_a, pb + lb * spread_b, c, 3.0 * alpha + 1.0, true)
			draw_line(pa - la * spread_a, pb - lb * spread_b, c, 3.0 * alpha + 1.0, true)
			draw_line(pa, pb, Color(0.8, 0.93, 1.0, 0.22 * alpha), (a[2] as float) * (1.0 + age_a * 0.8), true)
