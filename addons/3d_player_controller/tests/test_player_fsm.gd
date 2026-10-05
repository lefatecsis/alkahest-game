extends GutTest

## Purpose: To test the state transitions of the Player FSM.

class FsmTestBase:
	extends IntegrationTestBase

	var PlayerScene = load("res://addons/3d_player_controller/scenes/player.tscn")
	var root: Node3D
	var player: Player
	var floor_body: StaticBody3D
	var wall: StaticBody3D
	
	func before_each() -> void:
		root = Node3D.new()
		add_child_autofree(root)
		
		# Create floor
		floor_body = StaticBody3D.new()
		var floor_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(100, 1, 100)
		floor_shape.shape = box
		floor_body.add_child(floor_shape)
		floor_body.position = Vector3(0, -0.5, 0)
		root.add_child(floor_body)
		
		# Create walls for climbing (surrounding player closely so 1m raycast hits)
		for dir in [Vector3(0, 0, -1.2), Vector3(0, 0, 1.2), Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0)]:
			var w = StaticBody3D.new()
			var w_shape = CollisionShape3D.new()
			var w_box = BoxShape3D.new()
			if dir.z != 0:
				w_box.size = Vector3(10, 10, 1)
			else:
				w_box.size = Vector3(1, 10, 10)
			w_shape.shape = w_box
			w.add_child(w_shape)
			w.position = dir + Vector3(0, 5, 0)
			root.add_child(w)
		
		# Instantiate Player
		player = PlayerScene.instantiate()
		root.add_child(player)
		player.position = Vector3(0, 0.1, 0) # Slightly above floor to snap down
		
		# Await physics frames so state machine can boot
		await wait_physics_frames(2)

	func after_each() -> void:
		Input.action_release("jump")
		Input.action_release("sprint")
		Input.action_release("crouch")
		Input.action_release("attack")
		Input.action_release("move_up")
		Input.action_release("ui_down")
		Input.action_release("whistle")
		if is_instance_valid(root):
			root.free()
			root = null
			player = null

class TestStandingTransitions:
	extends FsmTestBase
	
	func test_standing_to_jumping():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.JUMPING, "Player should transition to JUMPING state after jump action.")

	func test_exhausted_player_can_jump():
		player.enable_stamina = true
		var stamina: Node = player.get_node("Hud/Stamina")
		stamina.set("stamina", 0.0)
		player.is_exhausted = true
		await wait_physics_frames(15)
		assert_eq(player.current_locomotion_node, "HeavyBreathing")

		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(45)

		assert_ne(player.current_locomotion_node, "HeavyBreathing")
		assert_false(
				player.is_jump_queued,
				"Jump queue should execute from %s." % player.current_locomotion_node,
		)
		assert_false(
				player.is_on_floor(),
				"Player should leave floor from %s." % player.current_locomotion_node,
		)
		
	func test_standing_to_sprinting():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.SPRINTING, "Player should transition to SPRINTING state while holding sprint.")
		
		sender.action_up("sprint")
		sender.action_up("move_up")
		player.smoothed_motion = Vector2.ZERO
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition back to STANDING after releasing sprint.")
		
	func test_standing_to_crouching():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.CROUCHING, "Player should transition to CROUCHING state while holding crouch.")
		
		sender.action_up("crouch")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition back to STANDING after releasing crouch.")
		
	func test_standing_to_attacking():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.ATTACKING, "Player should transition to ATTACKING state after attack action.")

	## Drains the stamina bar so exhaustion sticks (it clears again only once the bar has refilled).
	func _exhaust() -> void:
		player.enable_stamina = true
		player.get_node("Hud/Stamina").set("stamina", 0.0)
		player.is_exhausted = true
		await wait_physics_frames(15)

	func test_exhausted_player_cannot_attack():
		# Catching their breath: HeavyBreathing has no way into the attack animations, so the press is ignored
		await _exhaust()
		assert_eq(player.current_locomotion_node, "HeavyBreathing")
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)

		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "An exhausted Player stays standing.")
		assert_false(player.is_attacking, "And is never flagged as attacking.")

	func test_exhausted_crouching_player_cannot_attack():
		await _exhaust()
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.CROUCHING)
		await wait_physics_frames(2)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)

		assert_eq(player.current_state, NodeStateMachine.States.CROUCHING, "An exhausted crouching Player stays crouching.")
		assert_false(player.is_attacking)

	func test_attack_that_never_reaches_an_animation_times_out_to_standing():
		# The 2H axe while exhausted: the state was entered but HeavyBreathing never travels to a slash
		var axe: Equipment = Equipment.new()
		axe.equipment_type = Equipment.EquipmentType.AXE_2H
		root.add_child(axe)
		player.inventory.add_equipment(axe)
		await _exhaust()
		assert_eq(player.current_locomotion_node, "HeavyBreathing")
		var attacking: Attacking = player.state_machine.get_node("Attacking")
		attacking.attack_timeout = 0.3
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.ATTACKING)
		assert_eq(player.current_state, NodeStateMachine.States.ATTACKING)
		assert_true(player.is_attacking)
		assert_false(attacking.attack_timeout_timer.is_stopped(), "The safety timer runs until an attack animation starts.")

		await wait_seconds(0.5)
		await wait_physics_frames(2)

		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "No attack animation within the timeout returns to standing.")
		assert_false(player.is_attacking, "The attacking flag is cleared with the state.")
		assert_eq(player.current_locomotion_node, "HeavyBreathing", "Still catching their breath, not stuck mid-swing.")

