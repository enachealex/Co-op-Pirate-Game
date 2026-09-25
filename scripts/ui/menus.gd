class_name Menus
extends CanvasLayer
## Global menus (title, crew muster / device assignment, pause, controls, victory).
## These are shared screens, so they use standard Godot UI focus navigation
## (mouse, keyboard and any gamepad). In-game per-player menus live in each HUD.

var main: Node
var ui_scale := 1.0
var root: Control
var _theme: Theme
var _bg: ColorRect
var _title_panel: Control
var _lobby_panel: Control
var _pause_panel: Control
var _help_panel: Control
var _victory_panel: Control
var _help_overlay: Control
var _lobby_players := 2
var _lobby_vertical := false
var _slot_buttons: Array[Button] = []
var _players_btn: Button
var _layout_btn: Button
var _p2_row: Control
var _pause_layout_btn: Button
var _pause_arcs_btn: Button
var _pause_rumble_btn: Button
var _victory_stats: Label
var _help_return: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	root = Control.new()
	root.theme = _theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_bg = ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/ocean.gdshader")
	mat.set_shader_parameter("screen_space", true)
	_bg.material = mat
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_bg)
	_title_panel = _build_title()
	_lobby_panel = _build_lobby()
	_pause_panel = _build_pause()
	_help_panel = _build_help()
	_victory_panel = _build_victory()
	_help_overlay = _build_help_overlay()
	InputRouter.devices_changed.connect(_refresh_lobby)
	hide_all()


func set_ui_scale(s: float, win_size: Vector2) -> void:
	ui_scale = s
	scale = Vector2(s, s)
	root.size = win_size / s


# --- Theme -------------------------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.12, 0.09, 0.06, 0.9)
	btn.border_color = Color(0.75, 0.6, 0.35)
	btn.set_border_width_all(2)
	btn.set_corner_radius_all(6)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.28, 0.19, 0.1, 0.95)
	hov.border_color = Color(1.0, 0.85, 0.45)
	var foc := hov.duplicate() as StyleBoxFlat
	foc.border_color = Color(1.0, 0.9, 0.5)
	foc.set_border_width_all(3)
	var prs := hov.duplicate() as StyleBoxFlat
	prs.bg_color = Color(0.45, 0.3, 0.12, 1.0)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("focus", "Button", foc)
	t.set_stylebox("pressed", "Button", prs)
	t.set_color("font_color", "Button", Color(0.98, 0.93, 0.8))
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.7))
	t.set_color("font_focus_color", "Button", Color(1, 0.95, 0.7))
	t.set_font_size("font_size", "Button", 22)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.06, 0.08, 0.86)
	panel.border_color = Color(0.85, 0.7, 0.4, 0.8)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(10)
	panel.content_margin_left = 34
	panel.content_margin_right = 34
	panel.content_margin_top = 26
	panel.content_margin_bottom = 26
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Color(0.95, 0.92, 0.85))
	return t


