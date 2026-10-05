@tool
class_name AbilityEntry
extends Node3D
## One ability in an [AbilityLibrary]: a node carrying the [Ability] resource, so the library's contents are nodes a
## project can see and add to in the editor (instance the library scene, make its children editable, add an entry).
## In the editor it takes the ability's name when it still has a default one, and the inspector shows the resource.

@export var ability: Ability: ## The ability this entry puts in the library; its [method Ability.get_id] is its name there.
	set(value):
		ability = value
		if Engine.is_editor_hint() and ability and (String(name).begins_with("AbilityEntry") or String(name).begins_with("Node3D")):
			name = _entry_name(ability)


func _get_configuration_warnings() -> PackedStringArray:
	if ability == null:
		return ["No ability set: this entry puts nothing in the library."]
	return []


## The node name for [param of]: its display name in PascalCase, or its id.
static func _entry_name(of: Ability) -> String:
	var base: String = of.display_name if not of.display_name.is_empty() else String(of.get_id())
	return base.to_pascal_case().validate_node_name()
