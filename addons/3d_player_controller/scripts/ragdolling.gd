class_name Ragdolling
extends NodeStateMachine

var _hips_physical_bone: PhysicalBone3D


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	# Do nothing if the player is not set or is paused/pause layer visible
	if not player or player.is_paused or player.is_typing or (player.pause and player.pause.visible): return

	# If the player is ragdolling, pressing the "action" button will stop "ragdolling"; the dead wait for the respawn
	if player.is_ragdolling and player.health.is_alive() and event.is_action_pressed(&"action"):
		player.state_machine.travel(state, States.STANDING)


## Called every physics frame.
func _physics_process(_delta: float) -> void:
	# Sync player global position to the hips physical bone position while ragdolling
	if player and player.is_ragdolling and is_instance_valid(_hips_physical_bone):
		player.global_position = _hips_physical_bone.global_position


## Start "ragdolling". The body itself drops in [member Player.is_ragdolling]'s setter, which every peer runs.
func start() -> void:
	super.start()
	if player.physical_bone_simulator:
		_hips_physical_bone = player.physical_bone_simulator.find_child("Physical Bone Hips", true, false) as PhysicalBone3D
	player.is_ragdolling = true


## Stop "ragdolling".
func stop() -> void:
	super.stop()
	# Sync position one last time to hips bone position, before the setter puts the model back at its rest transform
	if is_instance_valid(_hips_physical_bone):
		player.global_position = _hips_physical_bone.global_position
	player.is_ragdolling = false
	_hips_physical_bone = null
