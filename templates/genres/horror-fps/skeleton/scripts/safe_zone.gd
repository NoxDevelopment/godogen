extends Area3D
## res://scripts/safe_zone.gd
## A pool of light the horror can't touch: while the player stands inside,
## sanity restores instead of draining (Sanity tracks overlapping zones by
## counter, so zones can overlap freely).


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		Sanity.enter_safe_zone()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		Sanity.exit_safe_zone()