class TestSprintingTransitions:
	extends FsmTestBase
	
	func test_sprinting_to_sliding():
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.SPRINTING, "Player should be in SPRINTING state.")
		
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.SLIDING, "Player should transition to SLIDING from sprint when crouch is pressed.")
		
		sender.action_up("sprint")
		sender.action_up("move_up")
		player.smoothed_motion = Vector2.ZERO

class TestPushingTransitions:
	extends FsmTestBase

	func test_standing_to_pushing_and_back():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")

		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")

		# Walk forward until the player presses into the surrounding wall
		var frames_waited: int = 0
		while player.current_state != NodeStateMachine.States.PUSHING and frames_waited < 180:
			await wait_physics_frames(5)
			frames_waited += 5

		assert_eq(player.current_state, NodeStateMachine.States.PUSHING, "Player should transition to PUSHING when moving into a wall.")
		assert_true(player.is_pushing, "Player should be flagged as pushing.")

		await wait_physics_frames(30)
		assert_true(player.current_locomotion_node in ["PushingStart", "Pushing"], "Pushing animation should become active, got %s." % player.current_locomotion_node)

		sender.action_up("move_up")
		player.smoothed_motion = Vector2.ZERO
		await wait_physics_frames(5)

		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition back to STANDING when input stops.")
		assert_false(player.is_pushing, "Player should not be flagged as pushing.")

class TestAirborneTransitions:
	extends FsmTestBase
	
	func test_falling_to_standing_on_floor():
		player.state_machine.travel(player.current_state, NodeStateMachine.States.FALLING)
		await wait_physics_frames(2)
		
		# Position player slightly above ground so they quickly land
		player.global_position = Vector3(0, 0.2, 0)
		await wait_physics_frames(10)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition to STANDING after landing on floor.")

	func test_jumping_to_climbing():
		# Start on floor
		player.global_position = Vector3(0, 0.1, 0)
		await wait_physics_frames(2)
		
		# Jump 1: STANDING -> JUMPING
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.JUMPING, "Player should be jumping.")
		
		# Teleport player into air near walls while in JUMPING state
		player.global_position = Vector3(0, 2.0, 0)
		player.ledge_detection_horizontal.force_raycast_update()
		await wait_physics_frames(2)
		
		# Jump 2: JUMPING -> CLIMBING
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.CLIMBING, "Player should transition to CLIMBING when jumping near wall while in air.")

class TestAttackingTransitions:
	extends FsmTestBase
	
	func test_attacking_timeout():
		player.state_machine.get_node("Attacking").boxing_inactivity_delay = 0.5
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.ATTACKING, "Player should be in ATTACKING state.")
		
		assert_true(player.is_boxing, "Unarmed attack should enter the boxing stance.")
		
		await wait_seconds(0.8)
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should return to STANDING after attack timeout.")

class TestEquipmentInteractionTransitions:
	extends FsmTestBase

	func test_greatsword_logging_animation():
		var greatsword: Equipment = Equipment.new()
		greatsword.equipment_type = Equipment.EquipmentType.SWORD_2H
		greatsword.can_log = true
		root.add_child(greatsword)
		player.inventory.add_equipment(greatsword)

		player.locomotion_state.start("GreatSword")
		var greatsword_playback: AnimationNodeStateMachinePlayback = player.animation_tree.get(
				"parameters/LocomotionStateMachine/GreatSword/playback",
		)
		greatsword_playback.start("GreatSwordLocomotion")
		player.travel_locomotion("GreatSword/Logging")
		await wait_physics_frames(2)

		assert_true(player.is_logging, "GreatSword logging animation should become active.")

