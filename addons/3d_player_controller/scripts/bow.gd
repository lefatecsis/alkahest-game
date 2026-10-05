class_name Bow
extends Equipment
## Fires arrows and plays draw/fire feedback from the Player's archery locomotion nodes.
##
## Every shot takes one arrow ([AmmoItem] for [constant Equipment.EquipmentType.BOW]) from the Player's inventory:
## the kind Use selected while any is carried, else regular arrows, and with none carried nothing flies. An arrow
## with its own [member AmmoItem.projectile_scene] flies as that scene, the rest as [member arrow_scene].
## The arrow leaves on the Player's projectile ray, level with the template arrow, on the arc that carries it through
## the crosshair's aim point ([method arc_direction]), so it lands where the crosshair is, give or take
## [member Equipment.accuracy].
## Expects a template [Arrow] child named "Arrow" and optional "BowDrawArrow"/"BowFireArrow"
## audio players. The release sound is the "BowFireArrow" node's stream, else [member Equipment.attack_sfx] (the
## TomMusic bow attack); it travels with the arrow in the launch data, as a [Firearm]'s shot does, so every peer hears
## it where the arrow left ([method Projectile.play_launch_sfx]); a stream saved in no file of its own cannot travel
## and is not heard. Drawing and stowing the bow play its take-out and put-away through the Player's [WeaponAudio].
## While a kind with its own scene is what [method get_ammo] names, a frozen template copy of that
## scene sits on the string in its place ([member nocked_arrow]), so a fire arrow burns and an ice arrow frosts
## while drawing. Only the equipped copy on the Player's multiplayer authority (with [member player] set) reacts;
## peers get the arrow, and its release sound, through the [ProjectileSpawner]. The nocked copy is cosmetic and local:
## a peer's copy of the bow, rebuilt from the inventory's synced equipment, shows the plain template arrow.
##
## In first person the bow rides the view instead of the torso ([method Player.set_first_person_hand_targets]):
## the bow hand sits at [member first_person_carry_hand] while the bow is only carried and rises to
## [member first_person_aim_hand] for the draw, and the string hand is pulled onto the bow's own "StringHand" marker,
## which slides from "StringNocked" to "StringDrawn" over [member first_person_draw_time] and snaps back on release,
## with the nocked arrow drawn back along with it. "DrawElbow" aims that arm's elbow, back and out. All four are
## optional children in the bow's own space; without them only the bow hand is glued.

signal ammo_selected(ammo: AmmoItem) ## Emitted when Use on an [AmmoItem] for the bow picks the arrows it fires.

const AIM_AXIS: SkeletonModifier3D.BoneAxis = SkeletonModifier3D.BONE_AXIS_PLUS_X ## The archery stance is side-on: the spine's +X runs down the aim, so that is the axis the look-at pitches while drawn.
const RAY_MISS_DISTANCE: float = 40.0 ## Aim point distance when the projectile ray hits nothing.
const TAKE_OUT_SFX: AudioStream = preload("res://addons/3d_player_controller/resources/audio/bow_take_out.tres") ## Randomizer resources rather than the clips: an exported scene list walks a resource for its clip, never a script preload.
const PUT_AWAY_SFX: AudioStream = preload("res://addons/3d_player_controller/resources/audio/bow_put_away.tres")
const ATTACK_SFX: AudioStream = preload("res://addons/3d_player_controller/resources/audio/bow_attack.tres")

@export var arrow_scene: PackedScene ## Fired arrow scene; falls back to duplicating the template "Arrow" child when empty.
@export_group("First person", "first_person_")
## Where the bow hand sits in the view while drawing and aiming in first person, in the camera's own space (the eyes
## at the origin, -Z ahead): the aim pose's bow arm, brought in a little so the arm keeps a bend and can follow a
## view that pivots at the eye, and turned about the nock so the arrow runs parallel to the line of sight.
@export var first_person_aim_hand: Transform3D = Transform3D(
		Basis(Vector3(-0.205331, -0.978693, 0.000382), Vector3(0.250665, -0.052967, -0.966624), Vector3(0.946048, -0.198382, 0.256200)),
		Vector3(0.0220, -0.1871, -0.5198))
## And while the bow is only carried: low and to the left, in frame, the way the relaxed clip holds it.
@export var first_person_carry_hand: Transform3D = Transform3D(
		Basis(Vector3(-0.576713, -0.647669, 0.497922), Vector3(-0.076319, -0.564113, -0.822163), Vector3(0.813374, -0.512153, 0.275902)),
		Vector3(-0.25, -0.34, -0.42))
@export var first_person_draw_time: float = 0.9 ## Seconds the string hand takes from the string's rest to full draw, the length of the draw clip.
@export var first_person_raise_time: float = 0.3 ## Seconds the bow hand takes between the carry and the aim.
@export_group("")

