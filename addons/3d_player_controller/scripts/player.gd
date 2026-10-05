class_name Player
extends CharacterBody3D

const CLICK_MARKER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/vfx/click_marker.tscn") ## Dropped where a click-to-move click lands: the marker from the Guild Wars Heroes Island project.

signal state_changed(from_state: int, to_state: int) ## Emitted when [member current_state] changes.
signal ride_started(rideable: Node3D) ## Emitted when the Player gets on a rideable.
signal ride_ended(rideable: Node3D) ## Emitted when the Player gets off it.
signal locomotion_node_changed(state_path: String) ## Emitted when the locomotion path ("Group/Node" or "Node") changes; on puppets this follows replication.
signal exhausted_changed(is_exhausted: bool) ## Emitted when [member is_exhausted] changes.
signal navigating_changed(is_navigating: bool) ## Emitted when click-to-move navigation starts or stops.
signal paused_changed(is_paused: bool) ## Emitted when [member is_paused] changes (a menu opened or closed).
signal whistled(player: Player) ## Emitted on the authority when the `whistle` action is pressed on foot (not while riding); the world decides who answers.
signal respawned ## Emitted on the authority when [method respawn] has put the Player back on their feet.
signal checkpoint_changed(transform: Transform3D) ## Emitted on the authority when [member respawn_transform] changes.
signal scoping_changed(is_scoping: bool) ## Emitted when [member is_scoping] changes, on every peer; the [Spyglass] is wired to it.

const EMOTE_STATE_PLAYBACK_PATH: String = "parameters/EmoteStateMachine/playback"
const CAST_CHANNEL_EMOTE: StringName = &"ReadyToCastSpell" ## Upper-body pose held while an unarmed cast channels.
const GUARD_EMOTE: StringName = &"ShieldBlock" ## Upper-body pose held while the shield is raised ([member is_guarding]).
const LOCOMOTION_STATE_PLAYBACK_PATH: String = "parameters/LocomotionStateMachine/playback"
const ARCHERY_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Bow/ArcheryLocomotion/blend_position"
const BOW_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Bow/BowLocomotion/blend_position"
const BOXING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Boxing/BoxingLocomotion/blend_position"
const BRACED_HANG_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/BracedHangLocomotion/blend_position"
const CLIMBING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/ClimbingLocomotion/blend_position"
const CROUCHING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/CrouchingLocomotion/blend_position"
const FREE_HANGING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/FreeHangingLocomotion/blend_position"
const FLYING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/FlyingLocomotion/blend_position"
const GREATSWORD_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/GreatSword/GreatSwordLocomotion/blend_position"
const PISTOL_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Pistol/PistolLocomotion/blend_position"
const RIFLE_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Rifle/RifleLocomotion/blend_position"
const SHIELD_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Shield/ShieldLocomotion/blend_position"
const STANDING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/StandingLocomotion/blend_position"
const SWIMMING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/SwimmingLocomotion/blend_position"
const LOCOMOTION_GROUPS: Array[String] = ["Bow", "Boxing", "GreatSword", "Pistol", "Rifle", "Shield"] ## Grouped sub-state machines inside the LocomotionStateMachine.

@export var animation_tree: AnimationTree
@export var motion_interpolate_speed: float = 10.0
@export var rotation_interpolate_speed: float = 10.0
@export var swimming_root_motion_multiplier: float = 2.0

@export_category("Controls")
## The joypad this Player reads: -1, the default, is the whole input (every pad, the keyboard and the mouse, as
## a single player has); 0 and up is that pad alone, for a [SplitScreen] player. The action names never change;
## [method is_action_pressed], [method get_action_strength] and [method get_vector] resolve an action's pad
## bindings against that pad, and the view the Player sits in forwards only that pad's events.
@export var input_device: int = -1
var uses_mouse: bool: ## Whether the mouse is this Player's: only a Player on the whole input has it.
	get:
		return input_device < 0
## Which game's controls the Player answers to: the pad's face-button layout and what Focus does. Zelda locks on
## to a target; GTA aims freely over the shoulder. Any [ControlScheme] resource will do, so a game can ship a
## layout of its own without editing this addon; the ones here are in
## [code]resources/control_schemes/[/code]. The settings menu can override it for the player
## ([member PlayerSettingsResource.control_scheme_name]).
@export var control_scheme: ControlScheme = PlayerControls.DEFAULT_SCHEME:
	set(value):
		control_scheme = value
		# The HUD readies before the Player, so a scheme set from the Player's own _ready (the saved one) reaches it too
		if controls and controls.is_node_ready() and is_multiplayer_authority():
			controls.apply_control_scheme(value)
			_apply_cursor_mode()
@export_category("Enable Settings")
@export var enable_flying: bool = false
@export var enable_paraglider: bool = false
@export var enable_shield_surfing: bool = false ## With a shield on the left arm, Focus held in the air and Action rides it down the slope ([Surfing]), as in Breath of the Wild.
@export var enable_spyglass: bool = false ## The [code]scope[/code] action raises the [Spyglass] on the right hand: first person, zoomed, through a porthole.
@export var enable_ragdoll: bool = false
@export var enable_stamina: bool = false
@export var enable_temperature: bool = false ## Cold and heat hurt, as in Breath of the Wild ([BodyTemperature]), reading the WeatherFX when there is one.
@export var enable_double_jump: bool = false ## Jump again in the air, [member air_jumps] times before landing (a platformer's double jump).
@export var air_jumps: int = 1 ## Jumps allowed off nothing before the feet touch ground again.
@export var jump_speed: float = 5.0 ## The upward speed a jump starts with, on the ground (at the clip's keyframe) or in the air (at once).
@export var instant_jump: bool = false ## Leave the ground on the press itself rather than at the clip's keyframe a third of a second later: a platformer's jump, timed at the edge.
@export var enable_dodge: bool = false ## A tap of Sprint rolls (Souls style): a dive roll in the direction moved, a backstep when still, a forward dive in the air. Holding still sprints. A [ControlScheme] with [member ControlScheme.rolls] turns this on as well (see [member dodge_enabled]).
@export var dodge_stamina_cost: float = 20.0 ## Stamina a roll spends when stamina is on; an exhausted Player cannot roll.
@export var dodge_tap_seconds: float = 0.25 ## Sprint released within this many seconds of the press is a tap, and a roll.
@export var dodge_iframe_seconds: float = 0.45 ## The roll's first seconds take no hit at all.
@export var attack_stamina_cost: float = 0.0 ## Stamina every swing spends when stamina is on; 0 makes swings free.
@export_category("Optional Interaction")
@export var push_force: float = 1.0
@export var mass: float = 80.0

var current_state: int = -1: ## The current state of the Player (from the Node/Code [NodeStateMachine], not the AnimationTree NodeStateMachine).
	set(value):
		if value == current_state:
			return
		var previous_state: int = current_state
		current_state = value
		# Spawn-state replication assigns this while the puppet's children are still entering the tree (not ready yet)
		if is_node_ready():
			state_changed.emit(previous_state, value)
var locomotion_state: AnimationNodeStateMachinePlayback: ## Gets the [NodeStateMachine] "LocomotionStateMachine"
	get:
		return animation_tree.get(LOCOMOTION_STATE_PLAYBACK_PATH)
var active_locomotion_playback: AnimationNodeStateMachinePlayback: ## Playback of the active grouped locomotion machine, or the root LocomotionStateMachine playback.
	get:
		var root_playback: AnimationNodeStateMachinePlayback = animation_tree.get(LOCOMOTION_STATE_PLAYBACK_PATH)
		if root_playback == null:
			return null
		var root_node: String = String(root_playback.get_current_node())
		if root_node in LOCOMOTION_GROUPS:
			return animation_tree.get("parameters/LocomotionStateMachine/" + root_node + "/playback")
		return root_playback
var current_locomotion_node: String: ## The deepest current locomotion state name (the Node of "Group/Node"), read off [member sync_locomotion_node].
	get:
		return sync_locomotion_node.get_file()
var current_locomotion_path: String: ## The current locomotion state path ("Group/Node" or "Node"), as accepted by [method travel_locomotion]. It is [member sync_locomotion_node], which the authority reads off the AnimationTree once a frame and the puppets receive.
	get:
		return sync_locomotion_node
var equipped_axe_1h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.AXE_1H)
var equipped_axe_2h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.AXE_2H)
var equipped_bow: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.BOW)
var equipped_dagger: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.DAGGER)
var equipped_fishing_rod: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.FISHING_ROD)
var equipped_pistol: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.PISTOL)
var equipped_rifle: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.RIFLE)
var equipped_shield: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.SWORD_AND_SHIELD)
var equipped_staff: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.STAFF)
var equipped_sword_1h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.SWORD_1H)
var equipped_sword_2h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.SWORD_2H)
var has_move_input: bool:
	get:
		return player_input != null and player_input.motion.length_squared() > 0.001
var uses_equipment_jump_variants: bool: ## Read by the AnimationTree's jump edges: anything in hand jumps with the equipment's clips.
	get:
		return equipment_group() not in ["", "Boxing"]
var is_boxing: bool = false

# Attack Sequence
var attack_sequence: int = 0
var is_attacking: bool = false
var is_attacking_1: bool: # Attack Sequence: 1 of n
	get: return current_locomotion_node in ["GreatSwordDownwardSlash", "ShieldDownwardSlash", "ShortHeadJab"] if is_multiplayer_authority() and animation_tree else false
var is_attacking_2: bool: # Attack Sequence: 2 of n
	get: return current_locomotion_node in ["GreatSwordLowSlash", "ShieldCrossSlash", "BackHandCross"] if is_multiplayer_authority() and animation_tree else false
var is_attacking_3: bool: # Attack Sequence: 3 of n
	get: return current_locomotion_node in ["GreatSwordPowerSlash", "ShieldPowerSlash"] if is_multiplayer_authority() and animation_tree else false
# Bow and Arrow
var is_aiming_bow: bool:
	get:
		if not is_multiplayer_authority():
			return is_aiming_bow
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return equipped_bow and current_locomotion_node == "ArcheryLocomotion"
var is_drawing_arrow: bool:
	get:
		if not is_multiplayer_authority():
			return is_drawing_arrow
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return equipped_bow and current_locomotion_node == "BowDrawArrow"
var is_firing_arrow: bool:
	get:
		if not is_multiplayer_authority():
			return is_firing_arrow
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return equipped_bow and current_locomotion_node == "BowFireArrow"
# Climbing
var is_climbing: bool = false ## Is the Player currently climbing?
var is_climbing_on: bool = false ## Is the Player currently climbing on to a ledge?
var climbing_on_target: Vector3 ## The target position the Player is climbing on to (from ledge detection).
var is_climbing_hopping_left: bool = false ## Is the Player currently hopping left while climbing?
var is_climbing_hopping_right: bool = false ## Is the Player currently hopping right while climbing?
var is_climbing_hopping_up: bool = false ## Is the Player currently hopping up while climbing?
var is_hopping_from_climbing: bool = false ## Is the Player currently hopping while climbing?
# Riding
var is_riding: bool = false ## Riding something (a board, a vehicle, a mount); [member riding] moves the Player.
var riding: Node3D = null ## What is being ridden; it follows the rideable contract described in [Riding].
var is_mounting: bool = false ## Playing the get-on animation; the rideable does not move the Player yet.
var is_dismounting: bool = false ## Playing the get-off animation.
# Hanging
var is_hanging_braced: bool = false ## Is the Player currently hanging (braced)?
var is_hanging_free: bool = false ## Is the Player currently hanging (free)?

var is_crouching: bool = false ## Is the Player currently crouching?
var is_emoting: bool = false ## Is the Player currently emoting?
var has_started_emoting: bool = false ## Has the player's emote animation transitioned away from Idle yet?
var is_exhausted: bool = false: ## Is the Player currently exhausted?
	set(value):
		if value != is_exhausted:
			is_exhausted = value
			exhausted_changed.emit(value)
var is_falling: bool = false ## Is the Player currently falling?
var is_fishing: bool = false ## Is the Player currently fishing (has a rod equipped)?
var is_casting_line: bool = false ## Is the Player currently casting a fishing line?
var is_reeling_line: bool = false ## Is the Player currently casting a fishing line?
var is_flying: bool = false ## Is the Player currently flying?
var is_first_person: bool: ## Is the view from the Player's own eyes? The body then turns with the view at once and a gun in hand follows its pitch (see [Camera]).
	get:
		return camera is Camera and (camera as Camera).perspective == Camera.Perspective.FIRST_PERSON
var is_focusing: bool: ## Is the Player currently focusing (forward or on a target)?
	get:
		if not is_multiplayer_authority() or is_typing or is_paused or riding_blocks_hands():
			return false
		if held_object and held_object.is_holding_object():
			return false
		# While the cursor is visible, right-click is the camera drag. Only that button is held back, so a pad or the
		# touch slot still focuses on a web page before its first click, and on a phone, where the cursor never hides.
		if uses_mouse and DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			return false
		# A scheme that frees the cursor makes Focus a tap that picks the Target ([Focus]), never a held lock-on
		if control_scheme and control_scheme.frees_cursor:
			return false
		# Also suppressed during the temporary right-click capture used for camera rotation.
		if camera is Camera and (camera as Camera).is_temporarily_captured:
			return false
		return is_action_pressed(&"focus")
