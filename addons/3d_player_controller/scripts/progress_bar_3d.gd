class_name ProgressBar3D
extends Node3D
## Billboarded world-space bar. Hidden while empty or full unless [member always_visible], so harvest
## progress and hit points only show while they matter.

@export var max_value: float = 3.0
@export var fill_color: Color = Color(0.35, 0.85, 0.3):
	set(value):
		fill_color = value
		if bar_mesh:
			bar_mesh.set_instance_shader_parameter("fill_color", fill_color)
@export var always_visible: bool = false

var value: float = 0.0:
	set(new_value):
		value = new_value
		_update_bar()

@onready var bar_mesh: MeshInstance3D = $BarMesh


func _ready() -> void:
	bar_mesh.set_instance_shader_parameter("fill_color", fill_color)
	_update_bar()


## One call for signals that report a value with its maximum.
func set_progress(new_value: float, new_max: float) -> void:
	max_value = new_max
	value = new_value


func _update_bar() -> void:
	if not is_node_ready():
		return
	bar_mesh.set_instance_shader_parameter("ratio", clampf(value / maxf(max_value, 0.001), 0.0, 1.0))
	visible = always_visible or (value > 0.0 and value < max_value)
