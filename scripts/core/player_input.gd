class_name PlayerInput
extends RefCounted
## One player's isolated input device. State is polled directly from a single
## keyboard scheme or a single joypad id, so actions never bleed between players
## (spec 2: discrete multi-device input binding).

enum Scheme { KB_WASD, KB_ARROWS, KB_IJKL, PAD }

const ACTIONS: Array[String] = [
	"steer_left", "steer_right", "sail_up", "sail_down",
	"fire_port", "fire_starboard", "fire_bow", "fire_aim",
	"board", "interact",
	"menu_up", "menu_down", "menu_left", "menu_right", "menu_accept", "menu_back",
]

# Keyboard bindings. Every action can have several physical keys.
const KB_BINDINGS := {
	Scheme.KB_WASD: {
		"steer_left": [KEY_A], "steer_right": [KEY_D],
		"sail_up": [KEY_W], "sail_down": [KEY_S],
		"fire_port": [KEY_Q], "fire_starboard": [KEY_E], "fire_bow": [KEY_SPACE],
		"board": [KEY_F], "interact": [KEY_R],
		"menu_up": [KEY_W], "menu_down": [KEY_S], "menu_left": [KEY_A], "menu_right": [KEY_D],
		"menu_accept": [KEY_SPACE, KEY_E], "menu_back": [KEY_R, KEY_Q],
	},
	Scheme.KB_ARROWS: {
		"steer_left": [KEY_LEFT], "steer_right": [KEY_RIGHT],
		"sail_up": [KEY_UP], "sail_down": [KEY_DOWN],
		"fire_port": [KEY_KP_1, KEY_COMMA], "fire_starboard": [KEY_KP_3, KEY_PERIOD],
		"fire_bow": [KEY_KP_0, KEY_SLASH],
		"board": [KEY_KP_2, KEY_CTRL], "interact": [KEY_KP_ENTER, KEY_ENTER],
		"menu_up": [KEY_UP], "menu_down": [KEY_DOWN], "menu_left": [KEY_LEFT], "menu_right": [KEY_RIGHT],
		"menu_accept": [KEY_KP_0, KEY_SLASH, KEY_KP_3, KEY_PERIOD],
		"menu_back": [KEY_KP_ENTER, KEY_ENTER, KEY_KP_1, KEY_COMMA],
	},
	Scheme.KB_IJKL: {
		"steer_left": [KEY_J], "steer_right": [KEY_L],
		"sail_up": [KEY_I], "sail_down": [KEY_K],
		"fire_port": [KEY_U], "fire_starboard": [KEY_O], "fire_bow": [KEY_P],
		"board": [KEY_H], "interact": [KEY_Y],
		"menu_up": [KEY_I], "menu_down": [KEY_K], "menu_left": [KEY_J], "menu_right": [KEY_L],
		"menu_accept": [KEY_P, KEY_O], "menu_back": [KEY_Y, KEY_U],
	},
}

# Joypad bindings (Xbox layout names; DualShock maps to the same indices in SDL).
const PAD_BUTTONS := {
	"steer_left": [JOY_BUTTON_DPAD_LEFT], "steer_right": [JOY_BUTTON_DPAD_RIGHT],
	"sail_up": [JOY_BUTTON_DPAD_UP], "sail_down": [JOY_BUTTON_DPAD_DOWN],
	"fire_port": [JOY_BUTTON_LEFT_SHOULDER], "fire_starboard": [JOY_BUTTON_RIGHT_SHOULDER],
	"fire_bow": [JOY_BUTTON_A], "board": [JOY_BUTTON_X], "interact": [JOY_BUTTON_Y],
	"menu_up": [JOY_BUTTON_DPAD_UP], "menu_down": [JOY_BUTTON_DPAD_DOWN],
	"menu_left": [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER],
	"menu_right": [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER],
	"menu_accept": [JOY_BUTTON_A], "menu_back": [JOY_BUTTON_B, JOY_BUTTON_Y],
}

const GLYPHS := {
	Scheme.KB_WASD: {"fire_port": "Q", "fire_starboard": "E", "fire_bow": "Space", "board": "F",
		"interact": "R", "sail_up": "W", "sail_down": "S", "steer": "A/D", "menu_accept": "Space",
		"menu_back": "R", "menu_nav": "W/S", "menu_tab": "A/D"},
	Scheme.KB_ARROWS: {"fire_port": "Num1", "fire_starboard": "Num3", "fire_bow": "Num0", "board": "Num2/Ctrl",
		"interact": "Enter", "sail_up": "Up", "sail_down": "Down", "steer": "Left/Right",
		"menu_accept": "Num0", "menu_back": "Enter", "menu_nav": "Up/Down", "menu_tab": "Left/Right"},
	Scheme.KB_IJKL: {"fire_port": "U", "fire_starboard": "O", "fire_bow": "P", "board": "H",
		"interact": "Y", "sail_up": "I", "sail_down": "K", "steer": "J/L", "menu_accept": "P",
		"menu_back": "Y", "menu_nav": "I/K", "menu_tab": "J/L"},
	Scheme.PAD: {"fire_port": "LB", "fire_starboard": "RB", "fire_bow": "A", "board": "X",
		"interact": "Y", "sail_up": "RT", "sail_down": "LT", "steer": "L-Stick", "menu_accept": "A",
		"menu_back": "B", "menu_nav": "D-Pad", "menu_tab": "LB/RB"},
}

