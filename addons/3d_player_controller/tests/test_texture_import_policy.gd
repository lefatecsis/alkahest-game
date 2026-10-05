extends GutTest

## Purpose: no texture in this project is imported as Lossy, and the project-wide importer defaults
## are the ones Godot itself would use.
##
## The project used to force compress/mode=1 (Lossy) on every texture with detect_3d/compress_to=0
## so nothing was ever promoted, which was how built .pck files were squeezed under GitHub's 100 MB
## limit. Lossy re-encodes through WebP at quality 0.7 before Godot ever sees the image, so normal
## maps and ORM masks lost real data, and it uploads to VRAM uncompressed anyway, so it bought
## nothing at run time. Nothing built is committed now, so the limit does not apply, and
## tools/web_texture_cap.py caps the web build alone.
##
## This is the guard that stops the rule coming back: tools/texture_import_policy.py puts it right,
## and this fails if anything drifts off it.

const LOSSLESS: int = 0
const VRAM_COMPRESSED: int = 2
const DETECT_3D_VRAM_COMPRESSED: int = 1

## Addons pulled from their own repositories, which are fixed there rather than here.
var _vendored: PackedStringArray = []


func before_all() -> void:
	_vendored = _vendored_addon_paths()


func test_the_importer_defaults_are_lossless_full_size_and_promote_in_3d() -> void:
	var project := ConfigFile.new()
	assert_eq(project.load("res://project.godot"), OK, "project.godot should be readable")
	var texture: Dictionary = project.get_value("importer_defaults", "texture", {})

	# A project that overrides nothing is already on policy, because the policy is Godot's own
	# default. Only what it does override has to be checked, so each key falls back to the value
	# the engine would have used.
	assert_eq(int(texture.get(&"compress/mode", LOSSLESS)), LOSSLESS, "Textures import Lossless, not Lossy")
	assert_eq(
		int(texture.get(&"detect_3d/compress_to", DETECT_3D_VRAM_COMPRESSED)),
		DETECT_3D_VRAM_COMPRESSED,
		"and a texture the editor sees used in 3D is promoted to VRAM Compressed"
	)
	assert_eq(int(texture.get(&"process/size_limit", 0)), 0, "and nothing is capped on disk; the web build caps itself")


func test_no_texture_in_the_project_is_imported_as_lossy() -> void:
	var lossy: PackedStringArray = []
	for path: String in _import_files("res://"):
		var mode: int = _compress_mode(path)
		if mode != LOSSLESS and mode != VRAM_COMPRESSED and mode != -1:
			lossy.append(path)
	assert_eq(
		lossy.size(),
		0,
		"Every texture imports Lossless, or VRAM Compressed once detected in 3D. Off policy: %s" % ", ".join(lossy)
	)


## A Lossless texture still waiting to be seen in 3D must be allowed to become VRAM Compressed when it is; one set to
## never promote (the old detect_3d/compress_to=0) uploads to VRAM uncompressed for as long as it is used in 3D.
func test_every_lossless_texture_promotes_to_vram_compressed_in_3d() -> void:
	var stuck: PackedStringArray = []
	for path: String in _import_files("res://"):
		if _compress_mode(path) == LOSSLESS and _int_setting(path, "detect_3d/compress_to") != DETECT_3D_VRAM_COMPRESSED:
			stuck.append(path)
	assert_eq(stuck.size(), 0, "Lossless textures promote in 3D (detect_3d/compress_to=1). Off policy: %s" % ", ".join(stuck))


## Only a texture's own settings are the policy's business: an audio .import has a compress/mode too (a WAV's is
## its codec), and read as a texture's it once counted 154 sounds as VRAM textures.
func test_only_texture_imports_are_checked() -> void:
	var files: PackedStringArray = _import_files("res://")
	assert_gt(files.size(), 0, "The addon has textures to check")
	for path: String in files:
		assert_eq(_importer(path), "texture", "%s is a texture import" % path)
	var sounds: int = 0
	for path: String in _all_import_files("res://addons/3d_player_controller/assets"):
		if _importer(path) == "wav":
			sounds += 1
			assert_false(files.has(path), "%s is left out" % path)
	assert_gt(sounds, 0, "The addon has sounds that must be left out")


func test_no_committed_texture_carries_a_size_limit() -> void:
	var capped: PackedStringArray = []
	for path: String in _import_files("res://"):
		var limit: int = _int_setting(path, "process/size_limit")
		if limit > 0:
			capped.append("%s (%d)" % [path, limit])
	assert_eq(
		capped.size(),
		0,
		"Source textures keep their resolution; only the web build caps itself. Capped: %s" % ", ".join(capped)
	)


## Every texture's .import file in the project, skipping the addons that are pulled from elsewhere.
func _import_files(from: String) -> PackedStringArray:
	return PackedStringArray(Array(_all_import_files(from)).filter(func(path: String) -> bool: return _importer(path) == "texture"))


## Every .import file under [param from], whatever it imports, skipping the vendored addons.
func _all_import_files(from: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var directory := DirAccess.open(from)
	if directory == null:
		return found
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while name != "":
		var path: String = from.path_join(name)
		if directory.current_is_dir():
			if not name.begins_with(".") and not _vendored.has(path):
				found.append_array(_all_import_files(path))
		elif name.ends_with(".import"):
			found.append(path)
		name = directory.get_next()
	directory.list_dir_end()
	return found


## The [remap] section's importer ("texture", "wav", "scene" and so on).
func _importer(import_path: String) -> String:
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return ""
	return str(config.get_value("remap", "importer", ""))


func _compress_mode(import_path: String) -> int:
	return _int_setting(import_path, "compress/mode")


## An .import file is a ConfigFile whose [params] section holds the importer's settings.
func _int_setting(import_path: String, key: String) -> int:
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return -1
	if not config.has_section_key("params", key):
		return -1
	return int(config.get_value("params", key))


func _vendored_addon_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var file := FileAccess.open("res://tools/addons.json", FileAccess.READ)
	if file == null:
		return paths
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or not (parsed as Dictionary).has("addons"):
		return paths
	for addon: Variant in (parsed as Dictionary)["addons"]:
		paths.append("res://addons/%s" % (addon as Dictionary)["name"])
	return paths
