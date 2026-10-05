extends GutTest

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")


func test_player_synchronizer_node_exists() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	assert_not_null(player.player_synchronizer, "Player should have PlayerSynchronizer node")
	assert_true(player.player_synchronizer is MultiplayerSynchronizer, "PlayerSynchronizer should be a MultiplayerSynchronizer")
	assert_not_null(player.player_synchronizer.replication_config, "PlayerSynchronizer should have a SceneReplicationConfig")


func test_player_synchronizer_properties_tracked() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var config: SceneReplicationConfig = player.player_synchronizer.replication_config
	assert_not_null(config, "Replication config must not be null")

	var tracked_properties: Array[NodePath] = config.get_properties()
	assert_true(tracked_properties.has(NodePath(".:position")), "Should track player position")
	assert_true(tracked_properties.has(NodePath(".:rotation")), "Should track player rotation")
	assert_true(tracked_properties.has(NodePath("PlayerModel:position")), "Should track PlayerModel position")
	assert_true(tracked_properties.has(NodePath("PlayerModel:rotation")), "Should track PlayerModel rotation")
	assert_true(tracked_properties.has(NodePath(".:sync_locomotion_node")), "Should track sync_locomotion_node")
	assert_true(tracked_properties.has(NodePath(".:sync_blend_position")), "Should track sync_blend_position")
	assert_true(tracked_properties.has(NodePath(".:current_state")), "Should track current_state")


func test_animation_sync_properties_update() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	# Test blend position update
	player.sync_blend_position = Vector2(0.5, 0.8)
	assert_eq(player.sync_blend_position, Vector2(0.5, 0.8), "sync_blend_position should store blend coordinates")

	# Test locomotion node name update
	player.sync_locomotion_node = "StandingLocomotion"
	assert_eq(player.sync_locomotion_node, "StandingLocomotion", "sync_locomotion_node should store state name")


func _make_puppet() -> Player:
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.set_multiplayer_authority(2)
	add_child_autofree(puppet)
	return puppet


func test_puppet_applies_grouped_locomotion_path() -> void:
	var puppet: Player = _make_puppet()
	puppet.sync_locomotion_node = "Bow/BowLocomotion"
	await wait_physics_frames(5)
	assert_eq(String(puppet.locomotion_state.get_current_node()), "Bow", "Root machine should enter the Bow group")
	assert_eq(puppet.current_locomotion_node, "BowLocomotion", "Inner machine should reach the synced node")


func test_puppet_applies_root_locomotion_node_without_bow_group() -> void:
	var puppet: Player = _make_puppet()
	puppet.sync_locomotion_node = "CrouchingLocomotion"
	await wait_physics_frames(5)
	assert_eq(String(puppet.locomotion_state.get_current_node()), "CrouchingLocomotion", "Root-level nodes must not be routed through the Bow group")


func test_puppet_blend_position_targets_synced_node() -> void:
	var puppet: Player = _make_puppet()
	puppet.sync_locomotion_node = "CrouchingLocomotion"
	puppet.sync_blend_position = Vector2(0.0, 0.7)
	assert_eq(puppet.animation_tree.get(Player.CROUCHING_LOCOMOTION_BLEND_POSITION_PATH), Vector2(0.0, 0.7))


## The stance flags are replicated getters. On the authority they read the input and the AnimationTree; on a
## puppet they must hand back what the synchronizer wrote, or the puppet never aims, draws or swings.
func test_a_puppet_reads_the_stance_flags_the_authority_sent() -> void:
	var branch: Node = Node.new()
	branch.set_multiplayer_authority(42)
	add_child_autofree(branch)
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.set_multiplayer_authority(42)
	branch.add_child(puppet)
	assert_false(puppet.is_multiplayer_authority(), "The Player belongs to peer 42")
	# The synchronizer writes the backing field, as it does on a real puppet
	puppet.is_shooting = true
	puppet.is_aiming_bow = true
	puppet.is_drawing_arrow = true
	puppet.is_firing_arrow = true
	puppet.is_mining = true
	puppet.is_logging = true
	assert_true(puppet.is_shooting, "A puppet reports the synced value, not its own absent input")
	assert_true(puppet.is_aiming_bow)
	assert_true(puppet.is_drawing_arrow)
	assert_true(puppet.is_firing_arrow)
	assert_true(puppet.is_mining)
	assert_true(puppet.is_logging)


## The name over the head is a replicated property: the setter writes the label, and spawn state that lands
## before the label exists is applied on ready.
func test_display_name_writes_the_label_and_replicates() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.display_name = "Kirby"
	add_child_autofree(player)
	assert_eq(player.steam_persona_name.text, "Kirby", "Applied once the label exists")
	assert_true(player.steam_persona_name.visible)
	player.display_name = ""
	assert_false(player.steam_persona_name.visible, "Empty hides the label")
	var tracked: Array[NodePath] = player.player_synchronizer.replication_config.get_properties()
	assert_true(tracked.has(NodePath(".:display_name")), "so every peer reads it")


## The camera a peer controls claims the view when it is ready, and a remote player's copy spawning after it
## leaves the view alone: the scene marks no camera current, so nothing is taken over on entering the tree.
## (A camera entering an empty viewport is made current by the engine, so the order here is the real one.)
func test_a_puppet_spawning_later_does_not_take_the_view() -> void:
	var own: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(own)
	await wait_process_frames(2)
	assert_true(own.camera.current, "The player this peer controls looks through its own camera")
	var host: Node = Node.new()
	host.name = "42"
	host.set_multiplayer_authority(42)
	add_child_autofree(host)
	var puppet: Player = PLAYER_SCENE.instantiate()
	puppet.name = "42"
	host.add_child(puppet)
	await wait_process_frames(2)
	assert_false(puppet.is_multiplayer_authority())
	assert_false(puppet.camera.current, "A remote player's camera is not this peer's view")
	assert_true(own.camera.current, "and the view stayed where it was")


## The emote layer's weight over the spine crosses with the Player, so a puppet's copy of a throw or a draw
## shows on its upper body; before this only the authority's tree was ever raised.
func test_the_emote_spine_blend_reaches_a_puppets_tree() -> void:
	var host: Node = Node.new()
	host.name = "42"
	host.set_multiplayer_authority(42)
	add_child_autofree(host)
	var puppet: Player = PLAYER_SCENE.instantiate()
	puppet.name = "42"
	host.add_child(puppet)
	await wait_process_frames(2)
	assert_false(puppet.is_multiplayer_authority())
	puppet.emote_spine_blend = 1.0 # what the synchronizer writes when the authority raises it
	assert_eq(float(puppet.animation_tree.get("parameters/EmoteSpineBlend2/blend_amount")), 1.0, "The puppet's spine blend follows")
	puppet.emote_spine_blend = 0.0
	assert_eq(float(puppet.animation_tree.get("parameters/EmoteSpineBlend2/blend_amount")), 0.0, "and lowers again")
	var config: SceneReplicationConfig = puppet.get_node("PlayerSynchronizer").replication_config
	assert_true(config.has_property(NodePath(".:emote_spine_blend")), "and it is in the replication config")