class TestEnableSettings:
	extends FsmTestBase

	func test_disabled_special_states_block_entry():
		var special_states: Array[NodeStateMachine.States] = [
			NodeStateMachine.States.FLYING,
			NodeStateMachine.States.PARAGLIDING,
			NodeStateMachine.States.RAGDOLLING,
		]
		for state: NodeStateMachine.States in special_states:
			player.state_machine.travel(player.current_state, state)
			assert_eq(
					player.current_state,
					NodeStateMachine.States.STANDING,
					"Disabled special state should not be entered.",
			)

	func test_enabled_flying_allows_entry():
		player.enable_flying = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.FLYING)
		assert_eq(player.current_state, NodeStateMachine.States.FLYING)

	func test_enabled_paraglider_allows_entry():
		player.enable_paraglider = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.PARAGLIDING)
		assert_eq(player.current_state, NodeStateMachine.States.PARAGLIDING)

	func test_enabled_ragdoll_allows_entry():
		player.enable_ragdoll = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.RAGDOLLING)
		assert_eq(player.current_state, NodeStateMachine.States.RAGDOLLING)

class TestPauseTransitions:
	extends FsmTestBase
	
	func test_no_ragdoll_when_pause_visible():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		player.enable_ragdoll = true
		player.pause.show_menu()
		assert_true(player.is_paused, "Player should be paused.")
		assert_true(player.pause.visible, "Pause CanvasLayer should be visible.")
		
		player.state_machine.travel(player.current_state, NodeStateMachine.States.RAGDOLLING)
		await wait_physics_frames(2)
		
		assert_ne(player.current_state, NodeStateMachine.States.RAGDOLLING, "Player should not transition to RAGDOLLING when Pause CanvasLayer is visible.")

	## Only a living Player's ragdoll waits for the menu: dying behind it, or with the chat open, drops the body.
	func test_death_behind_the_menu_or_the_chat_still_ragdolls():
		player.respawn_timer.wait_time = 30.0
		player.pause.show_menu()
		player.is_typing = true
		player.take_hit(player.health.max_health, player.global_position + Vector3.FORWARD)
		assert_eq(player.current_state, NodeStateMachine.States.RAGDOLLING, "A dead Player drops even behind a menu")
		assert_false(player.respawn_timer.is_stopped(), "and the respawn is on its way")
		player.is_typing = false
		player.pause.hide_menu()

	## A menu holds the aim and the trigger: in multiplayer the clock keeps running behind it.
	func test_focus_and_shooting_stop_behind_a_menu():
		player.inventory.can_player_shoot = true
		Input.action_press("focus")
		Input.action_press("shoot")
		assert_true(player.is_focusing, "Holding focus focuses")
		assert_true(player.is_shooting, "and holding shoot shoots")
		player.is_paused = true
		assert_false(player.is_focusing, "but not behind a menu")
		assert_false(player.is_shooting, "and neither does the trigger")
		player.is_paused = false
		Input.action_release("focus")
		Input.action_release("shoot")

	## A dead Player lies there until the respawn; Action gets only a living one up.
	func test_the_dead_do_not_stand_up_early():
		player.respawn_timer.wait_time = 30.0
		var action := InputEventAction.new()
		action.action = "action"
		action.pressed = true
		var ragdolling: NodeStateMachine = player.get_node("NodeStateMachine/Ragdolling")
		player.take_hit(player.health.max_health, player.global_position + Vector3.FORWARD)
		assert_eq(player.current_state, NodeStateMachine.States.RAGDOLLING)
		ragdolling._input(action)
		assert_eq(player.current_state, NodeStateMachine.States.RAGDOLLING, "Action does not bring the dead back")
		player.respawn()
		player.enable_ragdoll = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.RAGDOLLING)
		ragdolling._input(action)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "A living Player knocked down gets up on Action")