var is_jumping: bool = false ## Is the Player currently jumping?
var is_jump_queued: bool = false ## Is the Player currently queued to jump?
var is_front_flipping: bool = false ## Is the Player currently front flipping?
var is_back_flipping: bool = false ## Is the Player currently back flipping?
var is_flipping: bool: ## Is the Player currently front or back flipping?
	get:
		if not is_multiplayer_authority():
			return false
		var node: String = current_locomotion_node
		return is_front_flipping or is_back_flipping or node in ["Backflip", "FowardFlip"] or node.ends_with("Dive")
var is_throwing: bool: ## Is the Player currently in a throw wind-up? (Delegates to [HeldObject].)
	get:
		return held_object != null and held_object.is_throwing
	set(value):
		if held_object:
			held_object.is_throwing = value
var held_rigidbody: RigidBody3D: ## The [RigidBody3D] currently carried, if any. (Delegates to [HeldObject].)
	get:
		return held_object.held_rigidbody if held_object else null
var current_focus_target: Node3D: ## The body currently locked on to, if any. (Delegates to [Focus].)
	get:
		return focus.current_focus_target if focus else null
var selected_target: Node3D: ## The Target: what abilities land on and the target frame shows. (Delegates to [Focus].)
	get:
		return focus.selected_target if focus else null


## The cursor the control scheme wants: visible when it frees the cursor ([member ControlScheme.frees_cursor]),
## captured otherwise. Menus and wheels that borrow the cursor put it back to this.
func cursor_mode() -> Input.MouseMode:
	return Input.MOUSE_MODE_VISIBLE if control_scheme and control_scheme.frees_cursor else Input.MOUSE_MODE_CAPTURED


func _apply_cursor_mode() -> void:
	# A menu owns the cursor while it is up (a scheme picked in the settings changes nothing until it closes)
	if is_multiplayer_authority() and DisplayServer.get_name() != "headless" and not is_paused:
		Input.mouse_mode = cursor_mode()


## [method Input.is_action_pressed] for this Player: the whole input on a single player, this Player's pad alone
## on [member input_device]. Every polled action read in the controller goes through here and the two below.
func is_action_pressed(action_name: StringName) -> bool:
	if input_device < 0:
		return Input.is_action_pressed(action_name)
	return get_action_strength(action_name) > 0.0


## [method Input.get_action_strength] for this Player: on a pad of their own, the action's joypad bindings are
## read off that pad ([method Input.is_joy_button_pressed], [method Input.get_joy_axis]), past the action's deadzone.
func get_action_strength(action_name: StringName) -> float:
	if input_device < 0:
		return Input.get_action_strength(action_name)
	if not InputMap.has_action(action_name):
		return 0.0
	var strength: float = 0.0
	var deadzone: float = InputMap.action_get_deadzone(action_name)
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventJoypadButton:
			if Input.is_joy_button_pressed(input_device, (event as InputEventJoypadButton).button_index):
				strength = 1.0
		elif event is InputEventJoypadMotion:
			var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
			var value: float = Input.get_joy_axis(input_device, motion.axis)
			if signf(value) == signf(motion.axis_value) and absf(value) > deadzone:
				strength = maxf(strength, absf(value))
	return strength


## [method Input.get_vector] for this Player.
func get_vector(negative_x: StringName, positive_x: StringName, negative_y: StringName, positive_y: StringName) -> Vector2:
	if input_device < 0:
		return Input.get_vector(negative_x, positive_x, negative_y, positive_y)
	return Vector2(get_action_strength(positive_x) - get_action_strength(negative_x), get_action_strength(positive_y) - get_action_strength(negative_y)).limit_length(1.0)


## A [enum PlayerSettingsResource.HudMode] this Player draws its on-screen controls by instead of the saved
## setting; -1 follows the setting. A demo scene sets SHOWN so the whole HUD is on screen whatever the player saved.
var hud_mode_override: int = -1:
	set(value):
		hud_mode_override = value
		if is_node_ready():
			apply_hud_visibility()


## Whether Focus locks on to a target (the Zelda scheme) rather than aiming freely over the shoulder (GTA).
## The scheme resource says so itself, so a layout that ships with a game decides this too.
func lock_on_enabled() -> bool:
	return control_scheme != null and control_scheme.locks_on


## Returns the 3D focus target position (the Marker3D_FocusTarget on the target body if present, which [Focus]
## looks up once when the lock changes).
func get_focus_target_position() -> Vector3:
	if not is_instance_valid(current_focus_target):
		return global_position
	return focus.focus_aim_position()

var has_firearm_equipped: bool: ## Is a firearm (Pistol, Rifle) currently equipped?
	get:
		return inventory != null and inventory.has_firearm_equipped()

var is_aiming_firearm: bool: ## Is the Player currently aiming with a firearm (Pistol, Rifle)?
	get:
		if not is_multiplayer_authority() or riding_blocks_hands() or inventory == null:
			return false
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return is_focusing and has_firearm_equipped

var is_mining: bool: ## Is the Player currently mining? Replicated: a puppet reads what the authority sent.
	get:
		if not is_multiplayer_authority():
			return is_mining
		return current_locomotion_node == "Mining"
var is_logging: bool: ## Is the Player currently logging? Replicated: a puppet reads what the authority sent.
	get:
		if not is_multiplayer_authority():
			return is_logging
		return current_locomotion_node == "Logging"
var is_navigating: bool = false: ## Is the Player currently navigating (click to move)?
	set(value):
		if value != is_navigating:
			is_navigating = value
			navigating_changed.emit(value)
var is_paragliding: bool = false ## Is the Player currently paragliding?
var is_shield_surfing: bool = false: ## Is the Player riding their shield down a slope ([Surfing])? Replicated, so every peer puts the shield under the feet; the snow addon's FootStamper reads it by name to cut a groove instead of footprints.
	set(value):
		if value != is_shield_surfing:
			is_shield_surfing = value
			_place_surf_shield(value)
var surf_spin: float = 0.0: ## How far round the rider is in a shield-surf spin ([Surfing]), in radians. Replicated, so every peer turns the body (the Armature) and the shield under it; the Player's facing, and the camera that follows it, stay put.
	set(value):
		if value != surf_spin:
			surf_spin = value
			_apply_surf_spin()
var _spin_rests: Dictionary = {} ## The Armature's and the ShieldSurfMount's own transforms, which a spin turns from.
var is_guarding: bool = false: ## Is the shield raised ([ShieldGuard])? Replicated, so every peer shows the guard pose.
	set(value):
		if value != is_guarding:
			is_guarding = value
			_show_guard(value)
var _surf_shield: Equipment = null ## The shield under the feet during a ride.
var _screamed: bool = false ## This fall's scream has gone out.
var footstep_override: AudioStream = null ## Steps a surface lends the Player while it stands on it (the snow addon's FootStamper sets its crunch in snow), played instead of the ground's own, so only one step sounds.
var knockback_velocity: Vector3 = Vector3.ZERO ## A shove from a hit, on top of the walking speed the animation gives, dying away at [member knockback_damping].
var _surf_shield_home: Node = null ## Where the surfed shield hangs when it is not under the feet: its bone attachment.
var _surf_shield_transform: Transform3D = Transform3D.IDENTITY
var _surf_mount_lift: float = 0.0 ## How far the ShieldSurfMount rides above its rest, following the feet through a hop.
var _surf_feet_rest: float = INF ## The lower foot's height in the model on the ground in the stance, which the lift is measured from; INF until the ride has stood on the ground.
var is_scoping: bool = false: ## Is the Player looking through the [Spyglass]? It stands still meanwhile. Replicated, so every peer sees it raised.
	set(value):
		if value != is_scoping:
			is_scoping = value
			scoping_changed.emit(value)
var is_paused: bool = false: ## Is the Player currently paused?
	set(value):
		if value != is_paused:
			is_paused = value
			paused_changed.emit(value)
var is_typing: bool = false ## Is the local Player typing in the chat window? Gameplay input is blocked while true.
var is_pushing: bool = false ## Is the Player currently pushing?
var is_ragdolling: bool = false: ## Is the Player currently ragdolling? Replicated, and the setter drops or lifts the body on every peer, so another player's copy ragdolls where they do.
	set(value):
		if value == is_ragdolling:
			return
		is_ragdolling = value
		if is_node_ready():
			_set_ragdoll_physics(value)
var requires_shoot_release_after_throw: bool = false ## Set during a throw to require releasing the shoot button before shooting weapons.
var selected_throwable: Item = null ## The throwable [Item] the seeker wheel picked; "throw" throws it when the equipped equipment is not throwable (see [HeldObject]).
var is_shooting: bool: ## Is the Player currently shooting? Replicated: a puppet reads what the authority sent.
	get:
		if not is_multiplayer_authority():
			return is_shooting
		if is_typing or is_paused or riding_blocks_hands() or inventory == null:
			return false
		if is_throwing:
			return false
		if held_object:
			if held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throw_queued or held_object.is_throwing:
				return false
		if requires_shoot_release_after_throw:
			if is_action_pressed(&"shoot"):
				return false
			else:
				requires_shoot_release_after_throw = false
		# With the cursor showing, a left click is click-to-move, not the trigger; the pad and touch still shoot
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return false
		return is_action_pressed(&"shoot") and inventory.can_player_shoot
var is_sitting: bool = false ## Is the Player currently sitting?
var is_sliding: bool = false ## Is the Player currently sliding?
var is_dodging: bool = false ## Is the Player mid-roll (see [member enable_dodge])?
var dodge_enabled: bool: ## The Souls roll is on: [member enable_dodge], or the scheme in use rolls ([member ControlScheme.rolls]).
	get:
		return enable_dodge or (control_scheme != null and control_scheme.rolls)
var dodge_from_run: bool = false ## The roll being started came out of a run (see [method try_dodge]), so it is the longer sprinting dive.
var dive_from_air: bool = false ## The roll being started is a dive from the air (see [method try_air_dive]).
var _sprint_press_motion: float = 0.0 ## How hard the Player was moving when Sprint went down, to tell a roll out of a run from one out of a stand.
var _sprint_hold_ended_msec: int = -1 ## When a held sprint was last let go, so a tap right after it still rolls out of the run.
var air_jumps_left: int = 0 ## Air jumps still to be had before landing; refilled on the ground.
var dodge_invulnerable: bool = false ## The roll's invulnerability frames are on: [method take_hit] does nothing.
var _sprint_pressed_msec: int = -1 ## When Sprint last went down, for telling a tap (a roll) from a hold (a sprint).
var is_sprinting: bool = false ## Is the Player currently sprinting?
var is_standing: bool = false ## Is the Player currently standing?
var is_typing_at_keyboard: bool = false ## Is the Player seated and typing? The AnimationTree advances the Sitting -> SittingToTyping -> SittingTyping chain off this, the way [member is_sitting] drives Sitting itself; it is the keyboard pose, unrelated to [member is_typing], which means a text field has focus.
var last_safe_shore_position: Vector3 = Vector3.ZERO ## Last known grounded position on dry land.
var is_stealthed: bool = false: ## Is the Player hidden by Stealth? Replicated, so puppets fade too (through [StealthLook]) and followers ignore them.
	set(value):
		is_stealthed = value
		if stealth_look and is_inside_tree():
			stealth_look.apply(is_stealthed)
var is_swimming: bool = false ## Is the Player currently swimming?
var is_diving: bool = false ## Is the Player currently diving underwater (submerged swimming)?
var swim_vertical_speed: float = 0.0 ## Vertical swim speed (m/s along up_direction) applied while swimming/diving.
var model_pitch: float = 0.0 ## Local pitch (radians) applied to the player model, used while diving.
@export var model_pitch_pivot_height: float = 0.9 ## Height (m) above the model origin the dive pitch pivots around (hips), so the body doesn't sweep through walls.
var drawn_weapon_group: String = "" ## Locomotion group whose draw animation already played; its Start skips the redraw.
var last_fall_speed: float = 0.0 ## The downward vertical fall speed right before movement update.
var initial_collision_shape_height: float
var initial_collision_shape_position: Vector3
var orientation: Transform3D = Transform3D()
var smoothed_motion: Vector2 = Vector2.ZERO
var _updrafts: Array[Area3D] = [] ## Updraft and Thermal areas UpdraftDetection is inside, from its area signals.

