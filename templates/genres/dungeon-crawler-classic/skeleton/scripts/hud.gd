extends CanvasLayer
## res://scripts/hud.gd
## The classic crawler bottom bar (Lands of Lore anatomy): a scrolling
## message log on the left, three portrait panels in the middle (ColorRect
## placeholder portrait + name + HP/MP bars + attack button — the portrait
## art slot is Studio-bound, see the template guide), and a side column with
## the compass (N/E/S/W from party facing), keys/potions counters, the drink
## button and the kill counter. Buttons never take focus so Space/Enter stay
## with interact and the run summary; everything textual is in the
## "scalable_text" group per the NoxDev ABI.

const PORTRAIT_COLORS: Array[Color] = [
	Color(0.75, 0.45, 0.3), Color(0.4, 0.55, 0.75), Color(0.5, 0.7, 0.45),
]

@onready var _party: Node3D = $"../Party"
@onready var _log: RichTextLabel = $BottomBar/Margin/Cols/LogPanel/LogMargin/Log
@onready var _compass_label: Label = $BottomBar/Margin/Cols/SidePanel/CompassLabel
@onready var _keys_label: Label = $BottomBar/Margin/Cols/SidePanel/KeysLabel
@onready var _potions_label: Label = $BottomBar/Margin/Cols/SidePanel/PotionsLabel
@onready var _potion_button: Button = $BottomBar/Margin/Cols/SidePanel/PotionButton
@onready var _kills_label: Label = $BottomBar/Margin/Cols/SidePanel/KillsLabel
@onready var _member_panels: Array[PanelContainer] = [
	$BottomBar/Margin/Cols/Portraits/Member1,
	$BottomBar/Margin/Cols/Portraits/Member2,
	$BottomBar/Margin/Cols/Portraits/Member3,
]


func _ready() -> void:
	_party.message.connect(add_message)
	_party.member_changed.connect(_on_member_changed)
	_party.inventory_changed.connect(_on_inventory_changed)
	_party.facing_changed.connect(_on_facing_changed)
	_potion_button.pressed.connect(_party.use_potion)
	for i in _member_panels.size():
		var index := i
		_attack_button(i).pressed.connect(func() -> void: _party.attack(index))
		_portrait(i).color = PORTRAIT_COLORS[i]
		_on_member_changed(i)
	_on_inventory_changed(_party.keys, _party.potions)
	_on_facing_changed(_party.facing)
	set_kills(0)
	add_message("You descend into the dungeon...")
	add_message("WASD: move/strafe   Q/E: turn   1-3: attack   R: potion   Space: interact")


func _process(_delta: float) -> void:
	for i in _member_panels.size():
		_attack_button(i).disabled = not _party.can_attack(i)
	_potion_button.disabled = _party.potions <= 0


func add_message(text: String) -> void:
	_log.add_text(text + "\n")


func set_kills(kills: int) -> void:
	_kills_label.text = "Kills: %d" % kills


func _on_member_changed(index: int) -> void:
	var member: Dictionary = _party.members[index]
	var panel := _member_panels[index]
	var rows := panel.get_node("Rows")
	(rows.get_node("NameLabel") as Label).text = member["name"]
	var hp_bar := rows.get_node("HPBar") as ProgressBar
	hp_bar.max_value = member["max_hp"]
	hp_bar.value = member["hp"]
	var mp_bar := rows.get_node("MPBar") as ProgressBar
	mp_bar.max_value = member["max_mp"]
	mp_bar.value = member["mp"]
	_portrait(index).color = PORTRAIT_COLORS[index] if member["hp"] > 0 \
			else Color(0.2, 0.2, 0.22)


func _on_inventory_changed(keys: int, potions: int) -> void:
	_keys_label.text = "Keys: %d" % keys
	_potions_label.text = "Potions: %d" % potions


func _on_facing_changed(facing: int) -> void:
	_compass_label.text = _party.DIR_NAMES[facing]


func _portrait(index: int) -> ColorRect:
	return _member_panels[index].get_node("Rows/Portrait") as ColorRect


func _attack_button(index: int) -> Button:
	return _member_panels[index].get_node("Rows/AttackButton") as Button
