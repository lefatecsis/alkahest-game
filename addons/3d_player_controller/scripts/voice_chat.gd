class_name VoiceChat
extends Node
## Steam voice for the [Player] above it: push-to-talk (the "broadcast" action) or voice activation captures the
## microphone on the owning peer, measures how loudly they are speaking ([member voice_loudness], which
## [PlayerNoise] counts as noise), and sends it to the other peers, whose copy plays it through
## [member audio_player] where this Player stands. Steam is optional: without a Steamworks session nothing is
## captured or sent, and the indicator still follows the key.

const VOICE_FALLOFF_PER_SECOND: float = 2.5 ## How fast [member voice_loudness] falls once the talk key is let go.
const VOICE_FULL_BYTES: float = 900.0 ## Compressed bytes in one frame's worth of voice that counts as speaking at full volume. Measured packets ran from about 186 to 8202 bytes.
const VOICE_RISE_PER_SECOND: float = 6.0 ## How fast the reading comes up once Steam starts sending voice.
const VOICE_ACTIVATION_LEVEL: float = 0.6 ## How loud counts as speaking while voice activation is on. It is the mark on the microphone bar, so "drag until an ordinary voice reaches the mark" and "reaching the mark transmits" are the same instruction.
const STEAM_VOICE_RESULT_OK: int = 0 ## Mirrors Steam.VOICE_RESULT_OK (Steam class is absent on web exports).

@export var player: Player ## Whose voice this is; its pause, chat and ragdoll gates hold the talk key like any other action.
@export var indicator: MeshInstance3D ## The mark over the head while this Player is talking.
@export var audio_player: AudioStreamPlayer3D ## Plays this Player's incoming voice, positioned where they stand.

var voice_playback: AudioStreamGeneratorPlayback = null
var is_broadcasting: bool = false
var voice_loudness: float = 0.0 ## How loudly this Player is speaking on push-to-talk, 0 to 1, measured from the captured voice rather than from the fact of holding the key. [PlayerNoise] treats it as noise, so talking gives you away.
var _recording: bool = false ## Whether Steam is capturing, which is not the same as transmitting: voice activation listens continuously and decides per packet.


## Only the owning peer listens to its microphone and its talk key; every copy can play voice that arrives.
func _ready() -> void:
	set_process(is_multiplayer_authority())
	set_process_unhandled_input(is_multiplayer_authority())
	if not is_multiplayer_authority() or audio_player == null:
		return
	var generator: AudioStreamGenerator = audio_player.stream as AudioStreamGenerator
	var steam: Object = SteamPeer.session(self)
	if generator and steam:
		var optimal_rate: int = steam.getVoiceOptimalSampleRate()
		if optimal_rate > 0:
			generator.mix_rate = float(optimal_rate)
	if not audio_player.playing:
		audio_player.play()
	voice_playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback


## Push-to-talk voice broadcasting (action="broadcast", key="V"). Only the press is held back while paused, typing
## or ragdolling: a release always closes the channel, or letting go behind a menu would leave the mic open.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released(&"broadcast"):
		stop_broadcasting()
	elif event.is_action_pressed(&"broadcast") and not (player and (player.is_paused or player.is_typing or player.is_ragdolling)):
		start_broadcasting()


## Wired to Chat.typing_changed. The chat row is a Window of its own, so a talk key let go while typing never
## reaches this node; opening the row closes the channel instead.
func _on_chat_typing_changed(typing: bool) -> void:
	if typing:
		stop_broadcasting()


## Captures and sends the voice while the channel is open or voice activation is listening.
func _process(delta: float) -> void:
	var listening: bool = is_broadcasting or voice_activation_enabled()
	# Looked up while capture is on too, so the frame the channel closes can turn Steam's capture off; left on, it
	# buffers everything said with the key up and sends it on the next press
	var steam: Object = SteamPeer.session(self) if listening or _recording else null
	_set_recording(steam, listening)
	var packet_arrived: bool = false
	if steam and listening:
		var available_voice: Dictionary = steam.getAvailableVoice()
		# GodotSteam returns "size" here, not "written". Reading the wrong key meant this was always 0, so the
		# capture below never ran and push-to-talk sent nothing at all.
		if available_voice.get("result") == STEAM_VOICE_RESULT_OK and available_voice.get("size", 0) > 0:
			var voice_data: Dictionary = steam.getVoice()
			if voice_data.get("result") == STEAM_VOICE_RESULT_OK:
				var buffer: PackedByteArray = voice_data.get("buffer", PackedByteArray())
				if not buffer.is_empty():
					packet_arrived = true
					# Rise rather than snap, so a burst of speech does not make the meter flicker
					var heard: float = loudness_of(int(available_voice.get("size", 0)), voice_full_bytes())
					voice_loudness = minf(voice_loudness + delta * VOICE_RISE_PER_SECOND, heard) if heard > voice_loudness else heard
					if is_broadcasting and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
						_receive_voice_packet.rpc(buffer)
	if not packet_arrived and voice_loudness > 0.0:
		# Falls away whenever no voice arrived this frame, which covers letting the key go, holding it while
		# saying nothing, and Steam being there but sending nothing. Steam goes quiet during a pause, so a held
		# key in silence reads as silence. Keyed off the packet rather than off Steam being absent: as an elif
		# on the branch above, a running Steam client with nothing to say held the last reading forever.
		voice_loudness = maxf(voice_loudness - delta * VOICE_FALLOFF_PER_SECOND, 0.0)
	if voice_activation_enabled():
		# Speaking past the mark opens the channel, and falling back under it closes it
		var speaking: bool = voice_loudness >= VOICE_ACTIVATION_LEVEL
		if speaking != is_broadcasting:
			_set_transmitting(speaking)