@onready var attack_sequence_timer: Timer = $AttackSequenceTimer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var initial_collision_shape_transform: Transform3D = collision_shape.transform
@onready var separation_ray_shape: CollisionShape3D = $SeparationRayShape3D
@onready var initial_separation_ray_transform: Transform3D = separation_ray_shape.transform
@onready var hud: PlayerHud = $Hud ## Everything drawn on the screen; the properties below reach into it.
@onready var controls: PlayerControls = $Hud/Controls
## The gameplay readouts, each its own scene beside the system that drives it. Looked up rather than required,
## because a game is free to move them, replace them or leave them out; every driver checks before writing.
@onready var boss_bar: BossBar = get_node_or_null("Hud/BossBar")
@onready var ammo_readout: AmmoReadout = get_node_or_null("Hud/AmmoReadout")
@onready var cast_bar: CastBar = get_node_or_null("Hud/CastBar")
@onready var chat: ChatWindow = get_node_or_null("Hud/Chat") as ChatWindow ## The local chat window; puppets keep a hidden copy that relays RPCs.
@onready var crosshair: TextureRect = $Hud/Crosshair
@onready var debug: Debug = $Hud/Debug
@onready var inventory: Inventory = $Hud/Inventory
@onready var abilities: Abilities = $Hud/Abilities
@onready var weapon_audio: WeaponAudio = get_node_or_null("SFX_Weapons") as WeaponAudio ## The weapon one-shots (draw, stow, swing, hit); optional.
@onready var radial_menu: RadialMenu = $Hud/Inventory/RadialMenu
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var pause: PlayerMenuLayer = $Hud/Pause
@onready var settings: PlayerMenuLayer = $Hud/Settings
@onready var audio_settings: PlayerMenuLayer = $Hud/AudioSettings
@onready var controls_settings: PlayerMenuLayer = $Hud/ControlsSettings
@onready var video_settings: PlayerMenuLayer = $Hud/VideoSettings
@onready var lobby_manager: PlayerMenuLayer = get_node_or_null("Hud/LobbyManager") as PlayerMenuLayer
@onready var stamina: Stamina = $Hud/Stamina
@onready var health: Health = $Hud/Health
@onready var respawn_timer: Timer = $RespawnTimer ## Runs after death; its timeout is wired to [method respawn].
@onready var quest_log: QuestLog = get_node_or_null("QuestLog") as QuestLog ## The Player's quests; saved with them.
@onready var quest_tracker: QuestTracker = get_node_or_null("Hud/QuestTracker") as QuestTracker ## The tracked quest's objectives, top right.
var _ragdoll_was_enabled: bool = true ## enable_ragdoll before death forced it on.
@onready var respawn_transform: Transform3D = global_transform ## Where [method respawn] and Unstuck put the Player: the spawn point until a [Checkpoint] is taken.
@onready var falling_raycast: RayCast3D = $FallingRaycast
@onready var player_model: Node3D = $PlayerModel
@onready var ledge_detection_horizontal: RayCast3D = $PlayerModel/LedgeDetectionHorizontal
@onready var ledge_detection_vertical: RayCast3D = $PlayerModel/LedgeDetectionHorizontal/LedgeDetectionVertical
@onready var ledge_detection_marker: MeshInstance3D = $PlayerModel/LedgeDetectionHorizontal/LedgeDetectionVertical/LedgeDetectionMarker
@onready var hanging_braced_detection: RayCast3D = $PlayerModel/HangingBracedDetection
@onready var look_at_target: Marker3D = $CameraMount/ProjectileRaycast/LookAtTarget
@onready var camera_mount: Node3D = $CameraMount
@onready var item_spring_arm: SpringArm3D = $CameraMount/ItemSpringArm
@onready var player_input: InputSynchronizer = $InputSynchronizer
@onready var focus: Focus = $Focus
@onready var held_object: HeldObject = $HeldObject
@onready var seeker_wheel: SeekerWheel = get_node_or_null("Hud/SeekerWheel") as SeekerWheel ## The ammunition and throwable picker, held open with "seeker".
var initial_player_model_transform: Transform3D ## The model's rest transform from the scene, read as the Player first enters the tree: a late joiner's spawn state moves the model before ready.
@onready var paraglider_raycast: RayCast3D = $ParagliderRaycast
@onready var projectile_raycast: RayCast3D = $CameraMount/ProjectileRaycast
@onready var skeleton: Skeleton3D = $PlayerModel/Armature/GeneralSkeleton
@onready var head_attachment: BoneAttachment3D = $PlayerModel/Armature/GeneralSkeleton/HeadAttachment ## Follows the Head bone; what a [TalkingNpc] looks at, and where the headshot area sits.
@onready var look_at_modifier: LookAtModifier3D = $PlayerModel/Armature/GeneralSkeleton/LookAtModifier3D
@onready var head_look_at_modifier: LookAtModifier3D = $PlayerModel/Armature/GeneralSkeleton/HeadLookAtModifier3D ## Turns the head alone; the spine one above is for aiming.
@onready var body_temperature: BodyTemperature = get_node_or_null("BodyTemperature") as BodyTemperature ## Cold and heat hurt ([member enable_temperature]).
@onready var shield_guard: ShieldGuard = get_node_or_null("ShieldGuard") as ShieldGuard ## Guard and parry with a shield on the arm.
@onready var sfx_fall_scream: AudioStreamPlayer3D = get_node_or_null("SFX_FallScream") as AudioStreamPlayer3D ## Screams once on a fall that will kill ([method scream_if_doomed]).
@onready var head_look_target: Marker3D = get_node_or_null("HeadLookTarget") as Marker3D ## Where the head looks when nothing else claims it: ahead, at the camera's pitch ([method Camera._sync_head_look_target]).
@onready var right_hand_ik: TwoBoneIK3D = $PlayerModel/Armature/GeneralSkeleton/RightHandIK
@onready var left_hand_ik: TwoBoneIK3D = $PlayerModel/Armature/GeneralSkeleton/LeftHandIK ## First person with a gun: the support hand on the grip (see [method set_first_person_hands]).
@onready var first_person_right_hand_rotation: CopyTransformModifier3D = $PlayerModel/Armature/GeneralSkeleton/FirstPersonRightHandRotation ## Turns the right hand with the view once the IK has placed it.
@onready var first_person_left_hand_rotation: CopyTransformModifier3D = $PlayerModel/Armature/GeneralSkeleton/FirstPersonLeftHandRotation ## The same for the left.
@onready var first_person_right_hand: Marker3D = %FirstPersonRightHand ## Where the right hand sits in the view in first person; a Firearm places it.
@onready var first_person_left_hand: Marker3D = %FirstPersonLeftHand ## And the left.
@onready var hand_ik_pole: Marker3D = $PlayerModel/HandIKPole ## The elbow pole both hand IKs share unless a caller brings its own.
@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $PlayerModel/Armature/GeneralSkeleton/PhysicalBoneSimulator3D
@onready var spring_arm: SpringArm3D = $CameraMount/CameraSpringArm
@onready var camera: Camera3D = $CameraMount/CameraSpringArm/Camera3D
@onready var toon_filter: ToonFilter = $CameraMount/CameraSpringArm/Camera3D/ToonFilter ## Screen-space toon shading; a local video setting.
@onready var state_machine: NodeStateMachine = $NodeStateMachine ## Enables/Disables the scripts that run when various States are entered/exited.
@onready var audio: Audio = $SFX_Footsteps
@onready var steam_persona_name: Label3D = $SteamPersonaName
@onready var voice_chat: VoiceChat = get_node_or_null("VoiceChat") as VoiceChat ## Steam push-to-talk and voice activation; optional.
@onready var stealth_look: StealthLook = get_node_or_null("StealthLook") as StealthLook ## Draws [member is_stealthed]; optional.
## Optional: an effect a game hangs on its Player as a child named UpdraftAura (a weather addon's rising air), shown on
## every peer while the Player is in a thermal or within five metres of one. The Player hides it on ready.
@onready var updraft_aura: Node3D = get_node_or_null("UpdraftAura") as Node3D
@onready var player_synchronizer: MultiplayerSynchronizer = get_node_or_null("PlayerSynchronizer") as MultiplayerSynchronizer

@export var sync_locomotion_node: String = "":
	set(value):
		if value == sync_locomotion_node:
			return
		sync_locomotion_node = value
		# is_node_ready first: a copy made by duplicate() gets this set before it is in the tree, where authority is unknown
		if is_node_ready() and not is_multiplayer_authority() and animation_tree:
			_apply_synced_locomotion_node(value)
		locomotion_node_changed.emit(value)

## How far the emote layer is blended over the spine, 0 to 1; replicated, so a puppet's copy of a throw, a
## draw or a wave shows on its upper body the way the authority's does. Every writer goes through this rather
## than the tree parameter, so the one write reaches the tree here and every copy elsewhere.
@export var emote_spine_blend: float = 0.0:
	set(value):
		emote_spine_blend = value
		if animation_tree:
			animation_tree.set("parameters/EmoteSpineBlend2/blend_amount", value)

@export var sync_blend_position: Vector2 = Vector2.ZERO:
	set(value):
		sync_blend_position = value
		if is_node_ready() and not is_multiplayer_authority() and animation_tree:
			_apply_synced_blend_position(value)

var display_name: String = "": ## The name over the head (the Steam persona); replicated, so every peer reads it. Empty hides the label.
	set(value):
		display_name = value
		if steam_persona_name:
			steam_persona_name.text = value
			steam_persona_name.visible = not value.is_empty()

var current_water_area: Area3D = null


## Spawned players are named by their peer id (see [PlayerSpawner]); that peer owns this copy.
func _enter_tree() -> void:
	if str(name).is_valid_int():
		set_multiplayer_authority(str(name).to_int())
	# Children enter after this, and the synchronizer applies a spawn state as it does
	if not is_node_ready():
		initial_player_model_transform = (get_node(^"PlayerModel") as Node3D).transform


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Ensure AnimationTree is active so animations render on authority and puppets
	if animation_tree:
		animation_tree.active = true
		animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_apply_cursor_mode()

	# Spawn state lands before the label exists, so a late joiner applies it here
	display_name = display_name
	if updraft_aura:
		_show_updraft_aura(false)

	# A late joiner's copy of a player lying in a ragdoll: the spawn state set the flag before the body could drop
	if is_ragdolling:
		_set_ragdoll_physics(true)

	# Do nothing if not the authority
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return


	# Pre-initialize orientation transform.
	orientation = player_model.global_transform
	orientation.origin = Vector3()

	# Apply persistent user settings; the on-screen controls follow the device in hand from here on (the HUD's
	# input_type_changed is wired to _on_controls_input_type_changed in player.tscn)
	PlayerSettingsResource.load_or_create().apply_all(get_viewport(), self)

	# Record the initial collision shape height and position for crouching and sliding.
	initial_collision_shape_height = collision_shape.shape.height
	initial_collision_shape_position = collision_shape.position


	# Improve traction on spheres/slopes
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(60.0)
	floor_constant_speed = true

	# Ensure the projectile RayCast3D doesn't collide with the player
	projectile_raycast.add_exception(self)

	# The head looks up and down with the camera from the start
	set_head_look_at_target(null)
	# Metal in hand draws a storm's lightning (a weather addon asks, through the group)
	add_to_group(&"LightningAttractor")

	# Ensure PhysicalBone3D nodes never collide with the player CharacterBody3D
	if physical_bone_simulator:
		for child: Node in physical_bone_simulator.get_children():
			if child is PhysicalBone3D:
				child.add_collision_exception_with(self)
				add_collision_exception_with(child)

	# Set the Player's initial state
	if state_machine:
		state_machine.travel(-1, NodeStateMachine.States.STANDING)
	else:
		current_state = NodeStateMachine.States.STANDING

	# Update Steam persona name if Steam is enabled
	var steam: Object = SteamPeer.session(self)
	if steam:
		if not steam.is_connected("lobby_chat_update", _on_steam_lobby_chat_update):
			steam.connect("lobby_chat_update", _on_steam_lobby_chat_update)
		# A name given before ready (a spawner's, a test's) stands; only an unnamed Player asks Steam for one
		if display_name.is_empty():
			_update_steam_persona_name()


## Called when there is an unhandled input event.
func _unhandled_input(event: InputEvent) -> void:
	# Do nothing while paused, typing in the chat, or ragdolling
	if is_paused or is_typing or is_ragdolling: return

	# Chat; handled here rather than in _input so a menu that consumes Enter through the GUI wins
	if event.is_action_pressed(&"chat") and chat:
		chat.open_input()
		get_viewport().set_input_as_handled()
		return

	# [Left Mouse Button] pressed while the cursor is visible -> Start "navigating", unless the click is on a body,
	# which is a Target being picked (Focus), not a place to walk to
	if event is InputEventMouse \
			and uses_mouse \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and not (focus and focus.body_under((event as InputEventMouse).position)):
		click_to_move_at((event as InputEventMouse).position)

	# Whistle (action="whistle", key="K", D-Pad Down): the horse and whoever else listens answer; a rideable takes it first
	if event.is_action_pressed(&"whistle") and not event.is_echo() and not is_riding:
		whistled.emit(self)


