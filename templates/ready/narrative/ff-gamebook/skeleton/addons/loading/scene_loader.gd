extends CanvasLayer
## SceneLoader — autoload. Threaded async scene change with a loading screen.
## Autoload as "SceneLoader". Call SceneLoader.change_scene("res://.../game.tscn").
## Replaces bare get_tree().change_scene_to_file() so large scenes don't hitch and
## the player always sees progress + a tip instead of a frozen frame.

signal load_finished(path: String)

const LOADING_SCENE := "res://addons/loading/loading_screen.tscn"
const MIN_DISPLAY_SEC := 0.8   # never flash the loading screen for one frame

var _target := ""
var _loading := false
var _elapsed := 0.0
var _screen: Control = null

func change_scene(path: String) -> void:
	if _loading:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneLoader: scene does not exist: %s" % path)
		return
	_target = path
	_loading = true
	_elapsed = 0.0
	get_tree().paused = false
	_show_screen()
	ResourceLoader.load_threaded_request(path)

func _show_screen() -> void:
	if ResourceLoader.exists(LOADING_SCENE):
		_screen = (load(LOADING_SCENE) as PackedScene).instantiate()
		add_child(_screen)

func _process(delta: float) -> void:
	if not _loading:
		return
	_elapsed += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_target, progress)
	var p: float = (progress[0] if progress.size() > 0 else 0.0)
	if _screen and _screen.has_method("set_progress"):
		_screen.set_progress(p)
	match status:
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("SceneLoader: failed to load %s" % _target)
			_loading = false
			_dismiss()
		ResourceLoader.THREAD_LOAD_LOADED:
			if _elapsed < MIN_DISPLAY_SEC:
				return   # hold the screen so it doesn't flash
			var packed: PackedScene = ResourceLoader.load_threaded_get(_target)
			_loading = false
			get_tree().change_scene_to_packed(packed)
			load_finished.emit(_target)
			_dismiss()

func _dismiss() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
