class_name Quest
extends Resource
## A quest: a title, a description, the [QuestObjective]s that finish it and what the Player gets for it.
## Start it with [method QuestLog.start] (a conversation, a trigger, a pickup), report progress with
## [method QuestLog.progress], and the log completes it and hands out [member rewards] once every objective is met.

@export var id: StringName = &"" ## Stable name the log and saves key it by; the file name when empty.
@export var title: String = ""
@export_multiline var description: String = ""
@export var objectives: Array[QuestObjective] = []
@export var rewards: Dictionary[Item, int] = {} ## Items put in the inventory on completion, by count.
@export var tracked_on_start: bool = true ## Starting it puts it on the HUD tracker.


## [member id], or the file name for a quest saved without one.
func get_id() -> StringName:
	if not id.is_empty():
		return id
	return StringName(resource_path.get_file().get_basename())


## The objective with [param objective_id], or null.
func find_objective(objective_id: StringName) -> QuestObjective:
	for objective: QuestObjective in objectives:
		if objective.id == objective_id:
			return objective
	return null
