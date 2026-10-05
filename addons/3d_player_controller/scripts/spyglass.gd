class_name Spyglass
extends Node3D
## A spyglass, Tears of the Kingdom style. It is a node of [code]player.tscn[/code], saved hidden on the Player's right
## hand the way the paraglider is, and the Player's scoping_changed is wired to it there. [member action] (the
## [code]scope[/code] action: Middle-Mouse, and the right stick's click under the Tears of the Kingdom scheme) raises it
## while [member Player.enable_spyglass] is on, and pressing it again puts it away.
##
## There is no animation for it, so the arm is posed by IK: [member hand_ik] pulls the right hand to [member hand_target]
## and [member hand_rotation] turns it to match, the marker placed every frame where the hand has to be for the eyepiece
## to sit at the right eye. Their influence tweens up over [member raise_time], which is the raise. Once it is at the
## eye this peer's own view goes first person, the spyglass and the arm holding it go out of the way, [member overlay]
## (the porthole) comes up and the view zooms to [member magnification]; the mouse wheel and [member zoom_in_action] / [member zoom_out_action] change it,
## and looking slows by as much, so the view does not swing about at ten times. Putting it away runs the other way and
## gives back the perspective the Player had.
##
## [member Player.is_scoping] replicates, so every peer raises every Player's spyglass; only the Player's own peer
## changes its view, so everyone else sees it held to the eye. The Player stands still while scoping.

@export var action: StringName = &"scope" ## Raises the spyglass, and puts it away again.
@export var zoom_in_action: StringName = &"ui_up" ## Zooms in while scoping, as the mouse wheel up does.
@export var zoom_out_action: StringName = &"ui_down" ## Zooms out while scoping, as the mouse wheel down does.
@export_range(1.0, 30.0, 0.5) var magnification: float = 4.0 ## How far it zooms when raised.
@export_range(1.0, 30.0, 0.5) var min_magnification: float = 2.0
@export_range(1.0, 30.0, 0.5) var max_magnification: float = 12.0
@export_range(1.05, 2.0, 0.05) var zoom_step: float = 1.25 ## Magnification multiplies by this for each step in or out.
@export_range(0.1, 2.0, 0.05, "suffix:s") var raise_time: float = 0.45 ## Seconds to bring it to the eye, and to take it down.
@export var eye_offset: Vector3 = Vector3(-0.035, 0.0, 0.03) ## Where the eyepiece sits from the eyes, in the model's frame: toward the right eye and just in front of it.
@export var overlay: CanvasLayer ## The porthole shown while looking through it.
@export var zoom_label: Label ## Shows the magnification on the porthole.
@export var hand_ik: TwoBoneIK3D ## Brings the right hand to the face; after every other right hand IK, so it wins while raised.
@export var hand_rotation: CopyTransformModifier3D ## Turns the right hand the way [member hand_target] faces, after [member hand_ik].
@export var hand_target: Node3D ## Where the right hand goes, placed every frame from the eyes and the grip.
@export var eyes: Node3D ## The first person eyes on the head bone.

var is_raised: bool = false ## True once it is at the eye and this peer is looking through it.

var _tween: Tween = null
var _zoom_tween: Tween = null
var _was_perspective: int = Camera.Perspective.THIRD_PERSON

@onready var player: Player = owner as Player


func _ready() -> void:
	set_physics_process(false)


## Wired to Player.scoping_changed: raises it on every peer, or puts it away.
func _on_player_scoping_changed(scoping: bool) -> void:
	if scoping:
		_raise()
	else:
		_lower()


## True when [param state] is one a Player can stop in and look through a spyglass.
static func can_scope_in(state: int) -> bool:
	return state in [NodeStateMachine.States.STANDING, NodeStateMachine.States.CROUCHING, NodeStateMachine.States.SPRINTING]


## The field of view that magnifies [param base_fov] by [param times].
static func zoomed_fov(base_fov: float, times: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / maxf(times, 1.0)))