func _panel(parent: Control, min_w: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(min_w, 0)
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	return vb


func _label(parent: Control, text: String, size: int, color := Color(0.95, 0.92, 0.85), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Sfx.ui("ui_ok", -8.0)
		cb.call()
	)
	b.focus_entered.connect(func(): Sfx.ui("ui_move", -14.0))
	parent.add_child(b)
	return b


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	return c


# --- Screens -----------------------------------------------------------------------------------

func _build_title() -> Control:
	var s := _screen()
	var vb := _panel(s, 620)
	_label(vb, "BROADSIDE BRETHREN", 60, Color("ffd98a"))
	_label(vb, "Local split-screen co-op naval combat", 22, Color(0.85, 0.9, 1.0))
	vb.add_child(HSeparator.new())
	_button(vb, "Set Sail  (Muster the Crew)", show_lobby)
	_button(vb, "How to Play", func(): show_help(_title_panel))
	_button(vb, "Quit", func(): get_tree().quit())
	_label(vb, "Two captains, one treasury. Hunt convoys, raid forts, claim bounties.", 16, Color(1, 1, 1, 0.55))
	return s


func _build_lobby() -> Control:
	var s := _screen()
	var vb := _panel(s, 820)
	_label(vb, "MUSTER THE CREW", 40, Color("ffd98a"))
	_label(vb, "Assign each captain an input device. Devices are isolated: no input bleeds between players.", 17, Color(1, 1, 1, 0.7))
	for i in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vb.add_child(row)
		var tag := _label(row, "PLAYER %d" % (i + 1), 24, U.PLAYER_COLORS[i], HORIZONTAL_ALIGNMENT_LEFT)
		tag.custom_minimum_size = Vector2(150, 0)
		var prev := _button(row, "<", func(): InputRouter.cycle(i, -1))
		var dev := _button(row, "device", func(): InputRouter.cycle(i, 1))
		dev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nxt := _button(row, ">", func(): InputRouter.cycle(i, 1))
		prev.custom_minimum_size = Vector2(50, 0)
		nxt.custom_minimum_size = Vector2(50, 0)
		_slot_buttons.append(dev)
		if i == 1:
			_p2_row = row
	vb.add_child(HSeparator.new())
	_players_btn = _button(vb, "", func():
		_lobby_players = 1 if _lobby_players == 2 else 2
		_refresh_lobby()
	)
	_layout_btn = _button(vb, "", func():
		_lobby_vertical = not _lobby_vertical
		_refresh_lobby()
	)
	var go := _button(vb, "Begin Voyage", func(): main.start_voyage(_lobby_players, _lobby_vertical))
	go.add_theme_color_override("font_color", Color("9dffb0"))
	_button(vb, "Back", show_title)
	_label(vb, "Tip: two players can share one keyboard (WASD + Arrows/Numpad). Some keyboards cannot register many simultaneous keys; gamepads are recommended.", 14, Color(1, 1, 1, 0.5))
	return s


func _refresh_lobby() -> void:
	for i in _slot_buttons.size():
		var pi := InputRouter.get_player(i)
		_slot_buttons[i].text = pi.describe() if pi else "-"
	if _p2_row:
		_p2_row.modulate.a = 1.0 if _lobby_players == 2 else 0.35
	if _players_btn:
		_players_btn.text = "Captains: %s" % ("2 (split-screen co-op)" if _lobby_players == 2 else "1 (solo)")
	if _layout_btn:
		_layout_btn.text = "Split layout: %s" % ("Stacked (top / bottom)" if _lobby_vertical else "Side-by-side (left / right)")


func _build_pause() -> Control:
	var s := _screen()
	var vb := _panel(s, 560)
	_label(vb, "BECALMED", 44, Color("ffd98a"))
	_label(vb, "Game paused", 18, Color(1, 1, 1, 0.6))
	var resume := _button(vb, "Resume", func(): main.resume())
	resume.name = "Resume"
	_pause_layout_btn = _button(vb, "", func():
		main.toggle_layout()
		_refresh_pause()
	)
	_pause_arcs_btn = _button(vb, "", func():
		GameManager.settings["show_arcs"] = not GameManager.settings["show_arcs"]
		_refresh_pause()
	)
	_pause_rumble_btn = _button(vb, "", func():
		GameManager.settings["rumble"] = not GameManager.settings["rumble"]
		_refresh_pause()
	)
	var vol_row := HBoxContainer.new()
	vb.add_child(vol_row)
	_label(vol_row, "Volume", 20, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_LEFT).custom_minimum_size = Vector2(120, 0)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = GameManager.settings["master_volume"]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 30)
	slider.value_changed.connect(func(v: float): Sfx.set_master_volume(v))
	vol_row.add_child(slider)
	_button(vb, "Controls", func(): show_help(_pause_panel))
	_button(vb, "Abandon Voyage (Title)", func(): main.quit_to_title())
	return s


func _refresh_pause() -> void:
	_pause_layout_btn.text = "Split layout: %s  [F2]" % ("Stacked" if GameManager.settings["split_vertical"] else "Side-by-side")
	_pause_arcs_btn.text = "Firing arcs: %s" % ("On" if GameManager.settings["show_arcs"] else "Off")
	_pause_rumble_btn.text = "Gamepad rumble: %s" % ("On" if GameManager.settings["rumble"] else "Off")


const HELP_TEXT := """[GOAL]  Share one treasury. Sink or board Armada convoys, raid forts and claim bounties. Dock at Haven to repair, upgrade and switch hulls.

[SAILING]  Steer port/starboard. Sails are geared: Reverse / Stop / Half / Full. Rudders bite harder at speed; ships drift and carry momentum.

[BROADSIDES]  Fire port or starboard batteries. Cannons auto-traverse +-35 deg toward targets in the arc (reticle), discharge one after another and reload per side. Bow chaser fires ahead once bought.

[PINCER BARRAGE]  Hit the same ship within 3 s of your partner for +25% damage.

[BOARDING]  Ships below 15% hull are disabled. Get within 12 m and board: crew vs crew. Captured ships pay 2x gold, cargo and repair kits. Board together for a bonus.

[TOW-LINE]  A dismasted partner has 40 s before sinking. Sail close, throw a tow-line and drag them into Haven's safe zone - or they can patch up with a repair kit.

[CARGO]  Crates fill your hold; cargo is sold automatically when you dock at Haven. Lose your ship and you lose the cargo."""

