extends GutTest

## Purpose: every animation still holds the pose it was last given, rather than the raw Mixamo
## capture the importer would put back.
##
## An animation imported with Save to File leaves a .tres next to its .glb that looks generated.
## Some of them were not. The %GeneralSkeleton:Hips position track in each swim animation is offset
## by hand to sit the body at the waterline, between 0.298 and 0.4 metres, and Driving's LowerLeg
## curves were collapsed to straighten the leg so the foot stopped poking through the floor of the
## CRV.
##
## That work was lost twice. Set to 1.2, back to the raw 0.69952834; set to 1.0995283, back to
## 0.69952834 again. The player swam 0.65 m under instead of 0.25 m, invisible from the ordinary
## camera. The cause is the importer, and it is worth being exact about how it was pinned down,
## because the obvious experiment says the opposite. Re-importing a small project holding just the
## .glb, its .import and the .tres leaves the file alone, even with a cold .godot cache, after a
## move, with a stale uid and with importer_version bumped. Cloning this repository fresh and
## importing it wipes them on the first pass. Neither keep_custom_tracks nor marking a track
## imported = false saves an imported track, and an import_script runs with the right offsets but too late, after
## the resource has already been written.
##
## So every animation resource was taken out of the import pipeline. All 29 live under tuned/ as
## hand-owned AnimationLibrary resources, no .glb has save_to_file enabled any more, every track in
## them is marked imported = false, and an importer that does not own a file cannot rewrite it.
## Verified on a fresh clone: a cold import of 1640 files changed nothing under tuned/ and recreated
## no .tres.
##
## The table covers every animation rather than the ones that were noticed, because whatever wipes
## one wipes its neighbours in the same pass. Judge a diff here by magnitude, not by its existence.
## The restructure that reverted the swim heights also rewrote 16 other animations, every one a
## rotation difference of about 1e-7 from a re-export, with no position change at all.

## Where the .glb files and their import settings live. No .tres belongs here any more.
const ANIMATIONS_PATH: String = "res://addons/3d_player_controller/assets/mixamo/animations/root_motion"

## The hand-owned resources, which is what stops a cold import rewriting them. Each holds one
## animation, named as the .glb's was so player.tscn's "Swimming/mixamo_com" still resolves.
const TUNED_PATH: String = "res://addons/3d_player_controller/assets/mixamo/animations/tuned"

const TUNED_ANIMATION: StringName = &"mixamo_com"

const HIPS_TRACK: String = "%GeneralSkeleton:Hips"

## The Hips position track of every animation, as [first key, lowest, highest]. All 29 are
## hand-owned now, so this one table covers the lot. An empty array records that the animation has
## no such track, which most of the jumps do not, carrying their lift on Root instead.
##
## Lowest and highest are not decoration. Entering Car's hand edit sank the dip as the driver sits
## into the seat from 0.842 to 0.742 and never touched the first key, so a first-key check watched it
## get reverted three times and said nothing.
const EXPECTED_TUNED: Dictionary = {
	"Backflip": [0.9305699, 0.6450410, 1.3755330],
	"Bow Standing Aim Idle 01": [0.9323989, 0.9300874, 0.9374508],
	"Bow Standing Idle 01": [0.9057015, 0.8958216, 0.9057016],
	"Bow Standing Jump Running To Run Forward": [0.8787579, 0.8170261, 1.2609407],
	"Bow Standing Jumping": [0.9059604, 0.6815044, 1.2559845],
	"Boxing Idle": [0.8539546, 0.8533829, 0.9244993],
	"Crouching Idle": [0.5100191, 0.5084273, 0.5100191],
	"Driving": [0.6188195, 0.6188195, 0.6188195],
	"Entering Car": [0.9920238, 0.7420000, 1.0130469],
	"Fishing Idle": [0.9840188, 0.9840188, 0.9840188],
	"Great Sword Idle": [0.9484802, 0.9484802, 0.9508491],
	"Great Sword Jump": [0.9484800, 0.9053215, 1.3391531],
	"Great Sword Jump Attack": [0.9468914, 0.8564712, 1.1684833],
	"Great Sword Jump Forward": [0.9468913, 0.9468912, 1.1508582],
	"Idle": [0.9920238, 0.9920238, 0.9920238],
	"Jump": [0.8938875, 0.7940333, 1.4365578],
	"Jumping Up": [0.9305623, 0.5556197, 1.4869212],
	"Mutant Breathing Idle": [0.8775857, 0.8775857, 0.8881663],
	"Pistol Aimed Idle": [0.9525013, 0.9486916, 0.9541759],
	"Pistol Jump": [0.9525008, 0.5582689, 1.3935983],
	"Pistol Jump Forward": [0.9157895, 0.8392248, 1.3117052],
	"Ready To Cast Spell Standing Idle": [0.8914642, 0.8442172, 0.8951364],
	"Rifle Aiming Jump": [0.9153314, 0.7656575, 1.0098870],
	"Rifle Aiming Standing Idle": [0.9612249, 0.9612249, 0.9633280],
	"Rifle Jump Backward": [0.9331605, 0.9039738, 1.0851871],
	"Rifle Jump Forward": [0.8126116, 0.7970697, 1.2510505],
	"Rifle Jump Up": [0.9398913, 0.6895890, 0.9398913],
	"Rifle Standing Idle": [0.9398697, 0.9332166, 0.9398697],
	"Running": [0.9219201, 0.9032632, 0.9703432],
	"Running Forward Flip": [0.9208747, 0.7412975, 1.7819712],
	"Running Jump": [0.8596953, 0.8596953, 1.3047173],
	"Running Slide": [0.9207888, 0.2397544, 0.9444287],
	"Sprint": [0.8830373, 0.8738528, 0.9565051],
	"Swimming": [1.0995283, 1.0838133, 1.1031445],
	"Swimming At Edge": [1.2018158, 1.1959828, 1.2044084],
	"Swimming To Edge": [1.1010405, 1.0896482, 1.1420684],
	"Sword And Shield Block Idle": [0.7323731, 0.7323730, 0.7361287],
	"Sword And Shield Idle": [0.8496349, 0.8496348, 0.8578424],
	"Sword And Shield Jump Attack": [0.9028425, 0.3710695, 1.7480969],
	"Sword and Shield Jump": [0.8496348, 0.8051223, 1.3529737],
	"Sword and Shield Jump Forward": [0.9019135, 0.9019135, 1.5937138],
	"Throw": [0.9800626, 0.9555750, 1.0105404],
}