class TestRidingTransitions:
	extends FsmTestBase

	## A rideable that only records what the Riding state does to it and asks for one animation.
	class MockRideable:
		extends Node3D
		signal locomotion_requested(state_path: String, immediate: bool)
		signal jump_requested
		var blocks_hands: bool = false
		var disables_collision: bool = false
		var mount_animation: String = ""
		var dismount_animation: String = ""
		var input_type: int = -1
		var seat: Node3D
		var camera: Camera3D
		var mounted_by: Player
		var dismounted: bool = false
		var rides: int = 0
		var labels: Dictionary = {"key_k": "Dismount", "joypad_button_1": "Fast Push", "no_such": "Dropped"}
		var input_type_at_ride_input: int = -1 ## What input_type read when ride_input last ran.

		func _ready() -> void:
			camera = Camera3D.new()
			add_child(camera)

		func mount(p: Player) -> void:
			mounted_by = p
			locomotion_requested.emit("StandingLocomotion", true)

		func dismount(_p: Player) -> void:
			dismounted = true

		func ride(_p: Player, _delta: float) -> void:
			rides += 1

		func ride_input(p: Player, event: InputEvent) -> void:
			input_type_at_ride_input = input_type
			if event.is_action_pressed("whistle"):
				p.dismount()

		func get_contextual_controls(_input_type: int) -> Dictionary:
			return labels

	var rideable: MockRideable

	func before_each() -> void:
		super.before_each()
		rideable = MockRideable.new()
		root.add_child(rideable)

	func test_mount_enters_riding_and_hands_the_rideable_the_player():
		player.mount(rideable)
		await wait_physics_frames(3)
		assert_eq(player.current_state, NodeStateMachine.States.RIDING, "mount() enters the RIDING state")
		assert_true(player.is_riding)
		assert_eq(player.riding, rideable)
		assert_eq(rideable.mounted_by, player, "The rideable was given the Player")
		assert_gt(rideable.rides, 0, "And is ridden every physics frame")

	func test_dismount_returns_to_standing_and_tells_the_rideable():
		player.mount(rideable)
		await wait_physics_frames(2)
		player.dismount()
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING)
		assert_false(player.is_riding)
		assert_null(player.riding)
		assert_true(rideable.dismounted)

	func test_rideable_input_can_dismount():
		player.mount(rideable)
		await wait_physics_frames(2)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("whistle")
		await wait_physics_frames(2)
		sender.action_up("whistle")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "The rideable's ride_input dismounted on whistle")

	func test_held_object_reserves_dpad_down_while_riding():
		player.mount(rideable)
		await wait_physics_frames(2)
		var held_body: RigidBody3D = RigidBody3D.new()
		root.add_child(held_body)
		player.held_object._pickup_rigidbody(held_body)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("whistle")
		await wait_physics_frames(2)
		sender.action_up("whistle")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.RIDING, "Held object controls reserve D-pad Down from the rideable")
		player.held_object.drop_held_rigidbody()

	func test_riding_contextual_controls_come_from_the_rideable_by_label_name():
		player.mount(rideable)
		await wait_physics_frames(2)
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		var kb_controls = riding_node.get_contextual_controls(0)
		assert_eq(kb_controls.get(player.controls.key_k_label), "Dismount", "\"key_k\" lands on the Controls' key_k_label")
		assert_eq(kb_controls.get(player.controls.joypad_button_1_label), "Fast Push", "and \"joypad_button_1\" on its label, by the name the rideable gave rather than by what the button does")
		assert_eq(kb_controls.size(), 2, "A name with no label on the Controls is dropped")

	func test_riding_contextual_controls_can_name_an_action_instead_of_a_label():
		rideable.labels = {&"sprint": "Gallop", &"no_such_action": "Dropped"}
		player.mount(rideable)
		await wait_physics_frames(2)
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		var resolved: Dictionary = riding_node.get_contextual_controls(0)
		assert_eq(resolved.get(player.controls.action_label(&"sprint")), "Gallop", "An action name lands on the label of whichever button carries that action")
		assert_eq(resolved.size(), 1, "and an action no button carries is dropped")

	func test_riding_hides_the_buttons_the_rideable_does_not_name_even_with_the_whole_hud_on():
		player.hud_mode_override = PlayerSettingsResource.HudMode.SHOWN # the whole set, whatever this machine's saved setting says
		player.controls.current_input_type = Controls.InputType.MICROSOFT
		assert_true(player.controls.joypad_button_2.visible, "On foot every mapped button is drawn")
		assert_true(player.controls.joypad_button_9.visible)
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(player.controls.joypad_button_1.visible, "The button the rideable named stays")
		assert_eq(player.controls.joypad_button_1_label.text, "Fast Push")
		assert_true(player.controls.joypad_button_12.visible, "and the d-pad button its key mirrors onto")
		assert_true(player.controls.dpad_base.visible)
		assert_false(player.controls.joypad_button_2.visible, "A button it did not name is a glyph with nothing to say, so it goes")
		assert_false(player.controls.joypad_button_9.visible)
		assert_true(player.controls.joypad_button_6.visible, "The pause button is the addon's own and stays")
		assert_true(player.controls.left_joystick.visible, "and so does the stick")
		player.dismount()
		await wait_physics_frames(2)
		assert_true(player.controls.joypad_button_2.visible, "Back on foot the whole set is back")
		assert_true(player.controls.joypad_button_9.visible)

	## The first key after a pad session is read as a key: the rideable is told the event's own device before it
	## reads the event, since the HUD that tracks the device may get the event after the state does.
	func test_the_rideable_reads_an_event_for_the_device_it_came_from():
		player.controls.current_input_type = Controls.InputType.SONY
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_eq(rideable.input_type, Controls.InputType.SONY, "On the pad to start")
		var key := InputEventKey.new()
		key.keycode = KEY_F
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events() # buffered until the next frame otherwise, which on CI is after this test ends
		await wait_process_frames(1)
		assert_eq(rideable.input_type_at_ride_input, Controls.InputType.KEYBOARD_MOUSE, "A key press reaches ride_input already read as the keyboard")
		assert_eq(player.controls.current_input_type, Controls.InputType.KEYBOARD_MOUSE, "and the HUD follows")
		var release: InputEventKey = key.duplicate()
		release.pressed = false
		Input.parse_input_event(release) # never leave a key held into the next test
		Input.flush_buffered_events()

	func test_riding_keeps_the_rideables_input_type_current():
		player.controls.current_input_type = Controls.InputType.SONY
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_eq(rideable.input_type, Controls.InputType.SONY, "Handed the Player's device on mount")
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		assert_eq(rideable.input_type, Controls.InputType.KEYBOARD_MOUSE, "And every change after")

	func test_riding_makes_the_rideables_camera_current_and_gives_the_view_back():
		assert_true(player.camera.current)
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(rideable.camera.current, "The rideable's camera is the view while ridden")
		assert_false(player.camera.current)
		player.dismount()
		await wait_physics_frames(2)
		assert_true(player.camera.current, "The Player's own camera returns on dismount")
		assert_false(rideable.camera.current)

	func test_riding_handles_collision_crosshair_and_step_up_ray():
		rideable.disables_collision = true
		rideable.blocks_hands = true
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(player.collision_shape.disabled, "disables_collision turns the Player's shape off")
		assert_true(player.separation_ray_shape.disabled, "The step-up ray is off for every ride")
		assert_false(player.crosshair.visible, "blocks_hands hides the crosshair")
		player.dismount()
		await wait_physics_frames(2)
		assert_false(player.collision_shape.disabled)
		assert_false(player.separation_ray_shape.disabled)
		assert_true(player.crosshair.visible)

	func test_a_seat_pins_the_player_to_the_rideable_every_frame():
		var seat: Node3D = Node3D.new()
		rideable.add_child(seat)
		rideable.set("seat", seat)
		rideable.global_position = Vector3(4.0, 0.0, 0.0)
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_eq(player.get_parent(), root, "The Player stays where it is in the tree")
		assert_almost_eq(player.global_position, seat.global_position, Vector3.ONE * 0.01, "But sits on the seat")
		rideable.rotate_y(1.0)
		rideable.global_position += Vector3(0.0, 0.0, 2.0)
		await wait_physics_frames(1)
		assert_almost_eq(player.global_basis.z.dot(rideable.global_basis.z), 1.0, 0.01, "Turning the rideable turns the Player with it")
		assert_almost_eq(player.global_position, seat.global_position, Vector3.ONE * 0.01, "And moving it moves them")
		var facing: Vector3 = player.player_model.global_basis.z
		assert_almost_eq(facing.dot(-seat.global_basis.z), 1.0, 0.01, "The rider faces along the seat's -Z, Godot's forward")
		assert_almost_eq(player.orientation.basis.z.dot(facing), 1.0, 0.01, "And orientation agrees with the model")
		player.dismount()
		await wait_physics_frames(2)
		assert_almost_eq(player.global_basis.y, Vector3.UP, Vector3.ONE * 0.01, "Upright again on dismount")
		assert_almost_eq(player.orientation.basis.z.dot(facing), 1.0, 0.05, "Still facing the way they sat, no spin on the way off")

	func test_mount_animation_plays_before_the_ride_and_ends_with_the_clip():
		rideable.mount_animation = "EnteringCar"
		player.mount(rideable)
		await wait_physics_frames(3)
		assert_true(player.is_mounting, "The get-on clip plays first")
		assert_eq(player.current_locomotion_node, "EnteringCar")
		assert_eq(rideable.rides, 0, "The rideable is not ridden while it plays")
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		riding_node._on_locomotion_node_changed("StandingLocomotion")
		await wait_physics_frames(2)
		assert_false(player.is_mounting, "The clip ending seats the rider")
		assert_gt(rideable.rides, 0, "And the ride begins")

	func test_dismount_animation_plays_before_the_dismount_unless_immediate():
		rideable.dismount_animation = "ExitingCar"
		player.mount(rideable)
		await wait_physics_frames(2)
		player.dismount()
		await wait_physics_frames(2)
		assert_true(player.is_dismounting, "The get-off clip plays first")
		assert_eq(player.current_locomotion_node, "ExitingCar")
		assert_eq(player.current_state, NodeStateMachine.States.RIDING, "Still riding until it ends")
		assert_false(rideable.dismounted)
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		riding_node._on_locomotion_node_changed("StandingLocomotion")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "The clip ending finishes the dismount")
		assert_true(rideable.dismounted)
		player.mount(rideable)
		await wait_physics_frames(2)
		player.dismount(true)
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "An immediate dismount skips the clip")

	func test_jump_requested_queues_the_players_jump():
		player.mount(rideable)
		await wait_physics_frames(2)
		rideable.jump_requested.emit()
		assert_true(player.is_jump_queued, "The rideable's jump request queues the Player's jump animation")

	func test_blocks_hands_holsters_equipment():
		rideable.blocks_hands = true
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(player.riding_blocks_hands())
		player.dismount()
		await wait_physics_frames(2)
		assert_false(player.riding_blocks_hands())


