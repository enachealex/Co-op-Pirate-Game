extends Node
## Split-screen-safe audio (spec 9: "Audio Listeners in Split-Screen").
##
## There are NO AudioListener2D / AudioStreamPlayer2D nodes. Every sound plays
## through one unified output: plain AudioStreamPlayers routed into a fixed set
## of pre-panned buses. For a world-space event we work out which player's
## viewport rect it falls in, derive volume from the distance to that player's
## ship and pan from the event's on-screen x position, then pick the matching
## pan bus. All sounds are synthesized at startup, so the project ships no audio files.

const RATE := 22050
const PAN_STEPS := 7            # buses Pan0..Pan6 map to pan -1 .. +1
const POOL_SIZE := 28
const HEAR_DISTANCE := 1500.0   # px beyond which a world sound is inaudible

var streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _pan_bus_names: Array[String] = []
var _ambient: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
## Registered by Main: objects exposing `ship`, `camera` and `get_global_rect()`.
var views: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1337
	_build_buses()
	_synthesize_all()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.stream = streams["ocean"]
	_ambient.volume_db = -16.0
	_ambient.bus = "SFX"
	add_child(_ambient)
	set_master_volume(GameManager.settings["master_volume"])


func _build_buses() -> void:
	var sfx_idx := AudioServer.bus_count
	AudioServer.add_bus(sfx_idx)
	AudioServer.set_bus_name(sfx_idx, "SFX")
	AudioServer.set_bus_send(sfx_idx, "Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 4.0
	AudioServer.add_bus_effect(sfx_idx, comp)
	for i in PAN_STEPS:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		var bus_name := "Pan%d" % i
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "SFX")
		var panner := AudioEffectPanner.new()
		panner.pan = lerpf(-0.85, 0.85, float(i) / float(PAN_STEPS - 1))
		AudioServer.add_bus_effect(idx, panner)
		_pan_bus_names.append(bus_name)


func set_master_volume(v: float) -> void:
	GameManager.settings["master_volume"] = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, GameManager.settings["master_volume"])))


func start_ambient() -> void:
	if not _ambient.playing:
		_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


## Non-positional UI / global sound, centered.
func ui(sound: String, volume_db: float = -4.0) -> void:
	_play(sound, volume_db, 0.0, 0.03)