## Total keys across every 3D track, per animation. The Hips figures above say where the body sits;
## this says whether the curves are still the shape someone left them.
##
## Driving is why it is here. Its hand edit collapsed the two LowerLeg rotation tracks from 10 and 47
## keys to 2 each, straightening the leg so the foot stopped poking through the floor of the CRV. No
## height moved, so a Hips check saw nothing, and the revert went unnoticed for months. A key count
## cannot drift on its own: a re-export rounds values, it does not add or remove keys.
const EXPECTED_KEYS: Dictionary = {
	"Backflip": 2849,
	"Bow Standing Aim Idle 01": 1691,
	"Bow Standing Idle 01": 2898,
	"Bow Standing Jump Running To Run Forward": 2086,
	"Bow Standing Jumping": 1715,
	"Boxing Idle": 1621,
	"Crouching Idle": 1153,
	"Driving": 1392,
	"Entering Car": 6159,
	"Fishing Idle": 862,
	"Great Sword Idle": 595,
	"Great Sword Jump": 693,
	"Great Sword Jump Attack": 1866,
	"Great Sword Jump Forward": 524,
	"Idle": 859,
	"Jump": 1494,
	"Jumping Up": 1167,
	"Mutant Breathing Idle": 1695,
	"Pistol Aimed Idle": 500,
	"Pistol Jump": 1446,
	"Pistol Jump Forward": 614,
	"Ready To Cast Spell Standing Idle": 2694,
	"Rifle Aiming Jump": 1969,
	"Rifle Aiming Standing Idle": 508,
	"Rifle Jump Backward": 889,
	"Rifle Jump Forward": 1250,
	"Rifle Jump Up": 446,
	"Rifle Standing Idle": 693,
	"Running": 883,
	"Running Forward Flip": 1335,
	"Running Jump": 1518,
	"Running Slide": 2038,
	"Sprint": 765,
	"Swimming": 5799,
	"Swimming At Edge": 978,
	"Swimming To Edge": 3358,
	"Sword And Shield Block Idle": 816,
	"Sword And Shield Idle": 1447,
	"Sword And Shield Jump Attack": 2488,
	"Sword and Shield Jump": 1014,
	"Sword and Shield Jump Forward": 664,
	"Throw": 2561,
}

## The standing idles, flattened: their Root keeps its height but no longer sways sideways, since movement is root
## motion and an idle should not carry the Player anywhere.
const STANDING_IDLES: PackedStringArray = [
	"Boxing Idle", "Bow Standing Aim Idle 01", "Bow Standing Idle 01", "Crouching Idle", "Fishing Idle",
	"Great Sword Idle", "Idle", "Mutant Breathing Idle", "Pistol Aimed Idle", "Ready To Cast Spell Standing Idle",
	"Rifle Aiming Standing Idle", "Rifle Standing Idle", "Sword And Shield Block Idle", "Sword And Shield Idle",
]

## Loose enough to survive a re-save rounding the float, tight enough that a raw capture fails: the
## smallest offset being guarded is 0.298.
const TOLERANCE: float = 0.001

