extends GutTest

## Purpose: the Spellbook unlocks spells from a tree for skill points behind prerequisites, keeps a wheel of at
## most eight active spells that drives the Player's Abilities, and survives a save and a load.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const DEMO_TREE: SpellTree = preload("res://addons/3d_player_controller/inventory/resources/spell_tree_demo.tres")
const STEALTH: Ability = preload("res://addons/3d_player_controller/resources/abilities/stealth.tres")
const HEAL: Ability = preload("res://addons/3d_player_controller/resources/abilities/heal.tres")
const TEST_SAVE: String = "user://test_spells.json"
const ContractActions: GDScript = preload("res://addons/3d_player_controller/inventory/tests/contract_actions.gd")

var root: Node3D
var player: Player
var spellbook: Spellbook
var actions: RefCounted = ContractActions.new()
var _persistence_was_enabled: bool


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


func before_each() -> void:
	_persistence_was_enabled = Inventory.persistence_enabled
	Inventory.persistence_enabled = true
	root = Node3D.new()
	add_child_autofree(root)
	player = _spawn_player()
	spellbook = player.inventory.spellbook
	await wait_physics_frames(3)


func after_each() -> void:
	Inventory.persistence_enabled = _persistence_was_enabled
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)
	await wait_process_frames(1) # the spells screen's replaced buttons were queued for freeing


## A Player whose starting spells are cleared, with the demo tree and some points.
func _spawn_player(points: int = 3) -> Player:
	var spawned: Player = PLAYER_SCENE.instantiate()
	spawned.get_node("Hud/Inventory").save_path = TEST_SAVE
	var none: Array[Ability] = []
	spawned.get_node("Hud/Abilities").abilities = none
	spawned.get_node("Hud/Abilities").active_ability = null
	var book: Spellbook = spawned.get_node("Hud/Inventory/Spellbook")
	book.tree = DEMO_TREE
	book.skill_points = points
	root.add_child(spawned)
	return spawned


## A tree of eleven free spells, to fill the wheel past its limit.
func _big_tree() -> SpellTree:
	var tree: SpellTree = SpellTree.new()
	for i: int in 11:
		var ability: Ability = Ability.new()
		ability.display_name = "Spell %d" % i
		var node: SpellNode = SpellNode.new()
		node.ability = ability
		node.cost = 0
		node.column = i
		tree.nodes.append(node)
	return tree


func test_starting_spells_are_unlocked_and_on_the_wheel() -> void:
	var stock: Player = PLAYER_SCENE.instantiate()
	stock.get_node("Hud/Inventory").save_path = TEST_SAVE
	root.add_child(stock)
	await wait_physics_frames(2)
	var book: Spellbook = stock.inventory.spellbook
	assert_true(book.is_unlocked(STEALTH), "player.tscn's Stealth counts as unlocked")
	assert_true(book.is_unlocked(HEAL))
	assert_eq(book.active[0], STEALTH, "And fills the first wheel slots")
	assert_eq(book.active[1], HEAL)
	assert_eq(stock.abilities.abilities, [STEALTH, HEAL] as Array[Ability], "The wheel is the loadout")
	assert_eq(stock.abilities.active_ability, STEALTH)


func test_unlocking_spends_points_and_needs_prerequisites() -> void:
	assert_false(spellbook.is_unlocked(STEALTH))
	assert_true(spellbook.can_unlock(STEALTH), "A root node with points enough")
	assert_false(spellbook.can_unlock(HEAL), "Heal needs Stealth first")
	assert_false(spellbook.unlock(HEAL))
	watch_signals(spellbook)
	assert_true(spellbook.unlock(STEALTH))
	assert_eq(spellbook.skill_points, 2, "Stealth cost one point")
	assert_signal_emitted_with_parameters(spellbook, "spell_unlocked", [STEALTH])
	assert_true(spellbook.is_active(STEALTH), "A new spell takes the first free wheel slot")
	assert_eq(player.abilities.abilities, [STEALTH] as Array[Ability])
	assert_eq(player.abilities.active_ability, STEALTH, "And is picked when nothing was")
	assert_true(spellbook.can_unlock(HEAL), "Now Heal is reachable")
	assert_true(spellbook.unlock(HEAL))
	assert_eq(spellbook.skill_points, 0)
	assert_false(spellbook.unlock(STEALTH), "Nothing unlocks twice")