func _input(event: InputEvent) -> void:
	if player == null or not player.is_multiplayer_authority() or player.is_paused or player.is_typing:
		return
	if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
		if player.is_scoping:
			player.is_scoping = false
		elif player.enable_spyglass and can_scope_in(player.current_state) \
				and not (player.held_object and player.held_object.is_holding_object()):
			player.is_scoping = true
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not is_raised:
		return
	var steps: int = 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			steps = 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			steps = -1
	elif InputMap.has_action(zoom_in_action) and event.is_action_pressed(zoom_in_action):
		steps = 1
	elif InputMap.has_action(zoom_out_action) and event.is_action_pressed(zoom_out_action):
		steps = -1
	if steps != 0:
		zoom_to(magnification * pow(zoom_step, steps))
		get_viewport().set_input_as_handled()


## Sets [member magnification], within its limits, and zooms the view to it if it is up.
func zoom_to(times: float) -> void:
	magnification = clampf(times, min_magnification, max_magnification)
	if zoom_label:
		zoom_label.text = "%.1fx" % magnification
	var camera: Camera = player.camera as Camera
	if not is_raised or camera == null:
		return
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(camera, "fov", zoomed_fov(camera.default_fov, magnification), 0.15)
	camera.look_scale = 1.0 / magnification


func _physics_process(_delta: float) -> void:
	_place_hand_target()
	# Knocked down, pushed off a ledge, grabbed: it comes down on its own.
	if player.is_multiplayer_authority() and player.is_scoping and not can_scope_in(player.current_state):
		player.is_scoping = false


## Puts the hand where it has to be for the eyepiece to sit at the right eye, looking the way the Player faces.
func _place_hand_target() -> void:
	if hand_target == null or eyes == null:
		return
	var facing: Basis = player.player_model.global_basis.orthonormalized()
	var at_eye: Transform3D = Transform3D(facing, eyes.global_position + facing * eye_offset)
	# This node's place in the hand is fixed, so the hand goes wherever puts this node at the eye.
	var grip: Transform3D = (get_parent() as Node3D).global_transform.affine_inverse() * global_transform
	hand_target.global_transform = at_eye * grip.affine_inverse()


func _raise() -> void:
	if player.inventory:
		player.inventory.set_equipment_visibility(false)
	if player.is_multiplayer_authority() and player.camera:
		# Face where the view looks before the arm comes up, as first person will
		player.rotate_model_to_direction(-player.camera_mount.global_basis.z)
	show()
	set_physics_process(true)
	_place_hand_target()
	hand_ik.active = true
	hand_rotation.active = true
	_blend_arm(1.0, _look_through)


func _lower() -> void:
	if is_raised:
		is_raised = false
		if overlay:
			overlay.hide()
		var camera: Camera = player.camera as Camera
		if camera:
			if _zoom_tween:
				_zoom_tween.kill()
			camera.look_scale = 1.0
			camera.fov = camera.default_fov
			camera.perspective = _was_perspective
		# Back at the eye, so it comes down from where it was looked through
		hand_ik.influence = 1.0
		hand_rotation.influence = 1.0
	show()
	_blend_arm(0.0, _put_away)


func _blend_arm(to: float, then: Callable) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(hand_ik, "influence", to, raise_time)
	_tween.tween_property(hand_rotation, "influence", to, raise_time)
	_tween.chain().tween_callback(then)


## At the eye: this peer's own view goes through it. Everyone else keeps seeing it held up.
func _look_through() -> void:
	if not player.is_multiplayer_authority() or not player.is_scoping:
		return
	var camera: Camera = player.camera as Camera
	if camera == null:
		return
	is_raised = true
	hide()
	# The arm holding it would fill the lens; everyone else keeps seeing it up
	hand_ik.influence = 0.0
	hand_rotation.influence = 0.0
	_was_perspective = camera.perspective
	camera.perspective = Camera.Perspective.FIRST_PERSON
	if overlay:
		overlay.show()
	zoom_to(magnification)


func _put_away() -> void:
	if player.is_scoping:
		return
	hide()
	set_physics_process(false)
	hand_ik.active = false
	hand_rotation.active = false
	if player.inventory:
		player.inventory.set_equipment_visibility(true)