## The most any swim key rides from the first. The real stroke bobs by 0.041 at most.
const MAXIMUM_SWIM_BOB: float = 0.15


func test_the_importer_owns_no_animation_resource_any_more() -> void:
	# The whole fix in one assertion. A .tres beside the .glb files is importer output, and a cold
	# import rewrites importer output from the capture, discarding whatever was tuned by hand.
	assert_eq(
		_names_in(ANIMATIONS_PATH),
		PackedStringArray(),
		"A .tres has reappeared beside the .glb files. Move it to tuned/ and turn save_to_file off."
	)


func test_tuned_holds_exactly_the_animations_this_test_knows_about() -> void:
	# Otherwise a new animation could be added, never be checked, and be wiped in the same silence.
	assert_eq(_names_in(TUNED_PATH), _sorted_keys(EXPECTED_TUNED), "Update EXPECTED_TUNED.")


func test_no_glb_is_configured_to_write_an_animation_resource() -> void:
	# Godot writes a .tres only for a .glb whose import has save_to_file enabled, so that setting is
	# what would put these files back under the importer's control.
	var enabled: PackedStringArray = []
	for file: String in _import_files():
		if FileAccess.get_file_as_string(file).contains("\"save_to_file/enabled\": true"):
			enabled.append(file.get_file())
	assert_eq(enabled, PackedStringArray(), "save_to_file is back on; these .glb files would overwrite a .tres.")


func test_every_hand_owned_glb_keeps_custom_tracks_if_save_to_file_ever_returns() -> void:
	# Belt and braces for the setting above, over the 29 animations that have a .tres to protect.
	# keep_custom_tracks cannot save an imported track, but it does preserve the method tracks that
	# call execute_jump, which exist in no .glb at all. The other imports write nothing and have
	# nothing to keep, so they are left alone rather than churned.
	var wrong: PackedStringArray = []
	for file: String in _hand_owned_import_files():
		if not FileAccess.get_file_as_string(file).contains("\"save_to_file/keep_custom_tracks\": true"):
			wrong.append(file.get_file())
	assert_eq(wrong, PackedStringArray(), "keep_custom_tracks is not true for these.")


func test_no_hand_owned_track_is_still_marked_imported() -> void:
	# An imported track is one the importer claims, and keep_custom_tracks does not protect it. These
	# resources are hand-owned now, so nothing in them should say otherwise.
	var claimed: PackedStringArray = []
	for name: String in EXPECTED_TUNED:
		if FileAccess.get_file_as_string("%s/%s.tres" % [TUNED_PATH, name]).contains("imported = true"):
			claimed.append(name)
	assert_eq(claimed, PackedStringArray(), "These still carry tracks marked imported = true.")


func test_every_hand_owned_animation_keeps_its_hips_track() -> void:
	for name: String in EXPECTED_TUNED:
		_check(_tuned(name), name, EXPECTED_TUNED[name])


func test_no_hand_owned_animation_is_importer_output_any_more() -> void:
	# The whole point of tuned/: an importer that does not own a file cannot rewrite it. A .tres
	# reappearing beside the .glb means save_to_file came back on and the edit is at risk again.
	for name: String in EXPECTED_TUNED:
		assert_false(
			ResourceLoader.exists("%s/%s.tres" % [ANIMATIONS_PATH, name]),
			"%s is importer output again; a cold import will overwrite it" % name
		)


func test_the_swim_offsets_are_on_the_whole_track_and_not_one_key() -> void:
	# The offset is applied to the track, so every key moves together and the body keeps its bob.
	# Offsetting key zero alone would satisfy the test above and still swim wrong for the rest of
	# the loop, with the remaining keys stranded a full offset away.
	for name: String in EXPECTED_TUNED:
		if not name.begins_with("Swimming"):
			continue  # Only the swim clips hold the body flat; everything else here dips or leaps.
		var animation: Animation = _tuned(name)
		if animation == null:
			continue
		var track: int = _hips_position_track(animation)
		assert_gt(track, -1, "%s should still animate %s" % [name, HIPS_TRACK])
		if track < 0:
			continue

		var first: float = (animation.track_get_key_value(track, 0) as Vector3).y
		var furthest: float = 0.0
		for key: int in animation.track_get_key_count(track):
			var height: float = (animation.track_get_key_value(track, key) as Vector3).y
			furthest = maxf(furthest, absf(height - first))

		assert_lt(
			furthest,
			MAXIMUM_SWIM_BOB,
			"%s has a key %f from its first. The offset belongs on the whole track, not one key." % [name, furthest]
		)


## The one animation inside a hand-owned library under tuned/.
func _tuned(name: String) -> Animation:
	var library: AnimationLibrary = load("%s/%s.tres" % [TUNED_PATH, name]) as AnimationLibrary
	return library.get_animation(TUNED_ANIMATION) if library != null else null


