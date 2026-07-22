extends Node
## res://scripts/asset_binder.gd
## Asset binder (autoload "AssetBinder"): reads res://assets.manifest.json —
## the contract between this project and the Studio asset board. Every art/
## audio surface in the game is a named SLOT; the manifest records, per slot,
## HOW it gets filled (policy/workflow/stylePack/promptTemplate) and WHAT
## currently fills it (file + provenance). Scene code never hardcodes asset
## paths — it asks the binder:
##
##     AssetBinder.get_texture("illustration/passage_1")   # null until generated
##     AssetBinder.placeholder_color("ui/dice_tray")       # deterministic tint
##
## `file: null` means "not generated yet" — callers show a ColorRect
## placeholder. The Studio asset board runs each slot's workflow (e.g.
## zit-txt2img with the veritas-ink style pack), writes the asset into the
## project and updates the slot's `file` + `provenance`; the next boot binds
## the real art with zero code changes. See TEMPLATE.md §Asset binding for the
## full schema.

signal manifest_loaded(slot_count: int)
signal book_slots_changed(slot_count: int)

const MANIFEST_PATH := "res://assets.manifest.json"

## stylePack declared at the manifest root (per-slot values may override it).
var style_pack := ""
var loaded := false

var _slots: Dictionary = {}
var _order: Array[String] = []

## Per-BOOK slot overlay (ADVENTURE_FORMAT.md §3): the active adventure package's
## `slots` map, pushed by AdventureLibrary.select() with every value already
## resolved to an absolute res:// or user:// file path. Book slots WIN over the
## global manifest while the book is active; selecting another book swaps them.
var _book_slots: Dictionary = {}


func _ready() -> void:
	reload()


## (Re)read the manifest — call again after the Studio board rewrites it.
func reload() -> void:
	_slots.clear()
	_order.clear()
	loaded = false
	style_pack = ""
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("AssetBinder: manifest missing at %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		push_error("AssetBinder: %s is not a valid JSON object" % MANIFEST_PATH)
		return
	var manifest: Dictionary = parsed
	style_pack = str(manifest.get("stylePack", ""))
	for slot: Variant in manifest.get("slots", []):
		if slot is Dictionary and slot.has("slotId"):
			var slot_id := str(slot.get("slotId"))
			_slots[slot_id] = slot
			_order.append(slot_id)
	loaded = true
	manifest_loaded.emit(_slots.size())


## Install the active book's slot overlay (slotId -> ABSOLUTE res:///user:// file
## path). Replaces any previous book's overlay — one active book at a time.
func push_book_slots(slots: Dictionary) -> void:
	_book_slots = slots.duplicate(true)
	book_slots_changed.emit(_book_slots.size())


## Drop the per-book overlay (back to the global manifest only).
func clear_book_slots() -> void:
	if _book_slots.is_empty():
		return
	_book_slots.clear()
	book_slots_changed.emit(0)


func book_slot_count() -> int:
	return _book_slots.size()


func slot_count() -> int:
	return _slots.size()


func slot_ids() -> Array[String]:
	return _order.duplicate()


func has_slot(slot_id: String) -> bool:
	return _book_slots.has(slot_id) or _slots.has(slot_id)


## The raw slot entry (treat as read-only — the manifest is Studio-owned).
func get_slot(slot_id: String) -> Dictionary:
	return _slots.get(slot_id, {})


## {"illustration": 6, "ui": 2, "audio": 1} — used by the boot probe.
func counts_by_kind() -> Dictionary:
	var counts := {}
	for slot_id in _order:
		var kind := str(_slots[slot_id].get("kind", "?"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


## The texture bound to a slot, or null while `file` is null/missing (show a
## placeholder). Falls back to loading the image from disk for files the
## Studio board dropped in after the last editor import.
func get_texture(slot_id: String) -> Texture2D:
	var path := _slot_file(slot_id)
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		return res if res is Texture2D else null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(image)
	push_warning("AssetBinder: slot '%s' file not found: %s" % [slot_id, path])
	return null


## The audio stream bound to a slot, or null while unfilled.
func get_stream(slot_id: String) -> AudioStream:
	var path := _slot_file(slot_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## Placeholder tint for an unfilled slot: the slot's explicit
## `placeholderColor` if declared, else a deterministic muted ink tone
## derived from the slot id (stable across boots, distinct per slot).
func placeholder_color(slot_id: String) -> Color:
	var declared: Variant = get_slot(slot_id).get("placeholderColor")
	if declared is String and Color.html_is_valid(declared):
		return Color.html(declared)
	var hue := absf(fmod(float(hash(slot_id)) * 0.61803398875, 1.0))
	return Color.from_hsv(hue, 0.22, 0.32)


func _slot_file(slot_id: String) -> String:
	# the active book's overlay wins (ADVENTURE_FORMAT.md §3)
	var over: Variant = _book_slots.get(slot_id)
	if over is String and str(over) != "":
		return str(over)
	var file: Variant = get_slot(slot_id).get("file")
	return file if file is String else ""
