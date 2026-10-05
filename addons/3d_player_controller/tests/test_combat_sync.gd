extends GutTest

## Purpose: combat, carrying and the world's props over a real host/client session: two scene branches with their
## own MultiplayerAPI talking ENet on localhost, as in test_multiplayer_spawning.gd. A client's automatic fires at its
## interval, not every tick; the ProjectileSpawner spawns only listed scenes for the sender's own shooter, without
## "properties"; a client's lightning reaches every peer through it; an enemy counts a client's hit, slow and hunt on
## the server, for the client's own Player only; a world body a client carries is in its hands on every peer and goes
## back to the server when dropped or thrown; a walk-over weapon vanishes on every peer; and a talking NPC talks to
## one Player at a time, as the server decides.

const PORT: int = 47401
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const BULLET_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/bullet.tscn")
const ARROW_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/arrow.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")
const TALKING_NPC_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/talking_npc.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PROJECTILE_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/projectile_spawner.gd")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")
const BODY_REPLICATION: SceneReplicationConfig = preload("res://addons/3d_player_controller/resources/replication/rigid_body_replication.tres")


## Stands in for weather_fx's LightningFX: the same group and the same two server-owned RPCs, recording the bolts.
class FakeLightning extends Node3D:
	var strikes: Array[Vector3] = []
	var arcs: Array[Vector3] = []

	func _ready() -> void:
		add_to_group(&"LightningFX")

	@rpc("authority", "call_local", "reliable")
	func strike_at(position: Vector3, _hit_damage: float = -1.0) -> void:
		strikes.append(position)

	@rpc("authority", "call_local", "reliable")
	func arc(_from: Vector3, to: Vector3) -> void:
		arcs.append(to)


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
	projectile_spawner.add_spawnable_scene(BULLET_SCENE.resource_path) # the arrow is left off the list on purpose
	projectile_spawner.add_to_group(&"ProjectileSpawner") # found by multiplayer session (ProjectileSpawner.find_for)
	root.add_child(projectile_spawner)


func before_each() -> void:
	server_root = Node3D.new()
	server_root.name = "ServerBranch"
	client_root = Node3D.new()
	client_root.name = "ClientBranch"
	client_root.position = Vector3(0.0, 0.0, 300.0) # one physics world: the client's copies stand clear of the host's
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
	Input.action_release("shoot")
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


## The client's own Player, on the client.
func _mine() -> Player:
	return client_root.get_node("Players/" + str(client_api.get_unique_id())) as Player


## The host's copy of the client's Player.
func _mine_on_host() -> Player:
	return server_root.get_node("Players/" + str(client_api.get_unique_id())) as Player


## The client's copy of the host's Player: not the client's to name.
func _host_on_client() -> Player:
	return client_root.get_node("Players/1") as Player


## Waits up to [param frames] process frames for [param condition].
func _until(condition: Callable, frames: int = 90) -> void:
	for i in frames:
		if condition.call():
			return
		await wait_process_frames(1)


## Puts one node from [param make] in each branch, under the same name; returns [host's, client's].
func _in_both(make: Callable) -> Array:
	var on_host: Node = make.call()
	server_root.add_child(on_host)
	var on_client: Node = make.call()
	client_root.add_child(on_client)
	return [on_host, on_client]


func _enemy() -> EnemyNpc:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	enemy.name = "Enemy"
	enemy.position = Vector3(12.0, 0.0, 0.0) # out of its aggro area's reach of the Players, inside its leash
	return enemy


## A plain prop with a SyncedBody, as the world's balls and pins are; weightless so it stays put.
func _ball() -> RigidBody3D:
	var ball := RigidBody3D.new()
	ball.name = "Ball"
	ball.gravity_scale = 0.0
	ball.position = Vector3(0.0, 1.0, -40.0)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	ball.add_child(shape)
	var sync := SyncedBody.new()
	sync.name = "BodySynchronizer"
	sync.replication_config = BODY_REPLICATION
	ball.add_child(sync)
	return ball


func _world_sword() -> Equipment:
	var pickup := Equipment.new()
	pickup.name = "WorldSword"
	pickup.equipment_type = Equipment.EquipmentType.SWORD_1H
	pickup.bone_attachment_bone_name = "RightHand"
	pickup.position = Vector3(-40.0, 0.0, 0.0)
	var detection := Area3D.new()
	detection.name = "PlayerDetection"
	pickup.add_child(detection)
	return pickup


