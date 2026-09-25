extends Node
## Owns the per-player PlayerInput devices and the global (non-player) actions.
## Player 1 defaults to Keyboard+Mouse, Player 2 to Gamepad 1 when present,
## otherwise the secondary keyboard mapping (Arrows + Numpad).

signal devices_changed

var players: Array[PlayerInput] = []
## Device options offered in the lobby: [scheme, device id]
var options: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100   # poll before anything reads input
	_register_global_actions()
	Input.joy_connection_changed.connect(_on_joy_changed)
	rebuild_options()
	reset_defaults()


func _register_global_actions() -> void:
	_add_action("pause", [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)])
	_add_action("toggle_layout", [_key(KEY_F2)])
	_add_action("toggle_help", [_key(KEY_F1), _pad(JOY_BUTTON_BACK)])
	_add_action("toggle_fullscreen", [_key(KEY_F11)])


func _add_action(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


func _on_joy_changed(_device: int, _connected: bool) -> void:
	rebuild_options()
	devices_changed.emit()


func rebuild_options() -> void:
	options.clear()
	options.append([PlayerInput.Scheme.KB_WASD, 0])
	options.append([PlayerInput.Scheme.KB_ARROWS, 0])
	options.append([PlayerInput.Scheme.KB_IJKL, 0])
	for id in Input.get_connected_joypads():
		options.append([PlayerInput.Scheme.PAD, id])


func reset_defaults() -> void:
	players.clear()
	var pads := Input.get_connected_joypads()
	players.append(PlayerInput.new(PlayerInput.Scheme.KB_WASD, 0))
	if pads.size() > 0:
		players.append(PlayerInput.new(PlayerInput.Scheme.PAD, pads[0]))
	else:
		players.append(PlayerInput.new(PlayerInput.Scheme.KB_ARROWS, 0))


func option_index_of(pi: PlayerInput) -> int:
	for i in options.size():
		if options[i][0] == pi.scheme and (pi.scheme != PlayerInput.Scheme.PAD or options[i][1] == pi.device):
			return i
	return 0


func option_label(i: int) -> String:
	var o: Array = options[i]
	return PlayerInput.new(o[0], o[1]).describe()


## Assign lobby option i to player slot, swapping if the other player holds it.
func assign(slot: int, option_i: int) -> void:
	var o: Array = options[wrapi(option_i, 0, options.size())]
	var other := 1 - slot
	if other < players.size():
		var op := players[other]
		if op.scheme == o[0] and (o[0] != PlayerInput.Scheme.PAD or op.device == o[1]):
			players[other] = PlayerInput.new(players[slot].scheme, players[slot].device)
	players[slot] = PlayerInput.new(o[0], o[1])
	devices_changed.emit()


func cycle(slot: int, step: int) -> void:
	assign(slot, option_index_of(players[slot]) + step)


func get_player(idx: int) -> PlayerInput:
	return players[idx] if idx < players.size() else null


func _process(_delta: float) -> void:
	for p in players:
		p.poll()
	if Input.is_action_just_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
