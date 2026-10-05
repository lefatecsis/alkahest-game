extends GutTest

## Purpose: the seeker wheel (D-pad Up / I held) is context sensitive: aiming with a rifle it lists the clip kinds
## and picking one is the Firearm's ammunition selection, aiming with a bow the arrow kinds, and otherwise the
## throwable items, where picking one sets Player.selected_throwable. Empty it stays closed, and a copy off the
## authority never opens it.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")
const BOW_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/bow.gd")

var root: Node3D
var player: Player
var wheel: SeekerWheel


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	wheel = player.seeker_wheel
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release("focus")
	Input.action_release("seeker")
	if is_instance_valid(root):
		root.free()
		root = null


func _ammo(id: StringName, type: Equipment.EquipmentType) -> AmmoItem:
	var ammo := AmmoItem.new()
	ammo.id = id
	ammo.weapon_type = type
	ammo.rounds_per_unit = 1 if type == Equipment.EquipmentType.BOW else 0
	return ammo


func _throwable(id: StringName) -> Item:
	var item := Item.new()
	item.id = id
	item.throwable = true
	return item


func _equip_rifle() -> Firearm:
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	gun.equipment_type = Equipment.EquipmentType.RIFLE
	gun.magazine_size = 2
	var timer := Timer.new()
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	player.add_child(gun)
	player.inventory.add_equipment(gun)
	return gun


func _equip_bow() -> Bow:
	var bow: Bow = BOW_SCRIPT.new()
	bow.player = player
	bow.equipment_type = Equipment.EquipmentType.BOW
	player.add_child(bow)
	player.inventory.add_equipment(bow)
	return bow


func test_the_wheel_is_in_the_player_and_held_open_by_seeker() -> void:
	assert_not_null(wheel, "player.tscn instances the SeekerWheel")
	assert_eq(wheel.radial_menu.hold_actions, [&"seeker"] as Array[StringName])
	assert_eq(wheel.radial_menu.player, player, "The wheel reads the Player through its owner")
	assert_true(wheel.radial_menu.custom_item_provider.is_valid())


func test_aiming_with_the_rifle_lists_the_clip_kinds_and_picking_one_selects_it() -> void:
	var gun: Firearm = _equip_rifle()
	var clip: AmmoItem = _ammo(&"seek_clip", Equipment.EquipmentType.RIFLE)
	var incendiary: AmmoItem = _ammo(&"seek_incendiary", Equipment.EquipmentType.RIFLE)
	var magazine: AmmoItem = _ammo(&"seek_magazine", Equipment.EquipmentType.PISTOL)
	player.inventory.add_item(clip, 2)
	player.inventory.add_item(incendiary, 1)
	player.inventory.add_item(magazine, 1)
	player.inventory.add_item(_throwable(&"seek_rock"), 3)
	Input.action_press("focus")
	assert_true(player.is_focusing, "Aiming")
	var wedges: Array[Dictionary] = wheel.get_wheel_items()
	assert_eq(wedges.size(), 2, "The two rifle kinds, not the pistol magazine or the rock")
	assert_eq(wedges[0]["item"], clip)
	assert_eq(wedges[0]["display_name"], "Seek Clip x2")
	assert_eq(wedges[1]["item"], incendiary)
	assert_true(wheel._is_wheel_item_selected(wedges[0], 0), "The plain clip is what the rifle draws by default")
	assert_false(wheel._is_wheel_item_selected(wedges[1], 1))
	wheel._on_wheel_item_selected(wedges[1], 1)
	assert_eq(gun.selected_ammo, incendiary, "Picking the incendiary clip is the Firearm's Use selection")
	assert_eq(gun.get_ammo(), incendiary)
	assert_true(wheel._is_wheel_item_selected(wedges[1], 1), "and the wheel marks it")
	assert_eq(incendiary.get_badge(player), "Loaded", "as the grid does")
	Input.action_release("focus")


func test_aiming_with_the_bow_lists_the_arrow_kinds() -> void:
	var bow: Bow = _equip_bow()
	var arrows: AmmoItem = _ammo(&"seek_arrow", Equipment.EquipmentType.BOW)
	var fire_arrows: AmmoItem = _ammo(&"seek_fire_arrow", Equipment.EquipmentType.BOW)
	player.inventory.add_item(arrows, 10)
	player.inventory.add_item(fire_arrows, 4)
	Input.action_press("focus")
	var wedges: Array[Dictionary] = wheel.get_wheel_items()
	assert_eq(wedges.size(), 2)
	assert_eq(wedges[0]["item"], arrows)
	assert_eq(wedges[1]["item"], fire_arrows)
	wheel._on_wheel_item_selected(wedges[1], 1)
	assert_eq(bow.selected_ammo, fire_arrows, "Picking fire arrows is the Bow's Use selection")
	Input.action_release("focus")