var selected_ammo: AmmoItem ## The arrows Use picked; null fires the plain kind.
var nocked_arrow: Projectile ## A template copy of the selected kind's own scene shown on the string in place of [member arrow_node]; null while regular arrows are nocked.
var nocked_scene: PackedScene ## The scene [member nocked_arrow] is a copy of; null while regular arrows are nocked.

var _first_person_rig: bool = false ## The bow hand is glued to the view (see [method _update_first_person_rig]).
var _raised: bool = false ## The bow is up at the aim (drawing, drawn or just released) rather than carried.
var _string_hand_glued: bool = false ## The string hand is on the bow's StringHand marker.
var _draw_amount: float = 0.0 ## 0 at the string's rest, 1 at full draw (see [method _set_draw_amount]).
var _draw_tween: Tween
var _raise_tween: Tween
var _glue_tween: Tween

@onready var arrow_node: Arrow = get_node_or_null("Arrow") as Arrow ## Template duplicated for every shot.
@onready var draw_sfx: AudioStreamPlayer3D = get_node_or_null("BowDrawArrow") as AudioStreamPlayer3D
@onready var fire_sfx: AudioStreamPlayer3D = get_node_or_null("BowFireArrow") as AudioStreamPlayer3D ## Its stream is the release sound, sent with the arrow; the node itself never plays.
@onready var string_nocked: Marker3D = get_node_or_null("StringNocked") as Marker3D ## Where the string hand holds the string at rest, in the bow's space.
@onready var string_drawn: Marker3D = get_node_or_null("StringDrawn") as Marker3D ## And at full draw.
@onready var string_hand: Marker3D = get_node_or_null("StringHand") as Marker3D ## What the string hand is pulled onto: slid between the two above.
@onready var draw_elbow: Marker3D = get_node_or_null("DrawElbow") as Marker3D ## The pole aiming the drawing arm's elbow, back and out.
@onready var _arrow_rest: Vector3 = arrow_node.position if arrow_node else Vector3.ZERO ## The template arrow's place on the string at rest.


## The bow's own sounds stand in for the sword defaults; a scene that sets others keeps them.
func _init() -> void:
	equip_sfx = TAKE_OUT_SFX
	stow_sfx = PUT_AWAY_SFX
	attack_sfx = ATTACK_SFX


func _ready() -> void:
	if player and player.is_multiplayer_authority():
		player.locomotion_node_changed.connect(_on_locomotion_node_changed)
		player.inventory.item_used.connect(_on_item_used)
		player.inventory.items_changed.connect(_on_items_changed)
		player.inventory.equipment_changed.connect(_update_first_person_rig)
		if player.camera is Camera:
			(player.camera as Camera).perspective_changed.connect(_on_perspective_changed)
		_on_items_changed()
		_update_first_person_rig()


func _on_locomotion_node_changed(state_path: String) -> void:
	if not player.inventory.equipment.has(self) or player.held_object.is_holding_object() or player.is_throwing:
		return
	var is_aiming: bool = state_path == "Bow/ArcheryLocomotion"
	# Third person turns the torso to the aim; first person rides the view with the hands instead
	player.set_look_at_target(player.look_at_target if is_aiming and not player.is_first_person else null, AIM_AXIS)
	_set_first_person_phase(state_path)
	var shown: Projectile = get_nocked_arrow()
	if shown:
		shown.visible = is_aiming
	match state_path:
		"Bow/BowDrawArrow":
			if draw_sfx:
				draw_sfx.play()
			player.controls.rumble(0.0, 0.2, 0.5)
		"Bow/BowFireArrow":
			if fire_arrow():
				player.controls.rumble(0.4, 0.0, 0.5)


## The view swapped: what the bow does with the hands follows it.
func _on_perspective_changed(_perspective: int) -> void:
	_update_first_person_rig()


## Glues the bow hand to the view while the bow is out in first person, and lets go otherwise. The bow hand goes to
## the carry or the aim marker for the phase the bow is in, and the string hand onto the bow only while drawing.
func _update_first_person_rig() -> void:
	if player == null or not is_instance_valid(player.left_hand_ik):
		return
	var on: bool = player.is_first_person and player.inventory.equipment.has(self) and not player.is_scoping \
			and not (player.held_object and player.held_object.is_holding_object())
	if on == _first_person_rig:
		return
	_first_person_rig = on
	if on:
		if _raise_tween:
			_raise_tween.kill()
		player.first_person_left_hand.transform = first_person_aim_hand if _raised else first_person_carry_hand
		player.set_first_person_hand_targets(string_hand if _string_hand_glued else null, player.first_person_left_hand, draw_elbow)
	else:
		if _glue_tween:
			_glue_tween.kill()
		player.clear_first_person_hands()


