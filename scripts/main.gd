extends Node
## Root (spec 3 architecture hierarchy):
##   Root
##    |- GameManager (autoload: state, economy; SpawnDirector is its child during a voyage)
##    |- WorldViewport (hidden SubViewport) -> World (ocean, islands, ships, projectiles, loot)
##    |- DisplayLayout
##    |    `- SplitScreenContainer (HSplitContainer = side-by-side, VSplitContainer = stacked)
##    |         |- SubViewportContainer_P1 -> SubViewport_P1 -> Camera2D + Player1_HUD_Canvas
##    |         `- SubViewportContainer_P2 -> SubViewport_P2 -> Camera2D + Player2_HUD_Canvas
##    `- Menus (CanvasLayer)

const DIVIDER_COLOR := Color(0.09, 0.06, 0.04)

var world_vp: SubViewport
var world: World
var display: Control
var split: SplitContainer
var views: Array[PlayerView] = []
var menus: Menus
var ui_scale := 1.0
var _autotest: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	var win := get_window()
	win.min_size = Vector2i(960, 540)
	_fit_window()
	display = Control.new()
	display.name = "DisplayLayout"
	display.process_mode = Node.PROCESS_MODE_PAUSABLE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(display)
	var bg := ColorRect.new()
	bg.color = DIVIDER_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(bg)
	menus = Menus.new()
	menus.name = "Menus"
	menus.main = self
	add_child(menus)
	get_tree().root.size_changed.connect(_on_resize)
	GameManager.victory.connect(_on_victory)
	_on_resize()
	menus.show_title()
	if OS.get_cmdline_user_args().has("--autotest"):
		_autotest = load("res://scripts/tests/autotest.gd").new()
		_autotest.main = self
		add_child(_autotest)


func _fit_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	if screen.size.x > 0 and (win.size.x > screen.size.x or win.size.y > screen.size.y):
		var target := Vector2i(int(screen.size.x * 0.9), int(screen.size.y * 0.9))
		win.size = target
		win.position = screen.position + (screen.size - target) / 2


func _on_resize() -> void:
	var sz := get_viewport().get_visible_rect().size
	ui_scale = clampf(sz.y / 1080.0, 0.5, 3.0)
	menus.set_ui_scale(ui_scale, sz)


func _process(_delta: float) -> void:
	for v in views:
		var vs := Vector2(v.viewport.size)
		v.set_ui_scale(clampf(sqrt(maxf(1.0, vs.x * vs.y) / (960.0 * 1080.0)), 0.62, 2.6))


# --- Voyage lifecycle --------------------------------------------------------------------------

func start_voyage(n_players: int, vertical: bool) -> void:
	_teardown()
	GameManager.settings["split_vertical"] = vertical
	GameManager.new_voyage(n_players)
	world_vp = SubViewport.new()
	world_vp.name = "WorldViewport"
	world_vp.size = Vector2i(4, 4)
	world_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world_vp.disable_3d = true
	world_vp.audio_listener_enable_2d = false
	world_vp.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world_vp)
	move_child(world_vp, 0)
	world = World.new()
	world.name = "World"
	world_vp.add_child(world)
	world.build(randi())
	GameManager.world = world
	GameManager.director = world.director
	GameManager.add_child(world.director)
	world.start(GameManager.player_count)
	_build_split(vertical)
	Sfx.start_ambient()
	GameManager.set_state(GameManager.State.PLAYING)
	menus.hide_all()
	GameManager.banner.emit("SET SAIL!", "Hunt convoys, raid forts, claim bounties. Dock at Haven [dotted ring] to upgrade.")


func _build_split(vertical: bool) -> void:
	split = VSplitContainer.new() if vertical else HSplitContainer.new()
	split.name = "SplitScreenContainer"
	split.dragger_visibility = SplitContainer.DRAGGER_HIDDEN
	split.add_theme_constant_override("separation", 6)
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(split)
	if views.is_empty():
		for i in GameManager.player_count:
			var v := PlayerView.new()
			v.setup(i, world_vp.world_2d)
			split.add_child(v)
			v.bind_ship(world.players[i])
			views.append(v)
	else:
		for v in views:
			split.add_child(v)
			v.camera.make_current()
	Sfx.views = views


func toggle_layout() -> void:
	if split == null:
		return
	var vertical: bool = not GameManager.settings["split_vertical"]
	GameManager.settings["split_vertical"] = vertical
	for v in views:
		split.remove_child(v)
	split.queue_free()
	split = null
	_build_split(vertical)


func _teardown() -> void:
	get_tree().paused = false
	for v in views:
		if is_instance_valid(v):
			v.queue_free()
	views.clear()
	Sfx.views = []
	if split:
		split.queue_free()
		split = null
	if world_vp:
		world_vp.queue_free()
		world_vp = null
		world = null
	GameManager.end_voyage()
	Sfx.stop_ambient()


func pause() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	get_tree().paused = true
	GameManager.set_state(GameManager.State.PAUSED)
	menus.show_pause()


func resume() -> void:
	get_tree().paused = false
	if world:
		for p in world.players:
			p.fire_lock = true
	GameManager.set_state(GameManager.State.PLAYING)
	menus.hide_all()


func quit_to_title() -> void:
	_teardown()
	GameManager.set_state(GameManager.State.TITLE)
	menus.show_title()


func _on_victory() -> void:
	get_tree().paused = true
	GameManager.set_state(GameManager.State.VICTORY)
	menus.show_victory()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match GameManager.state:
			GameManager.State.PLAYING:
				pause()
				get_viewport().set_input_as_handled()
			GameManager.State.PAUSED:
				if menus.is_submenu_open():
					menus.show_pause()
				else:
					resume()
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_layout") and GameManager.state == GameManager.State.PLAYING:
		toggle_layout()
	elif event.is_action_pressed("toggle_help") and GameManager.state == GameManager.State.PLAYING:
		menus.toggle_help_overlay()