## Walks to where [param screen_position] lands on the Player's movement plane, over the navigation mesh, and drops
## a [constant CLICK_MARKER_SCENE] there. Nothing happens when the click leaves the plane (the sky).
func click_to_move_at(screen_position: Vector2) -> void:
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var to: Vector3 = from + camera.project_ray_normal(screen_position) * 10000.0
	var movement_plane: Plane = Plane(up_direction, global_position.dot(up_direction))
	var cursor_position: Variant = movement_plane.intersects_ray(from, to)
	if cursor_position == null:
		return
	navigation_agent.target_position = cursor_position
	is_navigating = true
	var marker: Node3D = CLICK_MARKER_SCENE.instantiate()
	get_parent().add_child(marker)
	marker.global_position = cursor_position
	if debug.visible:
		debug.draw_navigation_marker(cursor_position)


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	# A frozen clock (a menu holding Engine.time_scale at zero) moves nothing, and root motion is divided by delta
	if delta <= 0.0:
		return
	# A shove dies away whatever the Player is doing, so one taken on the glider is not saved for the landing
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_damping * delta)
	# Track which weapon group has finished its draw so re-entering it skips the redraw.
	var root_locomotion_node: String = sync_locomotion_node.get_slice("/", 0)
	if root_locomotion_node in LOCOMOTION_GROUPS:
		var inner_node: String = current_locomotion_node
		# Skip Start/End so the flag isn't set before the entry edge picks draw vs skip.
		if not inner_node.ends_with("Draw") and inner_node not in ["Start", "End", ""]:
			drawn_weapon_group = root_locomotion_node
	elif drawn_weapon_group != "" and drawn_weapon_group != equipment_group():
		drawn_weapon_group = ""

	# Apply player input to control the character and update the animation state.
	apply_input(delta)

	# Treat "jumping" as queued jump or upward airborne movement.
	is_jumping = is_jump_queued or (not is_on_floor() and current_locomotion_node.contains("Jump"))
	if is_on_floor():
		air_jumps_left = air_jumps

	# Stop emote state when the animation finishes and reset the blend amount.
	if is_emoting:
		if animation_tree.get(EMOTE_STATE_PLAYBACK_PATH).get_current_node() != "Idle":
			has_started_emoting = true
		elif has_started_emoting:
			emote_spine_blend = 0.0
			is_emoting = false
			has_started_emoting = false
			is_throwing = false

	# The blend the puppets play (only the authority runs this)
	var blend_to_sync: Vector2 = Vector2(0.0, smoothed_motion.length())
	if is_focusing or is_shooting or is_boxing:
		blend_to_sync = smoothed_motion
	if blend_to_sync != sync_blend_position:
		sync_blend_position = blend_to_sync


## Wired to AnimationTree.mixer_applied in player.tscn: once a frame, right after the tree has advanced, the
## authority reads where the locomotion machine is into [member sync_locomotion_node], which replicates it and
## emits [signal locomotion_node_changed]. Every per-frame reader goes through that one value rather than the tree.
func _on_animation_tree_mixer_applied() -> void:
	if not is_multiplayer_authority():
		return
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if root_playback == null:
		return
	var path: String = String(root_playback.get_current_node())
	if path in LOCOMOTION_GROUPS:
		var group_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/LocomotionStateMachine/" + path + "/playback")
		path += "/" + String(group_playback.get_current_node())
	if path != sync_locomotion_node and not path.is_empty():
		sync_locomotion_node = path

# https://github.com/godotengine/tps-demo/blob/master/player/gd#L86
func apply_input(delta: float) -> void:
	# Get the target motion from the synchronized input.
	var target_motion: Vector2 = player_input.motion

	# Block player movement control if paused, typing or ragdolling.
	if is_paused or is_typing or is_ragdolling:
		target_motion = Vector2.ZERO
		smoothed_motion = Vector2.ZERO
		is_sprinting = false

	# If the player is mining, logging, flipping or looking through the spyglass, block regular locomotion transitions by
	# setting the `target_motion` to zero.
	if is_mining or is_logging or is_flipping or is_scoping:
		target_motion = Vector2.ZERO

	# Smoothly interpolate the target_motion for more gradual changes in animation blending and rotation.
	var motion_weight: float = clampf(motion_interpolate_speed * delta, 0.0, 1.0)
	smoothed_motion = smoothed_motion.lerp(target_motion, motion_weight)
	target_motion = smoothed_motion

	# While riding, paragliding, flying, or ragdolling, block regular locomotion.
	# Riding.gd / Paragliding.gd / Flying.gd / Ragdolling.gd will handle movement.
	if (is_riding and not is_mounting and not is_dismounting) or is_paragliding or is_shield_surfing or is_flying or is_ragdolling or is_sitting:
		return

	# Sprint logic
	if is_sprinting:
		if is_focusing:
			var forward_amount: float = clampf(absf(target_motion.y), 0.0, 1.0)
			target_motion.y *= 1.5
			# Favor the forward blend only on diagonal sprints; pure strafing keeps full speed.
			target_motion.x *= lerpf(1.0, 0.5, forward_amount)
		else:
			target_motion *= 1.5

	# A slow scales the wish, so the blend walks where it would run
	target_motion *= movement_scale * terrain_speed_scale

	# Handle movement is strafing
	var carrying: Node3D = held_rigidbody if held_object and held_object.is_holding_object() else null
	if not is_riding and (is_shooting or is_focusing or is_first_person or carrying != null):
		# Rotate to face the target, or the camera direction when shooting or in first person, or what is held, so a
		# body carried off to the side is in front of the Player rather than over a shoulder
		if not is_firing_arrow and not is_hanging_braced and not is_hanging_free and not is_climbing:
			var look_dir: Vector3 = Vector3.ZERO
			
			if is_focusing and is_instance_valid(current_focus_target):
				look_dir = (get_focus_target_position() - global_position).slide(up_direction)
			elif carrying != null and (carrying.global_position - global_position).slide(up_direction).length_squared() > 0.04:
				look_dir = (carrying.global_position - global_position).slide(up_direction)
			else:
				var camera_basis: Basis = spring_arm.global_transform.basis
				look_dir = - camera_basis.z
				look_dir = look_dir.slide(up_direction)
				
			if look_dir.length_squared() > 0.001:
				look_dir = look_dir.normalized()
				var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
				var q_to: Quaternion = Basis.looking_at(-look_dir, up_direction).get_rotation_quaternion()
				if is_focusing and is_instance_valid(current_focus_target):
					# Catch up quickly on lock-on, then track the target exactly (lag causes orbit wobble).
					var focus_weight: float = clampf(delta * rotation_interpolate_speed * 2.0, 0.0, 1.0)
					if q_from.angle_to(q_to) < 0.05:
						focus_weight = 1.0
					orientation.basis = Basis(q_from.slerp(q_to, focus_weight))
				else:
					var rotate_speed: float = rotation_interpolate_speed * 2.0 if is_aiming_firearm else rotation_interpolate_speed
					# First person turns the body with the view at once: any lag here swings the hands, and the gun in them, across the screen
					var rotate_weight: float = 1.0 if is_first_person else clampf(delta * rotate_speed, 0.0, 1.0)
					orientation.basis = Basis(q_from.slerp(q_to, rotate_weight))

		_set_locomotion_blend(target_motion)

	# Handle movement when not strafing
	elif not is_riding:
		# Use camera-relative direction for target_motion direction
		var camera_basis: Basis = spring_arm.global_transform.basis
		var target_dir: Vector3 = camera_basis * Vector3(target_motion.x, 0.0, -target_motion.y)
		target_dir = target_dir.slide(up_direction)
		if target_dir.length_squared() > 0.001 and not is_firing_arrow and not is_hanging_braced and not is_hanging_free and not is_climbing:
			target_dir = target_dir.normalized()
			var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
			var q_to: Quaternion = Basis.looking_at(-target_dir, up_direction).get_rotation_quaternion()
			orientation.basis = Basis(q_from.slerp(q_to, delta * rotation_interpolate_speed))

		_set_locomotion_blend(Vector2(0.0, target_motion.length()))

	var root_motion_position: Vector3 = animation_tree.get_root_motion_position()
	if is_swimming and not is_climbing_on:
		root_motion_position *= swimming_root_motion_multiplier

	var root_motion: Transform3D = Transform3D(animation_tree.get_root_motion_rotation(), root_motion_position)

	orientation *= root_motion

	var h_velocity: Vector3 = orientation.origin / delta
	
	# Override h_velocity when targeting so tangential root motion follows an exact circular arc.
	if is_focusing and is_instance_valid(current_focus_target):
		var to_target: Vector3 = (get_focus_target_position() - global_position).slide(up_direction)
		var orbit_radius: float = to_target.length()
		if orbit_radius > 0.1:
			var target_dir: Vector3 = to_target / orbit_radius
			# Strafe distance becomes rotation about the target; forward/back changes the radius.
			var arc_angle: float = - root_motion_position.x / orbit_radius
			var new_radius: float = maxf(orbit_radius - root_motion_position.z, 0.1)
			var new_offset: Vector3 = (-target_dir * new_radius).rotated(up_direction, arc_angle)
			h_velocity = (to_target + new_offset) / delta

	# Influence of root motion is removed when in the air, and movement is instead based on the input direction to allow for more player control while jumping and falling.
	# Flips stay root-motion driven so held move input doesn't push the player around.
	if (is_jumping or is_falling) and not is_flipping:
		var camera_basis: Basis = spring_arm.global_transform.basis
		var target_dir: Vector3 = camera_basis * Vector3(target_motion.x, 0.0, -target_motion.y)
		target_dir = target_dir.slide(up_direction)
		
		var current_h_vel: Vector3 = velocity.slide(up_direction)
		var current_speed: float = current_h_vel.length()
		var air_speed_cap: float = maxf(current_speed, 5.0)
		var target_h_vel: Vector3 = target_dir * air_speed_cap
		
		# Slowly lerp to target air speed to preserve momentum
		h_velocity = current_h_vel.lerp(target_h_vel, 3.0 * delta)

	var vertical_speed: float = velocity.dot(up_direction)
	if is_climbing or is_climbing_on or is_climbing_hopping_left or is_climbing_hopping_right or is_climbing_hopping_up:
		vertical_speed = h_velocity.dot(up_direction)
	elif is_hanging_braced or is_hanging_free:
		vertical_speed = 0.0
	elif is_riding:
		# While riding, vertical movement is driven by root motion/input, not gravity.
		vertical_speed = h_velocity.dot(up_direction)
	elif is_swimming:
		# While swimming, vertical movement is driven by root motion/input, not gravity.
		vertical_speed = h_velocity.dot(up_direction) + swim_vertical_speed
	else:
		vertical_speed += get_gravity().dot(up_direction) * 1.5 * delta
	velocity = (h_velocity + knockback_velocity).slide(up_direction) + (up_direction * vertical_speed)
	last_fall_speed = - vertical_speed
	update_movement_and_rotation(delta)


## Feeds [param motion] to the blend space of the stance being played: crouching is its own locomotion state, so
## while crouched only that space moves; otherwise the [method equipment_group]'s space, or plain standing.
func _set_locomotion_blend(motion: Vector2) -> void:
	if is_crouching:
		animation_tree.set(CROUCHING_LOCOMOTION_BLEND_POSITION_PATH, motion)
		return
	match equipment_group():
		"GreatSword":
			animation_tree.set(GREATSWORD_LOCOMOTION_BLEND_POSITION_PATH, motion)
		"Bow":
			animation_tree.set(ARCHERY_LOCOMOTION_BLEND_POSITION_PATH if is_shooting else BOW_LOCOMOTION_BLEND_POSITION_PATH, motion)
		"Shield":
			animation_tree.set(SHIELD_LOCOMOTION_BLEND_POSITION_PATH, motion)
		"Pistol":
			animation_tree.set(PISTOL_LOCOMOTION_BLEND_POSITION_PATH, motion)
		"Rifle":
			animation_tree.set(RIFLE_LOCOMOTION_BLEND_POSITION_PATH, motion)
		"Boxing":
			animation_tree.set(BOXING_LOCOMOTION_BLEND_POSITION_PATH, motion)
		_:
			animation_tree.set(STANDING_LOCOMOTION_BLEND_POSITION_PATH, motion)


## Detect if the player is in front of a ledge and can hang from it and/or climb on to it.
func detect_ledge() -> bool:
	# Ledge detection [Raycast]
	var ledge_detected: bool = false
	if not is_on_floor() and ledge_detection_horizontal and ledge_detection_horizontal.is_colliding():
		var forward_direction: Vector3 = -ledge_detection_horizontal.global_transform.basis.z.normalized()
		ledge_detection_vertical.global_position = ledge_detection_horizontal.get_collision_point() + (forward_direction * 0.05) + up_direction
		ledge_detection_vertical.force_raycast_update()
		if ledge_detection_vertical.is_colliding():
			ledge_detection_marker.global_position = ledge_detection_vertical.get_collision_point() + (ledge_detection_vertical.get_collision_normal() * 0.02)
			ledge_detected = true

	# Show/hide ledge detection gizmos.
	if ledge_detected:
		climbing_on_target = ledge_detection_marker.global_position
		ledge_detection_horizontal.show()
		ledge_detection_marker.show()
	else:
		clear_ledge_visuals()

	return ledge_detected


