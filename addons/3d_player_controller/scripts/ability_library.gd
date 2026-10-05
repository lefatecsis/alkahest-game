@tool
class_name AbilityLibrary
extends Node3D
## Every ability a game has, loaded once and kept warm, so any Player, puppet or NPC can cast any of them without
## the hitch of a first use. Each child [AbilityEntry] names one [Ability]; a project instances
## [code]scenes/ability_library.tscn[/code] in its world, marks it editable and adds entries for its own spells.
## At ready every phase VFX is instanced once for a frame, which is what compiles its shaders and particles, then
## freed. Casters find the library through [method find] and take their abilities from it by id
## ([method Ability.get_id]), so all of them share the one loaded copy; without a library they use their own.

signal warmed ## Every VFX has been instanced once and freed again.

const GROUP: StringName = &"AbilityLibrary"

@export var warm_on_ready: bool = true ## Instance every phase VFX once at ready, for a frame, so its shaders compile before a cast needs them.

var is_warm: bool = false ## [signal warmed] has fired.
var _by_id: Dictionary[StringName, Ability] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	_collect()
	if warm_on_ready:
		warm()


## The library in [param node]'s tree, or null when the scene has none.
static func find(node: Node) -> AbilityLibrary:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as AbilityLibrary


## The ability called [param id], or null when the library has no such entry.
func get_ability(id: StringName) -> Ability:
	return _by_id.get(id)


func has_ability(id: StringName) -> bool:
	return _by_id.has(id)


## Every ability an entry names, in the children's order.
func get_abilities() -> Array[Ability]:
	var out: Array[Ability] = []
	for child: Node in get_children():
		if child is AbilityEntry and (child as AbilityEntry).ability:
			out.append((child as AbilityEntry).ability)
	return out


## The library's copy of [param ability] by id, or [param ability] itself when the library has no entry for it.
func resolve(ability: Ability) -> Ability:
	if ability == null:
		return null
	var known: Ability = _by_id.get(ability.get_id())
	return known if known else ability


## Instances every phase VFX of every ability once, hidden under this node for a frame, then frees them. Shaders
## and particles compile on that first instance, so a later cast pays nothing.
func warm() -> void:
	var instances: Array[Node] = []
	for ability: Ability in get_abilities():
		for phase: Ability.Phase in [Ability.Phase.CHANNELING, Ability.Phase.CASTING, Ability.Phase.IMPACT]:
			var scene: PackedScene = ability.get_vfx(phase)
			if scene == null:
				continue
			var vfx: Node = scene.instantiate()
			add_child(vfx)
			instances.append(vfx)
	if is_inside_tree():
		await get_tree().process_frame
	for vfx: Node in instances:
		if is_instance_valid(vfx):
			vfx.queue_free()
	is_warm = true
	warmed.emit()


func _collect() -> void:
	_by_id.clear()
	for child: Node in get_children():
		var entry: AbilityEntry = child as AbilityEntry
		if entry == null or entry.ability == null:
			continue
		var id: StringName = entry.ability.get_id()
		if _by_id.has(id):
			push_warning("AbilityLibrary: two entries are called %s; %s keeps the first" % [id, name])
			continue
		_by_id[id] = entry.ability