class TestCrouchingTransitions:
	extends FsmTestBase

	func test_crouching_to_falling_when_airborne():
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.CROUCHING, "Player should be crouching.")

		player.global_position = Vector3(0, 6.0, 0)
		await wait_physics_frames(3)
		assert_eq(player.current_state, NodeStateMachine.States.FALLING, "Crouching player leaving the floor should fall.")
		sender.action_up("crouch")

class TestSlidingTransitions:
	extends FsmTestBase

	func test_sliding_auto_exits_to_standing():
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		sender.action_up("sprint")
		sender.action_up("move_up")
		assert_eq(player.current_state, NodeStateMachine.States.SLIDING, "Player should be sliding.")

		var frames_waited: int = 0
		while player.current_state == NodeStateMachine.States.SLIDING and frames_waited < 300:
			await wait_physics_frames(5)
			frames_waited += 5
		# On the CI runner the slide now and then ends in a one-tick FALLING that lands at once, which
		# never happens here; give it a moment to settle before judging where the slide ended.
		frames_waited = 0
		while player.current_state != NodeStateMachine.States.STANDING and frames_waited < 30:
			await wait_physics_frames(5)
			frames_waited += 5
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Sliding should end in STANDING once RunningSlide finishes.")

	## RunningSlide is reached only from StandingLocomotion, so with a sword out Crouch does not slide at a sprint.
	func test_no_slide_with_a_weapon_out():
		var greatsword: Equipment = Equipment.new()
		greatsword.equipment_type = Equipment.EquipmentType.SWORD_2H
		root.add_child(greatsword)
		player.inventory.add_equipment(greatsword)
		await wait_physics_frames(5)
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.SPRINTING, "Sprinting with the sword")
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		assert_ne(player.current_state, NodeStateMachine.States.SLIDING, "The GreatSword stance has no way into the slide")
		sender.action_up("sprint")
		sender.action_up("move_up")

	## A slide whose clip never plays stands up after the timeout, with the full-height capsule back.
	func test_a_slide_that_never_plays_times_out():
		var height: float = player.initial_collision_shape_height
		player.animation_tree.active = false # the locomotion never moves, as when the tree has no path into RunningSlide
		player.state_machine.travel(player.current_state, NodeStateMachine.States.SLIDING)
		assert_eq(player.current_state, NodeStateMachine.States.SLIDING)
		assert_lt(player.collision_shape.shape.height, height, "Sliding halves the capsule")
		await wait_seconds(Sliding.TIMEOUT + 0.3)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "The slide gives up")
		assert_eq(player.collision_shape.shape.height, height, "and the capsule is whole again")
		player.animation_tree.active = true

	## Sliding off a ledge falls rather than sliding on through the air.
	func test_sliding_off_a_ledge_falls():
		player.state_machine.travel(player.current_state, NodeStateMachine.States.SLIDING)
		player.global_position = Vector3(0, 6.0, 0)
		await wait_physics_frames(3)
		assert_eq(player.current_state, NodeStateMachine.States.FALLING, "No ground, no slide")

