extends "res://addons/cogito/SceneManagement/cogito_scene.gd"
## res://scripts/test_room.gd
## COGITO scene root for the horror test room: inherits the addon's scene
## contract (registers with CogitoSceneManager, connector spawn points), and
## adds the horror direction layer — starts the resonate ambient track, and
## wires the Sanity autoload to (a) the sanity vignette overlay shader and
## (b) the "dread" music stem (enabled under the low-sanity threshold,
## disabled after recovery). Also emits the boot probe proving the loop:
## COGITO player + interactables + sanity drop driving overlay and stem.

const MUSIC_BANK := "horror"
const MUSIC_TRACK := "ambient"
const DREAD_STEM := "dread"

@onready var _overlay_rect: ColorRect = $SanityOverlay/Vignette


func _ready() -> void:
	Sanity.sanity_changed.connect(_on_sanity_changed)
	Sanity.low_sanity_entered.connect(_on_low_sanity_entered)
	Sanity.low_sanity_exited.connect(_on_low_sanity_exited)
	_on_sanity_changed(Sanity.sanity, Sanity.max_sanity)
	_start_music.call_deferred()
	_emit_boot_probe.call_deferred()


func _start_music() -> void:
	if not MusicManager.has_loaded:
		await MusicManager.loaded
	# auto_loop=true: the placeholder stems are plain (non-looped) WAVs, so
	# resonate restarts the track itself; with gapless pre-looped stems you
	# can drop the flag.
	MusicManager.play(MUSIC_BANK, MUSIC_TRACK, 0.5, true)


func _on_sanity_changed(_current: float, _max_sanity: float) -> void:
	var material := _overlay_rect.material as ShaderMaterial
	material.set_shader_parameter(&"intensity", 1.0 - Sanity.normalized())


func _on_low_sanity_entered() -> void:
	if MusicManager.has_loaded and MusicManager.is_playing(MUSIC_BANK, MUSIC_TRACK):
		MusicManager.enable_stem(DREAD_STEM, 1.5)


func _on_low_sanity_exited() -> void:
	if MusicManager.has_loaded and MusicManager.is_playing(MUSIC_BANK, MUSIC_TRACK):
		MusicManager.disable_stem(DREAD_STEM, 3.0)


func _emit_boot_probe() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: Node = CogitoSceneManager._current_player_node
	var interactables := get_tree().get_nodes_in_group(&"interactable").size()
	# Let resonate finish its first scan and start the ambient track.
	if not MusicManager.has_loaded:
		await MusicManager.loaded
	await get_tree().process_frame
	var music_playing: bool = MusicManager.is_playing(MUSIC_BANK, MUSIC_TRACK)
	# Scripted scare: drop sanity through the low threshold and verify the
	# overlay shader and the dread stem both reacted.
	Sanity.scare(60.0)
	await get_tree().process_frame
	var material := _overlay_rect.material as ShaderMaterial
	var overlay_intensity: float = material.get_shader_parameter(&"intensity")
	var dread: Variant = MusicManager.get_stem_details(DREAD_STEM)
	var dread_enabled: bool = dread != null and dread.enabled
	print("DEBUG: horror-fps core loop ready — player=%s interactables=%d music_playing=%s sanity=%.0f overlay_intensity=%.2f dread_stem_enabled=%s" % [
		is_instance_valid(player), interactables, music_playing,
		Sanity.sanity, overlay_intensity, dread_enabled,
	])
