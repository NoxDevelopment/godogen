extends Pile
## res://scripts/play_area.gd
## Drop target for playing cards. Accepts one card at a time, only when the
## game says it is playable (enough energy, combat still running); emits
## card_played when the card finishes arriving so the game can resolve its
## effect. Works for both drag-and-drop and programmatic plays.

signal card_played(card: Card)

## Assigned by main.gd: Callable(card: Card) -> bool.
var can_play := func(_card: Card) -> bool: return true


func _card_can_be_added(cards: Array) -> bool:
	if cards.size() != 1:
		return false
	return can_play.call(cards[0])


func on_card_move_done(card: Card) -> void:
	card_played.emit(card)