const STICK_DEADZONE := 0.22
const TRIGGER_THRESHOLD := 0.55
const STICK_MENU_THRESHOLD := 0.6

var scheme: int = Scheme.KB_WASD
var device: int = 0          # joypad id when scheme == PAD
var uses_mouse := false      # KB_WASD also reads the mouse (Left-Click = aimed broadside)
var enabled := true

var _now := {}
var _prev := {}
var _steer_axis := 0.0


func _init(p_scheme: int = Scheme.KB_WASD, p_device: int = 0) -> void:
	scheme = p_scheme
	device = p_device
	uses_mouse = scheme == Scheme.KB_WASD
	for a in ACTIONS:
		_now[a] = false
		_prev[a] = false


func describe() -> String:
	match scheme:
		Scheme.KB_WASD: return "Keyboard + Mouse (WASD)"
		Scheme.KB_ARROWS: return "Keyboard (Arrows + Numpad)"
		Scheme.KB_IJKL: return "Keyboard (IJKL)"
		Scheme.PAD:
			var n := Input.get_joy_name(device)
			return "Gamepad %d%s" % [device + 1, (" - " + n) if n != "" else ""]
	return "?"


func is_pad() -> bool:
	return scheme == Scheme.PAD


func glyph(action: String) -> String:
	var g: Dictionary = GLYPHS[scheme]
	return str(g.get(action, action))


## Call once per frame before reading actions.
func poll() -> void:
	for a in ACTIONS:
		_prev[a] = _now[a]
		_now[a] = false
	_steer_axis = 0.0
	if not enabled:
		return
	if scheme == Scheme.PAD:
		_poll_pad()
	else:
		_poll_keyboard()


func _poll_keyboard() -> void:
	var map: Dictionary = KB_BINDINGS[scheme]
	for a in map.keys():
		for k in map[a]:
			if Input.is_physical_key_pressed(k):
				_now[a] = true
				break
	if uses_mouse and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_now["fire_aim"] = true
	_steer_axis = (1.0 if _now["steer_right"] else 0.0) - (1.0 if _now["steer_left"] else 0.0)


func _poll_pad() -> void:
	if not Input.get_connected_joypads().has(device):
		return
	for a in PAD_BUTTONS.keys():
		for b in PAD_BUTTONS[a]:
			if Input.is_joy_button_pressed(device, b):
				_now[a] = true
				break
	var lx := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	var rt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	var lt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	if rt > TRIGGER_THRESHOLD:
		_now["sail_up"] = true
	if lt > TRIGGER_THRESHOLD:
		_now["sail_down"] = true
	# Left stick doubles as menu navigation.
	if ly < -STICK_MENU_THRESHOLD:
		_now["menu_up"] = true
	elif ly > STICK_MENU_THRESHOLD:
		_now["menu_down"] = true
	if lx < -STICK_MENU_THRESHOLD:
		_now["menu_left"] = true
	elif lx > STICK_MENU_THRESHOLD:
		_now["menu_right"] = true
	var axis := 0.0
	if absf(lx) > STICK_DEADZONE:
		axis = signf(lx) * inverse_lerp(STICK_DEADZONE, 1.0, absf(lx))
	var dpad := (1.0 if _now["steer_right"] else 0.0) - (1.0 if _now["steer_left"] else 0.0)
	_steer_axis = clampf(axis + dpad, -1.0, 1.0)


func held(action: String) -> bool:
	return bool(_now.get(action, false))


func just_pressed(action: String) -> bool:
	return bool(_now.get(action, false)) and not bool(_prev.get(action, false))


## 1D steering axis: -1 = port (left), +1 = starboard (right).
func steer() -> float:
	return _steer_axis


## Any "join / confirm" style press on this device (used by the lobby).
func any_confirm_pressed() -> bool:
	return just_pressed("fire_bow") or just_pressed("menu_accept")


func rumble(weak: float, strong: float, duration: float) -> void:
	if scheme == Scheme.PAD and GameManager.settings.get("rumble", true):
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)