## World-space sound, spatialized against the split-screen viewports.
func at(sound: String, world_pos: Vector2, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var info := _listen(world_pos)
	if info.x <= 0.001:
		return
	_play(sound, volume_db + linear_to_db(info.x), info.y, pitch_jitter)


## Returns Vector2(volume 0..1, pan -1..1) for a world position.
func _listen(world_pos: Vector2) -> Vector2:
	if views.is_empty():
		return Vector2(1.0, 0.0)
	var best_vol := 0.0
	var best_pan := 0.0
	var win_w := maxf(1.0, get_viewport().get_visible_rect().size.x)
	for v in views:
		if not is_instance_valid(v) or v.camera == null:
			continue
		var rect: Rect2 = v.get_global_rect().abs()
		var cam: Camera2D = v.camera
		var center := cam.get_screen_center_position()
		var screen := rect.get_center() + (world_pos - center) * cam.zoom
		var ship_pos: Vector2 = center
		if v.ship != null and is_instance_valid(v.ship):
			ship_pos = v.ship.global_position
		var d := world_pos.distance_to(ship_pos)
		var vol := clampf(1.0 - d / HEAR_DISTANCE, 0.0, 1.0)
		vol = vol * vol
		# Events visible inside this player's viewport are prioritised.
		if rect.grow(80.0).has_point(screen):
			vol = maxf(vol, 0.35)
		if vol > best_vol:
			best_vol = vol
			best_pan = clampf(screen.x / win_w * 2.0 - 1.0, -1.0, 1.0)
	return Vector2(best_vol, best_pan)


func _play(sound: String, volume_db: float, pan: float, pitch_jitter: float) -> void:
	if not streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	var step := int(round((pan + 1.0) * 0.5 * float(PAN_STEPS - 1)))
	p.bus = _pan_bus_names[clampi(step, 0, PAN_STEPS - 1)]
	p.play()


# --- Synthesis ------------------------------------------------------------------------

func _synthesize_all() -> void:
	streams["cannon"] = _make(_cannon(1.1, 55.0, 1.0))
	streams["chaser"] = _make(_cannon(0.7, 80.0, 0.7))
	streams["hit"] = _make(_hit())
	streams["splash"] = _make(_splash())
	streams["coin"] = _make(_coin())
	streams["sink"] = _make(_sink())
	streams["explosion"] = _make(_cannon(2.0, 38.0, 1.4))
	streams["clash"] = _make(_clash())
	streams["bell"] = _make(_bell())
	streams["rope"] = _make(_rope())
	streams["ui_move"] = _make(_blip(660.0, 0.06, 0.25))
	streams["ui_ok"] = _make(_blip(880.0, 0.12, 0.35))
	streams["ui_error"] = _make(_buzz())
	streams["repair"] = _make(_repair())
	var ocean := _make(_ocean())
	ocean.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ocean.loop_begin = 0
	ocean.loop_end = ocean.data.size() / 2
	streams["ocean"] = ocean


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


func _cannon(length: float, base_hz: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var hz := base_hz * (1.0 + 1.5 * exp(-t * 18.0))
		phase += TAU * hz / RATE
		var thump := sin(phase) * exp(-t * 5.5)
		lp += (_noise() - lp) * (0.25 * exp(-t * 3.0) + 0.02)
		lp2 += (lp - lp2) * 0.3
		var crack := _noise() * exp(-t * 60.0) * 0.8
		var rumble := lp2 * exp(-t * 2.2) * 2.2
		out[i] = (thump * 0.9 + rumble + crack) * gain * 0.6
	return out


func _hit() -> PackedFloat32Array:
	var n := int(0.45 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.35
		var knock := sin(TAU * 190.0 * t) * exp(-t * 22.0)
		var crack := _noise() * exp(-t * 40.0)
		var splinter := lp * exp(-t * 9.0) * 0.6 * (0.5 + 0.5 * sin(TAU * 31.0 * t))
		out[i] = (knock * 0.8 + crack * 0.7 + splinter) * 0.6
	return out


func _splash() -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp_prev := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := _noise()
		var hp := x - hp_prev
		hp_prev = x
		lp += (hp - lp) * 0.5
		var env := minf(1.0, t * 40.0) * exp(-t * 6.0)
		out[i] = lp * env * 0.55
	return out


func _coin() -> PackedFloat32Array:
	var n := int(0.35 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 1320.0 if t < 0.08 else 1760.0
		var tt := t if t < 0.08 else t - 0.08
		out[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-tt * 14.0) * 0.35
	return out


func _sink() -> PackedFloat32Array:
	var n := int(2.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var bubble_t := 0.0
	var bubble_f := 300.0
	for i in n:
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.04
		var rumble := lp * 3.0 * exp(-t * 0.9)
		bubble_t += 1.0 / RATE
		if bubble_t > 0.09 and _rng.randf() < 0.002:
			bubble_t = 0.0
			bubble_f = _rng.randf_range(220.0, 520.0)
		var bub := sin(TAU * bubble_f * (1.0 + bubble_t * 6.0) * bubble_t) * exp(-bubble_t * 30.0) * 0.4
		var groan := sin(TAU * (70.0 + 12.0 * sin(t * 3.0)) * t) * 0.15 * exp(-t * 1.2)
		out[i] = (rumble + bub + groan) * 0.6
	return out


func _clash() -> PackedFloat32Array:
	var n := int(1.3 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hits := [0.0, 0.22, 0.41, 0.63, 0.9]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for h in hits:
			var dt: float = t - h
			if dt >= 0.0:
				var e := exp(-dt * 26.0)
				v += (sin(TAU * 1870.0 * dt) + 0.7 * sin(TAU * 2630.0 * dt) + 0.5 * sin(TAU * 3910.0 * dt)) * e * 0.25
		v += _noise() * 0.05 * (0.5 + 0.5 * sin(t * 9.0))
		out[i] = v
	return out


func _bell() -> PackedFloat32Array:
	var n := int(1.8 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[520.0, 1.0], [1040.0, 0.5], [1370.0, 0.35], [1860.0, 0.2], [2740.0, 0.12]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t * (1.6 + float(p[0]) / 1500.0))
		out[i] = v * 0.22
	return out


func _rope() -> PackedFloat32Array:
	var n := int(0.4 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_noise() - lp) * (0.05 + 0.4 * t)
		out[i] = lp * sin(PI * t / 0.4) * 0.7
	return out


func _blip(hz: float, length: float, gain: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * hz * t) * exp(-t * 30.0) * gain
	return out


func _buzz() -> PackedFloat32Array:
	var n := int(0.18 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (1.0 if fmod(t * 140.0, 1.0) < 0.5 else -1.0) * 0.12 * (1.0 - t / 0.18)
	return out


func _repair() -> PackedFloat32Array:
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var knocks := [0.0, 0.25, 0.5]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in knocks:
			var dt: float = t - k
			if dt >= 0.0:
				v += sin(TAU * 420.0 * dt) * exp(-dt * 35.0) * 0.5 + _noise() * exp(-dt * 80.0) * 0.3
		out[i] = v * 0.6
	return out


func _ocean() -> PackedFloat32Array:
	var seconds := 6.0
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.06
		lp2 += (lp - lp2) * 0.2
		# Swell envelope: whole number of cycles in the loop keeps it seamless.
		var swell := 0.55 + 0.45 * sin(TAU * t / seconds * 2.0) * sin(TAU * t / seconds * 3.0)
		out[i] = lp2 * swell * 1.6
	# Cross-fade the loop seam.
	var fade := int(0.25 * RATE)
	for i in fade:
		var a := float(i) / fade
		out[i] = out[i] * a + out[n - fade + i] * (1.0 - a)
	out.resize(n - fade)
	return out