## Called by the animation(s) using "Call Method Track" to execute the jump logic at the right time. 
func execute_jump() -> void:
	if not is_jump_queued:
		return
	# A rideable applies its own jump on the press; here the keyframe only clears the queue
	if not is_riding:
		velocity = velocity.slide(up_direction) + (up_direction * jump_speed)
	is_jump_queued = false
	is_jumping = true
	# Flip flags are only needed to enter the flip animation state, so clear them here.
	is_front_flipping = false
	is_back_flipping = false


## A jump off nothing: one of [member air_jumps_left] is spent and the Player goes up at [member jump_speed] at
## once (the clip's keyframe would come too late in the air), with the jump clip played again for the look of
## it. The air states call it on a Jump press when [member enable_double_jump] is on; false when none is left.
func air_jump() -> bool:
	if not enable_double_jump or air_jumps_left <= 0 or is_on_floor():
		return false
	air_jumps_left -= 1
	bounce(jump_speed)
	return true


## Thrown upward at [param speed] by a spring, a mushroom, a stomp: straight into the air, the jump clip on.
func bounce(speed: float) -> void:
	if current_state != NodeStateMachine.States.JUMPING:
		state_machine.travel(current_state, NodeStateMachine.States.JUMPING)
	# After the travel: an instant ground jump in Jumping.start would otherwise have the last word on the speed
	velocity = velocity.slide(up_direction) + up_direction * speed
	is_jump_queued = false
	is_jumping = true
	travel_locomotion("JumpingUp")


## Snaps the model orientation to face the given direction on the movement plane.
func rotate_model_to_direction(dir: Vector3) -> void:
	var horizontal_dir: Vector3 = dir.slide(up_direction)
	if horizontal_dir.length_squared() > 0.001:
		horizontal_dir = horizontal_dir.normalized()
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(-horizontal_dir, up_direction).get_rotation_quaternion()
		orientation.basis = Basis(q_from.slerp(q_to, 1.0))
		player_model.global_transform.basis = orientation.basis


## Smoothly turns the model orientation toward the given direction on the movement plane.
func turn_model_toward_direction(dir: Vector3, delta: float) -> void:
	var horizontal_dir: Vector3 = dir.slide(up_direction)
	if horizontal_dir.length_squared() > 0.001:
		horizontal_dir = horizontal_dir.normalized()
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(-horizontal_dir, up_direction).get_rotation_quaternion()
		var rotate_weight: float = clampf(delta * rotation_interpolate_speed, 0.0, 1.0)
		orientation.basis = Basis(q_from.slerp(q_to, rotate_weight))
		player_model.global_transform.basis = orientation.basis


## Starts charging a throw when the shoot button is pressed. (Delegates to [HeldObject].)
func start_charging_throw() -> void:
	if held_object:
		held_object.start_charging_throw()


## Called when the shoot button is released while charging a throw. (Delegates to [HeldObject].)
func release_charging_throw() -> void:
	if held_object:
		held_object.release_charging_throw()


## Updates the Steam persona label for the current lobby size.
func _update_steam_persona_name() -> void:
	display_name = ""
	var steam: Object = SteamPeer.session(self)
	var lobby_id: int = SteamPeer.lobby_of(self)
	if steam == null or lobby_id == 0 or steam.getNumLobbyMembers(lobby_id) <= 1:
		return
	display_name = steam.getPersonaName()


## Refreshes the Steam persona label when a lobby member joins or leaves.
func _on_steam_lobby_chat_update(
		lobby_id: int,
		_changed_id: int,
		_making_change_id: int,
		_chat_state: int,
) -> void:
	if lobby_id == SteamPeer.lobby_of(self):
		_update_steam_persona_name()


## Called by throw animation(s) using "Call Method Track" to throw the held object at the right frame.
func execute_throw() -> void:
	if held_object:
		held_object.execute_throw()



## Gets the grounded locomotion state that matches the current equipment and intent.
## Grouped states use "Group/State" travel paths.
func get_grounded_locomotion_state() -> StringName:
	if is_exhausted and is_on_floor() and not has_move_input:
		return &"HeavyBreathing"
	if is_crouching:
		return &"CrouchingLocomotion"
	var group: String = equipment_group()
	if group.is_empty():
		return &"StandingLocomotion"
	if group == "Bow" and is_shooting:
		return &"Bow/ArcheryLocomotion"
	return StringName(group + "/" + group + "Locomotion")


## The locomotion group the equipment in hand plays in: "GreatSword" (two-handed weapons, the rod and the staff),
## "Bow", "Shield" (one-handed weapons and the sword and shield), "Pistol", "Rifle", "Boxing" when unarmed in the
## stance, or "" for plain standing. Two-handed wins over the bow, which wins over one-handed, so the stance, its
## blend space and the drawn-weapon check always name the same group.
func equipment_group() -> String:
	if equipped_axe_2h or equipped_fishing_rod or equipped_staff or equipped_sword_2h:
		return "GreatSword"
	if equipped_bow:
		return "Bow"
	if equipped_axe_1h or equipped_dagger or equipped_shield or equipped_sword_1h:
		return "Shield"
	if equipped_pistol:
		return "Pistol"
	if equipped_rifle:
		return "Rifle"
	if is_boxing:
		return "Boxing"
	return ""


## True if the state is the deepest current locomotion node or queued in a travel path.
func is_locomotion_state_active_or_queued(state_name: String) -> bool:
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if root_playback == null:
		return false
	var playback: AnimationNodeStateMachinePlayback = active_locomotion_playback
	if String(playback.get_current_node()) == state_name:
		return true
	if StringName(state_name) in playback.get_travel_path():
		return true
	return StringName(state_name) in root_playback.get_travel_path()


## Travels the locomotion state machine; supports "Group/State" paths into nested machines.
func travel_locomotion(state_path: String) -> void:
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if root_playback == null:
		return
	var parts: PackedStringArray = state_path.split("/")
	var entering_group: bool = parts[0] in LOCOMOTION_GROUPS \
			and String(root_playback.get_current_node()) != parts[0]
	root_playback.travel(parts[0])
	if parts.size() > 1:
		# On fresh entry of an undrawn group, let the Start edges route through the draw.
		if entering_group and drawn_weapon_group != parts[0] and parts[1].ends_with("Locomotion"):
			return
		var group_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/LocomotionStateMachine/" + parts[0] + "/playback")
		if group_playback:
			group_playback.travel(parts[1])


## Wired to Abilities.cast_started: holds the weapon group's Spell Casting channel for the cast time; unarmed,
## where no such clip exists, the Ready To Cast Spell emote holds the upper body instead.
func _on_abilities_cast_started(ability: Ability) -> void:
	var state_path: String = ability.get_cast_state(get_spell_group(), true)
	if not state_path.is_empty():
		_travel_spell_state(state_path)
	elif is_standing and ability.cast_style != Ability.CastStyle.NONE and get_spell_group().is_empty():
		_start_channel_emote()


## Wired to Chat.typing_changed: gameplay input stays blocked while the chat input row is open.
func _on_chat_typing_changed(typing: bool) -> void:
	is_typing = typing


## Wired to Abilities.ability_activated: plays the cast (or power up) clip for the ability's cast style.
func _on_abilities_ability_activated(ability: Ability) -> void:
	_end_channel_emote()
	_travel_spell_state(ability.get_cast_state(get_spell_group(), false))


## Wired to Abilities.cast_interrupted: drops the channel pose.
func _on_abilities_cast_interrupted(_ability: Ability) -> void:
	_end_channel_emote()
	if not is_standing or not current_locomotion_node.ends_with("SpellCasting"):
		return
	var stance: String = String(get_grounded_locomotion_state())
	if active_locomotion_playback.get_fading_from_node() != &"":
		# A travel is dropped while the channel is still fading in, so snap back to the stance
		active_locomotion_playback.start(stance.get_file())
	else:
		travel_locomotion(stance)


## The locomotion group spell clips are picked for ("Shield", "GreatSword", ...), or "" unarmed.
func get_spell_group() -> String:
	var node: String = String(locomotion_state.get_current_node()) if locomotion_state else ""
	return node if node in LOCOMOTION_GROUPS else ""


## Spell clips only exist for standing on the ground; anywhere else the cast plays no pose.
func _travel_spell_state(state_path: String) -> void:
	if is_standing and not state_path.is_empty():
		travel_locomotion(state_path)


## Holds the Ready To Cast Spell pose on the emote layer, the way a carried object does.
func _start_channel_emote() -> void:
	var emote_state: AnimationNodeStateMachinePlayback = animation_tree.get(EMOTE_STATE_PLAYBACK_PATH)
	if emote_state == null or (held_object and held_object.is_holding_object()):
		return
	emote_spine_blend = 1.0
	emote_state.start(CAST_CHANNEL_EMOTE)
	is_emoting = true
	has_started_emoting = false


## Lets go of the channel pose, if it is the one showing.
func _end_channel_emote() -> void:
	var emote_state: AnimationNodeStateMachinePlayback = animation_tree.get(EMOTE_STATE_PLAYBACK_PATH)
	if emote_state and emote_state.get_current_node() == CAST_CHANNEL_EMOTE and not (held_object and held_object.is_holding_object()):
		emote_state.start("Idle")
		emote_spine_blend = 0.0
		is_emoting = false
		has_started_emoting = false


static var _weather_fx_script: Script = null
static var _weather_fx_checked: bool = false

## Soft WeatherFX interop: returns the global precipitation strength, or 0.0 when the addon is absent.
func get_precipitation_strength() -> float:
	if not _weather_fx_checked:
		_weather_fx_checked = true
		var weather_fx_path: String = "res://addons/weather_fx/scripts/weather_fx.gd"
		if ResourceLoader.exists(weather_fx_path):
			_weather_fx_script = load(weather_fx_path) as Script
	if _weather_fx_script:
		return _weather_fx_script.get_precipitation_strength()
	return 0.0


## Returns true if the player is currently inside an updraft or thermal air column. The overlaps come from
## UpdraftDetection's area signals; a burned-out thermal has monitoring off, so a ghost updraft never grants lift.
func is_in_updraft() -> bool:
	for area: Area3D in _updrafts:
		if is_instance_valid(area) and area.monitoring:
			return true
	return false


## Wired to UpdraftDetection.area_entered in player.tscn: an area in the "Updraft" or "Thermal" group is lift.
func _on_updraft_detection_area_entered(area: Area3D) -> void:
	if area.is_in_group(&"Updraft") or area.is_in_group(&"Thermal"):
		_updrafts.append(area)


## Wired to UpdraftDetection.area_exited in player.tscn.
func _on_updraft_detection_area_exited(area: Area3D) -> void:
	_updrafts.erase(area)


## Wired to UpdraftVfxTimer.timeout: the optional [member updraft_aura] shows, on every peer, while the Player is in
## a thermal or within five metres of an active one.
func _update_updraft_vfx() -> void:
	if not is_instance_valid(updraft_aura):
		return
	var should_show: bool = is_in_updraft()
	if not should_show:
		for node: Node in get_tree().get_nodes_in_group(&"Updraft") + get_tree().get_nodes_in_group(&"Thermal"):
			var area: Area3D = node as Area3D
			if area and (area.monitoring or area.monitorable) and area.global_position.distance_to(global_position) <= 5.0:
				should_show = true
				break
	if updraft_aura.visible != should_show:
		_show_updraft_aura(should_show)


## Shows or hides [member updraft_aura], its particles emitting only while it shows.
func _show_updraft_aura(shown: bool) -> void:
	updraft_aura.visible = shown
	for particles: Node in updraft_aura.find_children("*", "GPUParticles3D", true, false):
		(particles as GPUParticles3D).emitting = shown


## Gets the player's forward direction projected onto the movement plane.
func get_facing_direction() -> Vector3:
	var facing_direction: Vector3 = -player_model.global_transform.basis.z
	facing_direction = facing_direction.slide(up_direction)
	if facing_direction.length_squared() <= 0.001:
		return Vector3.ZERO
	return facing_direction.normalized()


## Called by the animation(s) using "Call Method Track" to play footstep sound effects at the right time. The
## ground raycast, not is_on_floor(): only move_and_slide() computes that, and a puppet never moves itself.
func sfx_footsteps_play() -> void:
	if paraglider_raycast.is_colliding() and not is_ragdolling:
		var collider: Node3D = paraglider_raycast.get_collider() as Node3D
		if audio:
			audio.play_footstep(collider)


## Called by the animation(s) using "Call Method Track" to play sliding footstep sound effects at the right time.
func sfx_footsteps_slide_play() -> void:
	if paraglider_raycast.is_colliding():
		var collider: Node3D = paraglider_raycast.get_collider() as Node3D
		if audio:
			audio.play_slide(collider)


## Reset the attack sequence when the attack sequence timer times out.
func _on_attack_sequence_timer_timeout() -> void:
	attack_sequence = 0


