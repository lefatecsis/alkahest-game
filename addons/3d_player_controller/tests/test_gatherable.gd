extends GutTest

## Purpose: a Gatherable (scenes/prop/gatherable.tscn) gives its item to whoever strikes it with the right tool, every
## few hits, fires struck with its progress for every counted strike, is spent after its yields (hidden, or left
## standing without hide_when_spent) and grows back on its RegrowTimer; over a real host/client session the server
## counts a client's hits, the client's own inventory gets the yield, struck fires on every peer, and a felled one is
## felled on every peer.

const PORT: int = 47402
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const GATHERABLE_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/prop/gatherable.tscn")
const PLAYER_SPAWNER: Script = preload("res://addons/3d_player_controller/scripts/player_spawner.gd")

var log_item: Item


func before_each() -> void:
	log_item = Item.new()
	log_item.id = &"test_gatherable_log"


## A tree needing an axe, two hits a log, two logs and it is spent; a box shape so its collision can be seen to go.
func _tree() -> Gatherable:
	var tree: Gatherable = GATHERABLE_SCENE.instantiate()
	tree.name = "Tree"
	tree.item = log_item
	tree.hits_per_yield = 2
	tree.total_yields = 2
	tree.needs = Gatherable.Needs.LOGGING
	tree.position = Vector3(0.0, 0.0, -20.0)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	tree.add_child(shape)
	return tree


func _axe(player: Player) -> Equipment:
	var axe := Equipment.new()
	axe.can_log = true
	axe.player = player
	return axe


func test_the_right_tool_gathers_every_few_hits_until_it_is_spent_and_it_grows_back() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var tree: Gatherable = _tree()
	tree.regrow_seconds = 0.3
	add_child_autofree(tree)
	var axe: Equipment = _axe(player)
	autofree(axe)
	var bare_hands: Equipment = Equipment.new()
	bare_hands.player = player
	autofree(bare_hands)
	await wait_physics_frames(2)
	assert_true(tree.is_in_group(&"Gatherable"), "A swing reaches it through the Gatherable group")
	watch_signals(tree)
	tree.register_weapon_hit(bare_hands)
	assert_eq(tree.hits, 0, "The wrong tool does nothing")
	assert_signal_not_emitted(tree, "struck", "and strikes nothing")
	tree.register_weapon_hit(axe)
	assert_eq(tree.hits, 1)
	assert_signal_emitted_with_parameters(tree, "struck", [0.25])
	assert_eq(player.inventory.count_of(log_item), 0, "One hit is not a log yet")
	tree.register_weapon_hit(axe)
	assert_eq(player.inventory.count_of(log_item), 1, "Every second hit puts a log in the striker's bag")
	assert_signal_emitted_with_parameters(tree, "harvested", [player, log_item, 1])
	assert_eq(tree.hits, 0)
	tree.register_weapon_hit(axe)
	tree.register_weapon_hit(axe)
	assert_eq(player.inventory.count_of(log_item), 2)
	assert_signal_emitted_with_parameters(tree, "struck", [1.0])
	assert_true(tree.is_spent, "After its yields it is spent")
	assert_signal_emitted(tree, "depleted")
	assert_false(tree.visible, "and gone from sight")
	await wait_physics_frames(1)
	assert_true((tree.get_node("CollisionShape3D") as CollisionShape3D).disabled, "and from the way")
	tree.register_weapon_hit(axe)
	tree.register_weapon_hit(axe)
	assert_eq(player.inventory.count_of(log_item), 2, "A spent one gives nothing")
	assert_signal_emit_count(tree, "struck", 4, "and strikes nothing")
	assert_false(tree.regrow_timer.is_stopped(), "The scene's RegrowTimer is running")
	await wait_seconds(0.45)
	assert_false(tree.is_spent, "and brings it back")
	assert_true(tree.visible)
	await wait_physics_frames(1)
	assert_false((tree.get_node("CollisionShape3D") as CollisionShape3D).disabled)


