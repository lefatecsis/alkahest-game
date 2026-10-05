class_name StealthLook
extends Node
## How a stealthed [Player] looks. While [member Player.is_stealthed] is on, every mesh under [member skeleton]
## (equipment included) turns into its ghost, two passes over each surface: one that writes the body's depth and
## draws nothing, then the stealth shader carrying the surface's own colour and texture, washed pale, which colours
## only the nearest surface, so limbs never show through the body. Its alpha tweens over [member fade_time] each
## way; the original materials return once the fade out lands. The flag replicates and its setter calls
## [method apply] on every peer, so puppets fade too.

const STEALTH_SHADER: Shader = preload("res://addons/3d_player_controller/assets/shaders/stealth.gdshader")
const STEALTH_DEPTH_SHADER: Shader = preload("res://addons/3d_player_controller/assets/shaders/stealth_depth.gdshader")

@export var player: Player ## Whose stealth this draws.
@export var skeleton: Skeleton3D ## Every mesh under it fades.
@export var transparency: float = 0.7 ## How faded the model is while stealthed: 1 is invisible.
@export var fade_time: float = 1.0 ## Seconds the ghost takes to settle in when stealth starts, and to solidify when it ends.

var _originals: Dictionary[MeshInstance3D, Array] = {} ## Mesh -> its surface override materials before stealth, restored when it ends.
var _tween: Tween


## Spawn state lands before the skeleton exists, so a late joiner's copy of a stealthed Player fades here.
func _ready() -> void:
	if player and player.is_stealthed:
		apply(true)


## Turns every mesh under the skeleton into its ghost, or back.
func apply(stealthed: bool) -> void:
	if skeleton == null:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if stealthed:
		# owned = false: equipment is attached at runtime and has no owner, and it has to fade with the body
		for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or _originals.has(mesh):
				continue
			var originals: Array[Material] = []
			for surface: int in mesh.mesh.get_surface_count():
				originals.append(mesh.get_surface_override_material(surface))
				mesh.set_surface_override_material(surface, _ghost_of(mesh.get_active_material(surface)))
			_originals[mesh] = originals
	var target_alpha: float = 1.0 - transparency if stealthed else 1.0
	for ghost: ShaderMaterial in _ghosts():
		# A method, not the shader_parameter property: it exists only once the shader is compiled, which a headless run never does
		_tween.tween_method(_set_ghost_alpha.bind(ghost), float(ghost.get_shader_parameter(&"alpha")), target_alpha, fade_time)
	if not stealthed:
		_tween.chain().tween_callback(_restore_materials)


## Wired to Inventory.equipment_changed in player.tscn: a piece equipped while stealthed fades too. The ghost pass
## only touches meshes it has not seen, so this is cheap when nothing new is there.
func _on_equipment_changed() -> void:
	if player and player.is_stealthed:
		apply(true)


## The ghost of [param original]: a depth pass that draws nothing, with the stealth shader wearing the original's
## colours as its next_pass, drawn after it. Anything but a StandardMaterial3D ghosts as plain white.
func _ghost_of(original: Material) -> ShaderMaterial:
	var depth: ShaderMaterial = ShaderMaterial.new()
	depth.shader = STEALTH_DEPTH_SHADER
	depth.render_priority = 0
	var ghost: ShaderMaterial = ShaderMaterial.new()
	ghost.shader = STEALTH_SHADER
	ghost.render_priority = 1 # After the depth pass, so it only finds the nearest surface to colour
	ghost.set_shader_parameter(&"alpha", 1.0)
	depth.next_pass = ghost
	if original is StandardMaterial3D:
		var standard: StandardMaterial3D = original as StandardMaterial3D
		ghost.set_shader_parameter(&"albedo_color", standard.albedo_color)
		if standard.albedo_texture:
			ghost.set_shader_parameter(&"albedo_texture", standard.albedo_texture)
			ghost.set_shader_parameter(&"use_texture", true)
	return depth


func _set_ghost_alpha(alpha: float, ghost: ShaderMaterial) -> void:
	ghost.set_shader_parameter(&"alpha", alpha)


func _ghosts() -> Array[ShaderMaterial]:
	var ghosts: Array[ShaderMaterial] = []
	for mesh: MeshInstance3D in _originals:
		if not is_instance_valid(mesh):
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_surface_override_material(surface)
			if material is ShaderMaterial and (material as ShaderMaterial).shader == STEALTH_DEPTH_SHADER:
				ghosts.append(material.next_pass as ShaderMaterial) # The colour is on the pass after the depth
	return ghosts


func _restore_materials() -> void:
	for mesh: MeshInstance3D in _originals:
		if not is_instance_valid(mesh):
			continue
		var originals: Array = _originals[mesh]
		for surface: int in originals.size():
			mesh.set_surface_override_material(surface, originals[surface])
	_originals.clear()
