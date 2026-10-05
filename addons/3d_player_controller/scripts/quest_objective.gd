class_name QuestObjective
extends Resource
## One thing a [Quest] asks for, counted up by [method QuestLog.progress] under its [member id].

@export var id: StringName = &"" ## What the game reports progress against: "chop_tree", "talk_guide".
@export var description: String = "" ## What the tracker and the quest screen show: "Chop down a tree".
@export_range(1, 9999) var required: int = 1 ## How many times [member id] has to be reported before it is done.