## True when the last move touched a [RigidBody3D] (a ball, a crate, a snowball) as floor or as wall. Godot takes
## platform velocity from either, so a ball the Player is only walking into counts too.
func is_touching_rigid_body() -> bool:
	for i: int in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is RigidBody3D:
			return true
	return false


## Applies the current velocity, moves the player, and updates the orientation to match the up_direction.
func update_movement_and_rotation(delta: float) -> void:
	var current_body_up: Vector3 = global_basis.y
	if not current_body_up.is_equal_approx(up_direction):
		var q_align_body: Quaternion = Quaternion(current_body_up, up_direction)
		global_basis = Basis(q_align_body) * global_basis

	var pre_velocity: Vector3 = velocity
	# A rigid body is a prop, not a lift. A rolling ball or a tumbling crate must not carry the Player with the
	# speed of its surface, nor throw them with it on parting: a snowball the Player walked into, whose back
	# comes up as it rolls away, handed over 1.4 m/s upward and launched the Player a metre and a half into the
	# air. Moving platforms (AnimatableBody3D) still carry the Player as they always have.
	var on_prop: bool = is_touching_rigid_body()
	platform_floor_layers = 0 if on_prop else 0xFFFFFFFF
	# Both: the velocity a leave adds is the one recorded last frame, before the layers were cleared.
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING if on_prop else PLATFORM_ON_LEAVE_ADD_VELOCITY
	move_and_slide()

	for i: int in get_slide_collision_count():
		var c: KinematicCollision3D = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			var rb: RigidBody3D = c.get_collider() as RigidBody3D
			if rb != held_rigidbody:
				var push_dir: Vector3 = -c.get_normal()
				var velocity_proj: float = pre_velocity.dot(push_dir)
				var rb_velocity_proj: float = rb.linear_velocity.dot(push_dir)
				var relative_velocity_proj: float = velocity_proj - rb_velocity_proj
				if relative_velocity_proj > 0.0:
					var effective_mass: float = (mass * rb.mass) / (mass + rb.mass)
					rb.apply_impulse(push_dir * relative_velocity_proj * effective_mass * push_force, c.get_position() - rb.global_position)

	if is_on_floor() and not is_swimming and not is_falling:
		last_safe_shore_position = global_position


	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.

	# Smoothly align character body and model orientation Y-axis with up_direction
	var current_up: Vector3 = orientation.basis.y
	if not current_up.is_equal_approx(up_direction):
		var next_up: Vector3 = current_up.slerp(up_direction, delta * 10.0).normalized()
		var q_align: Quaternion = Quaternion(current_up, next_up)
		orientation.basis = Basis(q_align) * orientation.basis


	# Rotate the Player Model (unless entering/exiting a vehicle or ragdolling)
	if not (is_riding and (is_mounting or is_dismounting)) and not is_ragdolling:
		if is_zero_approx(model_pitch):
			player_model.global_transform.basis = orientation.basis
			player_model.transform.origin = initial_player_model_transform.origin
		else:
			# Pitch about a hip-height pivot so the body doesn't sweep around the feet like a ball
			var pitched_basis: Basis = orientation.basis * Basis(Vector3.RIGHT, model_pitch)
			var pivot_local: Vector3 = Vector3(0.0, model_pitch_pivot_height, 0.0)
			var base_origin: Vector3 = to_global(initial_player_model_transform.origin)
			var pivot_global: Vector3 = base_origin + (orientation.basis * pivot_local)
			player_model.global_transform = Transform3D(pitched_basis, pivot_global - (pitched_basis * pivot_local))
		var model_facing_basis: Basis = orientation.basis.rotated(up_direction, PI)
		var rotated_basis: Basis = model_facing_basis * initial_separation_ray_transform.basis
		var rotated_origin: Vector3 = global_position + (model_facing_basis * initial_separation_ray_transform.origin)
		separation_ray_shape.global_transform = Transform3D(rotated_basis, rotated_origin)


## Called by a water Area3D when the player enters water. Every peer's area reports it, but only the owning peer
## runs the state machine; the others follow the replicated state (and see the splash through [Swimming]).
func enter_water(water_area: Area3D = null) -> void:
	if not is_multiplayer_authority():
		return
	current_water_area = water_area
	if not is_swimming and not is_riding and not is_ragdolling:
		if state_machine:
			state_machine.travel(current_state, NodeStateMachine.States.SWIMMING)


## Called by a water Area3D when the player exits water; like [method enter_water], the owning peer's alone.
func exit_water(water_area: Area3D = null) -> void:
	if not is_multiplayer_authority():
		return
	if water_area == null or water_area == current_water_area:
		current_water_area = null
		if is_swimming:
			is_swimming = false
			if state_machine:
				state_machine.travel(NodeStateMachine.States.SWIMMING, NodeStateMachine.States.STANDING if is_on_floor() else NodeStateMachine.States.FALLING)


## Update volume on all SFX footstep AudioStreamPlayer3D nodes under player.
func update_sfx_volume(value: float) -> void:
	if audio:
		audio.set_sfx_volume(value)


## Update volume on RadiOtPlayer3D node under player.
func update_music_volume(value: float) -> void:
	if audio:
		audio.set_music_volume(value)


## Applies the synchronized locomotion path ("Group/Node" or "Node") to a puppet's AnimationTree.
func _apply_synced_locomotion_node(state_path: String) -> void:
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if state_path.is_empty() or root_playback == null:
		return
	var parts: PackedStringArray = state_path.split("/")
	if String(root_playback.get_current_node()) != parts[0]:
		root_playback.travel(parts[0])
	if parts.size() > 1:
		var group_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/LocomotionStateMachine/" + parts[0] + "/playback")
		if group_playback and String(group_playback.get_current_node()) != parts[1]:
			group_playback.travel(parts[1])


## Applies the synchronized blend position to the puppet's current locomotion blend space (1D spaces take the forward axis).
func _apply_synced_blend_position(blend_pos: Vector2) -> void:
	if sync_locomotion_node.is_empty():
		return
	var path: String = "parameters/LocomotionStateMachine/" + sync_locomotion_node + "/blend_position"
	var current: Variant = animation_tree.get(path)
	if current is Vector2:
		animation_tree.set(path, blend_pos)
	elif current is float:
		animation_tree.set(path, blend_pos.y if blend_pos.y != 0.0 else blend_pos.length())


## Points the spine [LookAtModifier3D] at [param target], or clears it when [param target] is null.
## [HeldObject] (carried body), [Bow] and [Firearm] (crosshair while aiming) are the only callers.
## [param forward_axis] is the axis of the Spine that the stance already points at the target, and the
## modifier pitches about the horizontal axis square to it: +Z for a gun held out in front (pitching about X),
## +X for the archer's side-on stance, where the spine's front faces the bow arm's side (pitching about Z).
func set_look_at_target(target: Node3D, forward_axis: SkeletonModifier3D.BoneAxis = SkeletonModifier3D.BONE_AXIS_PLUS_Z) -> void:
	var modifier: LookAtModifier3D = look_at_modifier as LookAtModifier3D
	if modifier == null:
		return
	if target:
		var sideways: bool = forward_axis in [SkeletonModifier3D.BONE_AXIS_PLUS_X, SkeletonModifier3D.BONE_AXIS_MINUS_X]
		modifier.forward_axis = forward_axis
		modifier.primary_rotation_axis = Vector3.AXIS_Z if sideways else Vector3.AXIS_X
	modifier.target_node = modifier.get_path_to(target) if target else NodePath("")
	modifier.active = target != null


## Glues the hands to two nodes for first person: [param right] and [param left] are what the hand IKs reach for
## and the two rotation copies turn the hands as, so whatever is in hand rides them instead of the torso, and the
## head, and the camera on it, never move. Either may be null to leave that arm to the animation. [param right_pole]
## aims the right elbow for as long as this holds (a drawing arm bends back and out, a grip on a gun low and in
## front); null keeps the shared [member hand_ik_pole]. [Firearm] passes the two camera markers, placed by
## [method set_first_person_hands]; [Bow] its string hand marker and the camera's left one.
## [method clear_first_person_hands] gives the arms back to the animation.
func set_first_person_hand_targets(right: Node3D, left: Node3D, right_pole: Node3D = null) -> void:
	if not is_instance_valid(right_hand_ik) or not is_instance_valid(left_hand_ik):
		return
	if is_instance_valid(right):
		var pole: Node3D = right_pole if is_instance_valid(right_pole) else hand_ik_pole
		right_hand_ik.set_target_node(0, right_hand_ik.get_path_to(right))
		right_hand_ik.set_pole_node(0, right_hand_ik.get_path_to(pole))
		right_hand_ik.influence = 1.0
		right_hand_ik.active = true
		first_person_right_hand_rotation.set_reference_node(0, first_person_right_hand_rotation.get_path_to(right))
		first_person_right_hand_rotation.influence = 1.0
		first_person_right_hand_rotation.active = true
	else:
		_release_right_hand()
	if is_instance_valid(left):
		left_hand_ik.set_target_node(0, left_hand_ik.get_path_to(left))
		left_hand_ik.active = true
		first_person_left_hand_rotation.set_reference_node(0, first_person_left_hand_rotation.get_path_to(left))
		first_person_left_hand_rotation.active = true
	else:
		left_hand_ik.active = false
		first_person_left_hand_rotation.active = false


## Glues both hands to the view at [param right] and [param left], the hands' transforms in the camera's own space:
## a gun, held the same way whatever the view does. [Firearm] is the caller, with the transforms it exports per gun.
func set_first_person_hands(right: Transform3D, left: Transform3D) -> void:
	first_person_right_hand.transform = right
	first_person_left_hand.transform = left
	set_first_person_hand_targets(first_person_right_hand, first_person_left_hand)


## Lets go of the view: both hand IKs and rotation copies off, the right IK's target cleared and its pole back on
## the shared one for whoever asks next.
func clear_first_person_hands() -> void:
	if not is_instance_valid(right_hand_ik) or not is_instance_valid(left_hand_ik):
		return
	_release_right_hand()
	left_hand_ik.active = false
	first_person_left_hand_rotation.active = false


func _release_right_hand() -> void:
	right_hand_ik.active = false
	right_hand_ik.influence = 0.0
	right_hand_ik.set_target_node(0, NodePath(""))
	right_hand_ik.set_pole_node(0, right_hand_ik.get_path_to(hand_ik_pole))
	first_person_right_hand_rotation.active = false


## Points the head [LookAtModifier3D] at [param target], or, when [param target] is null, back at
## [member head_look_target], where the camera's pitch puts it, so the head looks up and down with the camera
## whenever nothing else claims it. Separate from [method set_look_at_target], which turns the spine to aim: this
## one turns the head only, so it can sit on top of whatever the body is doing (reading a screen while the hands
## keep typing). The modifier is last among the skeleton's children so it applies after the spine look-at and the
## hand IK, and its angle limits keep the neck inside a plausible range, so a target behind the Player is simply
## not followed all the way.
func set_head_look_at_target(target: Node3D) -> void:
	var modifier: LookAtModifier3D = head_look_at_modifier as LookAtModifier3D
	if modifier == null:
		return
	var looked_at: Node3D = target if target else head_look_target
	modifier.target_node = modifier.get_path_to(looked_at) if looked_at else NodePath("")
	modifier.active = looked_at != null


@export_category("Combat")
@export var skill_level: int = 0 ## Marksmanship: shrinks the spread of ranged equipment per its [Accuracy] resource (0 novice, expert at the resource's expert_level).
@export_category("Traversal")
@export var lethal_fall_speed: float = 15.0 ## Landing at or above this downward speed (m/s), about an 11.5 m drop, costs the whole of the health ([method take_fall]).
@export var parry_recoil: float = 5.0 ## Speed (m/s) this Player is thrown back when another Player parries its swing.
@export var hit_knockback: float = 4.0 ## Speed (m/s) a hit shoves the Player away from where it came from, dying away at [member knockback_damping].
@export var knockback_damping: float = 12.0 ## How fast (m/s²) a shove dies away.
@export var safe_fall_speed: float = 10.0 ## Landing slower than this (m/s), about a 5 m drop, hurts nothing; from here to [member lethal_fall_speed] the damage rises to all of the health.
@export var wall_leap_horizontal_speed: float = 5.0 ## Horizontal impulse away from the wall on a climbing/hanging back-eject.
@export var wall_leap_vertical_speed: float = 3.5 ## Vertical impulse on a climbing/hanging back-eject.


## Smoothly turns the model to face the wall hit by the horizontal ledge raycast.
func face_wall(delta: float) -> void:
	if ledge_detection_horizontal.is_colliding():
		turn_model_toward_direction(-ledge_detection_horizontal.get_collision_normal(), delta)


## Launches the player away from the wall they are facing (climbing/hanging back-eject).
func leap_off_wall() -> void:
	var wall_normal: Vector3 = player_model.global_transform.basis.z.slide(up_direction).normalized()
	velocity = (wall_normal * wall_leap_horizontal_speed) + (up_direction * wall_leap_vertical_speed)