func _hips_position_track(animation: Animation) -> int:
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if str(animation.track_get_path(track)) == HIPS_TRACK:
			return track
	return -1


func test_no_animation_has_gained_or_lost_keys() -> void:
	for name: String in EXPECTED_KEYS:
		var animation: Animation = _tuned(name)
		assert_not_null(animation, "%s should load" % name)
		if animation == null:
			continue
		var total: int = 0
		for track: int in animation.get_track_count():
			var type: int = animation.track_get_type(track)
			if type == Animation.TYPE_POSITION_3D or type == Animation.TYPE_ROTATION_3D \
					or type == Animation.TYPE_SCALE_3D:
				total += animation.track_get_key_count(track)
		assert_eq(
			total,
			int(EXPECTED_KEYS[name]),
			"%s has %d keys rather than %d. A re-export rounds values, it never adds or removes keys, so a curve was reshaped or a reshape was reverted." % [
				name, total, EXPECTED_KEYS[name],
			]
		)


## Checks a Hips track against [first, lowest, highest]; an empty expectation means no track at all.
func _check(animation: Animation, name: String, expected: Array) -> void:
	assert_not_null(animation, "%s should load" % name)
	if animation == null:
		return
	var track: int = _hips_position_track(animation)
	if expected.is_empty():
		assert_eq(track, -1, "%s has gained a %s track; record it" % [name, HIPS_TRACK])
		return
	assert_gt(track, -1, "%s has lost its %s track entirely" % [name, HIPS_TRACK])
	if track < 0:
		return

	var first: float = (animation.track_get_key_value(track, 0) as Vector3).y
	var lowest: float = INF
	var highest: float = -INF
	for key: int in animation.track_get_key_count(track):
		var y: float = (animation.track_get_key_value(track, key) as Vector3).y
		lowest = minf(lowest, y)
		highest = maxf(highest, y)

	var label: String = "%s [first %f, lowest %f, highest %f] against [%f, %f, %f]" % [
		name, first, lowest, highest, expected[0], expected[1], expected[2],
	]
	assert_almost_eq(first, float(expected[0]), TOLERANCE, label)
	assert_almost_eq(lowest, float(expected[1]), TOLERANCE, label)
	assert_almost_eq(highest, float(expected[2]), TOLERANCE, label)


func _sorted_keys(table: Dictionary) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(table.keys())
	names.sort()
	return names


func _names_in(folder: String) -> PackedStringArray:
	var names: PackedStringArray = []
	var directory := DirAccess.open(folder)
	if directory == null:
		return names
	directory.list_dir_begin()
	var file: String = directory.get_next()
	while file != "":
		if not directory.current_is_dir() and file.ends_with(".tres"):
			names.append(file.trim_suffix(".tres"))
		file = directory.get_next()
	directory.list_dir_end()
	names.sort()
	return names


## Every .glb.import beside the animations, which is where save_to_file lives.
func _import_files() -> PackedStringArray:
	var files: PackedStringArray = []
	var directory := DirAccess.open(ANIMATIONS_PATH)
	if directory == null:
		return files
	directory.list_dir_begin()
	var file: String = directory.get_next()
	while file != "":
		if not directory.current_is_dir() and file.ends_with(".glb.import"):
			files.append("%s/%s" % [ANIMATIONS_PATH, file])
		file = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files


## The .glb.import files belonging to the hand-owned animations. Most are named after the animation,
## but the flip's .glb spells it "Foward", so the recorded fallback path is checked first.
func _hand_owned_import_files() -> PackedStringArray:
	var owned: PackedStringArray = []
	for file: String in _import_files():
		var text: String = FileAccess.get_file_as_string(file)
		var claimed: bool = false
		for name: String in EXPECTED_TUNED:
			if text.contains("/%s.tres\"" % name) or file.get_file() == "%s.glb.import" % name:
				claimed = true
				break
		if claimed:
			owned.append(file)
	return owned


func test_no_standing_idle_moves_the_player() -> void:
	for name: String in STANDING_IDLES:
		var animation: Animation = _tuned(name)
		assert_not_null(animation, "%s is hand-owned in tuned/" % name)
		if animation == null:
			continue
		var root: int = animation.find_track(NodePath("%GeneralSkeleton:Root"), Animation.TYPE_POSITION_3D)
		assert_gte(root, 0, "%s has its Root track" % name)
		if root < 0:
			continue
		var first: Vector3 = animation.track_get_key_value(root, 0)
		var sway: float = 0.0
		for k: int in animation.track_get_key_count(root):
			var v: Vector3 = animation.track_get_key_value(root, k)
			sway = maxf(sway, Vector2(v.x - first.x, v.z - first.z).length())
		assert_lt(sway, 0.0001, "%s's Root does not sway sideways, so an idle Player stays where it stands" % name)
