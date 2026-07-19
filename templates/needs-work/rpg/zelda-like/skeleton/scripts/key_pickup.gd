extends Area2D
## res://scripts/key_pickup.gd
## Small key pickup: touched by the player it adds one key
## (player.gain_key()) and records itself in GameManager.flags under flag_id
## so it never respawns — picked-up keys survive room transitions and scene
## reloads.

@export var flag_id := ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not flag_id.is_empty() and GameManager.get_flag(flag_id):
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player") or not body.has_method("gain_key"):
		return
	body.gain_key()
	if not flag_id.is_empty():
		GameManager.set_flag(flag_id)
	queue_free()
