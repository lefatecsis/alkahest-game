extends GutTest

## Purpose: pickups are the server's to hand out, and a peer joining later finds the world as it stands. The server
## grants every take, so a partial one leaves the rest on every peer and two peers taking at once get the stack once;
## drops come through the ProjectileSpawner, so a late joiner sees them; a level pickup the host emptied or thinned
## before anyone joined reads the same on the joiner. Two scene branches with their own MultiplayerAPI talk over ENet
## on localhost, as test_equipment_sync does; the client connects inside each test, so a test can act before it joins.

const PORT: int = 47403
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PROJECTILE_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/projectile_spawner.gd")
const PICKUP_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/item_pickup.tscn")
const SWORD_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const ORE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/iron_ore.tres")
const KEY: Item = preload("res://addons/3d_player_controller/inventory/resources/items/old_key.tres")
const SWORD: Item = preload("res://addons/3d_player_controller/inventory/resources/items/wooden_sword.tres")

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer


## One branch: Players and their spawner, Projectiles and the ProjectileSpawner (listing what a client drops), and
## the level's pickups, saved in it as a level's are (owned by its root): three stacks and a walk-over sword.
func _build_branch(root: Node3D) -> void:
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	root.add_child(projectiles)
	var player_spawner: PlayerSpawner = PLAYER_SPAWNER.new()
	player_spawner.name = "PlayerSpawner"
	player_spawner.spawn_path = NodePath("../Players")
	player_spawner.add_child(PLAYER_SCENE.instantiate()) # the template every peer's player is a copy of
	root.add_child(player_spawner)
	var projectile_spawner: ProjectileSpawner = PROJECTILE_SPAWNER.new()
	projectile_spawner.name = "ProjectileSpawner"
	projectile_spawner.spawn_path = NodePath("../Projectiles")
	projectile_spawner.add_spawnable_scene(PICKUP_SCENE.resource_path) # a client's drop is only for a listed scene
	projectile_spawner.add_spawnable_scene(SWORD_SCENE.resource_path)
	projectile_spawner.add_to_group(&"ProjectileSpawner")
	root.add_child(projectile_spawner)
	var x: float = 10.0
	for stack: Array in [["Apples", APPLE, 3], ["Ore", ORE, 5], ["Key", KEY, 1]]:
		var pickup: ItemPickup = PICKUP_SCENE.instantiate()
		pickup.name = stack[0]
		pickup.item = stack[1]
		pickup.count = stack[2]
		pickup.position = Vector3(x, 0.0, 0.0) # out of the Players' reach
		root.add_child(pickup)
		pickup.owner = root
		x += 4.0
	var sword := Equipment.new()
	sword.name = "Sword"
	sword.equipment_type = Equipment.EquipmentType.SWORD_1H
	sword.bone_attachment_bone_name = "RightHand"
	sword.position = Vector3(x, 0.0, 0.0)
	var detection := Area3D.new()
	detection.name = "PlayerDetection"
	sword.add_child(detection)
	root.add_child(sword)
	sword.owner = root


func before_each() -> void:
	server_root = Node3D.new()
	server_root.name = "ServerBranch"
	add_child(server_root)
	server_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK, "ENet server should open on localhost")
	server_api.multiplayer_peer = server_peer
	_build_branch(server_root)
	await wait_process_frames(10)


## The client builds the same level and connects.
func _join() -> void:
	client_root = Node3D.new()
	client_root.name = "ClientBranch"
	client_root.position = Vector3(0.0, 0.0, 300.0) # one physics world: the client's copies stand clear of the host's
	add_child(client_root)
	client_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer # before the branch readies, or its spawner takes itself for the server
	_build_branch(client_root)
	for i in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(client_api.get_peers().size(), 0, "Client should connect to the loopback server")
	await wait_process_frames(30)


func after_each() -> void:
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path() if client_root else NodePath()
	server_root.free()
	if client_root:
		client_root.free()
	server_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	if client_api:
		client_api.multiplayer_peer.close()
		get_tree().set_multiplayer(null, client_path)
	client_root = null
	client_api = null


func _host() -> Player:
	return server_root.get_node("Players/1") as Player


func _client() -> Player:
	return client_root.get_node("Players/" + str(client_api.get_unique_id())) as Player


## Waits up to [param frames] process frames for [param condition].
func _until(condition: Callable, frames: int = 120) -> void:
	for i in frames:
		if condition.call():
			return
		await wait_process_frames(1)


## Fills [param player]'s tab for [param item] until only [param room] more fit.
func _leave_room(player: Player, item: Item, room: int) -> void:
	player.inventory.add_item(item, item.max_stack * player.inventory.slots_per_tab - room)


func test_a_partial_take_leaves_the_rest_on_every_peer() -> void:
	await _join()
	var client: Player = _client()
	_leave_room(client, ORE, 2)
	var before: int = client.inventory.count_of(ORE)
	var on_host: ItemPickup = server_root.get_node("Ore")
	var on_client: ItemPickup = client_root.get_node("Ore")
	on_client.player = client # as walking up to it would
	on_client.take()
	await _until(func() -> bool: return on_host.count != 5 and on_client.count != 5)
	assert_eq(client.inventory.count_of(ORE) - before, 2, "The client took the two that fit")
	assert_eq(on_host.count, 3, "The host's copy keeps the rest")
	assert_eq(on_client.count, 3, "and so does the client's")
	assert_true(on_host.visible and on_client.visible, "still lying there on both")