class TestHangingTransitions:
	extends FsmTestBase

	func test_drop_blocked_while_climbing_on_and_cleared_on_exit():
		player.global_position = Vector3(0, 2.0, 0)
		player.state_machine.travel(player.current_state, NodeStateMachine.States.HANGING)
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.HANGING, "Player should be hanging.")

		player.is_climbing_on = true
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		assert_eq(player.current_state, NodeStateMachine.States.HANGING, "Drop must be ignored while climbing on to the ledge.")

		player.state_machine.travel(player.current_state, NodeStateMachine.States.FALLING)
		assert_false(player.is_climbing_on, "Leaving HANGING must clear is_climbing_on.")

class TestStandingLocomotion:
	extends FsmTestBase

	func test_equipment_changed_rederives_grounded_locomotion():
		var greatsword: Equipment = Equipment.new()
		greatsword.equipment_type = Equipment.EquipmentType.SWORD_2H
		root.add_child(greatsword)
		player.inventory.add_equipment(greatsword)
		await wait_physics_frames(2)

		assert_true(
			player.current_locomotion_path.begins_with("GreatSword"),
			"Equipping a greatsword while standing should travel to the GreatSword locomotion, got %s." % player.current_locomotion_path,
		)


class TestAnimationTreeExpressions:
	extends GutTest

	var PlayerScene = load("res://addons/3d_player_controller/scenes/player.tscn")

	const KNOWN_GAPS: Array[String] = ["is_stomping"] ## Boxing's Stomping edge reads a flag nothing sets; it is dead until the Player grows one.

	## Every name an advance_expression reads is something the Player has, so a typo cannot leave an edge that
	## never fires (HeavyBreathing -> StandingLocomotion once read jump_queued).
	func test_every_advance_expression_names_player_members() -> void:
		var player: Player = PlayerScene.instantiate()
		add_child_autofree(player)
		var blend_tree: AnimationNodeBlendTree = player.animation_tree.tree_root as AnimationNodeBlendTree
		var machines: Array[AnimationNodeStateMachine] = [blend_tree.get_node("LocomotionStateMachine")]
		for group: String in Player.LOCOMOTION_GROUPS:
			machines.append(machines[0].get_node(group))
		var quoted: RegEx = RegEx.create_from_string("\"[^\"]*\"")
		var identifier: RegEx = RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
		var checked: int = 0
		for machine: AnimationNodeStateMachine in machines:
			for i: int in machine.get_transition_count():
				var expression: String = quoted.sub(machine.get_transition(i).advance_expression, "", true)
				for found: RegExMatch in identifier.search_all(expression):
					var name: String = found.get_string()
					if name in ["and", "or", "not", "true", "false", "in"] or name in KNOWN_GAPS:
						continue
					checked += 1
					assert_true(name in player or player.has_method(name), "%s -> %s reads '%s', which the Player does not have" % [machine.get_transition_from(i), machine.get_transition_to(i), name])
		assert_gt(checked, 0, "The tree has expressions to check")