## Sets the first person phase for a locomotion state: the draw raises the bow and pulls the string hand onto the
## string, then back to full draw over [member first_person_draw_time]; aiming holds it there; the release lets the
## string go at once and keeps the bow up; anything else carries the bow with the string hand free.
func _set_first_person_phase(state_path: String) -> void:
	match state_path:
		"Bow/BowDrawArrow":
			_raise(true)
			_glue_string_hand(true)
			_draw_to(1.0, first_person_draw_time)
		"Bow/ArcheryLocomotion":
			_raise(true)
			_glue_string_hand(true)
			_draw_to(1.0, 0.0)
		"Bow/BowFireArrow":
			_draw_to(0.0, 0.0)
		_:
			_raise(false)
			_glue_string_hand(false)
			_draw_to(0.0, 0.0)


## Moves the bow hand between the carry and the aim marker, eased over [member first_person_raise_time] while the
## rig is on; remembered either way for when it comes on.
func _raise(up: bool) -> void:
	if up == _raised:
		return
	_raised = up
	if not _first_person_rig:
		return
	if _raise_tween:
		_raise_tween.kill()
	var marker: Marker3D = player.first_person_left_hand
	_raise_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_raise_tween.tween_property(marker, "transform", first_person_aim_hand if up else first_person_carry_hand, first_person_raise_time)


## Pulls the string hand onto the bow's StringHand marker, blending in over a third of the draw so the hand reaches
## for the string rather than appearing on it, or lets the animation have the arm back at once.
func _glue_string_hand(on: bool) -> void:
	if on == _string_hand_glued:
		return
	_string_hand_glued = on
	if not _first_person_rig:
		return
	if _glue_tween:
		_glue_tween.kill()
	player.set_first_person_hand_targets(string_hand if on else null, player.first_person_left_hand, draw_elbow)
	if on and string_hand:
		player.right_hand_ik.influence = 0.0
		player.first_person_right_hand_rotation.influence = 0.0
		_glue_tween = create_tween().set_parallel(true)
		_glue_tween.tween_property(player.right_hand_ik, "influence", 1.0, first_person_draw_time / 3.0)
		_glue_tween.tween_property(player.first_person_right_hand_rotation, "influence", 1.0, first_person_draw_time / 3.0)


## Slides the string hand marker, and the nocked arrow with it, to [param amount] of the draw over [param seconds]
## (0 is at once), easing in so the pull gathers the way the clip's does.
func _draw_to(amount: float, seconds: float) -> void:
	if _draw_tween:
		_draw_tween.kill()
	if seconds <= 0.0 or not (string_nocked and string_drawn):
		_set_draw_amount(amount)
		return
	_draw_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	_draw_tween.tween_method(_set_draw_amount, _draw_amount, amount, seconds)


## Puts the StringHand marker [param amount] of the way from StringNocked to StringDrawn, and the arrow on the string
## the same distance back from its rest, in every perspective: the third person draw shows the arrow drawn too.
func _set_draw_amount(amount: float) -> void:
	_draw_amount = amount
	if not (string_nocked and string_drawn):
		return
	var pull: Vector3 = string_nocked.position.lerp(string_drawn.position, amount)
	if string_hand:
		string_hand.transform = Transform3D(string_nocked.basis.slerp(string_drawn.basis, amount), pull)
	for arrow: Node3D in [arrow_node, nocked_arrow]:
		if is_instance_valid(arrow):
			arrow.position = _arrow_rest + (pull - string_nocked.position)


## Use on an [AmmoItem] for the bow selects it; the next shots take that kind while any is carried.
func _on_item_used(item: Item, _count: int) -> void:
	var ammo: AmmoItem = item as AmmoItem
	if ammo == null or ammo.weapon_type != equipment_type:
		return
	selected_ammo = ammo
	ammo_selected.emit(ammo)
	_on_items_changed()


## The carried arrows changed (a selection, a kind running out): the string shows the kind the next shot takes.
func _on_items_changed() -> void:
	var ammo: AmmoItem = get_ammo()
	nock(ammo.projectile_scene if ammo else null)


## The arrows the next shot takes: [member selected_ammo] while some is carried, else regular arrows, else null.
func get_ammo() -> AmmoItem:
	return AmmoItem.pick(player.inventory, equipment_type, selected_ammo) if player else null


## The arrow on the string: [member nocked_arrow] while a special kind is nocked, else the template [member arrow_node].
func get_nocked_arrow() -> Projectile:
	return nocked_arrow if is_instance_valid(nocked_arrow) else arrow_node


