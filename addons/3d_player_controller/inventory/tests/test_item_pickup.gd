extends GutTest

## Purpose: an ItemPickup is taken Zelda style: walking up shows the prompt, Action moves the stack into the
## inventory and the pickup goes away, walking off hides the prompt. The Action button reading "Pick Up" while the
## prompt is up is the player controller's label, covered in tests/integration.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/item_pickup.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

var root: Node3D
var player: Player
var sender
var actions: RefCounted = ContractActions.new()


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


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


func _drop_pickup_at(offset: Vector3, count: int = 1) -> ItemPickup:
	var pickup: ItemPickup = PICKUP_SCENE.instantiate()
	pickup.item = APPLE
	pickup.count = count
	root.add_child(pickup)
	pickup.global_position = player.global_position + offset
	return pickup


func test_walking_up_shows_the_prompt() -> void:
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0))
	await wait_physics_frames(3)
	assert_eq(pickup.player, player, "The Player in range is remembered")
	assert_true(pickup.action_prompt.visible, "The prompt is up")
	assert_eq(pickup.action_prompt.message_end, "to pick up", "reading Press ... to pick up")
	assert_true(pickup.icon.visible, "The item's icon floats over the spot")
	assert_eq(pickup.icon.texture, APPLE.icon)


func test_action_takes_the_stack_and_frees_the_pickup() -> void:
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0), 3)
	await wait_physics_frames(3)
	var taken: Array = []
	pickup.picked_up.connect(func(by: Player, amount: int) -> void: taken.append([by, amount]))
	sender.action_down("action")
	await wait_physics_frames(2)
	sender.action_up("action")
	await wait_physics_frames(2)
	assert_eq(player.inventory.count_of(APPLE), 3, "The apples are in the inventory")
	assert_eq(taken, [[player, 3]], "picked_up reported who took how many")
	assert_false(is_instance_valid(pickup), "The pickup is gone")


func test_walking_away_hides_the_prompt() -> void:
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0))
	await wait_physics_frames(3)
	assert_true(pickup.action_prompt.visible)
	pickup.global_position = player.global_position + Vector3(10.0, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_false(pickup.action_prompt.visible, "Out of range the prompt is down")
	assert_null(pickup.player)
	sender.action_down("action")
	await wait_physics_frames(2)
	sender.action_up("action")
	assert_eq(player.inventory.count_of(APPLE), 0, "Action out of range takes nothing")


func test_a_full_inventory_leaves_the_rest_lying_there() -> void:
	player.inventory.add_item(APPLE, APPLE.max_stack * player.inventory.slots_per_tab - 1)
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0), 3)
	await wait_physics_frames(3)
	pickup.take()
	assert_eq(pickup.count, 2, "Only one fitted; two stay")
	assert_true(is_instance_valid(pickup), "The pickup stays for later")


func test_an_item_with_a_model_lies_there_as_the_model_turning_instead_of_the_icon() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new() # a metre box centred on its origin
	var scene := PackedScene.new()
	scene.pack(mesh)
	mesh.free()
	var crate := Item.new()
	crate.id = &"test_crate"
	crate.icon = APPLE.icon
	crate.model_scene = scene
	var pickup: ItemPickup = PICKUP_SCENE.instantiate()
	pickup.item = crate
	root.add_child(pickup)
	pickup.global_position = player.global_position + Vector3(5.0, 0.0, 0.0)
	await wait_physics_frames(1)
	assert_false(pickup.icon.visible, "The model stands in for the icon")
	assert_eq(pickup.model_pivot.get_child_count(), 1, "The item's model is on the spot")
	var model: Node3D = pickup.model_pivot.get_child(0)
	assert_almost_eq(model.position.y, 0.5, 0.01, "stood on the ground, not sunk half into it")
	var heading: float = pickup.model_pivot.rotation.y
	await wait_physics_frames(3)
	assert_ne(pickup.model_pivot.rotation.y, heading, "and turning")
	pickup.item = APPLE
	await wait_physics_frames(1)
	assert_true(pickup.icon.visible, "An item without a model floats its icon")
	assert_eq(pickup.model_pivot.get_child_count(), 0)


func test_typing_in_the_chat_does_not_take_the_stack() -> void:
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0))
	await wait_physics_frames(3)
	player.is_typing = true
	sender.action_down("action")
	await wait_physics_frames(2)
	sender.action_up("action")
	await wait_physics_frames(1)
	assert_eq(player.inventory.count_of(APPLE), 0, "Action while typing is text, not a pickup")
	assert_true(is_instance_valid(pickup))
	player.is_typing = false


## Any peer asks the server to take; only the server grants and says how many are left, on every peer. The two-peer
## session is covered in tests/test_pickup_sync.gd.
func test_the_server_arbitrates_a_take_and_the_take_action_is_exported() -> void:
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0))
	assert_eq(pickup.take_action, &"action")
	var config: Dictionary = (pickup.get_script() as Script).get_rpc_config()
	assert_eq(config["_request_take"]["rpc_mode"], MultiplayerAPI.RPC_MODE_ANY_PEER, "The taker, whoever it is, asks")
	assert_eq(config["_grant"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY, "The server grants")
	assert_eq(config["_set_count"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY, "and says how many are left")
	assert_true(config["_set_count"]["call_local"])


## A pickup saved in the level is hidden once empty rather than freed, so the server can still tell a peer joining
## later that it is gone.
func test_an_emptied_level_pickup_stays_hidden_instead_of_freed() -> void:
	var pickup: ItemPickup = _drop_pickup_at(Vector3(0.5, 0.0, 0.0), 2)
	pickup.owner = root # as a pickup saved in the level scene is
	await wait_physics_frames(3)
	pickup.take()
	await wait_physics_frames(2)
	assert_eq(player.inventory.count_of(APPLE), 2)
	assert_true(is_instance_valid(pickup), "It stays in the tree")
	assert_false(pickup.visible, "hidden")
	assert_false(pickup.player_detection.monitoring, "and nobody takes it again")
	var reach: CollisionShape3D = pickup.player_detection.get_child(0) as CollisionShape3D
	assert_true(reach.disabled, "nor does its reach catch the aim ray, which collides with areas")
	assert_false(pickup.action_prompt.visible, "The prompt went with it")


## A drop whose item was made at run time has no path to send, so it lies on this peer alone and is taken there.
func test_a_pickup_on_this_peer_alone_is_taken_without_asking_the_server() -> void:
	var stone: Item = Item.new()
	stone.id = &"local_stone"
	player.inventory.add_item(stone, 1)
	var pickup: ItemPickup = player.inventory.drop_slot(stone.category, 0) as ItemPickup
	assert_not_null(pickup)
	assert_true(pickup.local_only)
	assert_eq(pickup.item, stone, "It holds the item itself")
	player.warp_to(Transform3D(Basis(), pickup.global_position))
	await wait_physics_frames(3)
	pickup.player = player
	pickup.take()
	assert_eq(player.inventory.count_of(stone), 1, "Taken back")
	await wait_physics_frames(1)
	assert_false(is_instance_valid(pickup))
