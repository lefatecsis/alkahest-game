extends GutTest

## Purpose: Ammunition is decided on the Player's multiplayer authority alone. On a real host/client session the
## client's copy of the host's Player neither reloads nor spends arrows, and the scene the authority fires (an
## arrow, an incendiary round) reaches the client through the ProjectileSpawner by path, so the peer builds the same
## scene rather than the weapon's default.

const PORT: int = 47393
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const BULLET_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/bullet.tscn")
const ARROW_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/arrow.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PROJECTILE_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/projectile_spawner.gd")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")
const BOW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/bow.gd")

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer


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
	projectile_spawner.add_to_group(&"ProjectileSpawner") # weapons find the spawner by group; the host's branch is built first, so it is the one they find
	root.add_child(projectile_spawner)


func before_each() -> void:
	server_root = Node3D.new()
	server_root.name = "ServerBranch"
	client_root = Node3D.new()
	client_root.name = "ClientBranch"
	add_child(server_root)
	add_child(client_root)
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


func _ammo(id: StringName, type: Equipment.EquipmentType) -> AmmoItem:
	var ammo := AmmoItem.new()
	ammo.id = id
	ammo.weapon_type = type
	ammo.rounds_per_unit = 1 if type == Equipment.EquipmentType.BOW else 0
	return ammo


func test_a_copy_off_the_authority_neither_reloads_nor_spends_arrows() -> void:
	var remote: Player = client_root.get_node("Players/1")
	assert_false(remote.is_multiplayer_authority(), "The host's Player is not the client's to run")
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = remote
	gun.equipment_type = Equipment.EquipmentType.PISTOL
	gun.projectile_scene = BULLET_SCENE
	gun.magazine_size = 2
	gun.reload_time = 0.05
	var timer := Timer.new()
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	remote.add_child(gun)
	var bow: Bow = BOW_SCRIPT.new()
	bow.player = remote
	bow.equipment_type = Equipment.EquipmentType.BOW
	bow.arrow_scene = ARROW_SCENE
	remote.add_child(bow)
	var magazine: AmmoItem = _ammo(&"sync_magazine", Equipment.EquipmentType.PISTOL)
	var arrows: AmmoItem = _ammo(&"sync_arrow", Equipment.EquipmentType.BOW)
	remote.inventory.add_item(magazine, 1)
	remote.inventory.add_item(arrows, 2)
	assert_false(remote.inventory.item_used.is_connected(gun._on_item_used), "Off the authority a gun listens to no Use")
	assert_false(remote.inventory.item_used.is_connected(bow._on_item_used))
	gun.rounds = 0
	gun.reload()
	await wait_seconds(0.1)
	assert_false(gun.is_reloading)
	assert_eq(gun.rounds, 0, "No reload off the authority")
	assert_eq(remote.inventory.count_of(magazine), 1, "The magazine stays in the inventory")
	assert_false(bow.fire_arrow(), "No shot off the authority")
	assert_eq(remote.inventory.count_of(arrows), 2, "The arrows stay")
	assert_eq(client_root.get_node("Projectiles").get_child_count(), 0)
	assert_eq(server_root.get_node("Projectiles").get_child_count(), 0, "Nothing was asked of the host either")


func test_the_authoritys_arrow_scene_reaches_the_client_through_the_spawner() -> void:
	var host: Player = server_root.get_node("Players/1")
	var bow: Bow = BOW_SCRIPT.new()
	bow.player = host
	bow.equipment_type = Equipment.EquipmentType.BOW
	bow.arrow_scene = BULLET_SCENE # the bow's default is not what the selected arrows are
	host.add_child(bow)
	host.inventory.add_equipment(bow)
	var special: AmmoItem = _ammo(&"sync_special_arrow", Equipment.EquipmentType.BOW)
	special.projectile_scene = ARROW_SCENE
	host.inventory.add_item(special, 1)
	assert_true(bow.fire_arrow(), "The authority fires")
	assert_eq(host.inventory.count_of(special), 0, "The authority spent the arrow")
	await wait_process_frames(10)
	# The release sound travels with the arrow and plays beside it, so each peer's Projectiles also holds its speaker
	var host_rounds: Array[Node] = server_root.get_node("Projectiles").get_children().filter(func(n: Node) -> bool: return n is Projectile)
	var client_rounds: Array[Node] = client_root.get_node("Projectiles").get_children().filter(func(n: Node) -> bool: return n is Projectile)
	assert_eq(host_rounds.size(), 1)
	assert_eq(client_rounds.size(), 1, "The client spawns the same round")
	assert_true(host_rounds[0] is Arrow, "The host flies the selected arrows' scene")
	assert_true(client_rounds[0] is Arrow, "So does the client: the spawner carries the scene path, not the bow's default")
	assert_eq(client_rounds[0].scene_file_path, ARROW_SCENE.resource_path)
	assert_not_null(client_root.get_node_or_null("Projectiles/LaunchSfx"), "and the bow's release sound plays on the client too")