## Hides the ledge detection gizmos and resets the vertical probe to its default offset.
func clear_ledge_visuals() -> void:
	ledge_detection_vertical.position = Vector3(0, 0, -1)
	ledge_detection_horizontal.hide()
	ledge_detection_marker.hide()


## Gets on [param rideable] (a skateboard, a vehicle, a mount): it takes over movement and camera through the
## [Riding] state until [method dismount].
func mount(rideable: Node3D) -> void:
	if rideable == null or is_riding or state_machine == null:
		return
	riding = rideable
	state_machine.travel(current_state, NodeStateMachine.States.RIDING)


## Gets off whatever is being ridden, through the rideable's get-off animation when it has one;
## [param immediate] skips it (a bail out at speed).
func dismount(immediate: bool = false) -> void:
	if not is_riding or state_machine == null:
		return
	if not immediate:
		var riding_state: Node = state_machine.get_node_or_null("Riding")
		if riding_state and riding_state.has_method("begin_dismount") and riding_state.call("begin_dismount"):
			return
	state_machine.travel(NodeStateMachine.States.RIDING, NodeStateMachine.States.STANDING)


## Draws the on-screen controls the way the saved [member PlayerSettingsResource.hud_mode] (or
## [member hud_mode_override]) asks. The whole HUD shows on touch, or when Shown; otherwise only the contextual
## buttons show, the ones whose label means something right now (Pick Up on Action by a pickup, Climb on Jump at
## a wall, the fishing buttons with the rod out; see [member Controls.contextual_only]), so a desktop player
## keeps a clean screen and still sees what to press. Anything that hid the HUD for a while (a game taking the
## screen) calls this to give it back rather than showing it outright.
func apply_hud_visibility() -> void:
	if controls == null or not is_multiplayer_authority():
		return
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var mode: int = hud_mode_override if hud_mode_override >= 0 else settings.hud_mode
	var shown: bool = PlayerSettingsResource.hud_shown_for(mode, controls.current_input_type, DisplayServer.is_touchscreen_available())
	controls.contextual_only = not shown
	controls.visible = true


## Wired to Controls.input_type_changed in player.tscn: the HUD follows the device in hand, and the current state
## puts its own button labels back for it.
func _on_controls_input_type_changed(_input_type: int) -> void:
	if not is_multiplayer_authority():
		return
	apply_hud_visibility()
	refresh_contextual_controls()


## The current state's contextual labels, applied again (the device changed, the equipment changed, a prompt let go).
func refresh_contextual_controls() -> void:
	if controls == null or state_machine == null:
		return
	var state_node: NodeStateMachine = state_machine.get_node_or_null(NodePath(NodeStateMachine.get_state_name(current_state))) as NodeStateMachine
	if state_node:
		state_node._on_input_type_changed(controls.current_input_type)


## Whether the current rideable keeps weapons and items holstered (a car does, a board does not).
func riding_blocks_hands() -> bool:
	return is_riding and riding != null and riding.get("blocks_hands") == true


## Teleports the Player to the given transform, clearing motion and restoring the model and collision poses.
## A Player warped out of the water climbs out of it too, once the physics step has seen where they went.
func warp_to(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	up_direction = target.basis.y.normalized()
	orientation = Transform3D(target.basis, Vector3.ZERO)
	player_model.transform = initial_player_model_transform
	collision_shape.transform = initial_collision_shape_transform
	# A wall state has no gravity and no wall to hold once teleported, so it ends here; the ground decides the rest
	if state_machine and current_state in [NodeStateMachine.States.CLIMBING, NodeStateMachine.States.HANGING]:
		state_machine.travel(current_state, NodeStateMachine.States.FALLING)
	if current_water_area:
		_leave_water_if_out.call_deferred()


## After a warp: the water area reports its overlaps on the physics step, so this waits for one.
func _leave_water_if_out() -> void:
	await get_tree().physics_frame
	if is_instance_valid(current_water_area) and not current_water_area.overlaps_body(self):
		exit_water(current_water_area)


var movement_scale: float = 1.0 ## Fraction of normal movement speed; [method slow] lowers it for a while.
var terrain_speed_scale: float = 1.0 ## Fraction of normal movement speed the ground allows, set by whatever the Player is wading through: the snow addon's FootStamper lowers it in snow above the knee. Separate from [member movement_scale], which [method slow] owns and resets, and multiplied with it.
var _slow_timer: SceneTreeTimer


## Slows movement to [param factor] of normal for [param seconds], as a Frostbolt does. Lands on the owning peer like
## a hit: a copy on another peer sends it there. [param source_path] names the caster.
func slow(factor: float, seconds: float, source_path: NodePath = ^"") -> void:
	if not is_multiplayer_authority():
		_slow.rpc_id(get_multiplayer_authority(), factor, seconds, source_path)
		return
	movement_scale = clampf(factor, 0.0, 1.0)
	_slow_timer = get_tree().create_timer(maxf(seconds, 0.0))
	_slow_timer.timeout.connect(_end_slow.bind(_slow_timer))


## [method slow] arriving from another peer; see [method _may_affect].
@rpc("any_peer", "reliable")
func _slow(factor: float, seconds: float, source_path: NodePath) -> void:
	if is_multiplayer_authority() and _may_affect(source_path):
		slow(factor, seconds, source_path)


func _end_slow(timer: SceneTreeTimer) -> void:
	if timer == _slow_timer: # A newer slow runs on its own timer
		movement_scale = 1.0


## Whether an effect sent from another peer ([method take_hit], [method heal], [method slow], [method hunted_by])
## may land on this Player: one from the server (every NPC, projectile and hazard runs there), or one from the peer
## that owns [param source_path], the attacker or caster. Anyone else is ignored. Asked only by the RPC entry points
## (_take_hit, _heal, _slow, _hunted_by), the one place the remote sender is the caller: a call this peer makes itself
## while it handles somebody else's RPC is its own, and runs directly.
func _may_affect(source_path: NodePath) -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 1:
		return true
	var source: Node = null if source_path.is_empty() else get_node_or_null(source_path)
	return source != null and source.get_multiplayer_authority() == sender


## Damage lands on the owning peer: it costs health, shoves away from [param from] and rumbles the pad. A copy on
## another peer sends it there; enemies run on the server, so their hits arrive that way. [param source_path] names
## the attacker, which lets a hit from another player's peer through (see [method _may_affect]). A negative amount
## does nothing.
func take_hit(damage: float, from: Vector3, source_path: NodePath = ^"") -> void:
	if not is_multiplayer_authority():
		_take_hit.rpc_id(get_multiplayer_authority(), damage, from, source_path)
		return
	if not health.is_alive() or dodge_invulnerable:
		return
	# A raised shield facing the hit catches it: blocked, or parried
	if shield_guard and shield_guard.intercept(from, source_path):
		return
	health.damage(maxf(damage, 0.0), from)
	knock_back(from, hit_knockback)
	controls.rumble(0.6, 0.8, 0.25)


## Shoves the Player [param speed] m/s away from [param from], with a little lift, on its own peer (a copy sends it
## there, as [method take_hit] does). The shove rides on top of the walking speed and dies away, rather than being set
## once and overwritten by the next step's root motion.
func knock_back(from: Vector3, speed: float, source_path: NodePath = ^"") -> void:
	if not is_multiplayer_authority():
		_knock_back.rpc_id(get_multiplayer_authority(), from, speed, source_path)
		return
	var away: Vector3 = (global_position - from).slide(up_direction)
	if away.length_squared() < 0.001 or speed <= 0.0:
		return
	knockback_velocity = away.normalized() * speed
	velocity += up_direction * speed * 0.35


## [method knock_back] arriving from another peer; see [method _may_affect].
@rpc("any_peer", "reliable")
func _knock_back(from: Vector3, speed: float, source_path: NodePath) -> void:
	if is_multiplayer_authority() and _may_affect(source_path):
		knock_back(from, speed, source_path)


## [method take_hit] arriving from another peer; see [method _may_affect].
@rpc("any_peer", "reliable")
func _take_hit(damage: float, from: Vector3, source_path: NodePath) -> void:
	if is_multiplayer_authority() and _may_affect(source_path):
		take_hit(damage, from, source_path)


var hunters: Array[Node] = [] ## Enemies currently targeting this Player; mana regenerates only when it is empty.


## Enemies report starting and stopping their hunt; lands on the owning peer, where mana lives.
func hunted_by(enemy_path: NodePath, hunting: bool) -> void:
	if not is_multiplayer_authority():
		_hunted_by.rpc_id(get_multiplayer_authority(), enemy_path, hunting)
		return
	var enemy: Node = get_node_or_null(enemy_path)
	# A hunter freed without a word (a wave that stood down) is dropped before the list is touched, or the typed
	# array chokes on the dead reference
	var living: Array[Node] = []
	for hunter: Node in hunters:
		if is_instance_valid(hunter) and hunter != enemy:
			living.append(hunter)
	if hunting and is_instance_valid(enemy):
		living.append(enemy)
	hunters = living
	health.regen_paused = not hunters.is_empty()


## [method hunted_by] arriving from another peer; see [method _may_affect].
@rpc("any_peer", "reliable")
func _hunted_by(enemy_path: NodePath, hunting: bool) -> void:
	if is_multiplayer_authority() and _may_affect(enemy_path):
		hunted_by(enemy_path, hunting)


## True while a heal would do something; abilities check it before spending anything.
func can_heal() -> bool:
	return health.can_heal()


## Restores health on the owning peer, so one player can heal another; false only when already full here. A copy
## on another peer sends it there. [param source_path] names the healer, which lets a heal from another player's
## peer through (see [method _may_affect]). A negative amount heals nothing.
func heal(amount: float, source_path: NodePath = ^"") -> bool:
	if not is_multiplayer_authority():
		_heal.rpc_id(get_multiplayer_authority(), amount, source_path)
		return true
	return health.heal(maxf(amount, 0.0))


## [method heal] arriving from another peer; see [method _may_affect].
@rpc("any_peer", "reliable")
func _heal(amount: float, source_path: NodePath) -> void:
	if is_multiplayer_authority() and _may_affect(source_path):
		heal(amount, source_path)


## Called by a landing [Projectile] (its authority's copy alone); the Player is a valid target for enemy arrows and
## bullets, and the shooter is named as the hit's source.
func register_projectile_hit(projectile: Projectile, point: Vector3, _normal: Vector3) -> void:
	if projectile.shooter == self:
		return
	# A round on the Head hurtbox kills outright
	var headshot: bool = projectile.hit_part != null and projectile.hit_part.name == "Head"
	take_hit(health.max_health if headshot else projectile.damage, point, projectile.shooter.get_path() if is_instance_valid(projectile.shooter) else ^"")


## The body's side of a ragdoll, on every peer ([member is_ragdolling]'s setter): the model detached so the Player
## can follow the hips, the animation stopped, the physical bones colliding and simulating, the capsule off; or all
## of it undone, the model back at its rest transform. A detached model's replicated position is a world one, which
## is why a puppet must detach its own too.
func _set_ragdoll_physics(on: bool) -> void:
	if player_model:
		# A copy's model may already hold the owner's detached, world-space position as a local one; the bones would
		# start at twice the distance. Back at rest first, detaching keeps it where the body is.
		if on and not is_multiplayer_authority():
			player_model.position = initial_player_model_transform.origin
		player_model.top_level = on
		if not on:
			player_model.transform = initial_player_model_transform
	if animation_tree:
		animation_tree.active = not on # also stops method tracks playing audio on a limp body
	if head_look_at_modifier:
		head_look_at_modifier.active = not on # it applies after the physical bones, and would hold a limp head up
	if physical_bone_simulator:
		if not on:
			physical_bone_simulator.physical_bones_stop_simulation()
		# The scene ships the bones on no layer, so they collide only while the ragdoll simulates
		for bone: Node in physical_bone_simulator.find_children("*", "PhysicalBone3D", true, false):
			(bone as PhysicalBone3D).set_collision_layer_value(1, on)
			(bone as PhysicalBone3D).set_collision_mask_value(1, on)
		if on:
			physical_bone_simulator.physical_bones_start_simulation()
	if collision_shape:
		collision_shape.disabled = on


## Wired to Health.died: the body drops into the ragdoll and the RespawnTimer brings the Player back.
func _on_health_died() -> void:
	if not is_multiplayer_authority():
		return
	# Death always drops the body, even where falls are set not to ragdoll, and behind a menu or the chat too
	# (NodeStateMachine.travel holds only a living Player's ragdoll back while paused or typing)
	_ragdoll_was_enabled = enable_ragdoll
	enable_ragdoll = true
	state_machine.travel(current_state, NodeStateMachine.States.RAGDOLLING)
	respawn_timer.start()


## Back on your feet at the last checkpoint (the spawn point until one is taken) with full health.
func respawn() -> void:
	hunters.clear()
	health.regen_paused = false
	health.health = health.max_health
	state_machine.travel(current_state, NodeStateMachine.States.STANDING)
	enable_ragdoll = _ragdoll_was_enabled
	warp_to(respawn_transform)
	respawned.emit()


## Every state watches for the Sprint press so a tap can be told from a hold; see [method try_dodge].
func _input(event: InputEvent) -> void:
	if dodge_enabled and event.is_action_pressed(&"sprint") and not event.is_echo():
		_sprint_pressed_msec = Time.get_ticks_msec()
		_sprint_press_motion = smoothed_motion.length()


## A Sprint release: when [member dodge_enabled], the press was a tap ([member dodge_tap_seconds]), the Player
## is on the ground and can afford it, this rolls ([constant NodeStateMachine.States.DODGING]) from [param from_state]
## and returns true; the grounded states call it on the release and stop there when it took. The roll is the
## sprinting dive ([member dodge_from_run]) when the Player was already at a run when Sprint went down, or lets a
## held sprint go and taps again within half a second; otherwise the standing dive.
func try_dodge(from_state: NodeStateMachine.States) -> bool:
	if not dodge_enabled or _sprint_pressed_msec < 0 or is_paused or is_typing:
		return false
	var now: int = Time.get_ticks_msec()
	var held: float = (now - _sprint_pressed_msec) / 1000.0
	_sprint_pressed_msec = -1
	if held > dodge_tap_seconds:
		_sprint_hold_ended_msec = now
		return false
	if not is_on_floor() or is_exhausted or is_riding or is_swimming or is_climbing:
		return false
	if not stamina.spend(dodge_stamina_cost):
		return false
	dodge_from_run = _sprint_press_motion > 1.2 or (_sprint_hold_ended_msec >= 0 and now - _sprint_hold_ended_msec < 500)
	dive_from_air = false
	state_machine.travel(from_state, NodeStateMachine.States.DODGING)
	return true


## Wired to Inventory.item_used: a [FoodItem] eaten, [param count] of it, restores its health, mana, hunger and
## thirst, on the Player's own peer (the Inventory is the owner's). Anything else is some other listener's business.
func _on_inventory_item_used(item: Item, count: int) -> void:
	if not item is FoodItem or not is_multiplayer_authority():
		return
	var food: FoodItem = item as FoodItem
	if food.health > 0.0:
		heal(food.health * count)
	if food.mana > 0.0 and health.max_energy > 0.0:
		health.energy += food.mana * count
	var vitals: Vitals = get_vitals()
	if vitals:
		if food.hunger > 0.0:
			vitals.eat(food.hunger * count)
		if food.thirst > 0.0:
			vitals.drink(food.thirst * count)


## The Player's [Vitals] (hunger and thirst), a child a survival game adds; null without one.
func get_vitals() -> Vitals:
	for child: Node in get_children():
		if child is Vitals:
			return child as Vitals
	return null


## Whether this Player draws a thunderstorm's lightning: holding metal ([member Equipment.is_metal]) in hand, as in
## Breath of the Wild. A weather addon's lightning asks every node in the "LightningAttractor" group; WeatherFX sparks
## the metal for a few seconds, then strikes it.
func attracts_lightning() -> bool:
	if inventory == null or not health.is_alive():
		return false
	for item: Equipment in inventory.equipment:
		if is_instance_valid(item) and item.is_metal and item.is_visible_in_tree():
			return true
	return false


## The shield on the arm to guard with: a sword-and-shield piece for the left arm, in hand; null without one.
func get_guard_shield() -> Equipment:
	if inventory == null:
		return null
	for item: Equipment in inventory.equipment:
		if is_instance_valid(item) and item.equipment_type == Equipment.EquipmentType.SWORD_AND_SHIELD \
				and item.bone_attachment_bone_name.contains("Left"):
			return item
	return null


## This Player's swing was parried by the Player at [param by_path] (from this node): thrown back from them, on this
## Player's own peer, as a knock-back from them.
func parried(by_path: NodePath) -> void:
	var by: Node3D = get_node_or_null(by_path) as Node3D
	if by:
		knock_back(by.global_position, parry_recoil, get_path_to(by))


## Raises the shield on the upper body or lowers it, on every peer ([member is_guarding]'s setter); a carried body keeps
## the carrying pose instead.
func _show_guard(on: bool) -> void:
	if animation_tree == null or (held_object and held_object.is_holding_object()):
		return
	var emote_state: AnimationNodeStateMachinePlayback = animation_tree.get(EMOTE_STATE_PLAYBACK_PATH)
	if emote_state == null:
		return
	if on:
		emote_spine_blend = 1.0
		emote_state.start(GUARD_EMOTE)
	elif emote_state.get_current_node() == GUARD_EMOTE:
		emote_state.start("Idle")
		emote_spine_blend = 0.0


## The shield a ride would be on: the sword-and-shield piece for the left arm, in hand or stowed (Link surfs on the
## shield off his back as readily as the one on his arm), or any sword-and-shield piece; null without one.
func get_surf_shield() -> Equipment:
	if is_shield_surfing and is_instance_valid(_surf_shield):
		return _surf_shield # under the feet, out of the backpack's reach
	if inventory == null:
		return null
	var found: Equipment = null
	for item: Equipment in inventory.get_all_weapons():
		if is_instance_valid(item) and item.equipment_type == Equipment.EquipmentType.SWORD_AND_SHIELD:
			if item.bone_attachment_bone_name.contains("Left"):
				return item
			found = item
	return found


## Shield surfing's way in, as in Breath of the Wild: Focus (ZL) held in the air and Action (A) pressed. The air
## states and the glider call it on Action; with [member enable_shield_surfing] and a shield ([method get_surf_shield])
## the Player drops onto it ([Surfing]). Returns true when it took.
func try_shield_surf(from_state: NodeStateMachine.States) -> bool:
	if not enable_shield_surfing or is_on_floor() or is_paused or is_typing or is_riding or is_swimming or is_climbing 			or is_flying or is_shield_surfing or not is_focusing or get_surf_shield() == null:
		return false
	state_machine.travel(from_state, NodeStateMachine.States.SURFING)
	return is_shield_surfing


## Turns the body and the shield under it [member surf_spin] round the model's up, from where they rest.
func _apply_surf_spin() -> void:
	for path: String in ["PlayerModel/Armature", "PlayerModel/ShieldSurfMount"]:
		var node: Node3D = get_node_or_null(path) as Node3D
		if node == null:
			continue
		if not _spin_rests.has(node):
			_spin_rests[node] = node.transform
		var lift: Vector3 = Vector3(0.0, _surf_mount_lift, 0.0) if path.ends_with("ShieldSurfMount") else Vector3.ZERO
		node.transform = Transform3D(Basis(Vector3.UP, surf_spin), lift) * (_spin_rests[node] as Transform3D)


## Keeps the shield under the feet through a hop. The mount rests at the model's origin, and the jump clip lifts the
## legs, so the shield stayed on the ground while the rider rose off it: as the skeleton updates (wired in the scene)
## the mount rides as far above its rest as the lower foot is above where it stands in the stance. Never below it.
func _follow_feet_with_surf_shield() -> void:
	if not is_shield_surfing or skeleton == null or player_model == null:
		return
	var lowest: float = INF
	for bone: StringName in [&"LeftFoot", &"RightFoot"]:
		var index: int = skeleton.find_bone(bone)
		if index >= 0:
			var in_model: Vector3 = player_model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(index).origin)
			lowest = minf(lowest, in_model.y)
	if lowest == INF:
		return
	if _surf_feet_rest == INF:
		if not is_on_floor() or current_locomotion_node != "SkateboardingLocomotion":
			return # the stance on the ground is what the feet rest at; a ride starts in the air
		_surf_feet_rest = lowest
	var lift: float = maxf(lowest - _surf_feet_rest, 0.0)
	if not is_equal_approx(lift, _surf_mount_lift):
		_surf_mount_lift = lift
		_apply_surf_spin()


