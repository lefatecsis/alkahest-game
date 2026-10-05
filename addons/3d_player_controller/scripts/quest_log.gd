class_name QuestLog
extends Node
## The Player's quests: which are active, how far each objective is, which are done. The game reports what
## happened ([method progress]), the log works out what that finishes, hands out rewards through the inventory,
## and keeps the HUD tracker ([QuestTracker]) on the tracked quest. It saves with the Player.

signal quest_started(quest: Quest)
signal objective_progressed(quest: Quest, objective: QuestObjective, count: int)
signal quest_completed(quest: Quest)
signal tracked_changed(quest: Quest) ## The quest on the HUD changed; null clears it.

enum Status { NOT_STARTED, ACTIVE, COMPLETE }

@export var player: Player

var tracked: Quest ## The quest on the HUD, if any.
var _entries: Dictionary[StringName, Dictionary] = {} ## Quest id to {"quest": Quest, "status": Status, "objectives": {id: count}}.


func _ready() -> void:
	if player == null and get_parent() is Player:
		player = get_parent() as Player


## Takes [param quest] on; false when it is already active or done.
func start(quest: Quest) -> bool:
	if quest == null or get_status(quest) != Status.NOT_STARTED:
		return false
	var counts: Dictionary = {}
	for objective: QuestObjective in quest.objectives:
		counts[objective.id] = 0
	_entries[quest.get_id()] = {"quest": quest, "status": Status.ACTIVE, "objectives": counts}
	quest_started.emit(quest)
	if quest.tracked_on_start or tracked == null:
		track(quest)
	return true


## Reports [param objective_id] happening [param amount] times to every active quest that asks for it; true when
## any of them counted it. A quest whose every objective is now met completes.
func progress(objective_id: StringName, amount: int = 1) -> bool:
	var counted: bool = false
	for id: StringName in _entries.keys():
		var entry: Dictionary = _entries[id]
		if entry["status"] != Status.ACTIVE:
			continue
		var quest: Quest = entry["quest"]
		var objective: QuestObjective = quest.find_objective(objective_id)
		if objective == null or entry["objectives"][objective_id] >= objective.required:
			continue
		entry["objectives"][objective_id] = mini(entry["objectives"][objective_id] + amount, objective.required)
		counted = true
		objective_progressed.emit(quest, objective, entry["objectives"][objective_id])
		if _all_met(quest, entry):
			_complete(quest, entry)
	if counted:
		_refresh_tracker()
	return counted


func get_status(quest: Quest) -> Status:
	if quest == null or not _entries.has(quest.get_id()):
		return Status.NOT_STARTED
	return _entries[quest.get_id()]["status"]


func is_active(quest: Quest) -> bool:
	return get_status(quest) == Status.ACTIVE


func is_complete(quest: Quest) -> bool:
	return get_status(quest) == Status.COMPLETE


## How far [param objective_id] of [param quest] is.
func get_count(quest: Quest, objective_id: StringName) -> int:
	if quest == null or not _entries.has(quest.get_id()):
		return 0
	return int(_entries[quest.get_id()]["objectives"].get(objective_id, 0))


## True when [param objective_id] of [param quest] has been met.
func is_objective_done(quest: Quest, objective_id: StringName) -> bool:
	var objective: QuestObjective = quest.find_objective(objective_id) if quest else null
	return objective != null and get_count(quest, objective_id) >= objective.required


func get_active() -> Array[Quest]:
	return _with_status(Status.ACTIVE)


func get_completed() -> Array[Quest]:
	return _with_status(Status.COMPLETE)


## Every quest the log knows, active first.
func get_all() -> Array[Quest]:
	var all: Array[Quest] = get_active()
	all.append_array(get_completed())
	return all


## Puts [param quest] on the HUD; null, or a quest that is not active, clears it.
func track(quest: Quest) -> void:
	tracked = quest if is_active(quest) else null
	tracked_changed.emit(tracked)
	_refresh_tracker()


## What the tracker shows for [param quest]: each objective with its count, done ones ticked.
func describe_objectives(quest: Quest) -> String:
	var lines: PackedStringArray = []
	for objective: QuestObjective in quest.objectives:
		var count: int = get_count(quest, objective.id)
		var mark: String = "[x]" if count >= objective.required else "[ ]"
		if objective.required > 1:
			lines.append("%s %s (%d/%d)" % [mark, objective.description, count, objective.required])
		else:
			lines.append("%s %s" % [mark, objective.description])
	return "\n".join(lines)


## What a [SaveGame] keeps: every quest by id with its status and counts, and where to load it from.
func save_state() -> Dictionary:
	var quests: Dictionary = {}
	for id: StringName in _entries:
		var entry: Dictionary = _entries[id]
		quests[String(id)] = {
			"path": (entry["quest"] as Quest).resource_path,
			"status": entry["status"],
			"objectives": entry["objectives"].duplicate(),
		}
	return {"quests": quests, "tracked": String(tracked.get_id()) if tracked else ""}


## Puts a [method save_state] back. A quest is found again by its resource path, or by a quest of the same id
## the log already knew; one that cannot be found is dropped.
func load_state(state: Dictionary) -> void:
	var known: Dictionary = {}
	for id: StringName in _entries:
		known[id] = _entries[id]["quest"]
	_entries.clear()
	var quests: Dictionary = state.get("quests", {})
	for id: String in quests:
		var saved: Dictionary = quests[id]
		var quest: Quest = known.get(StringName(id))
		var path: String = saved.get("path", "")
		if quest == null and not path.is_empty() and ResourceLoader.exists(path):
			quest = load(path) as Quest
		if quest == null:
			continue
		var counts: Dictionary = {}
		for objective: QuestObjective in quest.objectives:
			counts[objective.id] = int(saved.get("objectives", {}).get(objective.id, 0))
		_entries[StringName(id)] = {"quest": quest, "status": int(saved.get("status", Status.ACTIVE)), "objectives": counts}
	var tracked_id: String = state.get("tracked", "")
	track(_entries[StringName(tracked_id)]["quest"] if _entries.has(StringName(tracked_id)) else null)


func _with_status(status: Status) -> Array[Quest]:
	var quests: Array[Quest] = []
	for id: StringName in _entries:
		if _entries[id]["status"] == status:
			quests.append(_entries[id]["quest"])
	return quests


func _all_met(quest: Quest, entry: Dictionary) -> bool:
	for objective: QuestObjective in quest.objectives:
		if entry["objectives"].get(objective.id, 0) < objective.required:
			return false
	return true


func _complete(quest: Quest, entry: Dictionary) -> void:
	entry["status"] = Status.COMPLETE
	if player and player.inventory:
		for item: Item in quest.rewards:
			player.inventory.add_item(item, quest.rewards[item])
	quest_completed.emit(quest)
	if tracked == quest:
		var remaining: Array[Quest] = get_active()
		track(remaining[0] if not remaining.is_empty() else null)


func _refresh_tracker() -> void:
	if player == null or player.quest_tracker == null or not player.is_multiplayer_authority():
		return
	if tracked:
		player.quest_tracker.show_quest(tracked.title, describe_objectives(tracked))
	else:
		player.quest_tracker.hide_quest()