const CONTROLS_TEXT := """                       KEYBOARD+MOUSE   ARROWS+NUMPAD      IJKL          GAMEPAD
Steer                  A / D            Left / Right       J / L         L-Stick / D-Pad
Sails up / down        W / S            Up / Down          I / K         RT / LT (D-Pad Up/Down)
Fire port broadside    Q                Num1 or ,          U             LB
Fire starboard         E                Num3 or .          O             RB
Fire bow chaser        Space            Num0 or /          P             A
Aimed broadside        Left Click       -                  -             -
Board / Tow-line       F                Num2 or Ctrl       H             X
Depot / Repair kit     R                Enter              Y             Y
Pause: Esc / Start     Split layout: F2     Help: F1 / Back     Fullscreen: F11"""


func _build_help() -> Control:
	var s := _screen()
	var vb := _panel(s, 1180)
	_label(vb, "HOW TO PLAY", 38, Color("ffd98a"))
	var help := _label(vb, HELP_TEXT, 17, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	help.custom_minimum_size = Vector2(1100, 0)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "Courier New", "monospace"])
	var ctl := _label(vb, CONTROLS_TEXT, 16, Color(0.8, 0.92, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	ctl.add_theme_font_override("font", mono)
	ctl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_button(vb, "Back", func(): _help_back())
	return s


func _build_help_overlay() -> Control:
	var s := _screen()
	var pc := PanelContainer.new()
	pc.position = Vector2(20, 20)
	s.add_child(pc)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "Courier New", "monospace"])
	var l := Label.new()
	l.text = CONTROLS_TEXT
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", 15)
	pc.add_child(l)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _build_victory() -> Control:
	var s := _screen()
	var vb := _panel(s, 700)
	_label(vb, "THE SEAS ARE YOURS", 50, Color("ffd98a"))
	_label(vb, "Grand Admiral Varro's Leviathan is no more. The Armada's grip on the sector is broken.", 19)
	_victory_stats = _label(vb, "", 18, Color(0.85, 0.95, 1.0))
	_button(vb, "Keep Sailing (endless bounties)", func(): main.resume())
	_button(vb, "Return to Title", func(): main.quit_to_title())
	return s


# --- Navigation --------------------------------------------------------------------------------

func hide_all() -> void:
	for p in [_title_panel, _lobby_panel, _pause_panel, _help_panel, _victory_panel, _help_overlay]:
		p.visible = false
	_bg.visible = false
	var f := root.get_viewport().gui_get_focus_owner() if root.is_inside_tree() else null
	if f:
		f.release_focus()


func _show(p: Control, with_bg: bool) -> void:
	hide_all()
	_bg.visible = with_bg
	p.visible = true
	_focus_first(p)


func _focus_first(p: Control) -> void:
	for b in p.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			(b as Button).grab_focus.call_deferred()
			return


func show_title() -> void:
	_show(_title_panel, true)


func show_lobby() -> void:
	InputRouter.rebuild_options()
	_refresh_lobby()
	_show(_lobby_panel, true)


func show_pause() -> void:
	_refresh_pause()
	_show(_pause_panel, false)
	_pause_panel.modulate = Color(1, 1, 1, 1)


func show_help(return_to: Control) -> void:
	_help_return = return_to
	_show(_help_panel, return_to == _title_panel)


func _help_back() -> void:
	if _help_return == _pause_panel:
		show_pause()
	else:
		show_title()


func show_victory() -> void:
	var lines := []
	for p in GameManager.profiles:
		lines.append("%s: %d sunk, %d captured, %d damage dealt" % [U.PLAYER_NAMES[p.idx], p.sunk, p.captured, int(p.damage_dealt)])
	lines.append("Treasury: %s gold   Voyage time: %d min" % [U.fmt_gold(GameManager.treasury), int(GameManager.voyage_time / 60.0)])
	_victory_stats.text = "\n".join(lines)
	_show(_victory_panel, false)


func toggle_help_overlay() -> void:
	_help_overlay.visible = not _help_overlay.visible


func is_submenu_open() -> bool:
	return _help_panel.visible or _lobby_panel.visible or _victory_panel.visible