## Without hide_when_spent a spent one stays as it stands, a stump or a bare rock, still in the way; one that never runs
## out reads its progress toward the next yield.
func test_a_spent_one_stays_standing_without_hide_when_spent() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var tree: Gatherable = _tree()
	tree.hide_when_spent = false
	add_child_autofree(tree)
	var axe: Equipment = _axe(player)
	autofree(axe)
	await wait_physics_frames(2)
	watch_signals(tree)
	for i in 4:
		tree.register_weapon_hit(axe)
	assert_true(tree.is_spent, "Its yields given, it is spent")
	assert_signal_emitted(tree, "depleted")
	assert_true(tree.visible, "but still standing")
	await wait_physics_frames(1)
	assert_false((tree.get_node("CollisionShape3D") as CollisionShape3D).disabled, "and still in the way")
	var bush: Gatherable = _tree()
	bush.name = "Bush"
	bush.total_yields = 0
	add_child_autofree(bush)
	await wait_physics_frames(1)
	watch_signals(bush)
	for i in 3:
		bush.register_weapon_hit(axe)
	assert_eq(get_signal_parameters(bush, "struck", 0), [0.5], "One that never runs out reads toward the next yield")
	assert_eq(get_signal_parameters(bush, "struck", 1), [1.0], "full on the yield")
	assert_eq(get_signal_parameters(bush, "struck", 2), [0.5], "and starts again")
	assert_false(bush.is_spent)


## Over ENet: a client's swing is counted by the server, its yield lands in the client's own bag, a swing in the host's
## name is refused, every counted strike fires struck on both peers, and the spent tree is hidden on both peers.
func test_a_clients_swings_are_counted_on_the_server_and_a_felled_tree_is_felled_everywhere() -> void:
	var server_root := Node3D.new()
	server_root.name = "ServerBranch"
	var client_root := Node3D.new()
	client_root.name = "ClientBranch"
	client_root.position = Vector3(0.0, 0.0, 300.0)
	add_child(server_root)
	add_child(client_root)
	var server_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK)
	server_api.multiplayer_peer = server_peer
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	for root: Node3D in [server_root, client_root]:
		var players := Node3D.new()
		players.name = "Players"
		root.add_child(players)
		var spawner: PlayerSpawner = PLAYER_SPAWNER.new()
		spawner.name = "PlayerSpawner"
		spawner.spawn_path = NodePath("../Players")
		spawner.add_child(PLAYER_SCENE.instantiate())
		root.add_child(spawner)
		root.add_child(_tree())
	for i in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	await wait_process_frames(30)

	var client_id: String = str(client_api.get_unique_id())
	var mine: Player = client_root.get_node("Players/" + client_id)
	var host_on_client: Player = client_root.get_node("Players/1")
	var on_host: Gatherable = server_root.get_node("Tree")
	var on_client: Gatherable = client_root.get_node("Tree")
	var axe: Equipment = _axe(mine)
	autofree(axe)
	var hosts_axe: Equipment = _axe(host_on_client)
	autofree(hosts_axe)
	watch_signals(on_host)
	watch_signals(on_client)
	on_client.register_weapon_hit(hosts_axe) # the host's swing is not the client's to report
	await wait_process_frames(10)
	assert_eq(on_host.hits, 0, "A swing in another Player's name is refused")
	assert_signal_not_emitted(on_client, "struck", "and strikes nothing")
	on_client.register_weapon_hit(axe)
	for i in 60:
		await wait_process_frames(1)
		if on_client.hits == 1:
			break
	assert_eq(on_host.hits, 1, "The server counts the client's swing")
	assert_eq(on_client.hits, 1, "and the count reaches the client")
	for i in 60:
		await wait_process_frames(1)
		if get_signal_emit_count(on_client, "struck") == 1:
			break
	assert_signal_emitted_with_parameters(on_host, "struck", [0.25])
	assert_signal_emitted_with_parameters(on_client, "struck", [0.25])
	on_client.register_weapon_hit(axe)
	for i in 60:
		await wait_process_frames(1)
		if mine.inventory.count_of(log_item) == 1:
			break
	assert_eq(mine.inventory.count_of(log_item), 1, "The yield lands in the client's own bag")
	on_client.register_weapon_hit(axe)
	on_client.register_weapon_hit(axe)
	for i in 60:
		await wait_process_frames(1)
		if on_client.is_spent:
			break
	assert_true(on_host.is_spent, "Its yields given, it is spent on the server")
	assert_true(on_client.is_spent, "and on the client")
	assert_false(on_client.visible, "felled for everyone")
	assert_eq(mine.inventory.count_of(log_item), 2)
	for i in 60:
		await wait_process_frames(1)
		if get_signal_emit_count(on_client, "struck") == 4:
			break
	assert_signal_emit_count(on_host, "struck", 4, "Every counted strike plays on the host")
	assert_signal_emit_count(on_client, "struck", 4, "and on the client")
	assert_signal_emitted_with_parameters(on_client, "struck", [1.0])

	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)