## H2: fire() hands a client null (its round comes through the spawner), and the gun used to start its fire timer only
## for a round it got back, so a client's automatic fired every physics tick.
func test_a_clients_automatic_fires_at_its_interval_not_every_physics_tick() -> void:
	var player: Player = _mine()
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	gun.projectile_scene = BULLET_SCENE
	gun.equipment_type = Equipment.EquipmentType.PISTOL
	gun.bone_attachment_bone_name = "RightHand"
	gun.can_shoot = true
	gun.automatic = true
	gun.fire_interval = 0.12
	gun.magazine_size = 30
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	gun.add_child(muzzle)
	gun.muzzle = muzzle
	var timer := Timer.new()
	timer.name = "FireTimer"
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	client_root.add_child(gun)
	var held: Firearm = player.inventory.equip_pickup(gun) as Firearm
	held.muzzle = held.get_node("Muzzle") as Marker3D
	held.fire_timer = held.get_node("FireTimer") as Timer
	gun.queue_free()
	var spawned_on_host: Array[Node] = []
	server_root.get_node("Projectiles").child_entered_tree.connect(func(node: Node) -> void: spawned_on_host.append(node))
	await wait_physics_frames(2)
	assert_eq(held.rounds, 30)
	Input.action_press("shoot")
	await wait_physics_frames(20)
	Input.action_release("shoot")
	var spent: int = 30 - held.rounds
	assert_between(spent, 1, 4, "About one round per 0.12 s over a third of a second, not one every physics tick")
	await _until(func() -> bool: return spawned_on_host.size() >= spent)
	assert_eq(spawned_on_host.size(), spent, "and the host spawned exactly the rounds the client spent")


## M1: a client's request names a scene and a shooter; the host spawns only a scene on its list, only for the
## sender's own shooter, and never sets "properties" a client sent.
func test_the_host_spawns_only_listed_scenes_for_the_senders_own_shooter_without_properties() -> void:
	var client_spawner: ProjectileSpawner = client_root.get_node("ProjectileSpawner")
	var on_host: Node = server_root.get_node("Projectiles")
	var far: Transform3D = Transform3D(Basis.IDENTITY, Vector3(300.0, 50.0, 0.0))
	client_spawner.fire(ARROW_SCENE, far, Vector3.FORWARD, 30.0, _mine())
	client_spawner.fire(BULLET_SCENE, far, Vector3.FORWARD, 30.0, _host_on_client())
	await wait_process_frames(15)
	assert_eq(on_host.get_child_count(), 0, "A scene off the list, or a shooter that is not the sender's, spawns nothing")
	client_spawner.fire(BULLET_SCENE, far, Vector3.FORWARD, 30.0, _mine(), null, {"properties": {"damage": 9999.0}})
	await _until(func() -> bool: return on_host.get_child_count() > 0)
	assert_eq(on_host.get_child_count(), 1, "The sender's own shot of a listed scene spawns")
	var plain: Projectile = BULLET_SCENE.instantiate()
	assert_eq((on_host.get_child(0) as Projectile).damage, plain.damage, "without the properties the client sent")
	plain.free()


## H15: LightningFX's bolts are the server's to call, so a client's lightning spell goes through the spawner, which
## checks the caster is the sender's and has the bolt play on every peer, through the LightningFX of its own session
## even when another session's comes first in the group.
func test_a_clients_lightning_reaches_every_peer_through_the_spawner() -> void:
	move_child(client_root, server_root.get_index()) # the client's LightningFX is now the group's first node
	var bolts: Array = _in_both(func() -> Node:
		var lightning := FakeLightning.new()
		lightning.name = "LightningFX"
		return lightning)
	var on_host: FakeLightning = bolts[0]
	var on_client: FakeLightning = bolts[1]
	var client_spawner: ProjectileSpawner = client_root.get_node("ProjectileSpawner")
	client_spawner.strike_lightning(Vector3(9.0, 0.0, 9.0), _host_on_client()) # not the client's caster: refused
	client_spawner.strike_lightning(Vector3(1.0, 0.0, 2.0), _mine())
	client_spawner.arc_lightning(Vector3.ZERO, Vector3(3.0, 0.0, 0.0), _mine())
	await _until(func() -> bool: return on_client.strikes.size() > 0 and on_client.arcs.size() > 0)
	assert_eq(on_host.strikes, [Vector3(1.0, 0.0, 2.0)] as Array[Vector3], "The host strikes where the client's spell said")
	assert_eq(on_client.strikes, [Vector3(1.0, 0.0, 2.0)] as Array[Vector3], "and the client sees the same bolt")
	assert_eq(on_host.arcs, [Vector3(3.0, 0.0, 0.0)] as Array[Vector3], "An arc goes the same way")
	assert_eq(on_client.arcs, [Vector3(3.0, 0.0, 0.0)] as Array[Vector3])


