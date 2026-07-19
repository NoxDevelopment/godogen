class_name Crop
extends Resource
## res://scripts/crop.gd
## One crop definition. Growth is data-driven: `days_per_stage` game days per
## stage, `stage_count` stages from seed (0) to mature (stage_count - 1).
## Blockout visuals derive from `stage_colors`/growing size until real
## sprites land (then swap the colors for a stage spritesheet).

@export var id := "crop"
@export var display_name := "Crop"
## Total growth stages including seed (0) and mature (last).
@export var stage_count := 4
## Game days each stage lasts before advancing.
@export var days_per_stage := 1
## What harvesting yields (goes into GameManager flags / inventory systems).
@export var harvest_item := "crop"
@export var harvest_amount := 1
## Blockout tint per stage (seed -> mature). Replace with sprites later.
@export var stage_colors: Array[Color] = [
	Color(0.55, 0.47, 0.30),
	Color(0.49, 0.62, 0.34),
	Color(0.38, 0.62, 0.30),
	Color(0.85, 0.72, 0.28),
]


## Stage for a crop planted on `planted_day` when today is `current_day`.
func stage_on_day(planted_day: int, current_day: int) -> int:
	var elapsed := maxi(current_day - planted_day, 0)
	return mini(elapsed / maxi(days_per_stage, 1), stage_count - 1)


func is_mature(stage: int) -> bool:
	return stage >= stage_count - 1


func color_for_stage(stage: int) -> Color:
	if stage_colors.is_empty():
		return Color.WHITE
	return stage_colors[clampi(stage, 0, stage_colors.size() - 1)]
