extends GutTest

## Purpose: how loud the Player is. Standing still is silence, crouching is near silence, sprinting is loud,
## and a gunshot or a landing spikes the reading and falls back. Whatever is inside the audible distance is
## told to come looking, and the HUD meter follows the reading of this peer's own Player.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/npc/enemy_npc.tscn")
const METER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/noise_meter.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")
const PORT: int = 47434

var root: Node3D
var player: Player
var noise: PlayerNoise


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	noise = player.get_node("PlayerNoise") as PlayerNoise
	await wait_physics_frames(2)


func test_standing_still_is_silence() -> void:
	player.velocity = Vector3.ZERO
	await wait_physics_frames(3)
	assert_almost_eq(noise.moving_level(), 0.0, 0.001, "A Player who is not moving makes no noise")


## Crouching halves the noise, it does not mute it. It used to be a hard ceiling, which meant a crouch-walk
## read the same flat line however fast you were going, and the meter looked broken while you were moving.
func test_crouching_halves_the_noise_rather_than_silencing_it() -> void:
	player.velocity = Vector3(3.0, 0.0, 0.0)
	player.is_crouching = false
	var walking: float = noise.moving_level()
	player.is_crouching = true
	var crouched: float = noise.moving_level()

	assert_gt(walking, crouched, "The same pace crouched is quieter")
	assert_almost_eq(crouched, walking * noise.crouch_multiplier, 0.001, "by half, not to nothing")
	assert_gt(crouched, 0.05, "and a crouch-walk still reads on the meter")


## The pace still tells within a crouch, which a ceiling took away.
func test_a_crouch_walk_is_louder_than_a_crouch_creep() -> void:
	player.is_crouching = true
	player.velocity = Vector3(1.0, 0.0, 0.0)
	var creeping: float = noise.moving_level()
	player.velocity = Vector3(4.0, 0.0, 0.0)
	var walking: float = noise.moving_level()

	assert_gt(walking, creeping, "Moving faster while crouched is louder than creeping")


func test_sprinting_is_the_loudest_way_to_move() -> void:
	player.velocity = Vector3(5.5, 0.0, 0.0)
	player.is_crouching = false
	player.is_sprinting = false
	var walking: float = noise.moving_level()
	player.is_sprinting = true
	var sprinting: float = noise.moving_level()

	assert_gt(sprinting, walking, "Sprinting is louder than the same speed at a walk")
	assert_almost_eq(sprinting, noise.sprinting_level, 0.05, "and at full pace it reads about the sprint level")


func test_stealth_takes_the_edge_off() -> void:
	player.velocity = Vector3(4.0, 0.0, 0.0)
	var plain: float = noise.moving_level()
	player.is_stealthed = true
	var hidden: float = noise.moving_level()

	assert_lt(hidden, plain, "Stealth quiets the footfall")


func test_a_one_off_noise_spikes_and_falls_back() -> void:
	noise.make_noise(1.0)
	await wait_physics_frames(2)
	var spiked: float = noise.level
	await wait_seconds(0.6)
	var later: float = noise.level

	assert_gt(spiked, 0.4, "A gunshot is heard at once")
	assert_lt(later, spiked, "and fades rather than hanging there")


func test_a_gunshot_carries_further_than_a_sneak() -> void:
	player.is_crouching = true
	player.velocity = Vector3(1.0, 0.0, 0.0)
	await wait_physics_frames(4)
	var sneaking_reach: float = noise.audible_distance()

	noise.make_noise(noise.firearm_noise)
	await wait_physics_frames(4)
	var shot_reach: float = noise.audible_distance()

	assert_gt(shot_reach, sneaking_reach * 3.0, "A shot carries far further than a sneak")
	assert_almost_eq(shot_reach, noise.hearing_range, noise.hearing_range * 0.35,
		"and a shot at full level carries about the whole hearing range")


func test_an_enemy_in_earshot_comes_looking_and_one_out_of_it_does_not() -> void:
	var near: EnemyNpc = ENEMY_SCENE.instantiate()
	var far: EnemyNpc = ENEMY_SCENE.instantiate()
	root.add_child(near)
	root.add_child(far)
	# Both stand clear of the enemy's own 4.5m sight aggro, so only hearing can explain either result
	near.global_position = player.global_position + Vector3(10.0, 0.0, 0.0)
	far.global_position = player.global_position + Vector3(0.0, 0.0, 28.0)
	await wait_physics_frames(3)
	assert_null(near.target, "Nobody is hunting yet")

	noise.make_noise(0.5)   # carries 15m at the default range
	await wait_seconds(0.5)

	assert_eq(near.target, player, "The one in earshot heard it")
	assert_null(far.target, "The one out of earshot did not")


func test_a_sneaking_player_wakes_nobody() -> void:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	root.add_child(enemy)
	enemy.global_position = player.global_position + Vector3(8.0, 0.0, 0.0)   # outside its own sight aggro
	player.is_crouching = true
	player.velocity = Vector3(1.0, 0.0, 0.0)
	await wait_seconds(0.6)

	assert_null(enemy.target, "A sneak at eight metres goes unheard")


func test_the_meter_follows_the_reading() -> void:
	var meter: Control = METER_SCENE.instantiate()
	add_child_autofree(meter)
	var line: NoiseMeter = meter.get_node("Line") as NoiseMeter
	line.noise = noise
	await wait_physics_frames(1)

	noise.make_noise(0.8)
	await wait_physics_frames(3)

	assert_gt(line.level, 0.0, "The drawn level follows PlayerNoise")
	assert_almost_eq(line.level, noise.level, 0.001, "and is the same reading, not a second opinion")


