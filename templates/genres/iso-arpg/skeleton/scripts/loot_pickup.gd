extends Area2D
## res://scripts/loot_pickup.gd
## A dropped item on the ground: shows the item name tinted by rarity and is
## collected (into LootSystem.inventory) when the player walks over it.

## The drop dictionary produced by LootSystem.roll_drop().
var drop: Dictionary = {}

@onready var _label: Label = $Label
@onready var _gem: Polygon2D = $Gem


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var color := Color.from_string(str(drop.get("color", "#c8c8c8")), Color.WHITE)
	_label.text = "%s +%d %s" % [drop.get("name", "?"), drop.get("value", 0), drop.get("stat", "")]
	_label.add_theme_color_override(&"font_color", color)
	_gem.color = color


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	LootSystem.collect(drop)
	queue_free()
