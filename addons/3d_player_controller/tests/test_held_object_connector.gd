extends GutTest

## Purpose: the connector between the hand and a held object is a scene dependency, so every export ships it;
## it is instanced once, hidden, when the HeldObject enters the tree, and a HeldObject without one adds nothing.


func _packed_connector() -> PackedScene:
	var root := Node3D.new()
	root.name = "Connector"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func test_a_connector_scene_is_instanced_hidden_on_ready() -> void:
	var held := HeldObject.new()
	held.connector_scene = _packed_connector()
	add_child_autofree(held)
	assert_eq(held.get_child_count(), 1, "One connector under the HeldObject")
	var connector: Node3D = held.get_child(0) as Node3D
	assert_not_null(connector)
	assert_false(connector.visible, "Hidden until something is held")


func test_no_connector_scene_adds_nothing() -> void:
	var held := HeldObject.new()
	add_child_autofree(held)
	assert_eq(held.get_child_count(), 0)
