extends Area3D
## res://scripts/checkpoint.gd
## One checkpoint gate on the track. Purely a signal relay: the race manager
## connects gate_crossed and enforces ordering — gates themselves are dumb so
## re-ordering a track is just re-ordering children of the Checkpoints node.

signal gate_crossed(checkpoint: Area3D, body: Node3D)


func _ready() -> void:
	body_entered.connect(func(body: Node3D) -> void: gate_crossed.emit(self, body))
