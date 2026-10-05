@tool
extends EditorPlugin
## Controls. The scripts register their class names on their own; enabling the plugin only puts the world
## prompt in the Create New Node dialog under its own name.


func _enter_tree() -> void:
	add_custom_type("ActionPrompt", "Node3D", preload("action_prompt.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("ActionPrompt")