## Puts a frozen template copy of [param scene] on the string in place of [member arrow_node], at the template's own
## transform and visibility, so its VFX (a flame, a frost) show while drawing; null puts the regular arrow back.
## Nothing changes when that scene is already nocked or the bow has no template arrow.
func nock(scene: PackedScene) -> void:
	if arrow_node == null or scene == nocked_scene:
		return
	var shown: bool = get_nocked_arrow().visible
	if is_instance_valid(nocked_arrow):
		nocked_arrow.queue_free()
	nocked_scene = scene
	nocked_arrow = scene.instantiate() as Projectile if scene else null
	if nocked_arrow:
		nocked_arrow.is_template = true
		nocked_arrow.transform = arrow_node.transform # includes the draw the string is at right now
		for shape: Node in nocked_arrow.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).disabled = true
		add_child(nocked_arrow)
		nocked_arrow.visible = shown
	arrow_node.visible = shown and nocked_arrow == null


## The launch direction at [param speed] that carries a projectile under [param gravity] from [param from] through
## [param to]: the lower of the two arcs, the one closest to a straight shot. With [param to] out of range (or no
## gravity) the straight line, so the shot still flies at the crosshair.
static func arc_direction(from: Vector3, to: Vector3, speed: float, gravity: float) -> Vector3:
	var offset: Vector3 = to - from
	var flat: Vector3 = Vector3(offset.x, 0.0, offset.z)
	var distance: float = flat.length()
	var speed_squared: float = speed * speed
	var discriminant: float = speed_squared * speed_squared - gravity * (gravity * distance * distance + 2.0 * offset.y * speed_squared)
	if gravity <= 0.0 or distance < 0.001 or discriminant < 0.0:
		return offset.normalized()
	var angle: float = atan((speed_squared - sqrt(discriminant)) / (gravity * distance))
	return flat.normalized() * cos(angle) + Vector3.UP * sin(angle)


## Takes one arrow of the kind [method get_ammo] names from the inventory and fires it: its own scene, else
## [member arrow_scene], through the world's [ProjectileSpawner] when present (multiplayer), otherwise a local copy.
## The arrow leaves on the projectile ray, level with the nocked arrow, on the arc through the ray's hit point
## ([method arc_direction]), then [method Equipment.scatter] pushes it off that line for the Player's skill. The
## release sound ("BowFireArrow"'s stream, else [member Equipment.attack_sfx]) goes with it, as "fire_sfx" in the
## launch data. False, and nothing flies, with no arrows carried or off the authority.
func fire_arrow() -> bool:
	var ammo: AmmoItem = get_ammo()
	var scene: PackedScene = (ammo.projectile_scene if ammo.projectile_scene else arrow_scene) if ammo else null
	if ammo == null or (scene == null and arrow_node == null) or not player.is_multiplayer_authority() \
			or player.inventory.remove_item(ammo, 1) == 0:
		return false
	var nocked: Node3D = get_nocked_arrow() if get_nocked_arrow() else self
	var ray: RayCast3D = player.projectile_raycast
	ray.force_raycast_update()
	var aim: Vector3 = ray.get_collision_point() if ray.is_colliding() else ray.global_position - ray.global_basis.z * RAY_MISS_DISTANCE
	var along: Vector3 = -ray.global_basis.z
	var origin: Transform3D = nocked.global_transform
	origin.origin = ray.global_position + along * maxf((nocked.global_position - ray.global_position).dot(along), 0.0)
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * (nocked.gravity_scale if nocked is RigidBody3D else 1.0)
	var direction: Vector3 = scatter(arc_direction(origin.origin, aim, projectile_speed, gravity))
	var release: AudioStream = fire_sfx.stream if fire_sfx and fire_sfx.stream else attack_sfx
	var release_path: String = release.resource_path if release else ""
	var spawner: ProjectileSpawner = ProjectileSpawner.find_for(player)
	if scene and spawner:
		spawner.fire(scene, origin, direction, projectile_speed, player, self, {"fire_sfx": release_path} if not release_path.is_empty() else {})
		return true
	var arrow: Projectile = scene.instantiate() as Projectile if scene else arrow_node.duplicate() as Projectile
	arrow.is_template = false
	var world: Node = get_tree().current_scene if get_tree().current_scene else player.get_parent()
	world.add_child(arrow)
	arrow.show()
	for shape: Node in arrow.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = false
	if not arrow.body_entered.is_connected(arrow._on_body_entered):
		arrow.body_entered.connect(arrow._on_body_entered)
	arrow.launch(origin, direction, projectile_speed, player, self)
	if arrow is Arrow:
		arrow.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	var swish: AudioStreamPlayer3D = arrow.get_node_or_null("Swish") as AudioStreamPlayer3D
	if swish:
		swish.play()
	if not release_path.is_empty():
		arrow.play_launch_sfx(release_path)
	return true