## H3 and M3: the server counts a client's hit and puts the client's own Player on the threat table; the client's
## copy of the enemy hunts nobody, the client's Player hears it is hunted from the server, and a hit in another
## Player's name or a negative one does nothing.
func test_an_enemy_counts_a_clients_hit_on_the_server_for_the_clients_own_player_only() -> void:
	var pair: Array = _in_both(_enemy)
	var on_host: EnemyNpc = pair[0]
	var on_client: EnemyNpc = pair[1]
	await wait_process_frames(5)
	var mine: Player = _mine()
	var full: float = on_host.health.max_health
	on_client.take_hit(30.0, mine.global_position, on_client.get_path_to(mine))
	await _until(func() -> bool: return on_host.health.health < full)
	assert_eq(on_host.health.health, full - 30.0, "The server counts the client's hit")
	assert_eq(on_host.target, _mine_on_host(), "and hunts the host's copy of the client's Player")
	assert_true(on_host.threat.has(_mine_on_host()), "which is on its threat table")
	assert_null(on_client.target, "The client's copy of the enemy hunts nobody")
	assert_true(on_client.threat.is_empty(), "and keeps no table of its own")
	await _until(func() -> bool: return mine.hunters.size() > 0)
	assert_eq(mine.hunters.size(), 1, "The client's Player hears it is hunted, from the server")
	on_client.take_hit(500.0, mine.global_position, on_client.get_path_to(_host_on_client()))
	on_client.take_hit(-100.0, mine.global_position, on_client.get_path_to(mine))
	await wait_process_frames(20)
	assert_eq(on_host.health.health, full - 30.0, "A hit in another Player's name is refused, and a negative one heals nothing")


## H3: a slow relayed by a client lands for a caster of its own and not in somebody else's name.
func test_an_enemy_takes_a_clients_slow_only_for_the_clients_own_caster() -> void:
	var pair: Array = _in_both(_enemy)
	var on_host: EnemyNpc = pair[0]
	var on_client: EnemyNpc = pair[1]
	await wait_process_frames(5)
	on_client.slow(0.0, 999.0, on_client.get_path_to(_host_on_client()))
	on_client.slow(0.25, 5.0, on_client.get_path_to(_mine()))
	await _until(func() -> bool: return on_host.movement_scale < 1.0)
	await wait_process_frames(5)
	assert_almost_eq(on_host.movement_scale, 0.25, 0.001, "The client's own slow lands and the one in the host's name does not")


## M3: a noise on the client (PlayerNoise calls aggro) asks the server, which hunts the client's own Player only.
func test_a_clients_noise_asks_the_server_to_hunt_the_clients_own_player() -> void:
	var pair: Array = _in_both(_enemy)
	var on_host: EnemyNpc = pair[0]
	var on_client: EnemyNpc = pair[1]
	await wait_process_frames(5)
	on_client.aggro(_host_on_client())
	await wait_process_frames(15)
	assert_null(on_host.target, "A client cannot set the enemy on somebody else")
	on_client.aggro(_mine())
	await _until(func() -> bool: return on_host.target != null)
	assert_eq(on_host.target, _mine_on_host(), "It hunts the client's own Player, on the server")
	assert_null(on_client.target, "and the client's copy leaves the hunt to the server")


## H4: a world body a client picks up is in its hands on every peer and answers to the client for the carry; nobody
## else can take it meanwhile; a drop puts it back where it was and hands it to the server, and a throw is the
## server's to make.
func test_a_clients_carry_is_seen_everywhere_and_the_body_goes_back_to_the_server() -> void:
	var balls: Array = _in_both(_ball)
	var on_host: RigidBody3D = balls[0]
	var on_client: RigidBody3D = balls[1]
	await wait_process_frames(10)
	var mine: Player = _mine()
	var mine_on_host: Player = _mine_on_host()
	var client_id: int = client_api.get_unique_id()
	assert_true(on_client.freeze, "The client's copy follows the server's, frozen by its SyncedBody")
	mine.held_object._request_pickup.rpc_id(1, mine.held_object.get_path_to(on_client))
	await _until(func() -> bool: return on_host.get_parent() == mine_on_host.item_spring_arm and on_client.get_parent() == mine.item_spring_arm)
	assert_eq(on_host.get_parent(), mine_on_host.item_spring_arm, "On the host the ball is in the client's hands")
	assert_eq(on_client.get_parent(), mine.item_spring_arm, "and on the client")
	assert_eq(on_host.get_multiplayer_authority(), client_id, "It answers to the carrier's peer on the host")
	assert_eq(on_host.get_node("BodySynchronizer").get_multiplayer_authority(), client_id, "synchronizer and all")
	assert_eq(on_client.get_multiplayer_authority(), client_id, "and on the client")
	assert_true(mine.held_object.is_holding_rigidbody())
	var host: Player = server_root.get_node("Players/1")
	host.held_object._request_pickup.rpc_id(1, host.held_object.get_path_to(on_host))
	await wait_process_frames(10)
	assert_eq(on_host.get_parent(), mine_on_host.item_spring_arm, "Nobody else can take a body out of the carrier's hands")

	mine.held_object.drop_held_rigidbody()
	await _until(func() -> bool: return on_host.get_parent() == server_root and on_client.get_parent() == client_root)
	assert_eq(on_host.get_parent(), server_root, "A drop puts it back where it was, on the host")
	assert_eq(on_client.get_parent(), client_root, "and on the client")
	assert_eq(on_host.get_multiplayer_authority(), 1, "and it is the server's again")
	assert_eq(on_client.get_multiplayer_authority(), 1)
	assert_false(on_host.freeze, "The server simulates it")
	assert_true(on_client.freeze, "and the client follows it")

	mine.held_object._request_pickup.rpc_id(1, mine.held_object.get_path_to(on_client))
	await _until(func() -> bool: return on_client.get_parent() == mine.item_spring_arm)
	mine.held_object.execute_instant_throw(Vector3.FORWARD, 1.0)
	await _until(func() -> bool: return on_host.get_parent() == server_root and on_host.linear_velocity.length() > 0.5)
	assert_gt(on_host.linear_velocity.length(), 0.5, "The server throws it")
	assert_eq(on_host.get_multiplayer_authority(), 1, "as its own")
	assert_false(mine.held_object.is_holding_object(), "and the client's hands are empty")