## The meter draws the noise of the Player this peer controls, handed to it by the PlayerSpawner's
## local_player_spawned (wired in the world scene). On a client the host's copy is in the tree first, and a meter
## that took the first Player it found drew that copy, which never moves on this peer and stayed flat.
func test_a_clients_meter_follows_its_own_player_not_the_hosts_copy() -> void:
	var server_root: Node3D = Node3D.new()
	server_root.name = "ServerBranch"
	var client_root: Node3D = Node3D.new()
	client_root.name = "ClientBranch"
	add_child(server_root)
	add_child(client_root)
	var server_api: SceneMultiplayer = SceneMultiplayer.new()
	var client_api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK)
	server_api.multiplayer_peer = server_peer
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	var meter: Control = METER_SCENE.instantiate()
	var line: NoiseMeter = meter.get_node("Line") as NoiseMeter
	for branch: Node3D in [server_root, client_root]:
		var players: Node3D = Node3D.new()
		players.name = "Players"
		branch.add_child(players)
		var spawner: PlayerSpawner = PLAYER_SPAWNER.new()
		spawner.name = "PlayerSpawner"
		spawner.spawn_path = NodePath("../Players")
		spawner.add_child(PLAYER_SCENE.instantiate())
		if branch == client_root:
			spawner.local_player_spawned.connect(line.follow) # as the world scene wires it
		branch.add_child(spawner)
	client_root.add_child(meter)
	var own_id: String = str(client_api.get_unique_id())
	for i in 180:
		await wait_process_frames(1)
		if client_root.get_node("Players").has_node(own_id) and client_root.get_node("Players").has_node("1"):
			break

	var own: Player = client_root.get_node("Players/" + own_id)
	assert_not_null(own, "The client's own Player spawned")
	assert_eq(line.noise, own.get_node("PlayerNoise"), "The meter draws the client's own Player")
	assert_ne(line.noise, client_root.get_node("Players/1").get_node("PlayerNoise"), "not the host's copy")
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


## Steam gates the microphone itself and normalises what it sends, so the samples inside a packet say almost
## nothing about how loudly somebody spoke: measured on a laptop, ten seconds of talking and eight of silence
## came back with the same peak, 0.0233 against 0.0246. What separates them is whether Steam sends anything at
## all, 165 packets against 10. The reading follows that flow, which is what these pin.
func test_no_voice_from_steam_reads_as_silence() -> void:
	assert_almost_eq(VoiceChat.loudness_of(0), 0.0, 0.001, "Nothing sent is nothing said")
	assert_almost_eq(VoiceChat.loudness_of(-1), 0.0, 0.001, "and neither is nonsense")


func test_more_voice_reads_louder_up_to_a_ceiling() -> void:
	var trickle: float = VoiceChat.loudness_of(186)    # the smallest packet measured
	var talking: float = VoiceChat.loudness_of(600)
	var full: float = VoiceChat.loudness_of(900)
	var torrent: float = VoiceChat.loudness_of(8202)   # the largest measured

	assert_gt(trickle, 0.0, "A small packet is still somebody speaking")
	assert_gt(talking, trickle, "and more of it reads louder")
	assert_almost_eq(full, 1.0, 0.001, "a full frame's worth fills the meter")
	assert_almost_eq(torrent, 1.0, 0.001, "and a burst is capped rather than running past the top")


func test_the_full_mark_can_be_moved_for_a_different_setup() -> void:
	assert_gt(VoiceChat.loudness_of(400, 400.0), VoiceChat.loudness_of(400),
		"Where the meter fills is a parameter, not something to edit the code for")


func test_talking_is_noise_and_holding_the_key_in_silence_is_not() -> void:
	player.voice_chat.is_broadcasting = true
	player.voice_chat.voice_loudness = 0.0
	assert_almost_eq(noise.voice_level(), 0.0, 0.001, "The key held while saying nothing is silence")

	player.voice_chat.voice_loudness = 1.0
	assert_almost_eq(noise.voice_level(), noise.voice_multiplier, 0.001, "and a full voice reads the voice level")

	player.voice_chat.is_broadcasting = false
	assert_almost_eq(noise.voice_level(), 0.0, 0.001, "and a Player not on the key is not speaking, whatever the microphone hears")


## Arriving voice keeps the reading up, so the test feeds it the way Steam would, a frame at a time.
func test_talking_is_loud_and_carries() -> void:
	player.voice_chat.is_broadcasting = true
	for i: int in 12:
		player.voice_chat.voice_loudness = 0.9
		await wait_physics_frames(1)

	assert_gt(noise.level, 0.5, "Talking is loud")
	assert_gt(noise.audible_distance(), 15.0, "and carries a long way")


## Steam sends nothing while you pause, so a held key in silence is silence. The reading drains on its own
## rather than waiting for the key to come up.
func test_the_reading_drains_when_no_voice_arrives() -> void:
	player.voice_chat.is_broadcasting = true
	player.voice_chat.voice_loudness = 0.9
	await wait_seconds(0.6)

	assert_lt(player.voice_chat.voice_loudness, 0.9, "A pause drains it even with the key still held")
	assert_almost_eq(player.voice_chat.voice_loudness, 0.0, 0.05, "and a long enough pause empties it")


func test_an_enemy_hears_you_talking() -> void:
	var enemy: EnemyNpc = ENEMY_SCENE.instantiate()
	root.add_child(enemy)
	enemy.global_position = player.global_position + Vector3(12.0, 0.0, 0.0)   # outside its own sight aggro
	await wait_physics_frames(3)
	assert_null(enemy.target, "Nobody is hunting yet")

	player.voice_chat.is_broadcasting = true
	for i: int in 24:
		player.voice_chat.voice_loudness = 0.9
		await wait_physics_frames(1)

	assert_eq(enemy.target, player, "Talking over voice chat gives your position away")
