class_name Sitting
extends NodeStateMachine

@export_category("Sitting Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_stand_action: StringName = &"jump"

@export_group("Controller/Touch Actions")
@export var pad_stand_action: StringName = &"jump"


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Stand up
	if event.is_action_pressed(action(keyboard_stand_action, pad_stand_action)):
		player.state_machine.travel(state, States.STANDING)


## Start "sitting".
func start() -> void:
	super.start()
	# Flag the player as "sitting"
	player.is_sitting = true


## Stop "sitting".
func stop() -> void:
	super.stop()
	# Flag the player as not "sitting"
	player.is_sitting = false


func get_contextual_controls(_input_type: int) -> Dictionary:
	return {
		player.controls.action_label(&"jump", player.controls.joypad_button_3_label): "Stand Up",
		player.controls.right_joystick_label: "Camera",
	}
