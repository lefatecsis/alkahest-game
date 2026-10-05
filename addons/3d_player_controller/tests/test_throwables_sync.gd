extends GutTest

## Purpose: throwing is decided on the Player's multiplayer authority alone. On a real host/client session the
## client's copy of the host's Player neither consumes nor spawns; the host's throw reaches the client as the same
## ThrownItem through the ProjectileSpawner, and when it lands the host replaces it with an ItemPickup on both peers.
## A client's throw request is checked by the host: its damage is the thrown thing's own, never the number it sent.

const PORT: int = 47395
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PROJECTILE_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/projectile_spawner.gd")
const THROWN_ITEM_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/thrown_item.tscn")
const SWORD_SCENE: PackedScene = preload("res://addons/3d_player_controller/inventory/scenes/demo/wooden_sword.tscn")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")
const PROJECT_ROCK_PATH: String = "res://addons/3d_player_controller/tests/sync_project_rock.tres" ## Held in the cache only, as a project's own throwable is.
const ROCK_PATH: String = "user://test_sync_rock.tres" ## A throwable saved to disk, so it has a path the spawner can send.

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer
var rock: Item


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
	projectile_spawner.add_to_group(&"ProjectileSpawner") # ProjectileSpawner.find_for matches by multiplayer session
	projectile_spawner.add_spawnable_scene(THROWN_ITEM_SCENE.resource_path) # a client's throw is only for a listed scene
	projectile_spawner.add_spawnable_scene(SWORD_SCENE.resource_path) # and lands only as listed equipment
	root.add_child(projectile_spawner)


func before_each() -> void:
	rock = Item.new()
	rock.id = &"sync_rock"
	rock.throwable = true
	assert_eq(ResourceSaver.save(rock, ROCK_PATH), OK)
	rock = ResourceLoader.load(ROCK_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as Item
	server_root = Node3D.new()
	server_root.name = "ServerBranch"
	client_root = Node3D.new()
	client_root.name = "ClientBranch"
	client_root.position = Vector3(0.0, 0.0, 200.0) # both branches share one physics world; positions replicate locally, so the client's copies stand clear of the host's throw
	add_child(server_root)
	add_child(client_root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -1.5
	server_root.add_child(floor_body) # one physics world: a floor for both branches' bodies
	server_api = SceneMultiplayer.new()
	client_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK, "ENet server should open on localhost")
	server_api.multiplayer_peer = server_peer
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	_build_branch(server_root)
	_build_branch(client_root)
	for i in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(client_api.get_peers().size(), 0, "Client should connect to the loopback server")
	await wait_process_frames(30)


func after_each() -> void:
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)
	if FileAccess.file_exists(ROCK_PATH):
		DirAccess.remove_absolute(ROCK_PATH)
	await wait_process_frames(1) # a body the host despawned leaves the client's tree queued for freeing


func test_a_copy_off_the_authority_neither_consumes_nor_spawns() -> void:
	var remote: Player = client_root.get_node("Players/1")
	assert_false(remote.is_multiplayer_authority(), "The host's Player is not the client's to run")
	assert_false(remote.held_object.is_processing_input(), "Its HeldObject reads no input")
	assert_false(remote.seeker_wheel.is_processing_unhandled_input(), "nor does its seeker wheel")
	remote.inventory.add_item(rock, 2)
	assert_false(remote.held_object.start_throwable_throw(), "No throw off the authority")
	assert_false(remote.held_object.is_holding_object())
	assert_eq(remote.inventory.count_of(rock), 2, "The rocks stay")
	await wait_process_frames(10)
	assert_eq(client_root.get_node("Projectiles").get_child_count(), 0)
	assert_eq(server_root.get_node("Projectiles").get_child_count(), 0, "Nothing was asked of the host either")


