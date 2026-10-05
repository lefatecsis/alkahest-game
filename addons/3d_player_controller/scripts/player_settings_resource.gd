class_name PlayerSettingsResource
extends Resource

static var SAVE_PATH: String = "user://settings.tres" ## Where the settings live; a test run points it elsewhere so it never touches the player's own.
const MSAA_VALUES: Array[Viewport.MSAA] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X] ## Indexed by [member msaa_index].
const SSAA_SCALES: Array[float] = [1.0, 1.5, 2.0] ## Indexed by [member ssaa_index].
const TOON_NEWSPAPER: int = 1 ## ToonFilter.Mode.NEWSPAPER, what an old saved toon_enabled = true meant.
const MINIMAP_GROUP: StringName = &"minimap" ## The group a minimap joins (the minimap addon's does) for [member rotate_minimap] to reach it.

static var _cached: PlayerSettingsResource ## One shared instance so every menu edits and saves the same settings.

# Audio Settings
@export var dialog_volume: float = 50.0
@export var menu_volume: float = 50.0
@export var music_volume: float = 50.0
@export var sfx_volume: float = 50.0
@export var voice_volume: float = 50.0 ## Steam voice chat playback; local like the other volumes.
@export var voice_muted: bool = false ## Mutes the Voice bus on this machine only.
@export var voice_activation: bool = false ## Transmit whenever you speak, instead of holding the push-to-talk key. The only way to use voice chat on a pad, since the Zelda layout leaves no button free for it.
@export var voice_sensitivity: float = 100.0 ## How readily the microphone reads as speaking, as a percentage where 100 is a normal voice. Microphones differ by more than any built-in default can cover, so this is set by talking and watching the meter rather than guessed.

# Video Settings
@export var vsync_enabled: bool = true
@export var msaa_index: int = 0
@export var ssaa_index: int = 0 ## Bilinear supersampling; mutually exclusive with [member fsr_index].
@export var fxaa_enabled: bool = false
@export var ssrl_enabled: bool = false
@export var taa_enabled: bool = false
@export var fsr_index: int = 0 ## [enum Viewport.Scaling3DMode] index; mutually exclusive with [member ssaa_index].
@export var toon_mode: int = 0 ## [enum ToonFilter.Mode] of the [ToonFilter] under the Player's camera; local to this machine like the rest.
@export var rotate_minimap: bool = false ## Turn the game's minimap with the Player rather than keeping north up. Handed to every node in [constant MINIMAP_GROUP] as its [code]rotate_with_target[/code], so this addon needs no minimap of its own and a game without one never sees the setting.

# Chat Settings
@export var chat_rect: Rect2 = Rect2() ## Where the [ChatWindow] sits and how big it is; zero size means bottom-left at the default size.

# UI Settings
const UI_SCALES: Array[float] = [0.0, 1.0, 1.25, 1.5, 2.0] ## Indexed by [member ui_scale_index]; 0 is Auto.
const UI_DESIGN_HEIGHT: float = 800.0 ## The window's shorter side the menus were laid out for; Auto scales from it.
enum HudMode { AUTO, SHOWN, HIDDEN } ## Auto shows the on-screen controls on touch only.
@export var ui_scale_index: int = 0 ## Index into [constant UI_SCALES]; scales the game's whole UI through the window's content_scale_factor.
@export var hud_mode: int = HudMode.AUTO ## Whether the Player's on-screen controls ([member Player.controls]) are drawn; a [enum HudMode].

# Controls Settings
## The [member ControlScheme.scheme_name] of the layout the player picked, or empty to keep whatever the scene
## set on [member Player.control_scheme]. A name nothing answers to falls back the same way, which is what a
## settings file written before a layout was renamed or uninstalled does.
@export var control_scheme_name: String = ""

var _scaled_window: Window ## The window Auto follows on resize, connected once.


## Migrates a settings file saved before [member toon_mode]: toon_enabled = true was the Newspaper look.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"toon_enabled":
		toon_mode = TOON_NEWSPAPER if value else 0
		return true
	return false


## Returns the shared settings instance, loading it from disk the first time.
## Puts the controls back to the defaults a new game starts on: the scene's own layout (Tears of the Kingdom in
## the addon) and the on-screen controls on Auto. A game calls it on New Game, so a layout or HUD mode picked in
## an earlier game does not carry in; Continue keeps them.
func reset_controls() -> void:
	control_scheme_name = ""
	hud_mode = HudMode.AUTO


static func load_or_create() -> PlayerSettingsResource:
	if _cached == null:
		if ResourceLoader.exists(SAVE_PATH):
			_cached = ResourceLoader.load(SAVE_PATH) as PlayerSettingsResource
		if _cached == null:
			_cached = PlayerSettingsResource.new()
	return _cached


