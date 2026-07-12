extends StaticBody2D
## res://scripts/chest.gd
## Treasure chest ("interactables" group): the player opens it with the
## interact button when in range; it grants item_id via player.give_item()
## (which also equips it in the item slot). Opened state is a GameManager
## flag — the item itself lives in the player's saved inventory, so a
## restored chest only re-opens its lid, it never double-grants.

signal opened(item_id: String)

@export var item_id := "boomerang"
@export var flag_id := "chest_boomerang"

var is_open := false

@onready var _lid: Polygon2D = $Lid


func _ready() -> void:
	if not flag_id.is_empty() and GameManager.get_flag(flag_id):
		_open_visual()


## Player interact contract. Returns true if the chest just opened.
func interact(by: Node) -> bool:
	if is_open:
		return false
	_open_visual()
	if not flag_id.is_empty():
		GameManager.set_flag(flag_id)
	if by != null and by.has_method("give_item"):
		by.give_item(item_id)
	opened.emit(item_id)
	return true


func _open_visual() -> void:
	is_open = true
	# Blockout "open" state: the lid goes dark (a sprite swap when art lands).
	_lid.color = Color(0.16, 0.11, 0.06)
