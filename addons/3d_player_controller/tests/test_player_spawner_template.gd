extends GutTest

## Purpose: the PlayerSpawner's Player child is the template. It is a real node in the editor and never in the
## game: the spawner takes it out before it readies, and every peer's player is a duplicate of it, standing where
## the template stood and carrying the overrides and the children the world scene gave it.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var root: Node3D


func before_each() -> void:
	root = Node3D.new()
	root.name = "Branch"
	add_child_autofree(root)
	var players: Node3D = Node3D.new()
	players.name = "Players"
	root.add_child(players)


## A spawner with a template the way a world scene would set one up: moved, an export overridden, a child added.
func _spawner_with_template() -> PlayerSpawner:
	var spawner: PlayerSpawner = PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	var template: Player = PLAYER_SCENE.instantiate()
	template.position = Vector3(3.0, 0.0, -2.0)
	template.enable_paraglider = true
	var extra: Node = Node.new()
	extra.name = "FishingLog"
	template.add_child(extra)
	spawner.add_child(template)
	return spawner


func test_the_template_never_enters_the_tree_and_the_local_player_is_its_copy() -> void:
	var spawner: PlayerSpawner = _spawner_with_template()
	var template: Player = spawner.get_child(0)
	watch_signals(spawner)
	root.add_child(spawner)
	assert_false(template.is_inside_tree(), "The template leaves before it enters the tree")
	assert_false(template.is_node_ready(), "so it never readies: no camera, no HUD, no physics of its own")
	assert_eq(spawner.template, template, "The spawner keeps it")
	assert_eq(spawner.get_child_count(), 0)
	var player: Player = root.get_node_or_null("Players/1") as Player
	assert_not_null(player, "Offline the local peer is 1 and spawns on ready")
	if player == null:
		return
	assert_ne(player, template, "a copy, not the template itself")
	assert_eq(spawner.get_local_player(), player)
	assert_signal_emitted_with_parameters(spawner, "local_player_spawned", [player])
	assert_eq(player.position, Vector3(3.0, 0.0, -2.0), "standing where the template stood")
	assert_true(player.enable_paraglider, "with the template's overrides")
	assert_not_null(player.get_node_or_null("FishingLog"), "and the children the world added to it")
	assert_true(player.is_multiplayer_authority(), "Named by peer id, so this peer owns it")


func test_the_template_is_freed_with_the_spawner() -> void:
	var spawner: PlayerSpawner = _spawner_with_template()
	root.add_child(spawner)
	var template: Player = spawner.template
	spawner.free()
	assert_false(is_instance_valid(template), "No orphan left behind")


func test_a_spawner_without_a_player_child_warns_and_spawns_nothing() -> void:
	var spawner: PlayerSpawner = PlayerSpawner.new()
	spawner.spawn_path = NodePath("../Players")
	assert_gt(spawner._get_configuration_warnings().size(), 0, "The editor says what is missing")
	root.add_child(spawner)
	assert_null(spawner.template)
	assert_eq(root.get_node("Players").get_child_count(), 0)
	assert_null(spawner.get_local_player())
	var complete: PlayerSpawner = autofree(_spawner_with_template())
	assert_eq(complete._get_configuration_warnings().size(), 0, "A Player child clears it")


## A peer that quits with a crate in its hands: the crate hangs under that Player's hands, so freeing the Player
## freed it too, on every peer. It goes back into the world, and to the server, before the Player goes.
func test_a_body_carried_by_a_player_who_leaves_stays_in_the_world() -> void:
	var spawner: PlayerSpawner = _spawner_with_template()
	root.add_child(spawner)
	var player: Player = root.get_node("Players/1") as Player
	var crate: RigidBody3D = RigidBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	crate.add_child(shape)
	root.add_child(crate)
	player.held_object._pickup_rigidbody(crate)
	crate.set_multiplayer_authority(7) # a carried body answers to its carrier's peer, as _carry hands it over
	assert_true(player.held_object.is_holding_rigidbody(), "In the Player's hands")
	spawner.despawn_player(1)
	await wait_process_frames(2)
	assert_false(is_instance_valid(player), "The Player is gone")
	assert_true(is_instance_valid(crate), "but the crate it carried is not")
	if not is_instance_valid(crate):
		return
	assert_eq(crate.get_parent(), root, "It is back where it lived")
	assert_eq(crate.get_multiplayer_authority(), 1, "and the server's again")
