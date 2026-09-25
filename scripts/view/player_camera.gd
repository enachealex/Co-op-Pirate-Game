class_name PlayerCamera
extends Camera2D
## Split-screen follow camera (spec 3 camera specs):
##  - smooth damp follow, smooth_speed = 4.0
##  - look-ahead along the ship's forward vector: target = pos + forward * (v * 0.6)
##  - zoom widens slightly with speed; base zoom adapts to the viewport's size
##  - trauma-style screen shake for broadsides and hits

const SMOOTH_SPEED := 4.0
const LOOK_AHEAD := 0.6
## World area (px^2) we aim to show in one viewport, regardless of split layout.
const TARGET_VIEW_AREA := 1150.0 * 1150.0

var target: Node2D
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	position_smoothing_enabled = false
	ignore_rotation = true
	process_priority = 10
	_rng.randomize()
	make_current()


func snap() -> void:
	if target:
		position = target.global_position
		reset_smoothing()


func add_shake(amount: float) -> void:
	_shake = minf(24.0, _shake + amount)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var vp_size := get_viewport_rect().size
	var base := sqrt(maxf(1.0, vp_size.x * vp_size.y) / TARGET_VIEW_AREA)
	var speed := 0.0
	var ratio := 0.0
	var size_f := 1.0
	var tgt: Vector2 = target.global_position
	if target is Ship:
		var s: Ship = target
		speed = s.forward_speed()
		ratio = clampf(absf(speed) / float(s.stats["max_speed"]), 0.0, 1.3)
		size_f = clampf(s.length() / (20.0 * U.M), 0.85, 1.35)
		tgt += s.forward() * (speed * LOOK_AHEAD)
	position = position.lerp(tgt, 1.0 - exp(-SMOOTH_SPEED * delta))
	var z := base / (1.0 + 0.16 * ratio) / sqrt(size_f)
	zoom = zoom.lerp(Vector2(z, z), 1.0 - exp(-2.0 * delta))
	_shake = maxf(0.0, _shake - delta * 30.0)
	if _shake > 0.01:
		offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake / zoom.x * 0.6
	else:
		offset = Vector2.ZERO