func test_two_peers_taking_at_once_get_the_stack_once() -> void:
	await _join()
	var host: Player = _host()
	var client: Player = _client()
	var on_host: ItemPickup = server_root.get_node("Key")
	var on_client: ItemPickup = client_root.get_node("Key")
	on_client.player = client
	on_host.player = host
	on_client.take() # the client's request is on its way to the server
	on_host.take() # while the host, the server itself, asks on the spot
	await wait_process_frames(20)
	assert_eq(host.inventory.count_of(KEY) + client.inventory.count_of(KEY), 1, "One key between the two of them")
	assert_eq(host.inventory.count_of(KEY), 1, "the host's, whose request reached the server first")
	assert_false(on_host.visible, "The key is gone on the host")
	assert_false(on_client.visible, "and on the client")


func test_a_peer_joining_later_sees_the_drops_and_the_pickups_as_they_stand() -> void:
	var host: Player = _host()
	var key: ItemPickup = server_root.get_node("Key")
	key.player = host
	key.take()
	_leave_room(host, ORE, 2)
	var ore: ItemPickup = server_root.get_node("Ore")
	ore.player = host
	ore.take()
	var sword: Equipment = server_root.get_node("Sword")
	sword._on_player_detection_body_entered(host) # the host walks over the level's sword
	host.inventory.add_item(APPLE, 1)
	var dropped: Node3D = host.inventory.drop_slot(APPLE.category, 0)
	assert_eq(dropped.get_parent(), server_root.get_node("Projectiles"), "The host's drop came through the spawner")
	assert_eq(ore.count, 3)
	assert_false(key.visible)
	assert_false(sword.visible)

	await _join()
	var drops: Node = client_root.get_node("Projectiles")
	await _until(func() -> bool: return drops.get_child_count() > 0 and not (client_root.get_node("Key") as Node3D).visible)
	var key_on_client: ItemPickup = client_root.get_node("Key")
	assert_false(key_on_client.visible, "The joiner never sees the key the host took")
	assert_eq(key_on_client.count, 0)
	assert_false(key_on_client.player_detection.monitoring, "and cannot take it again")
	assert_eq((client_root.get_node("Ore") as ItemPickup).count, 3, "It sees the ore the host left")
	assert_false((client_root.get_node("Sword") as Node3D).visible, "and no sword where the host took one")
	assert_eq(drops.get_child_count(), 1, "The apple dropped before it joined is there")
	var apple: ItemPickup = drops.get_child(0) as ItemPickup
	assert_not_null(apple)
	if apple == null:
		return
	assert_eq(apple.item, APPLE)
	assert_eq(apple.count, 1)
	var client: Player = _client()
	apple.player = client
	apple.take()
	var host_drops: Node = server_root.get_node("Projectiles")
	await _until(func() -> bool: return host_drops.get_child_count() == 0 and drops.get_child_count() == 0)
	assert_eq(client.inventory.count_of(APPLE), 1, "The joiner takes it")
	assert_false(is_instance_valid(dropped), "The host's copy is freed")
	assert_eq(drops.get_child_count(), 0, "and the spawner took the joiner's away with it")
	await wait_process_frames(2) # the despawned copy is freed at the end of its frame


func test_a_clients_drop_comes_back_to_both_peers_through_the_spawner() -> void:
	await _join()
	var client: Player = _client()
	var on_host: Node = server_root.get_node("Projectiles")
	var on_client: Node = client_root.get_node("Projectiles")
	client.inventory.add_item(APPLE, 1)
	assert_null(client.inventory.drop_slot(APPLE.category, 0), "A client's drop is not in its world yet")
	assert_eq(client.inventory.count_of(APPLE), 0, "but it has left the bag")
	await _until(func() -> bool: return on_host.get_child_count() == 1 and on_client.get_child_count() == 1)
	var apple: ItemPickup = on_host.get_child(0) as ItemPickup
	assert_not_null(apple, "The server put the apple down")
	assert_eq(on_client.get_child_count(), 1, "and it reached the client")
	if apple:
		assert_eq(apple.item, APPLE, "holding the item the client named")
		assert_eq(apple.count, 1)
	client.inventory.add_item(SWORD)
	client.inventory.drop_equipment(client.inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H))
	await _until(func() -> bool: return on_host.get_child_count() == 2 and on_client.get_child_count() == 2)
	var sword_on_client: Equipment = on_client.get_child(1) as Equipment
	var sword_on_host: Equipment = on_host.get_child(1) as Equipment
	assert_not_null(sword_on_client, "The sword came back as its scene")
	assert_not_null(sword_on_host)
	if sword_on_client == null or sword_on_host == null:
		return
	assert_eq(sword_on_client.get_meta("dropped_by"), client, "and the client walks over its own drop untaken until it steps off")
	sword_on_host._on_player_detection_body_entered(_host()) # the host walks over it
	assert_true(_host().inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The host takes the dropped sword")
	await _until(func() -> bool: return on_host.get_child_count() == 1 and on_client.get_child_count() == 1)
	assert_false(is_instance_valid(sword_on_host), "A taken drop is freed on the host, not left for the spawner to send a joiner")
	assert_false(is_instance_valid(sword_on_client), "and with it on the client")
