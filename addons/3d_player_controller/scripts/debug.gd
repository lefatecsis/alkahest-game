class_name Debug
extends CanvasLayer
## Debug HUD: mirrors the [Player] flags at 10 Hz (RefreshTimer in the scene) while visible.

@export var player: Player

var _mouse_mode_before: int = -1 ## The mouse mode the HUD found on opening, put back on closing; -1 when it changed nothing.

@onready var refresh_timer: Timer = $RefreshTimer
@onready var navigation_marker: MeshInstance3D = $NavigationMarker ## Green sphere marking the click-to-move target.
@onready var fps: Label = $FPS
@onready var current_perspective: Label = $CurrentPerspective
@onready var current_state: Label = $CurrentState
@onready var enable_flying: CheckButton = $Enable/EnableFlying
@onready var enable_paraglider: CheckButton = $Enable/EnableParaglider
@onready var enable_ragdoll: CheckButton = $Enable/EnableRagdoll
@onready var enable_stamina: CheckButton = $Enable/EnableStamina
@onready var is_attacking: CheckBox = $States/is_attacking
@onready var is_climbing: CheckBox = $States/is_climbing
@onready var is_crouching: CheckBox = $States/is_crouching
@onready var is_riding: CheckBox = $States/is_riding
@onready var is_emoting: CheckBox = $States/is_emoting
@onready var is_hanging: CheckBox = $States/is_hanging
@onready var is_falling: CheckBox = $States/is_falling
@onready var is_flying: CheckBox = $States/is_flying
@onready var is_focusing: CheckBox = $States/is_focusing
@onready var is_jumping: CheckBox = $States/is_jumping
@onready var is_paragliding: CheckBox = $States/is_paragliding
@onready var is_paused: CheckBox = $States/is_paused
@onready var is_ragdolling: CheckBox = $States/is_ragdolling
@onready var is_shooting: CheckBox = $States/is_shooting
@onready var is_sitting: CheckBox = $States/is_sitting
@onready var is_sliding: CheckBox = $States/is_sliding
@onready var is_sprinting: CheckBox = $States/is_sprinting
@onready var is_standing: CheckBox = $States/is_standing
@onready var is_swimming: CheckBox = $States/is_swimming
@onready var equipped_axe_1h: CheckBox = $Equipment/equipped_axe_1h
@onready var equipped_axe_2h: CheckBox = $Equipment/equipped_axe_2h
@onready var equipped_bow: CheckBox = $Equipment/equipped_bow
@onready var equipped_dagger: CheckBox = $Equipment/equipped_dagger
@onready var equipped_pistol: CheckBox = $Equipment/equipped_pistol
@onready var equipped_rifle: CheckBox = $Equipment/equipped_rifle
@onready var equipped_shield: CheckBox = $Equipment/equipped_shield
@onready var equipped_staff: CheckBox = $Equipment/equipped_staff
@onready var equipped_sword_1h: CheckBox = $Equipment/equipped_sword_1h
@onready var equipped_sword_2h: CheckBox = $Equipment/equipped_sword_2h
@onready var bow: VBoxContainer = $Bow
@onready var is_aiming_bow: CheckBox = $Bow/is_aiming_bow
@onready var is_drawing_arrow: CheckBox = $Bow/is_drawing_arrow
@onready var is_firing_arrow: CheckBox = $Bow/is_firing_arrow
@onready var attacking: VBoxContainer = $Attacking
@onready var is_attacking_1: CheckBox = $Attacking/is_attacking_1
@onready var is_attacking_2: CheckBox = $Attacking/is_attacking_2
@onready var is_attacking_3: CheckBox = $Attacking/is_attacking_3
@onready var climbing: VBoxContainer = $Climbing
@onready var is_climbing_on: CheckBox = $Climbing/is_climbing_on
@onready var is_climbing_hopping_left: CheckBox = $Climbing/is_climbing_hopping_left
@onready var is_climbing_hopping_right: CheckBox = $Climbing/is_climbing_hopping_right
@onready var is_climbing_hopping_up: CheckBox = $Climbing/is_climbing_hopping_up
@onready var is_hopping_from_climbing: CheckBox = $Climbing/is_hopping_from_climbing
@onready var driving: VBoxContainer = $Driving
@onready var is_entering_vehicle: CheckBox = $Driving/is_entering_vehicle
@onready var is_exiting_vehicle: CheckBox = $Driving/is_exiting_vehicle
@onready var hanging: VBoxContainer = $Hanging
@onready var hanging_is_climbing_on: CheckBox = $Hanging/is_climbing_on
@onready var is_hanging_braced: CheckBox = $Hanging/is_hanging_braced
@onready var is_hanging_free: CheckBox = $Hanging/is_hanging_free


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process_input(is_multiplayer_authority())
	if player:
		player.navigating_changed.connect(_on_player_navigating_changed)


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug"):
		visible = not visible


