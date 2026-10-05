class_name InteractionReach
extends Area3D
## Arm's length around something the Player can use: the volume they must be standing in before it will
## answer the action button.
##
## Hang one on anything that has [code]display_menu[/code], [code]hide_menu[/code] and [code]equip[/code].
## It shows no prompt and reads no input of its own. All it does is tell the Player's [Camera] that its host
## is within reach, and the Camera picks the one target out of everything reporting in: whatever the camera
## ray lands on, or, when the ray lands on nothing, the nearest one in reach.
##
## That single arbiter is the point. Every one of these used to watch for the button itself, so in a crowd
## several prompts floated at once and the first node in scene order took the press, whoever the player was
## actually facing. Now exactly one prompt is ever up, and it belongs to the thing that will answer.
##
## Something with no [InteractionReach] on it, like a computer or a skateboard, is reachable by the camera ray
## alone, out to the Camera's [member Camera.interaction_distance]. Adding one is what says "and you have to be
## standing next to it".

signal player_entered(player: Player) ## For a host that cares about proximity itself, like a door that swings shut once you walk off.
signal player_exited(player: Player)

func _ready() -> void:
	# The group name is the Camera's, so only this script names both: a class_name pointing each way stops
	# camera.gd compiling the first time a project loads it, and its Player comes up with a plain Camera3D.
	var host: Node3D = get_host()
	if host:
		host.add_to_group(Camera.REACH_GROUP)


## The thing this reach belongs to: its parent, which is what carries the prompt and the action.
func get_host() -> Node3D:
	return get_parent() as Node3D


## Wired to this area's own body_entered in the scene.
func _on_body_entered(body: Node3D) -> void:
	var camera: Camera = _camera_of(body)
	if camera:
		camera.reach_entered(get_host())
		player_entered.emit(body as Player)


## Wired to this area's own body_exited in the scene.
func _on_body_exited(body: Node3D) -> void:
	var camera: Camera = _camera_of(body)
	if camera:
		camera.reach_exited(get_host())
		player_exited.emit(body as Player)


## The [Camera] arbitrating for [param body], when it is a Player this peer is driving.
func _camera_of(body: Node3D) -> Camera:
	if body is Player and (body as Player).is_multiplayer_authority():
		return (body as Player).camera as Camera
	return null
