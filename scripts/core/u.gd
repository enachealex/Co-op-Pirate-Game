class_name U
## Shared constants and small math helpers.
## World units are pixels; gameplay values from the design spec are authored in
## meters and converted with U.M (pixels per meter).

const M := 8.0                        # pixels per meter
const GRAVITY := 9.8 * M              # g = 9.8 m/s^2 (spec 5: projectile ballistics)
const WORLD_SIZE := Vector2(7200, 7200)   # 900 m x 900 m sea sector
const WORLD_EDGE_SOFT := 200.0        # distance inside the border where the push-back starts

enum Team { PLAYER, ENEMY, NEUTRAL }

# Sail gears (spec 2: Throttle - Full Reverse, Neutral, Half Sail, Full Sail)
const SAIL_STATES: Array[float] = [-0.3, 0.0, 0.55, 1.0]
const SAIL_NAMES: Array[String] = ["REVERSE", "NEUTRAL", "HALF SAIL", "FULL SAIL"]

const DISABLE_THRESHOLD := 0.15       # hull ratio at which enemies become disabled/boardable
const BOARDING_RADIUS := 12.0 * M     # R <= 12 m
const DETECTION_RADIUS := 75.0 * M    # AI detection radius
const PINCER_WINDOW := 3.0            # seconds between both players' hits for the crossfire bonus
const PINCER_MULT := 1.25             # +25% "Pincer Barrage" damage
const BROADSIDE_ARC := deg_to_rad(35.0)   # player broadside traverse arc (+-35 deg from the beam)
const AI_FIRE_WINDOW := deg_to_rad(25.0)  # AI fires when the target is inside +-25 deg of the beam
const SALVO_STAGGER := 0.08           # seconds between cannons in a broadside
const TOW_LENGTH := 11.0 * M

const PLAYER_COLORS: Array[Color] = [Color("ff5a4f"), Color("4fb8ff")]
const PLAYER_NAMES: Array[String] = ["PLAYER 1", "PLAYER 2"]


static func m(meters: float) -> float:
	return meters * M


static func knots(px_per_sec: float) -> float:
	return px_per_sec / M * 1.94384


static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


static func angle_diff(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


static func damp_v(current: Vector2, target: Vector2, rate: float, dt: float) -> Vector2:
	return current.lerp(target, 1.0 - exp(-rate * dt))


static func dir(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle))


static func in_world(p: Vector2, margin: float = 0.0) -> bool:
	return p.x > margin and p.y > margin and p.x < WORLD_SIZE.x - margin and p.y < WORLD_SIZE.y - margin


static func fmt_gold(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
