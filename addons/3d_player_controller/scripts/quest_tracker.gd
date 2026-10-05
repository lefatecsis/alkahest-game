class_name QuestTracker
extends CanvasLayer
## The tracked quest and its objectives, top right of the screen; [QuestLog] drives it through [method show_quest]
## and [method hide_quest]. A layer of its own rather than part of the on-screen controls, which a desktop
## player keeps hidden: the objectives are for everyone.

@onready var title_label: Label = %QuestTitle
@onready var objectives_label: Label = %QuestObjectives


## Shows [param title] and its [param objectives], one per line.
func show_quest(title: String, objectives: String) -> void:
	title_label.text = title
	objectives_label.text = objectives
	show()


func hide_quest() -> void:
	hide()
