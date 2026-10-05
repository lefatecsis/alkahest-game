extends GutTest

## Purpose: Ammunition is an inventory item. An AmmoItem picks the plain kind of its weapon type by default and the
## kind Use selected while any is carried, badging the grid "Default" or "Loaded"; a Firearm reloads by taking one
## unit from the inventory (none carried, no reload) and fires the loaded kind's own projectile scene; a Bow takes
## one arrow per shot, falls back to regular arrows when the selected kind runs out and fires nothing at zero.

const BULLET_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/bullet.tscn")
const ARROW_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/projectile/arrow.tscn")
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")
const BOW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/bow.gd")
const ARROW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/arrow.gd")

var root: Node3D
var player: Player


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(1)


## An ammunition item built in code (no .tres, so it needs an id to stack on).
func _ammo(id: StringName, type: Equipment.EquipmentType, scene: PackedScene = null, rounds_per_unit: int = 0) -> AmmoItem:
	var ammo := AmmoItem.new()
	ammo.id = id
	ammo.weapon_type = type
	ammo.projectile_scene = scene
	ammo.rounds_per_unit = rounds_per_unit
	return ammo


## A pistol on the Player, equipped, with a two-round magazine and a quick reload.
func _gun() -> Firearm:
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	gun.equipment_type = Equipment.EquipmentType.PISTOL
	gun.projectile_scene = BULLET_SCENE
	gun.magazine_size = 2
	gun.reload_time = 0.1
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.3, 1.2, -0.4)
	gun.add_child(muzzle)
	gun.muzzle = muzzle
	var timer := Timer.new()
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	root.add_child(gun)
	player.inventory.add_equipment(gun)
	return gun


## A bow on the Player, equipped, with a template arrow.
func _bow() -> Bow:
	var bow: Bow = BOW_SCRIPT.new()
	bow.player = player
	bow.equipment_type = Equipment.EquipmentType.BOW
	var template := RigidBody3D.new()
	template.name = "Arrow"
	template.set_script(ARROW_SCRIPT)
	bow.add_child(template)
	root.add_child(bow)
	player.inventory.add_equipment(bow)
	return bow


## The Materials tab index holding [param item].
func _slot_index(item: Item) -> int:
	var slots: Array = player.inventory.get_slots(Item.Category.MATERIALS)
	for i: int in slots.size():
		if slots[i] and slots[i].item.is_same(item):
			return i
	return -1


func _projectiles() -> Array:
	return root.get_children().filter(func(n: Node) -> bool: return n is Projectile and not (n as Projectile).is_template)


func test_the_plain_kind_is_the_default_whatever_the_slot_order() -> void:
	var bow: Bow = _bow()
	var ice: AmmoItem = _ammo(&"ice_arrow", Equipment.EquipmentType.BOW, BULLET_SCENE, 1)
	var plain: AmmoItem = _ammo(&"arrow", Equipment.EquipmentType.BOW, null, 1)
	assert_null(bow.get_ammo(), "Nothing carried, nothing to draw")
	player.inventory.add_item(ice, 5)
	assert_eq(bow.get_ammo(), ice, "Only special arrows carried: they are what flies")
	assert_eq(ice.get_badge(player), "Default", "And the grid says so")
	player.inventory.add_item(plain, 5)
	assert_eq(bow.get_ammo(), plain, "With nothing selected the plain kind wins, even from a later slot")
	assert_eq(AmmoItem.find_default(player.inventory, Equipment.EquipmentType.BOW), plain)
	assert_null(AmmoItem.find_default(player.inventory, Equipment.EquipmentType.RIFLE), "Arrows load no rifle")


func test_use_selects_the_kind_and_badges_the_grid() -> void:
	var bow: Bow = _bow()
	var plain: AmmoItem = _ammo(&"arrow", Equipment.EquipmentType.BOW, null, 1)
	var ice: AmmoItem = _ammo(&"ice_arrow", Equipment.EquipmentType.BOW, BULLET_SCENE, 1)
	var mag: AmmoItem = _ammo(&"pistol_magazine", Equipment.EquipmentType.PISTOL)
	player.inventory.add_item(plain, 5)
	player.inventory.add_item(ice, 1)
	player.inventory.add_item(mag, 1)
	assert_eq(plain.get_badge(player), "Default", "Nothing selected: the plain kind is what the bow draws")
	assert_eq(ice.get_badge(player), "")
	assert_eq(mag.get_badge(player), "", "No pistol carried, so no badge on its magazines")
	watch_signals(bow)
	player.inventory.use_slot(Item.Category.MATERIALS, _slot_index(ice))
	assert_eq(bow.selected_ammo, ice, "Use on arrows for the bow selects them")
	assert_signal_emitted_with_parameters(bow, "ammo_selected", [ice])
	assert_eq(player.inventory.count_of(ice), 1, "Ammunition is not consumable; Use only selects")
	assert_eq(ice.get_badge(player), "Loaded")
	assert_eq(plain.get_badge(player), "")
	player.inventory.use_slot(Item.Category.MATERIALS, _slot_index(mag))
	assert_eq(bow.selected_ammo, ice, "A pistol magazine is not the bow's business")
	player.inventory.remove_item(ice, 1)
	assert_eq(bow.get_ammo(), plain, "The selected kind ran out: back to regular arrows")
	assert_eq(plain.get_badge(player), "Default")
	assert_eq(Item.new().get_badge(player), "", "Plain items carry no badge")