## M4: a walk-over weapon taken on one peer is spent on every peer, not only the taker's.
func test_a_walk_over_weapon_taken_on_a_client_vanishes_on_every_peer() -> void:
	var swords: Array = _in_both(_world_sword)
	var on_host: Equipment = swords[0]
	var on_client: Equipment = swords[1]
	await wait_process_frames(5)
	on_client._on_player_detection_body_entered(_mine())
	assert_true(_mine().inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The client takes it")
	await _until(func() -> bool: return not on_host.visible)
	assert_false(on_host.visible, "and the host's copy of the pickup vanishes")
	assert_false(on_client.visible)
	await wait_physics_frames(2)
	assert_false(on_host.player_detection.monitoring, "so nobody takes it again there")
	assert_false(on_client.player_detection.monitoring)


## H10: the take goes through the server, which spends the pickup only for the sender's own Player. A client
## naming somebody else's Player, the host's here, is ignored, so nobody can hide a world weapon they never took.
func test_a_forged_take_for_another_players_pickup_is_ignored() -> void:
	var swords: Array = _in_both(_world_sword)
	var on_host: Equipment = swords[0]
	var on_client: Equipment = swords[1]
	await wait_process_frames(5)
	on_client._request_vanish.rpc_id(1, on_client.get_path_to(_host_on_client()))
	await wait_process_frames(30)
	assert_true(on_host.visible, "The host's copy stays: the host's Player is not the client's to take with")
	assert_true(on_client.visible, "and so does the client's")
	assert_true(on_host.player_detection.monitoring, "still there to be taken")
	assert_false(_host_on_client().inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "and nobody got a sword")


## L1: talk and end_talk go to the server, which starts and ends the conversation on every peer, one talker at a time.
func test_a_talking_npc_talks_to_one_player_at_a_time_as_the_server_decides() -> void:
	var npcs: Array = _in_both(func() -> Node:
		var npc: TalkingNpc = TALKING_NPC_SCENE.instantiate()
		npc.name = "Npc"
		npc.position = Vector3(0.0, 0.0, -60.0)
		return npc)
	var on_host: TalkingNpc = npcs[0]
	var on_client: TalkingNpc = npcs[1]
	await wait_process_frames(5)
	watch_signals(on_host)
	watch_signals(on_client)
	var mine: Player = _mine()
	assert_true(on_client.talk(mine), "The client asks to talk")
	await _until(func() -> bool: return on_client.talker == mine and on_host.talker != null)
	assert_eq(on_host.talker, _mine_on_host(), "The host's NPC is talking to the client's Player")
	assert_eq(on_client.talker, mine, "and so is the client's")
	assert_true(mine.is_paused, "The talker is held still on its own peer")
	assert_false(_mine_on_host().is_paused, "and nowhere else")
	assert_signal_emitted(on_client, "talked_to", "The conversation starts where the talker is")
	assert_signal_not_emitted(on_host, "talked_to", "not on the host")
	var host: Player = server_root.get_node("Players/1")
	on_host._request_talk.rpc_id(1, on_host.get_path_to(host))
	await wait_process_frames(10)
	assert_eq(on_host.talker, _mine_on_host(), "Somebody else waits until the conversation is over")
	on_client.end_talk()
	await _until(func() -> bool: return on_client.talker == null and on_host.talker == null)
	assert_null(on_host.talker, "The end reaches the host")
	assert_null(on_client.talker)
	assert_false(mine.is_paused, "and lets the talker go")
	assert_signal_emitted(on_client, "conversation_ended")
