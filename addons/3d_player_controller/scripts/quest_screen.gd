class_name QuestScreen
extends PlayerMenuLayer
## The Quests page from the Pause menu: every quest the log knows on the left, active ones first, and the one
## under the cursor on the right with its description and objectives. Track puts an active quest on the HUD; Back
## returns to Pause. Every button takes focus, so a pad walks the list.

var focused_quest: Quest
var _quest_buttons: Array[Button] = []

@onready var quest_list: VBoxContainer = %QuestList
@onready var empty_label: Label = %Empty
@onready var detail_title: Label = %DetailTitle
@onready var detail_status: Label = %DetailStatus
@onready var detail_description: Label = %DetailDescription
@onready var detail_objectives: Label = %DetailObjectives
@onready var track_button: Button = %Track
@onready var back_button: Button = %Back


func show_menu() -> void:
	super()
	rebuild()


## Lists the log's quests again and shows the first.
func rebuild() -> void:
	for button: Button in _quest_buttons:
		button.queue_free()
	_quest_buttons.clear()
	var quest_log: QuestLog = player.quest_log if player else null
	var quests: Array[Quest] = quest_log.get_all() if quest_log else []
	empty_label.visible = quests.is_empty()
	for quest: Quest in quests:
		var button: Button = Button.new()
		button.text = quest.title if not quest.title.is_empty() else String(quest.get_id())
		if quest_log.is_complete(quest):
			button.text += " (done)"
		button.custom_minimum_size.y = 32.0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(_show_details.bind(quest))
		button.mouse_entered.connect(button.grab_focus)
		quest_list.add_child(button)
		_quest_buttons.append(button)
	if _quest_buttons.is_empty():
		_show_details(null)
		back_button.grab_focus()
	else:
		_quest_buttons[0].grab_focus()


func _show_details(quest: Quest) -> void:
	focused_quest = quest
	var quest_log: QuestLog = player.quest_log if player else null
	if quest == null or quest_log == null:
		detail_title.text = ""
		detail_status.text = ""
		detail_description.text = ""
		detail_objectives.text = ""
		track_button.visible = false
		return
	detail_title.text = quest.title
	detail_status.text = "Complete" if quest_log.is_complete(quest) else ("Tracked" if quest_log.tracked == quest else "Active")
	detail_description.text = quest.description
	detail_objectives.text = quest_log.describe_objectives(quest)
	track_button.visible = quest_log.is_active(quest) and quest_log.tracked != quest


func _on_track_pressed() -> void:
	if player and player.quest_log and focused_quest:
		player.quest_log.track(focused_quest)
		_show_details(focused_quest)


func _on_track_touch_screen_button_pressed() -> void:
	_on_track_pressed()


func _on_back_pressed() -> void:
	if player == null:
		return
	hide()
	player.pause.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()