func save() -> void:
	_cached = self
	ResourceSaver.save(self, SAVE_PATH)


func apply_audio_settings(player: Player = null) -> void:
	set_bus_volume(&"Dialog", dialog_volume)
	set_bus_volume(&"Menu", menu_volume)
	set_bus_volume(&"Music", music_volume)
	set_bus_volume(&"SFX", sfx_volume)
	set_bus_volume(&"Voice", voice_volume)
	set_bus_mute(&"Voice", voice_muted)
	if player:
		player.update_sfx_volume(sfx_volume)
		player.update_music_volume(music_volume)


static func set_bus_volume(bus_name: StringName, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value / 100.0) if value > 0.0 else -80.0)


static func set_bus_mute(bus_name: StringName, muted: bool) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_mute(bus_index, muted)


func apply_video_settings(viewport: Viewport) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	viewport.msaa_3d = MSAA_VALUES[clampi(msaa_index, 0, MSAA_VALUES.size() - 1)]
	# SSAA and FSR are mutually exclusive: fsr_index 0 is bilinear scaling, which is where the SSAA scale applies.
	viewport.scaling_3d_mode = fsr_index as Viewport.Scaling3DMode
	viewport.scaling_3d_scale = SSAA_SCALES[clampi(ssaa_index, 0, SSAA_SCALES.size() - 1)] if fsr_index == 0 else 1.0
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa_enabled else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.screen_space_roughness_limiter_set_active(ssrl_enabled, 0.25, 0.18)
	viewport.use_taa = taa_enabled
	apply_ui_scale(viewport.get_window())
	apply_minimap(viewport.get_tree())


## Hands [member rotate_minimap] to every minimap in [param tree] (the nodes in [constant MINIMAP_GROUP]).
func apply_minimap(tree: SceneTree) -> void:
	if tree != null:
		tree.call_group(MINIMAP_GROUP, &"set", &"rotate_with_target", rotate_minimap)


## The factor for a window of [param window_size]: the chosen one, or on Auto the shorter side over
## [constant UI_DESIGN_HEIGHT], never below 1 so a small window keeps the menus at their drawn size.
func ui_scale_for(window_size: Vector2i) -> float:
	var chosen: float = UI_SCALES[clampi(ui_scale_index, 0, UI_SCALES.size() - 1)]
	if chosen > 0.0:
		return chosen
	return clampf(minf(window_size.x, window_size.y) / UI_DESIGN_HEIGHT, 1.0, 4.0)


## Scales everything drawn in [param window] through its content_scale_factor, the one lever that works whatever
## the project's stretch mode is, and keeps following the window's size while Auto is chosen. The on-screen
## controls are not affected: the controls addon measures its buttons through the final transform, so they keep
## their share of the screen whatever the menus are scaled to.
func apply_ui_scale(window: Window) -> void:
	if window == null:
		return
	if _scaled_window != window:
		_scaled_window = window
		window.size_changed.connect(_on_window_resized)
	var factor: float = ui_scale_for(window.size)
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor


func _on_window_resized() -> void:
	if is_instance_valid(_scaled_window):
		apply_ui_scale(_scaled_window)


## Whether the on-screen controls are drawn for a player on [param input_type] (a [enum Controls.InputType]) with
## [param touchscreen] saying whether the machine has one: the HUD starts out as touch before any event arrives,
## and on Auto a desktop should not flash the buttons until the first key is pressed.
func hud_shown(input_type: int, touchscreen: bool) -> bool:
	return hud_shown_for(hud_mode, input_type, touchscreen)


## [method hud_shown] for any [param mode], for a Player overriding the saved one ([member Player.hud_mode_override]).
static func hud_shown_for(mode: int, input_type: int, touchscreen: bool) -> bool:
	match mode:
		HudMode.SHOWN:
			return true
		HudMode.HIDDEN:
			return false
	return input_type == Controls.InputType.TOUCH and touchscreen


## The layout the player picked, or null when nothing is saved and for a name nothing answers to.
func picked_scheme() -> ControlScheme:
	return PlayerControls.scheme_named(control_scheme_name)


## Puts the picked control scheme on [param player]; Game Default leaves the scene's choice alone.
func apply_control_scheme(player: Player) -> void:
	var scheme: ControlScheme = picked_scheme()
	if player and scheme:
		player.control_scheme = scheme


func apply_all(viewport: Viewport, player: Player = null) -> void:
	apply_audio_settings(player)
	if viewport:
		apply_video_settings(viewport)
	if player:
		apply_control_scheme(player)
		player.apply_hud_visibility()