## Starts the refresh timer while shown; hides the marker and stops refreshing while hidden.
func _on_visibility_changed() -> void:
	if not is_node_ready(): # Fires while the parent scene sets `visible` during instantiation
		return
	if visible:
		_on_refresh_timer_timeout()
		refresh_timer.start()
		# The toggles want a pointer; a captured mouse is let go for as long as the HUD is up
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_mouse_mode_before = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		refresh_timer.stop()
		navigation_marker.hide()
		if _mouse_mode_before >= 0:
			Input.mouse_mode = _mouse_mode_before as Input.MouseMode
			_mouse_mode_before = -1


## Copies the player's flags into the HUD controls.
func _on_refresh_timer_timeout() -> void:
	if player == null:
		return
	fps.text = str(Engine.get_frames_per_second())
	current_perspective.text = "First-person" if player.camera.perspective == Camera.Perspective.FIRST_PERSON else "Third-person"
	current_state.text = NodeStateMachine.get_state_name(player.current_state)

	enable_flying.button_pressed = player.enable_flying
	enable_paraglider.button_pressed = player.enable_paraglider
	enable_ragdoll.button_pressed = player.enable_ragdoll
	enable_stamina.button_pressed = player.enable_stamina

	is_attacking.button_pressed = player.is_attacking
	is_climbing.button_pressed = player.is_climbing
	is_crouching.button_pressed = player.is_crouching
	is_riding.button_pressed = player.is_riding
	is_emoting.button_pressed = player.is_emoting
	is_hanging.button_pressed = player.is_hanging_braced or player.is_hanging_free
	is_falling.button_pressed = player.is_falling
	is_flying.button_pressed = player.is_flying
	is_focusing.button_pressed = player.is_focusing
	is_jumping.button_pressed = player.is_jump_queued or player.is_jumping
	is_paragliding.button_pressed = player.is_paragliding
	is_paused.button_pressed = player.is_paused
	is_ragdolling.button_pressed = player.is_ragdolling
	is_shooting.button_pressed = player.is_shooting
	is_sitting.button_pressed = player.is_sitting
	is_sliding.button_pressed = player.is_sliding
	is_sprinting.button_pressed = player.is_sprinting
	is_standing.button_pressed = player.is_standing
	is_swimming.button_pressed = player.is_swimming

	equipped_axe_1h.button_pressed = player.equipped_axe_1h
	equipped_axe_2h.button_pressed = player.equipped_axe_2h
	equipped_bow.button_pressed = player.equipped_bow
	equipped_dagger.button_pressed = player.equipped_dagger
	equipped_pistol.button_pressed = player.equipped_pistol
	equipped_rifle.button_pressed = player.equipped_rifle
	equipped_shield.button_pressed = player.equipped_shield
	equipped_staff.button_pressed = player.equipped_staff
	equipped_sword_1h.button_pressed = player.equipped_sword_1h
	equipped_sword_2h.button_pressed = player.equipped_sword_2h

	bow.visible = player.equipped_bow
	is_aiming_bow.button_pressed = player.is_aiming_bow
	is_drawing_arrow.button_pressed = player.is_drawing_arrow
	is_firing_arrow.button_pressed = player.is_firing_arrow

	attacking.visible = player.inventory.can_player_attack and (player.is_attacking_1 or player.is_attacking_2 or player.is_attacking_3)
	is_attacking_1.button_pressed = player.is_attacking_1
	is_attacking_2.button_pressed = player.is_attacking_2
	is_attacking_3.button_pressed = player.is_attacking_3

	climbing.visible = player.is_climbing
	is_climbing_on.button_pressed = player.is_climbing_on
	is_climbing_hopping_left.button_pressed = player.is_climbing_hopping_left
	is_climbing_hopping_right.button_pressed = player.is_climbing_hopping_right
	is_climbing_hopping_up.button_pressed = player.is_climbing_hopping_up
	is_hopping_from_climbing.button_pressed = player.is_hopping_from_climbing

	driving.visible = player.is_riding
	is_entering_vehicle.button_pressed = player.is_mounting
	is_exiting_vehicle.button_pressed = player.is_dismounting

	hanging.visible = player.is_hanging_braced or player.is_hanging_free
	hanging_is_climbing_on.button_pressed = player.is_climbing_on
	is_hanging_braced.button_pressed = player.is_hanging_braced
	is_hanging_free.button_pressed = player.is_hanging_free


## Moves the marker sphere to the click-to-move target and shows it.
func draw_navigation_marker(marker_position: Vector3) -> void:
	navigation_marker.global_position = marker_position
	navigation_marker.show()


func _on_player_navigating_changed(is_navigating: bool) -> void:
	if not is_navigating:
		navigation_marker.hide()


func _on_enable_flying_pressed() -> void:
	player.enable_flying = not player.enable_flying


func _on_enable_paraglider_pressed() -> void:
	player.enable_paraglider = not player.enable_paraglider


func _on_enable_ragdoll_pressed() -> void:
	player.enable_ragdoll = not player.enable_ragdoll


func _on_enable_stamina_pressed() -> void:
	player.enable_stamina = not player.enable_stamina
