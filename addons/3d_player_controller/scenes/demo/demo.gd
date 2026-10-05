# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

extends "res://addons/3d_player_controller/scenes/demo/demo_arena.gd"

## Interactive Demo scene for 3D Player Controller: the demo arena with a Player and a teleport panel.
## Provides quick-teleport navigation across the sandbox arena
## (Courtyard, Glider Tower, Water Pool, Climbing Wall).
## Detailed player telemetry and toggleable features are available via F3 (Debug HUD).
## The Player's glider and stamina are switched on, and its state_changed wired here, in demo.tscn.

@onready var player: Player = $Player


## The Guide's errand asks for a swim: entering the water reports it to the quest log.
func _on_player_state_changed(_from_state: int, to_state: int) -> void:
	if to_state == NodeStateMachine.States.SWIMMING and player.quest_log:
		player.quest_log.progress(&"swim")


## Teleports the player to the marker bound in the scene's button connection.
func _on_teleport_pressed(marker_path: NodePath) -> void:
	var marker: Marker3D = get_node(marker_path) as Marker3D
	if not is_instance_valid(player) or marker == null:
		return
	player.is_navigating = false
	player.navigation_agent.target_position = marker.global_position
	player.global_position = marker.global_position
	player.velocity = Vector3.ZERO