class TestLocomotionBlend:
	extends FsmTestBase

	## Crouching is its own locomotion state, so while crouched only its blend space follows the input; standing
	## up with a one-handed weapon feeds the Shield space instead.
	func test_the_blend_follows_the_stance_crouch_first() -> void:
		var sword := Equipment.new()
		sword.equipment_type = Equipment.EquipmentType.SWORD_1H
		sword.bone_attachment_bone_name = "RightHand"
		root.add_child(sword)
		player.inventory.equip_pickup(sword)
		player.animation_tree.set(Player.SHIELD_LOCOMOTION_BLEND_POSITION_PATH, Vector2.ZERO)
		player.is_crouching = true
		player._set_locomotion_blend(Vector2(0.0, 0.7))
		assert_eq(player.animation_tree.get(Player.CROUCHING_LOCOMOTION_BLEND_POSITION_PATH), Vector2(0.0, 0.7), "Crouched, the crouch space moves")
		assert_eq(player.animation_tree.get(Player.SHIELD_LOCOMOTION_BLEND_POSITION_PATH), Vector2.ZERO, "and the weapon's does not")
		player.is_crouching = false
		player._set_locomotion_blend(Vector2(0.0, 0.7))
		assert_eq(player.animation_tree.get(Player.SHIELD_LOCOMOTION_BLEND_POSITION_PATH), Vector2(0.0, 0.7), "Standing with a sword, the Shield space moves")

	## One helper names the group for all of them: with a two-handed sword and a bow both in hand, the stance, its
	## blend space and the jump edges agree on the GreatSword, as the stance always chose.
	func test_the_stance_and_its_blend_space_name_the_same_group() -> void:
		for type: Equipment.EquipmentType in [Equipment.EquipmentType.BOW, Equipment.EquipmentType.SWORD_2H]:
			var item := Equipment.new()
			item.equipment_type = type
			root.add_child(item)
			player.inventory.add_equipment(item)
		assert_eq(player.equipment_group(), "GreatSword")
		assert_eq(player.get_grounded_locomotion_state(), &"GreatSword/GreatSwordLocomotion")
		player.animation_tree.set(Player.BOW_LOCOMOTION_BLEND_POSITION_PATH, Vector2.ZERO)
		player._set_locomotion_blend(Vector2(0.0, 0.6))
		assert_eq(player.animation_tree.get(Player.GREATSWORD_LOCOMOTION_BLEND_POSITION_PATH), Vector2(0.0, 0.6), "The blend feeds the stance being played")
		assert_eq(player.animation_tree.get(Player.BOW_LOCOMOTION_BLEND_POSITION_PATH), Vector2.ZERO, "not the bow's")
		assert_true(player.uses_equipment_jump_variants, "and the jump edges see something in hand")