func test_the_authoritys_throw_reaches_the_client_and_lands_as_a_pickup_on_both() -> void:
	var host: Player = server_root.get_node("Players/1")
	host.warp_to(Transform3D(Basis.IDENTITY, Vector3(20.0, 0.0, 0.0))) # clear of the client's puppet, which spawned on the same spot
	await wait_physics_frames(2)
	host.inventory.add_item(rock, 1)
	assert_true(host.held_object.start_throwable_throw(), "The authority throws")
	assert_eq(host.inventory.count_of(rock), 0, "and spent the rock")
	host.held_object.execute_instant_throw(Vector3(0.0, 0.3, -1.0).normalized(), 1.0)
	await wait_process_frames(5)
	var host_projectiles: Node = server_root.get_node("Projectiles")
	var client_projectiles: Node = client_root.get_node("Projectiles")
	assert_eq(host_projectiles.get_child_count(), 1)
	assert_eq(client_projectiles.get_child_count(), 1, "The client spawns the same body")
	assert_true(host_projectiles.get_child(0) is ThrownItem)
	var remote: ThrownItem = client_projectiles.get_child(0) as ThrownItem
	assert_not_null(remote, "as a ThrownItem")
	assert_eq(remote.item.get_id(), &"sync_rock", "carrying the same item, by path")
	assert_lt(remote.linear_velocity.z, -5.0, "and flying from the launch data")
	assert_false(remote.is_multiplayer_authority(), "The client's copy waits for the host to land it")
	for i in 240:
		await wait_process_frames(1)
		if host_projectiles.get_child_count() > 0 and host_projectiles.get_child(0) is ItemPickup and client_projectiles.get_child_count() > 0 and client_projectiles.get_child(0) is ItemPickup:
			break
	assert_eq(host_projectiles.get_child_count(), 1, "One node on the host after the landing")
	assert_true(host_projectiles.get_child(0) is ItemPickup, "the pickup the host placed")
	assert_eq(client_projectiles.get_child_count(), 1, "The client lost the body and got the pickup")
	var pickup: ItemPickup = client_projectiles.get_child(0) as ItemPickup
	assert_not_null(pickup)
	assert_eq(pickup.item.get_id(), &"sync_rock", "holding the rock")
	assert_eq(pickup.count, 1)


## A client that asks the host for a throw names the item and a damage. The host refuses an item the client could never
## have thrown (not throwable, or no Item of the project) and equipment off its list, and a throw it accepts does what
## the rock or the sword does, not the 9999 the client sent.
func test_the_host_derives_a_clients_throw_damage_and_refuses_what_it_could_not_have_thrown() -> void:
	var project_rock := Item.new()
	project_rock.id = &"sync_project_rock"
	project_rock.throwable = true
	project_rock.throw_damage = 5.0
	project_rock.take_over_path(PROJECT_ROCK_PATH)
	var mine: Player = client_root.get_node("Players/" + str(client_api.get_unique_id()))
	var client_spawner: ProjectileSpawner = client_root.get_node("ProjectileSpawner")
	var on_host: Node = server_root.get_node("Projectiles")
	var on_client: Node = client_root.get_node("Projectiles")
	var far: Transform3D = Transform3D(Basis.IDENTITY, Vector3(300.0, 50.0, 0.0))
	assert_false(APPLE.throwable, "The apple is food, never thrown")
	client_spawner.fire(THROWN_ITEM_SCENE, far, Vector3.FORWARD, 1.0, mine, null, {"item": APPLE.resource_path, "damage": 9999.0})
	client_spawner.fire(THROWN_ITEM_SCENE, far, Vector3.FORWARD, 1.0, mine, null, {"item": "res://nowhere/rock.tres", "damage": 9999.0})
	client_spawner.fire(THROWN_ITEM_SCENE, far, Vector3.FORWARD, 1.0, mine, null, {"equipment": PLAYER_SCENE.resource_path, "damage": 9999.0})
	await wait_process_frames(15)
	assert_eq(on_host.get_child_count(), 0, "An item it could not have thrown, or a scene off the list, flies nowhere")
	assert_eq(on_client.get_child_count(), 0)
	client_spawner.fire(THROWN_ITEM_SCENE, far, Vector3.FORWARD, 1.0, mine, null, {"item": PROJECT_ROCK_PATH, "damage": 9999.0})
	for i in 60:
		await wait_process_frames(1)
		if on_client.get_child_count() > 0:
			break
	assert_eq(on_host.get_child_count(), 1, "A throwable item of the project flies")
	assert_eq((on_host.get_child(0) as ThrownItem).damage, 5.0, "doing what the rock does on the host, whose copy lands it")
	assert_eq((on_client.get_child(0) as ThrownItem).damage, 5.0, "and the client's copy agrees")
	client_spawner.fire(THROWN_ITEM_SCENE, far, Vector3.FORWARD, 1.0, mine, null, {"equipment": SWORD_SCENE.resource_path, "damage": 9999.0})
	for i in 60:
		await wait_process_frames(1)
		if on_host.get_child_count() > 1:
			break
	assert_eq(on_host.get_child_count(), 2, "Listed equipment flies")
	var sword: ThrownItem = on_host.get_child(1) as ThrownItem
	assert_eq(sword.equipment_scene, SWORD_SCENE)
	assert_eq(sword.damage, 0.0, "doing the sword scene's throw_damage, not the client's number")
