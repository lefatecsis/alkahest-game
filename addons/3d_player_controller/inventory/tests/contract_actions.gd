extends RefCounted
## The InputMap actions the inventory listens for. The player controller registers them at runtime, so a bare project has
## none: a contract test makes one of these, calls [method add_missing] in before_all and [method remove_added] in
## after_all, and the suite runs without depending on a Controls node having readied first. Only the actions this
## call added are erased, so a project that had them already (project.godot, or a Controls that readied first) is
## left as it was.

const ACTIONS: Array[StringName] = [
	&"action", &"start", &"ability", &"throw", &"last_weapon", &"next_weapon",
	&"look_up", &"look_down", &"look_left", &"look_right",
]

var _added: Array[StringName] = []


## Adds every action in [constant ACTIONS] the InputMap lacks. The tests press them as InputEventActions, so no
## key or button is bound.
func add_missing() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_added.append(action)


## Erases the actions [method add_missing] added, and no others.
func remove_added() -> void:
	for action: StringName in _added:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_added.clear()
