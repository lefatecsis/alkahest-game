# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

extends Node3D

## The demo arena with no Player of its own: the courtyard, the glider tower, the water pool, the climbing wall,
## the Guide, the checkpoint, the kill zone and the SaveGame. demo.tscn inherits it and adds the Player and the
## teleport panel; split_screen_demo.tscn instances it under two views. The pool and the Guide answer whichever
## Player comes to them, so they work for every view.

const GUIDE_ERRAND: Quest = preload("res://addons/3d_player_controller/resources/quests/demo_errand.tres")

@onready var guide: TalkingNpc = $Guide
@onready var water_pool: Area3D = $Structures/PoolBasin/WaterPool


## Talking to the Guide is the errand's first objective and, the first time, what starts it. The addon has no
## dialogue of its own (a game brings its own, Dialogic say), so the talk is over as soon as it begins.
func _on_guide_talked_to(who: Player) -> void:
	if who.quest_log:
		who.quest_log.start(GUIDE_ERRAND)
		who.quest_log.progress(&"talk_guide")
	guide.end_talk()


func _on_water_pool_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).enter_water(water_pool)


func _on_water_pool_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_water(water_pool)