func test_a_reload_takes_one_magazine_from_the_inventory_and_refuses_without() -> void:
	var gun: Firearm = _gun()
	await wait_physics_frames(1)
	gun.rounds = 0
	assert_eq(gun.reserve_rounds, 0, "No magazines carried")
	gun.reload()
	assert_false(gun.is_reloading, "Nothing to load: no reload")
	assert_eq(gun.rounds, 0)
	var mag: AmmoItem = _ammo(&"pistol_magazine", Equipment.EquipmentType.PISTOL)
	player.inventory.add_item(mag, 2)
	assert_eq(gun.reserve_rounds, 4, "Two magazines of two rounds")
	watch_signals(gun)
	gun.reload()
	assert_true(gun.is_reloading)
	await wait_seconds(0.2)
	assert_false(gun.is_reloading)
	assert_eq(gun.rounds, 2, "The magazine is full again")
	assert_eq(player.inventory.count_of(mag), 1, "One magazine left the inventory")
	assert_eq(gun.reserve_rounds, 2)
	assert_eq(gun.loaded_ammo, mag)
	assert_signal_emitted_with_parameters(gun, "ammo_changed", [2, 2])
	assert_eq(player.ammo_readout.label.text, "2 / 2", "The HUD shows the magazine and what the inventory holds")
	player.inventory.remove_item(mag, 1)
	assert_eq(player.ammo_readout.label.text, "2 / 0", "Dropping a magazine updates the HUD at once")


func test_a_reload_takes_the_selected_kind_and_its_rounds_fly() -> void:
	var gun: Firearm = _gun()
	await wait_physics_frames(1)
	var plain: AmmoItem = _ammo(&"pistol_magazine", Equipment.EquipmentType.PISTOL)
	var special: AmmoItem = _ammo(&"special_magazine", Equipment.EquipmentType.PISTOL, ARROW_SCENE)
	player.inventory.add_item(plain, 1)
	player.inventory.add_item(special, 1)
	assert_eq(gun.get_ammo(), plain, "Nothing selected: the plain magazine")
	assert_eq(gun.get_projectile_scene(), BULLET_SCENE, "The starting magazine is the gun's own round")
	player.inventory.use_slot(Item.Category.MATERIALS, _slot_index(special))
	assert_eq(gun.selected_ammo, special)
	assert_eq(gun.get_ammo(), special)
	assert_eq(special.get_badge(player), "Loaded")
	gun.rounds = 0
	gun.reload()
	await wait_seconds(0.2)
	assert_eq(gun.loaded_ammo, special)
	assert_eq(player.inventory.count_of(special), 0, "The special magazine went into the gun")
	assert_eq(player.inventory.count_of(plain), 1)
	assert_eq(gun.get_projectile_scene(), ARROW_SCENE)
	var shot: Projectile = gun.fire()
	assert_not_null(shot)
	assert_true(shot is Arrow, "The round is the loaded kind's own scene")
	assert_eq(gun.get_ammo(), plain, "Out of the special kind, the next reload falls back to plain")
	assert_eq(gun.reserve_rounds, 2)
	shot.free()


func test_the_bow_takes_one_arrow_per_shot_and_stops_at_zero() -> void:
	var bow: Bow = _bow()
	await wait_physics_frames(1)
	assert_false(bow.fire_arrow(), "No arrows, no shot")
	assert_eq(_projectiles().size(), 0)
	var arrows: AmmoItem = _ammo(&"arrow", Equipment.EquipmentType.BOW, null, 1)
	player.inventory.add_item(arrows, 2)
	assert_true(bow.fire_arrow())
	assert_eq(player.inventory.count_of(arrows), 1, "A shot spends an arrow")
	assert_true(bow.fire_arrow())
	assert_eq(player.inventory.count_of(arrows), 0)
	assert_eq(_projectiles().size(), 2, "Two arrows flew")
	assert_true(_projectiles()[0] is Arrow, "Plain arrows are copies of the template")
	assert_false(bow.fire_arrow(), "The quiver is empty")
	assert_eq(_projectiles().size(), 2)
	for arrow: Node in _projectiles():
		arrow.free()


func test_the_bow_fires_the_selected_kinds_scene_and_falls_back_when_it_runs_out() -> void:
	var bow: Bow = _bow()
	await wait_physics_frames(1)
	var plain: AmmoItem = _ammo(&"arrow", Equipment.EquipmentType.BOW, null, 1)
	var ice: AmmoItem = _ammo(&"ice_arrow", Equipment.EquipmentType.BOW, BULLET_SCENE, 1)
	player.inventory.add_item(plain, 1)
	player.inventory.add_item(ice, 1)
	player.inventory.use_slot(Item.Category.MATERIALS, _slot_index(ice))
	assert_true(bow.fire_arrow())
	var first: Projectile = _projectiles()[0]
	assert_false(first is Arrow, "The selected kind flies as its own scene")
	assert_eq(first.shooter, player)
	assert_eq(player.inventory.count_of(ice), 0)
	assert_true(bow.fire_arrow(), "Ice arrows gone: a regular arrow flies")
	assert_eq(player.inventory.count_of(plain), 0)
	assert_true(_projectiles()[1] is Arrow)
	assert_false(bow.fire_arrow(), "Nothing left of any kind")
	for projectile: Node in _projectiles():
		projectile.free()


func test_a_gun_with_no_player_keeps_its_own_reserve() -> void:
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.magazine_size = 4
	gun.reserve_rounds = 6
	gun.reload_time = 0.1
	var timer := Timer.new()
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	root.add_child(gun)
	assert_eq(gun.reserve_rounds, 6, "Without a Player the export is the reserve")
	assert_null(gun.get_ammo())
	gun.rounds = 1
	gun.reload()
	await wait_seconds(0.2)
	assert_eq(gun.rounds, 4)
	assert_eq(gun.reserve_rounds, 3)
