extends GutTest

## Needs the real player controller: the Player's state machine owns the Action label the prompt borrows.
##
## Purpose: a pickup reads the Action button as "Pick Up" while the Player stands on it, and after Action takes the
## stack the label is the state's own text again, restored through Player.refresh_contextual_controls.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/item_pickup.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")

var root: Node3D
var player: Player
var sender


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(40.0, 1.0, 40.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	await wait_physics_frames(3)


func after_each() -> void:
	sender.release_all()
	sender.clear()


func test_the_action_label_is_the_states_own_again_after_a_pickup() -> void:
	var label: Label = player.controls.joypad_button_1_label
	var state_text: String = label.text
	assert_ne(state_text, "Pick Up", "The Standing state's label is not the prompt's")
	var pickup: ItemPickup = PICKUP_SCENE.instantiate()
	pickup.item = APPLE
	root.add_child(pickup)
	pickup.global_position = player.global_position + Vector3(0.5, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(label.text, "Pick Up", "The prompt borrows the Action button")
	sender.action_down("action")
	await wait_physics_frames(2)
	sender.action_up("action")
	await wait_physics_frames(2)
	assert_eq(player.inventory.count_of(APPLE), 1, "Action took the apple")
	assert_eq(label.text, state_text, "and the state put its own label back")
