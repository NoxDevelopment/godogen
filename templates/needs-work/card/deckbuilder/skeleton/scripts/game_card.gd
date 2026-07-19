extends Card
## res://scripts/game_card.gd
## Card with a readable face: overlays name, cost and description labels on
## the front-face art, populated from the JSON card_info the factory assigns
## before the card enters the tree.


func _ready() -> void:
	super()
	_apply_card_info()


func _apply_card_info() -> void:
	if card_info.is_empty():
		return
	var name_label: Label = $FrontFace/NameLabel
	var cost_label: Label = $FrontFace/CostLabel
	var description_label: Label = $FrontFace/DescriptionLabel
	name_label.text = str(card_info.get("display_name", String(card_name).capitalize()))
	cost_label.text = str(card_info.get("cost", 0))
	description_label.text = str(card_info.get("description", ""))