func test_too_few_points_refuses() -> void:
	spellbook.skill_points = 0
	assert_false(spellbook.can_unlock(STEALTH))
	assert_false(spellbook.unlock(STEALTH))
	assert_false(spellbook.is_unlocked(STEALTH))
	spellbook.skill_points = 1
	assert_true(spellbook.unlock(STEALTH))


func test_the_wheel_holds_eight_and_the_loadout_is_edited_by_slot() -> void:
	spellbook.tree = _big_tree()
	for node: SpellNode in spellbook.tree.nodes:
		spellbook.unlock(node.ability)
	assert_eq(spellbook.unlocked.size(), 11, "Everything unlocked")
	assert_eq(spellbook.get_active_spells().size(), Spellbook.MAX_ACTIVE, "But only eight fit on the wheel")
	assert_eq(player.abilities.abilities.size(), 8)
	var ninth: Ability = spellbook.tree.nodes[8].ability
	assert_false(spellbook.is_active(ninth))
	spellbook.set_active(2, ninth)
	assert_eq(spellbook.active[2], ninth, "Placing on a slot replaces what was there")
	spellbook.set_active(5, ninth)
	assert_null(spellbook.active[2], "A spell moved to another slot leaves its old one")
	assert_eq(spellbook.active[5], ninth)
	spellbook.clear_active(0)
	assert_null(spellbook.active[0])
	assert_eq(player.abilities.abilities.size(), 6, "The wheel follows the loadout without the gaps: two replaced, one moved off, one cleared")
	var stranger: Ability = Ability.new()
	spellbook.set_active(1, stranger)
	assert_ne(spellbook.active[1], stranger, "A spell that is not unlocked is refused")


func test_clearing_the_picked_spell_picks_another() -> void:
	spellbook.unlock(STEALTH)
	spellbook.unlock(HEAL)
	player.abilities.active_ability = HEAL
	spellbook.clear_active(1)
	assert_eq(player.abilities.active_ability, STEALTH, "The picked spell left the wheel, so the first one is picked")
	spellbook.clear_active(0)
	assert_null(player.abilities.active_ability, "An empty wheel picks nothing")


func test_spells_save_and_load_with_the_inventory() -> void:
	spellbook.unlock(STEALTH)
	spellbook.unlock(HEAL)
	spellbook.set_active(4, HEAL)
	spellbook.skill_points = 7
	assert_eq(player.inventory.save(), OK)
	var loaded: Player = _spawn_player(0)
	await wait_physics_frames(2)
	assert_true(loaded.inventory.load_save())
	var book: Spellbook = loaded.inventory.spellbook
	assert_eq(book.skill_points, 7)
	assert_true(book.is_unlocked(STEALTH))
	assert_true(book.is_unlocked(HEAL))
	assert_eq(book.active[0], STEALTH)
	assert_eq(book.active[4], HEAL, "The slot it was moved to")
	assert_null(book.active[1])
	assert_eq(loaded.abilities.abilities, [STEALTH, HEAL] as Array[Ability])


func test_persist_writes_after_an_unlock() -> void:
	player.inventory.persist = true
	spellbook.unlock(STEALTH)
	await wait_process_frames(1) # the write is deferred to the end of the frame
	assert_true(FileAccess.file_exists(TEST_SAVE), "Unlocking saved")
	var saved: Dictionary = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE)))
	var data: InventorySave = SaveGame.from_plain(saved["inventory"]) as InventorySave
	assert_true(data.spells_saved)
	assert_eq(data.unlocked_spells, [STEALTH] as Array[Ability])
	assert_eq(data.skill_points, 2)


func test_seeding_waits_for_an_abilities_node() -> void:
	var book: Spellbook = Spellbook.new()
	add_child_autofree(book) # no Inventory and no Player: nothing to seed into yet
	book._seed()
	assert_false(book._seeded, "Not seeded until there is an abilities node to apply to")
