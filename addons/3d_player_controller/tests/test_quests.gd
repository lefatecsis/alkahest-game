extends GutTest

## Purpose: The Player's QuestLog takes quests on, counts objectives as the game reports them, completes a quest
## once every objective is met and pays its rewards into the inventory, keeps the HUD tracker on the tracked
## quest, lists them for the Quests screen, and round-trips through save_state.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const DEMO_QUEST: Quest = preload("res://addons/3d_player_controller/resources/quests/demo_errand.tres")
const APPLE: Item = preload("res://addons/3d_player_controller/inventory/resources/items/apple.tres")

var player: Player
var quest_log: QuestLog


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	quest_log = player.quest_log
	await wait_physics_frames(2)


func _quest(id: String, objective_ids: Array, required: int = 1) -> Quest:
	var quest: Quest = Quest.new()
	quest.id = id
	quest.title = id.capitalize()
	for objective_id: String in objective_ids:
		var objective: QuestObjective = QuestObjective.new()
		objective.id = objective_id
		objective.description = objective_id.capitalize()
		objective.required = required
		quest.objectives.append(objective)
	return quest


func test_the_player_carries_a_quest_log() -> void:
	assert_not_null(quest_log)
	assert_eq(quest_log.player, player)
	assert_true(quest_log.get_all().is_empty())
	assert_false(player.quest_tracker.visible, "Nothing tracked, nothing shown")


func test_starting_a_quest_tracks_it_and_counts_its_objectives() -> void:
	var quest: Quest = _quest("errand", ["talk", "chop"], 1)
	watch_signals(quest_log)
	assert_true(quest_log.start(quest))
	assert_false(quest_log.start(quest), "A quest is started once")
	assert_signal_emitted(quest_log, "quest_started")
	assert_true(quest_log.is_active(quest))
	assert_eq(quest_log.tracked, quest)
	assert_true(player.quest_tracker.visible)
	assert_eq(player.quest_tracker.title_label.text, "Errand")
	assert_true(player.quest_tracker.objectives_label.text.contains("[ ] Talk"))
	assert_true(quest_log.progress(&"talk"))
	assert_signal_emitted(quest_log, "objective_progressed")
	assert_true(quest_log.is_objective_done(quest, &"talk"))
	assert_true(player.quest_tracker.objectives_label.text.contains("[x] Talk"))
	assert_false(quest_log.progress(&"talk"), "A met objective counts no further")
	assert_false(quest_log.progress(&"nothing_asks_for_this"))
	assert_signal_not_emitted(quest_log, "quest_completed")


func test_meeting_every_objective_completes_the_quest_and_pays() -> void:
	var quest: Quest = _quest("gather", ["logs"], 3)
	quest.rewards[APPLE] = 2
	watch_signals(quest_log)
	quest_log.start(quest)
	quest_log.progress(&"logs", 2)
	assert_eq(quest_log.get_count(quest, &"logs"), 2)
	assert_true(player.quest_tracker.objectives_label.text.contains("(2/3)"))
	quest_log.progress(&"logs")
	assert_signal_emitted(quest_log, "quest_completed")
	assert_true(quest_log.is_complete(quest))
	assert_eq(player.inventory.count_of(APPLE), 2, "The reward is in the bag")
	assert_null(quest_log.tracked, "Done, it leaves the tracker")
	assert_false(player.quest_tracker.visible)
	assert_eq(quest_log.get_completed(), [quest])


func test_the_tracker_falls_back_to_another_active_quest() -> void:
	var first: Quest = _quest("first", ["a"])
	var second: Quest = _quest("second", ["b"])
	quest_log.start(first)
	quest_log.start(second)
	assert_eq(quest_log.tracked, second, "The latest started is tracked")
	quest_log.track(first)
	assert_eq(quest_log.tracked, first)
	quest_log.progress(&"a")
	assert_eq(quest_log.tracked, second, "Completing the tracked one tracks what is left")


func test_the_log_round_trips_through_a_save() -> void:
	var quest: Quest = _quest("errand", ["talk", "chop"], 2)
	quest_log.start(quest)
	quest_log.progress(&"talk", 2)
	quest_log.progress(&"chop")
	quest_log.start(DEMO_QUEST)
	quest_log.track(quest)
	var state: Dictionary = quest_log.save_state()
	assert_true(state["quests"].has("errand"))
	assert_eq(state["tracked"], "errand")
	# A fresh log on a fresh Player: the demo quest comes back by path, the ad hoc one by the id it already knows
	var other: QuestLog = QuestLog.new()
	other.player = player
	add_child_autofree(other)
	other.start(quest)
	other.load_state(state)
	assert_eq(other.get_count(quest, &"talk"), 2)
	assert_eq(other.get_count(quest, &"chop"), 1)
	assert_true(other.is_active(DEMO_QUEST), "The demo quest is found by its resource path")
	assert_eq(other.tracked, quest)


func test_the_quests_screen_lists_and_tracks() -> void:
	var quest: Quest = _quest("errand", ["talk"])
	var done: Quest = _quest("finished", ["x"])
	quest_log.start(done)
	quest_log.progress(&"x")
	quest_log.start(quest)
	player.pause.show_menu()
	assert_true(player.pause.quests_button.visible, "The pause menu offers Quests")
	player.pause._on_quests_pressed()
	var screen: QuestScreen = player.pause.quests_screen
	assert_true(screen.visible)
	assert_eq(screen._quest_buttons.size(), 2)
	assert_eq(screen._quest_buttons[0].text, "Errand", "Active quests list first")
	assert_eq(screen._quest_buttons[1].text, "Finished (done)")
	assert_eq(screen.detail_title.text, "Errand")
	assert_true(screen.detail_objectives.text.contains("[ ] Talk"))
	assert_false(screen.track_button.visible, "Already tracked")
	screen._show_details(done)
	assert_eq(screen.detail_status.text, "Complete")
	screen._on_back_pressed()
	assert_false(screen.visible)
	assert_true(player.pause.visible)
	player.pause.hide_menu()


func test_the_demo_quest_resource_is_complete() -> void:
	assert_eq(DEMO_QUEST.get_id(), &"demo_errand")
	assert_eq(DEMO_QUEST.objectives.size(), 2)
	assert_not_null(DEMO_QUEST.find_objective(&"swim"))
	assert_eq(DEMO_QUEST.rewards[APPLE], 2)
