extends Area2D
## res://scripts/heart_pickup.gd
## Heart drop: touched by the player it restores heal_amount hearts and
## disappears. Spawned by main.gd when an enemy dies (heart_drop_chance);
## drops are transient, so no GameManager flag.

@export var heal_amount := 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player") and body.has_method("heal"):
		body.heal(heal_amount)
		queue_free()