func test_not_aiming_lists_the_throwables_and_picking_one_sets_selected_throwable() -> void:
	_equip_rifle()
	player.inventory.add_item(_ammo(&"seek_clip", Equipment.EquipmentType.RIFLE), 2)
	var rock: Item = _throwable(&"seek_rock")
	var apple: Item = _throwable(&"seek_apple")
	apple.category = Item.Category.FOOD
	player.inventory.add_item(rock, 3)
	player.inventory.add_item(apple, 1)
	assert_false(player.is_focusing)
	var wedges: Array[Dictionary] = wheel.get_wheel_items()
	assert_eq(wedges.size(), 2, "The throwables; the clip is not one")
	assert_eq(wedges[0]["item"], rock)
	assert_eq(wedges[1]["item"], apple)
	assert_true(wheel._is_wheel_item_selected(wedges[0], 0), "Nothing picked yet: the first throwable is what a throw would take")
	wheel._on_wheel_item_selected(wedges[1], 1)
	assert_eq(player.selected_throwable, apple)
	assert_true(wheel._is_wheel_item_selected(wedges[1], 1))
	assert_false(wheel._is_wheel_item_selected(wedges[0], 0))
	assert_eq(player.held_object.get_selected_throwable(), apple, "and the throw takes it")


func test_holding_seeker_opens_the_wheel_and_releasing_closes_it() -> void:
	player.inventory.add_item(_throwable(&"seek_rock"), 1)
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down("seeker")
	await wait_physics_frames(1)
	assert_false(wheel.hold_timer.is_stopped(), "Pressing seeker starts the hold timer")
	assert_false(wheel.radial_menu.visible)
	await wait_for_signal(wheel.hold_timer.timeout, wheel.hold_timer.wait_time + 0.5)
	await wait_physics_frames(1)
	assert_true(wheel.radial_menu.visible, "Holding past the timer opens the wheel")
	assert_eq(wheel.radial_menu.weapons.size(), 1)
	sender.action_up("seeker")
	await wait_physics_frames(2)
	assert_false(wheel.radial_menu.visible, "Releasing closes it")
	sender.release_all()
	sender.clear()


func test_an_empty_context_keeps_the_wheel_closed() -> void:
	assert_eq(wheel.get_wheel_items().size(), 0, "No throwables carried")
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down("seeker")
	await wait_for_signal(wheel.hold_timer.timeout, wheel.hold_timer.wait_time + 0.5)
	await wait_physics_frames(1)
	assert_false(wheel.radial_menu.visible, "Nothing to pick, so it does not open")
	sender.action_up("seeker")
	sender.release_all()
	sender.clear()


func test_a_copy_off_the_authority_never_opens_the_wheel() -> void:
	var puppet: Player = PLAYER_SCENE.instantiate()
	puppet.set_multiplayer_authority(2)
	root.add_child(puppet)
	await wait_physics_frames(1)
	puppet.inventory.add_item(_throwable(&"seek_rock"), 1)
	assert_false(puppet.seeker_wheel.is_processing_unhandled_input(), "Off the authority the wheel reads no input")
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down("seeker")
	await wait_seconds(puppet.seeker_wheel.hold_timer.wait_time + 0.2)
	assert_true(puppet.seeker_wheel.hold_timer.is_stopped(), "Its hold timer never started")
	assert_false(puppet.seeker_wheel.radial_menu.visible)
	sender.action_up("seeker")
	sender.release_all()
	sender.clear()


func test_drawing_the_bow_lists_the_arrow_kinds_without_focus() -> void:
	var bow: Bow = _equip_bow()
	bow.can_shoot = true
	player.inventory.can_player_shoot = true # add_equipment read the flag before it was set on this bare bow
	var arrows: AmmoItem = _ammo(&"arrow", Equipment.EquipmentType.BOW)
	player.inventory.add_item(arrows, 5)
	await wait_physics_frames(1)
	assert_null(wheel.get_aimed_weapon(), "Nothing aimed while the bow just hangs there")
	Input.action_press("shoot")
	await wait_physics_frames(2)
	assert_eq(wheel.get_aimed_weapon(), bow, "A drawn bow counts as aimed, so arrows can be swapped mid-draw")
	var labels: Array = wheel.get_wheel_items().map(func(item: Dictionary) -> String: return str(item.get("display_name")))
	assert_true(labels.any(func(text: String) -> bool: return text.begins_with("Arrow")), "The wheel lists the arrow kinds: %s" % [labels])
	Input.action_release("shoot")


func test_the_seeker_hint_reads_arrows_only_while_the_bow_is_aimed() -> void:
	var controls: Controls = player.controls
	controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	_equip_bow()
	player.refresh_contextual_controls()
	assert_eq(controls.key_i_label.text, "Seeker", "A slung bow opens the throwables, so the hint stays Seeker")
	assert_eq(controls.joypad_button_11_label.text, "Seeker")
	Input.action_press("focus")
	assert_true(player.is_focusing)
	var press := InputEventAction.new()
	press.action = "focus"
	press.pressed = true
	controls._input(press)
	assert_eq(controls.key_i_label.text, "Arrows", "Aiming the bow: the wheel lists arrows and the hint says so")
	assert_eq(controls.joypad_button_11_label.text, "Arrows")
	Input.action_release("focus")
	var release := InputEventAction.new()
	release.action = "focus"
	release.pressed = false
	controls._input(release)
	assert_eq(controls.key_i_label.text, "Seeker", "Letting go of the aim takes the hint back")
	player.inventory.unequip_all()
	_equip_rifle()
	player.refresh_contextual_controls()
	assert_eq(controls.key_i_label.text, "Seeker", "A gun at rest likewise")
	Input.action_press("focus")
	controls.refresh_seeker_label()
	assert_eq(controls.key_i_label.text, "Ammo", "Aiming the gun lists its ammunition")
	Input.action_release("focus")
