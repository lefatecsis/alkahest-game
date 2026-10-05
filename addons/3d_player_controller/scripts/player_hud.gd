class_name PlayerHud
extends Node
## Everything the Player draws on the screen, in one scene so player.tscn keeps to the body, the camera and the
## logic. The on-screen controls, the readouts and bars, the chat and debug panels, the inventory and the
## abilities, and every menu and screen live here as children; the Player still reaches each of them through
## its own properties ([member Player.pause], [member Player.inventory] and the rest), which resolve into this
## node. player.tscn wires the children (each one's [code]player[/code], the abilities' effects root and audio) as
## overrides on this instance, which is marked editable so the editor keeps them and the connections from these
## children; setting [member player] hands it down as well, for a HUD built by hand.

@export var player: Player: ## The Player this HUD belongs to; every child with a player of its own is handed it.
	set(value):
		player = value
		_hand_player_down()

@onready var controls: PlayerControls = $Controls
@onready var crosshair: TextureRect = $Crosshair
@onready var stamina: Stamina = $Stamina
@onready var health: Health = $Health
@onready var boss_bar: BossBar = $BossBar
@onready var target_frame: TargetFrame = $TargetFrame
@onready var ammo_readout: AmmoReadout = $AmmoReadout
@onready var cast_bar: CastBar = $CastBar
@onready var throw_charge_bar: ProgressBar = $ThrowChargeBar
@onready var seeker_wheel: SeekerWheel = $SeekerWheel
@onready var chat: ChatWindow = $Chat
@onready var debug: Debug = $Debug
@onready var inventory: Inventory = $Inventory
@onready var abilities: Abilities = $Abilities
@onready var quest_tracker: QuestTracker = $QuestTracker
@onready var underwater_overlay: CanvasLayer = $UnderwaterOverlay
@onready var spyglass_overlay: CanvasLayer = $SpyglassOverlay
@onready var death_screen: DeathScreen = $DeathScreen
@onready var pause: PlayerMenuLayer = $Pause
@onready var settings: PlayerMenuLayer = $Settings
@onready var audio_settings: PlayerMenuLayer = $AudioSettings
@onready var controls_settings: PlayerMenuLayer = $ControlsSettings
@onready var video_settings: PlayerMenuLayer = $VideoSettings
@onready var lobby_manager: PlayerMenuLayer = $LobbyManager


func _ready() -> void:
	_hand_player_down()


## Gives [member player] to every child that carries a [code]player[/code] property. Done when the property is set,
## which player.tscn does before anything is ready, and again at ready for a HUD built by hand.
func _hand_player_down() -> void:
	for child: Node in get_children():
		if &"player" in child:
			child.set(&"player", player)