## Whether this Player transmits by speaking rather than by holding the key. A pad player has no choice: the
## Zelda layout binds every usable button, so there is none left for push-to-talk.
func voice_activation_enabled() -> bool:
	return PlayerSettingsResource.load_or_create().voice_activation


## Turns Steam's capture on or off, which is not the same as transmitting. Voice activation has to listen the
## whole time to know when you have started speaking, and Steam's own voice detection means listening costs
## nothing while the room is quiet: it simply sends no packets.
func _set_recording(steam: Object, on: bool) -> void:
	if steam == null or on == _recording:
		return
	_recording = on
	if on:
		steam.startVoiceRecording()
	else:
		steam.stopVoiceRecording()


## Opens or closes the channel: the indicator, Steam's own speaking flag and the peers all follow this.
func _set_transmitting(on: bool) -> void:
	if is_broadcasting == on:
		return
	is_broadcasting = on
	if indicator:
		indicator.visible = on
	var steam: Object = SteamPeer.session(self)
	if steam:
		var my_id: int = steam.getSteamID()
		if my_id > 0:
			steam.setInGameVoiceSpeaking(my_id, on)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_set_voice_indicator.rpc(on)


## Start push-to-talk voice broadcasting. Holding the key still works with voice activation on, so a player who
## wants to be certain they are heard can take the decision off the meter.
func start_broadcasting() -> void:
	_set_recording(SteamPeer.session(self), true)
	_set_transmitting(true)


## Stop push-to-talk voice broadcasting. The capture is left alone: voice activation may still be listening,
## and _process turns it off when nothing is.
func stop_broadcasting() -> void:
	_set_transmitting(false)


## The bytes that count as a full-voice frame on this machine, from the microphone sensitivity set in Audio
## settings. A quieter microphone needs fewer bytes to mean the same thing, so a higher sensitivity lowers the
## bar. Microphones differ by more than any built-in default can cover, which is why this is a setting the
## player calibrates by talking rather than a number guessed here.
func voice_full_bytes() -> float:
	var sensitivity: float = PlayerSettingsResource.load_or_create().voice_sensitivity
	return VOICE_FULL_BYTES * (100.0 / maxf(sensitivity, 1.0))


## How much voice [param available_bytes] of compressed Steam audio counts as, 0 to 1.
##
## Deliberately not an amplitude. Steam gates the microphone with its own voice-activity detection and
## normalises what it sends, so the samples inside a packet say almost nothing about how loudly you spoke:
## measured on a laptop, ten seconds of talking and eight seconds of silence came back with the same peak
## level, 0.0233 against 0.0246. What separates them is whether Steam sends anything at all, 165 packets
## against 10, and how much. So the reading follows the flow of voice rather than its waveform.
static func loudness_of(available_bytes: int, full_bytes: float = VOICE_FULL_BYTES) -> float:
	if available_bytes <= 0:
		return 0.0
	return clampf(float(available_bytes) / maxf(full_bytes, 1.0), 0.0, 1.0)


## Voice from the owning peer, decoded into this copy's 3D player; only the authority ever sends it.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_voice_packet(compressed_buffer: PackedByteArray) -> void:
	var steam: Object = SteamPeer.session(self)
	if steam == null or compressed_buffer.is_empty():
		return
	var sample_rate: int = steam.getVoiceOptimalSampleRate()
	if sample_rate <= 0:
		sample_rate = 48000
	var decompressed: Dictionary = steam.decompressVoice(compressed_buffer, sample_rate)
	if decompressed.get("result") == STEAM_VOICE_RESULT_OK:
		var uncompressed: PackedByteArray = decompressed.get("uncompressed", PackedByteArray())
		if uncompressed.is_empty():
			return
		if voice_playback == null and audio_player:
			if not audio_player.playing:
				audio_player.play()
			voice_playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if voice_playback:
			var sample_count: int = uncompressed.size() / 2
			var frames: PackedVector2Array = PackedVector2Array()
			frames.resize(sample_count)
			for i: int in range(sample_count):
				var sample_val: float = float(uncompressed.decode_s16(i * 2)) / 32768.0
				frames[i] = Vector2(sample_val, sample_val)
			var frames_available: int = voice_playback.get_frames_available()
			if frames.size() > frames_available:
				frames = frames.slice(0, frames_available)
			if not frames.is_empty():
				voice_playback.push_buffer(frames)


## The speaking indicator over this copy's head; only the authority ever sends it.
@rpc("authority", "call_remote", "reliable")
func _set_voice_indicator(is_speaking: bool) -> void:
	if indicator:
		indicator.visible = is_speaking
