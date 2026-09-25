class_name Ocean
extends Node2D
## Big world-space quad that renders the ocean shader, plus the storm border.

const MARGIN := 2600.0

var _rect := Rect2()


func _ready() -> void:
	z_index = -20
	_rect = Rect2(Vector2(-MARGIN, -MARGIN), U.WORLD_SIZE + Vector2(MARGIN, MARGIN) * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/ocean.gdshader")
	mat.set_shader_parameter("world_size", U.WORLD_SIZE)
	material = mat


func _draw() -> void:
	draw_rect(_rect, Color.WHITE)
