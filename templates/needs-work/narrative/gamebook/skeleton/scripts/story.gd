extends Node2D
## res://scripts/story.gd
## Book scene: spawns the textbox, opens the book at passage 1, keeps the
## adventure-sheet panel (SKILL/STAMINA/LUCK + inventory) live, and returns
## to the title screen when the adventure ends (or the adventurer dies).
## Illustrations go on the Stage — the textbox purposely stays a separate,
## reusable scene.

const TITLE_SCENE := "res://scenes/title.tscn"
const TEXTBOX_SCENE := preload("res://scenes/textbox.tscn")
const BOOK_DIALOGUE := preload("res://dialogue/book.dialogue")

@onready var _stats_label: Label = $SheetPanel/Margin/Rows/StatsLabel
@onready var _inventory_label: Label = $SheetPanel/Margin/Rows/InventoryLabel


func _ready() -> void:
	Sheet.stats_changed.connect(_refresh_sheet)
	Sheet.inventory_changed.connect(func(_items: Array) -> void: _refresh_sheet())
	Sheet.died.connect(_on_died)
	_refresh_sheet()
	_start_book.call_deferred()


func _start_book() -> void:
	var textbox := TEXTBOX_SCENE.instantiate()
	add_child(textbox)
	textbox.dialogue_finished.connect(_on_dialogue_finished)
	textbox.start(BOOK_DIALOGUE, "passage_1")


func _refresh_sheet() -> void:
	_stats_label.text = "SKILL %d/%d   STAMINA %d/%d   LUCK %d/%d   Provisions %d" % [
		Sheet.skill, Sheet.max_skill,
		Sheet.stamina, Sheet.max_stamina,
		Sheet.luck, Sheet.max_luck,
		Sheet.provisions,
	]
	_inventory_label.text = "Inventory: %s" % (
		", ".join(Sheet.inventory) if not Sheet.inventory.is_empty() else "(empty)"
	)


func _on_died() -> void:
	# STAMINA hit zero — the adventure is over (gamebook rules are unforgiving).
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


func _on_dialogue_finished() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
