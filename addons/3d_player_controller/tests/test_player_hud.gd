extends GutTest

## Purpose: The Player's screen lives in one scene, player_hud.tscn, instanced under the Player as Hud. The Player
## still reaches every panel, bar, menu and screen through its own properties, each child still knows its Player,
## the animation graph the AnimationTree drives is the shared resource, and the HUD scene opens on its own.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const HUD_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/ui/player_hud.tscn")
const ANIMATION_TREE: AnimationNodeBlendTree = preload("res://addons/3d_player_controller/resources/animation/player_animation_tree.tres")
const CHILDREN: Array[String] = ["Controls", "Crosshair", "Stamina", "Health", "BossBar", "TargetFrame", "AmmoReadout", "CastBar", "ThrowChargeBar", "SeekerWheel", "Chat", "Debug", "Inventory", "Abilities", "QuestTracker", "UnderwaterOverlay", "DeathScreen", "SpyglassOverlay", "Pause", "Settings", "AudioSettings", "ControlsSettings", "VideoSettings", "LobbyManager"]

var player: Player


func before_each() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)


func test_the_screen_is_one_child_of_the_player() -> void:
	var hud: PlayerHud = player.hud
	assert_not_null(hud, "The Player carries a Hud")
	assert_eq(hud.player, player, "The HUD knows its Player")
	for child: String in CHILDREN:
		assert_not_null(hud.get_node_or_null(child), child + " is under the Hud")
		assert_null(player.get_node_or_null(child), child + " is no longer a direct child of the Player")


func test_the_player_still_reaches_every_panel_through_its_properties() -> void:
	assert_eq(player.controls, player.hud.controls)
	assert_eq(player.pause, player.hud.pause)
	assert_eq(player.inventory, player.hud.inventory)
	assert_eq(player.abilities, player.hud.abilities)
	assert_eq(player.chat, player.hud.chat)
	assert_eq(player.debug, player.hud.debug)
	assert_eq(player.stamina, player.hud.stamina)
	assert_eq(player.health, player.hud.health)
	assert_eq(player.crosshair, player.hud.crosshair)
	assert_eq(player.seeker_wheel, player.hud.seeker_wheel)
	assert_eq(player.quest_tracker, player.hud.quest_tracker)
	assert_eq(player.settings, player.hud.settings)
	assert_eq(player.lobby_manager, player.hud.lobby_manager)
	assert_eq(player.radial_menu, player.hud.inventory.get_node("RadialMenu"))


func test_each_panel_still_knows_its_player() -> void:
	for child: String in ["Controls", "Chat", "Debug", "Inventory", "Abilities", "SeekerWheel", "Pause", "Settings", "AudioSettings", "ControlsSettings", "VideoSettings", "LobbyManager", "DeathScreen", "Stamina"]:
		assert_eq(player.hud.get_node(child).get("player"), player, child + " points two levels up, at the Player")
	assert_eq(player.abilities.fx_root, player.get_node("SFX_Ability"), "The abilities' effects root is still the Player's")
	assert_eq(player.held_object.throw_charge_bar, player.hud.throw_charge_bar, "The held object's charge bar is the one on the Hud")


func test_the_animation_graph_is_the_shared_resource() -> void:
	assert_eq(player.animation_tree.tree_root, ANIMATION_TREE, "The AnimationTree drives resources/animation/player_animation_tree.tres")
	assert_true(player.animation_tree.active)


func test_the_hud_scene_holds_the_whole_screen_and_nothing_else() -> void:
	# Built on its own the HUD has no Player above it, so it is looked at rather than run: its panels only work under a Player.
	var hud: PlayerHud = HUD_SCENE.instantiate()
	assert_null(hud.player, "Nothing above it: no Player")
	assert_eq(hud.get_child_count(), CHILDREN.size())
	for child: String in CHILDREN:
		assert_not_null(hud.get_node_or_null(child), child + " is in the HUD scene")
	hud.free()


## The crosshair is a region of Kenney's crosshair sheet, an SVG. A change to the sheet's import scale moves every
## shape under a fixed region, and once it moved so far the region cut empty space: the node was there, visible,
## centred, and drew nothing. So the region is checked against the sheet as Godot rasterises it.
func test_the_crosshair_region_cuts_a_shape_out_of_the_sheet() -> void:
	var atlas_texture: AtlasTexture = player.crosshair.texture as AtlasTexture
	assert_not_null(atlas_texture, "The crosshair is a region of the Kenney sheet")
	var sheet: Image = Image.new()
	sheet.load_svg_from_string(FileAccess.get_file_as_string(atlas_texture.atlas.resource_path), 1.0)
	assert_eq(sheet.get_size(), Vector2i(atlas_texture.atlas.get_size()), "The sheet is imported at the scale the region was picked at")
	var region: Rect2i = Rect2i(atlas_texture.region)
	assert_true(Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(region), "The region is inside the sheet")
	var opaque: int = 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			if sheet.get_pixel(x, y).a > 0.1:
				opaque += 1
	assert_gt(opaque, 50, "The region holds a crosshair, not the space between two: %d opaque pixels" % opaque)
	assert_true(player.crosshair.visible, "and the reticle is on screen from the start")


## A screen's own scene keeps its root shown, so it can be seen in its own editor tab; the scene that instances it
## hides the instance there, not the screen's code on ready. The death screen, the quest tracker and the loading
## screen used to hide themselves in _ready.
func test_the_screens_open_shown_on_their_own_and_hidden_where_they_are_instanced() -> void:
	for path: String in ["res://addons/3d_player_controller/scenes/ui/death_screen.tscn", "res://addons/3d_player_controller/scenes/ui/quest_tracker.tscn", "res://addons/3d_player_controller/scenes/ui/loading.tscn"]:
		var screen: CanvasLayer = (load(path) as PackedScene).instantiate()
		add_child_autofree(screen)
		assert_true(screen.visible, path.get_file() + " stays shown on its own")
	assert_false(player.hud.get_node("DeathScreen").visible, "The HUD hides its death screen in the scene")
	assert_false(player.quest_tracker.visible, "and its quest tracker")
	var explorer: LobbyExplorer = (load("res://addons/3d_player_controller/scenes/ui/lobby_explorer.tscn") as PackedScene).instantiate()
	add_child_autofree(explorer)
	assert_false(explorer.loading.visible, "The lobby explorer hides its loading screen in the scene")
