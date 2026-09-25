class_name PlayerView
extends SubViewportContainer
## SubViewportContainer_Pn -> SubViewport_Pn -> { Camera2D, PlayerN_HUD_Canvas }
## (spec 3 architecture). The SubViewport shares the World's World2D, so both
## players render the same world through independent cameras. The canvas cull
## mask lets each view also show world-space overlays meant only for its player.

var idx := 0
var viewport: SubViewport
var camera: PlayerCamera
var hud_layer: CanvasLayer
var hud: HUD
var ship: PlayerShip


func setup(p_idx: int, world_2d: World2D) -> void:
	idx = p_idx
	name = "SubViewportContainer_P%d" % (idx + 1)
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "SubViewport_P%d" % (idx + 1)
	viewport.world_2d = world_2d
	viewport.canvas_cull_mask = 1 | (2 << idx)   # shared layer + this player's private overlay layer
	viewport.audio_listener_enable_2d = false   # see Sfx: one unified output, no per-view listeners
	viewport.handle_input_locally = false
	viewport.msaa_2d = Viewport.MSAA_4X
	add_child(viewport)
	camera = PlayerCamera.new()
	camera.name = "Camera2D"
	viewport.add_child(camera)
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Player%d_HUD_Canvas" % (idx + 1)
	viewport.add_child(hud_layer)
	hud = HUD.new()
	hud_layer.add_child(hud)


func bind_ship(p_ship: PlayerShip) -> void:
	ship = p_ship
	ship.view = self
	camera.target = ship
	camera.snap()
	hud.bind(self, ship)


func shake(amount: float) -> void:
	if camera:
		camera.add_shake(amount)


## World position under the mouse cursor inside this viewport.
func mouse_world() -> Vector2:
	var local := get_local_mouse_position()
	var vp_size := Vector2(viewport.size)
	return camera.get_screen_center_position() + (local - vp_size * 0.5) / camera.zoom


func set_ui_scale(s: float) -> void:
	if hud_layer:
		hud_layer.scale = Vector2(s, s)
		hud.ui_scale = s
		hud.size = Vector2(viewport.size) / maxf(0.01, s)
		hud.queue_redraw()


func _process(_delta: float) -> void:
	if hud and viewport:
		hud.size = Vector2(viewport.size) / maxf(0.01, hud.ui_scale)
