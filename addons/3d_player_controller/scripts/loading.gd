class_name Loading
extends CanvasLayer

var tips: Array[String] = [
	"Tip: Don't bother reading this, it's a waste of time.",
	"Tip: Press [Alt]+[F4] to rage quit!",
	"Tip: The loading bar is moving.",
	"Tip: If you get lost, just keep wandering around until something happens.",
	"Tip: Watching the loading bar makes it load slower.",
	"Tip: This tip was carefully selected at random.",
	"Tip: Loading screens are just the game's way of building suspense.",
	"Tip: Something is happening. I just don't know what.",
	"Tip: A tip was supposed to appear here.",
	"Tip: This space intentionally left without a tip.",
	"Tip: Everything is going according to plan.",
	"Tip: It's supposed to take this long.",
	"Tip: This was a tip until it wasn't.",
	"Tip: It's a tip, mabey.",
	"Tip: This tip was made by a child.",
	"Tip: you can go forever until you can't.",
	"Tip: Have you punched the ball yet?",
	"Tip: Does that bar mace you want to eat a chocolate bar?"
]

var _scene_path: String = ""
var _last_status: int = -1
var _load_started_at_msec: int = 0
var _dependency_paths: PackedStringArray = []
var _reported_dependency_paths: Dictionary[String, bool] = {}
var _cached_dependency_count: int = 0

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var tip: Label = $Tip
@onready var details: RichTextLabel = $Details


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process(false)


## Polls the threaded load while a request is in flight (ResourceLoader has no completion signal).
func _process(_delta: float) -> void:
	var progress: Array[float] = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			_scene_path,
			progress,
	)
	var progress_percent: int = roundi(progress[0] * 100.0) if not progress.is_empty() else 0
	progress_bar.value = progress_percent
	_report_newly_cached_dependencies()

	if status != _last_status:
		_append_detail("Status: %s" % _get_status_name(status))
		_last_status = status

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		progress_bar.value = 100
		_append_detail("Loading complete; changing scene to " + _scene_path)
		var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_scene_path)
		_scene_path = ""
		set_process(false)
		get_tree().change_scene_to_packed(packed_scene)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_append_detail("Error loading scene: " + _scene_path)
		push_error("Error loading scene: " + _scene_path)
		_scene_path = ""
		set_process(false)
		hide()


## Starts loading a scene from the given file path; ignored while another load is in flight.
func load_scene(path: String) -> void:
	if path.is_empty():
		push_error("[Loading] Target scene path is empty.")
		return
	if not _scene_path.is_empty():
		return

	_scene_path = path
	set_process(true)
	_last_status = -1
	_load_started_at_msec = Time.get_ticks_msec()
	tip.text = tips[randi() % tips.size()]
	details.clear()
	_prepare_dependency_tracking(path)
	show()
	progress_bar.value = 0
	_append_detail("Requesting " + path)
	var request_error: Error = ResourceLoader.load_threaded_request(path)
	_append_detail("Request result: " + error_string(request_error))


func _prepare_dependency_tracking(path: String) -> void:
	_dependency_paths.clear()
	_reported_dependency_paths.clear()
	_cached_dependency_count = 0
	for dependency: String in ResourceLoader.get_dependencies(path):
		var dependency_parts: PackedStringArray = dependency.split("::")
		var dependency_path: String = dependency_parts[dependency_parts.size() - 1]
		if not dependency_path.begins_with("res://"):
			continue
		_dependency_paths.append(dependency_path)
		if ResourceLoader.has_cached(dependency_path):
			_reported_dependency_paths[dependency_path] = true
			_cached_dependency_count += 1
	_append_detail(
		"Tracking %d direct dependencies; %d already cached"
		% [_dependency_paths.size(), _cached_dependency_count]
	)


func _report_newly_cached_dependencies() -> void:
	for dependency_path: String in _dependency_paths:
		if _reported_dependency_paths.has(dependency_path):
			continue
		if not ResourceLoader.has_cached(dependency_path):
			continue
		_reported_dependency_paths[dependency_path] = true
		_cached_dependency_count += 1
		_append_detail(
			"Dependency cached (%d/%d): %s"
			% [_cached_dependency_count, _dependency_paths.size(), dependency_path]
		)


## Adds a line to the on-screen log and prints it too, so a browser console (or a headless run) shows the load.
func _append_detail(message: String) -> void:
	var line: String = _get_log_prefix() + message
	details.append_text(line + "\n")
	print(line)


func _get_log_prefix() -> String:
	var elapsed_msec: int = Time.get_ticks_msec() - _load_started_at_msec
	return "[Loading +%d ms] " % elapsed_msec


func _get_status_name(status: ResourceLoader.ThreadLoadStatus) -> String:
	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return "INVALID_RESOURCE"
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return "IN_PROGRESS"
		ResourceLoader.THREAD_LOAD_FAILED:
			return "FAILED"
		ResourceLoader.THREAD_LOAD_LOADED:
			return "LOADED"
	return "UNKNOWN"
