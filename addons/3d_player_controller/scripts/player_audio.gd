class_name Audio
extends Node3D

const BUSES: Array[StringName] = [&"Dialog", &"Menu", &"Music", &"SFX", &"Voice"] ## Buses the settings menus adjust; created at runtime when the project's bus layout lacks them.

@export var player: Player

@onready var sfx_footsteps_grass: AudioStreamPlayer3D = $SFX_Footsteps_Grass
@onready var sfx_footsteps_slide: AudioStreamPlayer3D = $SFX_Footsteps_Slide
@onready var sfx_footsteps_stone: AudioStreamPlayer3D = $SFX_Footsteps_Stone
@onready var sfx_footsteps_water: AudioStreamPlayer3D = $SFX_Footsteps_Water
@onready var sfx_footsteps_wood: AudioStreamPlayer3D = $SFX_Footsteps_Wood
@onready var sfx_footsteps_surface: AudioStreamPlayer3D = get_node_or_null("SFX_Footsteps_Surface") as AudioStreamPlayer3D ## Plays [member Player.footstep_override].


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process_input(is_multiplayer_authority())
	for bus_name: StringName in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


## Play surface-aware footstep audio based on collider groups.
func play_footstep(collider: Node3D = null) -> void:
	if not collider and player and player.paraglider_raycast and player.paraglider_raycast.is_colliding():
		collider = player.paraglider_raycast.get_collider() as Node3D

	# A surface that lends its own steps (snow) sounds instead of the ground under it
	if player and player.footstep_override and sfx_footsteps_surface:
		if sfx_footsteps_surface.stream != player.footstep_override:
			sfx_footsteps_surface.stream = player.footstep_override
		sfx_footsteps_surface.play()
		return

	if collider and (collider.is_in_group("DIRT") or collider.is_in_group("GRASS")):
		sfx_footsteps_grass.play()
	elif collider and collider.is_in_group("WOOD"):
		sfx_footsteps_wood.play()
	elif collider and collider.is_in_group("WATER"):
		sfx_footsteps_water.play()
	else:
		sfx_footsteps_stone.play()


## Play slide footstep sound.
func play_slide(_collider: Node3D = null) -> void:
	sfx_footsteps_slide.play()


## Update volume on all footstep AudioStreamPlayer3D nodes and on "vehicles" group members that expose set_sfx_volume.
func set_sfx_volume(value: float) -> void:
	var db: float = linear_to_db(value / 100.0) if value > 0.0 else -80.0
	for child: Node in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).volume_db = db
	if not is_inside_tree():
		return
	for vehicle: Node in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.has_method("set_sfx_volume"):
			vehicle.set_sfx_volume(value)


## Update volume on every "radio" group member that exposes set_volume(linear) (e.g. RadiOtPlayer3D).
func set_music_volume(value: float) -> void:
	if not is_inside_tree():
		return
	var linear: float = clampf(value / 100.0, 0.0, 1.0)
	for radio: Node in get_tree().get_nodes_in_group("radio"):
		if radio.has_method("set_volume"):
			radio.set_volume(linear)