class TestJumpVariants:
	extends FsmTestBase

	## A double jump: in the air, Jump goes up again at jump_speed, air_jumps times before the feet touch down.
	func test_air_jump_spends_one_jump_per_press() -> void:
		player.enable_double_jump = true
		player.air_jumps = 1
		await wait_physics_frames(10)
		assert_true(player.is_on_floor(), "Standing, the air jumps are refilled")
		assert_false(player.air_jump(), "Not from the ground")
		player.global_position = Vector3(0, 6.0, 0)
		await wait_physics_frames(3)
		assert_eq(player.current_state, NodeStateMachine.States.FALLING)
		var jump := InputEventAction.new()
		jump.action = "jump"
		jump.pressed = true
		player.get_node("NodeStateMachine/Falling")._input(jump)
		assert_eq(player.current_state, NodeStateMachine.States.JUMPING, "The air jump plays the jump")
		assert_almost_eq(player.velocity.dot(player.up_direction), player.jump_speed, 0.01, "and goes up at jump_speed at once")
		assert_eq(player.air_jumps_left, 0, "spending the one air jump")
		assert_false(player.air_jump(), "so there is no second one")

	## Without the double jump the air is the air.
	func test_air_jump_is_off_by_default() -> void:
		player.global_position = Vector3(0, 6.0, 0)
		await wait_physics_frames(3)
		assert_false(player.air_jump(), "No double jump unless the game turns it on")

	## A spring or a stomp throws the Player up at the given speed, into the jump.
	func test_bounce_throws_the_player_up() -> void:
		player.bounce(12.0)
		assert_eq(player.current_state, NodeStateMachine.States.JUMPING)
		assert_almost_eq(player.velocity.dot(player.up_direction), 12.0, 0.01, "Straight up at the bounce's speed")
		assert_false(player.is_jump_queued, "with no jump left waiting for the clip")
		await wait_physics_frames(5)
		assert_false(player.is_on_floor(), "and off the ground")

	## instant_jump leaves the ground on the press; without it the jump waits for the clip's keyframe.
	func test_instant_jump_leaves_the_ground_on_the_press() -> void:
		player.state_machine.travel(player.current_state, NodeStateMachine.States.JUMPING)
		assert_true(player.is_jump_queued, "The ordinary jump waits for the clip")
		assert_almost_eq(player.velocity.dot(player.up_direction), 0.0, 0.5, "and has not left yet")
		player.state_machine.travel(player.current_state, NodeStateMachine.States.STANDING)
		await wait_physics_frames(10)
		player.instant_jump = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.JUMPING)
		assert_false(player.is_jump_queued, "The platformer's jump is not queued")
		assert_almost_eq(player.velocity.dot(player.up_direction), player.jump_speed, 0.01, "it is under way on the press")


class TestInputThroughThePlayer:
	extends FsmTestBase

	## The states that hold an action down ask the Player, so a pad player in a split screen reads their own pad:
	## the keyboard's Sprint is not theirs, so it does not speed their flight.
	func test_a_pad_player_does_not_read_the_keyboard() -> void:
		player.enable_flying = true
		player.global_position = Vector3(0, 6.0, 0)
		player.state_machine.travel(player.current_state, NodeStateMachine.States.FLYING)
		Input.action_press("jump")
		await wait_physics_frames(2)
		assert_gt(player.velocity.dot(player.up_direction), 0.0, "The whole input flies up on Jump")
		player.input_device = 0
		await wait_physics_frames(2)
		assert_almost_eq(player.velocity.dot(player.up_direction), 0.0, 0.01, "Pad 0's player does not fly on the keyboard's Jump")
		player.input_device = -1
		player.is_paused = true
		await wait_physics_frames(2)
		assert_almost_eq(player.velocity.dot(player.up_direction), 0.0, 0.01, "nor does anyone behind a menu")
		player.is_paused = false
		Input.action_release("jump")


class TestSceneWiring:
	extends FsmTestBase

	## The HUD's device change reaches the current state through one connection in player.tscn (to
	## Player._on_controls_input_type_changed); travelling adds and removes no connections of its own.
	func test_a_device_change_reaches_the_current_state_through_the_scene() -> void:
		var before: int = player.controls.input_type_changed.get_connections().size()
		player.enable_flying = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.FLYING)
		assert_eq(player.controls.input_type_changed.get_connections().size(), before, "Travelling adds no connection")
		var jump_label: Label = player.controls.action_label(&"jump", player.controls.joypad_button_3_label)
		assert_eq(jump_label.text, "Fly Up", "The new state's labels go up on the way in")
		jump_label.text = ""
		player.controls.input_type_changed.emit(player.controls.current_input_type)
		assert_eq(jump_label.text, "Fly Up", "and a device change puts them back")