## Puts the shield under the feet for a ride, at the model's ShieldSurfMount, or back on its arm after one. Runs on
## every peer from [member is_shield_surfing]'s setter.
func _place_surf_shield(on: bool) -> void:
	var mount: Node3D = get_node_or_null("PlayerModel/ShieldSurfMount") as Node3D
	_surf_feet_rest = INF
	if _surf_mount_lift != 0.0:
		_surf_mount_lift = 0.0
		_apply_surf_spin()
	if on:
		var shield: Equipment = get_surf_shield()
		if shield == null or mount == null:
			return
		_surf_shield = shield
		_surf_shield_home = shield.get_parent()
		_surf_shield_transform = shield.transform
		shield.reparent(mount, false)
		shield.transform = Transform3D(Basis.from_scale(_surf_shield_transform.basis.get_scale()), Vector3.ZERO) # the mount lays it flat
	elif mount != null:
		for child: Node in mount.get_children():
			if child is Equipment:
				if is_instance_valid(_surf_shield_home):
					child.reparent(_surf_shield_home, false)
					(child as Node3D).transform = _surf_shield_transform
				else:
					child.queue_free() # its arm is gone (the Player was re-equipped meanwhile)
		_surf_shield = null
		_surf_shield_home = null


## Hurts the Player for landing at [param speed] (m/s, downward), on its own peer: nothing below
## [member safe_fall_speed], rising to the whole of the health at [member lethal_fall_speed], as a fall in Breath of the
## Wild hurts and then kills. Water breaks any fall. The landing states call it as they touch down.
func take_fall(speed: float) -> void:
	_screamed = false
	if not is_multiplayer_authority() or is_swimming or speed < safe_fall_speed or not health.is_alive():
		return
	var share: float = clampf((speed - safe_fall_speed) / maxf(lethal_fall_speed - safe_fall_speed, 0.01), 0.0, 1.0)
	health.damage(health.max_health * share, global_position)
	controls.rumble(0.8, 1.0, 0.3)


## A fall that has passed [member lethal_fall_speed] is going to end badly: the Player screams, once, on every peer, while
## there is still time to hear it (The Wilhelm Scream, in [code]SFX_FallScream[/code]). The air states call it every
## step with how fast the Player is coming down.
func scream_if_doomed(fall_speed: float) -> void:
	if _screamed or fall_speed < lethal_fall_speed or not is_multiplayer_authority() or is_paragliding:
		return
	_screamed = true
	_fall_scream.rpc()


@rpc("authority", "call_local", "unreliable")
func _fall_scream() -> void:
	if sfx_fall_scream and sfx_fall_scream.stream:
		sfx_fall_scream.play()


## A dive from the air, Odyssey's move: the air states call it on Sprint, or Throw with Crouch held, while off the
## ground, and with [member dodge_enabled] and the stamina for it the Player dives forward ([member dive_from_air],
## the Falling To Dive Forward clip) and rolls out of the landing. Returns true when it took.
func try_air_dive(from_state: NodeStateMachine.States) -> bool:
	if not dodge_enabled or is_on_floor() or is_paused or is_typing or is_exhausted or is_riding or is_swimming \
			or is_climbing or is_paragliding or is_flying or is_dodging:
		return false
	if not stamina.spend(dodge_stamina_cost):
		return false
	_sprint_pressed_msec = -1
	dive_from_air = true
	dodge_from_run = false
	state_machine.travel(from_state, NodeStateMachine.States.DODGING)
	return true


## Makes [param transform] where the Player comes back after dying; a [Checkpoint] calls it as it is taken.
func set_checkpoint(transform: Transform3D) -> void:
	if transform.is_equal_approx(respawn_transform):
		return
	respawn_transform = transform
	checkpoint_changed.emit(transform)


## What a [SaveGame] keeps of the Player: where they are and respawn, their pools, the whole inventory and the quests.
func save_state() -> Dictionary:
	var state: Dictionary = {
		"transform": global_transform,
		"facing": player_model.global_basis, # the body keeps its up; which way the model faces is the model's own
		"camera_rotation": camera_mount.rotation,
		"respawn_transform": respawn_transform,
		"health": health.health,
		"energy": health.energy,
		"stamina": stamina.stamina,
	}
	if inventory:
		state["inventory"] = inventory.make_save()
	if quest_log:
		state["quests"] = quest_log.save_state()
	return state


## Puts a [method save_state] back. A Player mid-ride gets off first; one saved dead (a write that landed during
## the respawn wait) comes back with full health rather than dead on the spot.
func load_state(state: Dictionary) -> void:
	if state.has("respawn_transform"):
		respawn_transform = state["respawn_transform"]
		checkpoint_changed.emit(respawn_transform)
	if is_riding:
		dismount(true)
	if state.has("transform"):
		warp_to(state["transform"])
	if state.get("facing") is Basis:
		orientation.basis = state["facing"]
		player_model.global_basis = state["facing"]
	if state.get("camera_rotation") is Vector3:
		camera_mount.rotation = state["camera_rotation"]
	var saved_health: float = float(state.get("health", health.max_health))
	health.health = saved_health if saved_health > 0.0 else health.max_health
	health.energy = float(state.get("energy", health.max_energy))
	stamina.stamina = float(state.get("stamina", stamina.max_value))
	if inventory and state.get("inventory") is InventorySave:
		inventory.apply_save(state["inventory"] as InventorySave)
	if quest_log and state.get("quests") is Dictionary:
		quest_log.load_state(state["quests"])
