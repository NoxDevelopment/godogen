extends Resource
class_name NoxSkin
## One world's look for the MUD client. The client builds its whole Godot theme +
## palette from these values, so a new themed world (sci-fi / dark-fantasy /
## cyberpunk / horror) is just a new .tres — no client code changes. Vital LABELS
## are skinnable too (Mana -> Essence -> Cyberdeck -> Sanity).

@export var world_name: String = "The Realm"
@export var body_font: FontFile
@export var display_font: FontFile

@export_group("Palette")
@export var bg: Color = Color("16110b")
@export var panel_bg: Color = Color("241a10")
@export var panel_border: Color = Color("8a6a2e")
@export var title: Color = Color("e8c766")
@export var accent: Color = Color("d4af37")     # headers, level, buttons
@export var text: Color = Color("e6dcc4")
@export var dim: Color = Color("9a8c6e")
@export var thoughts_col: Color = Color("9a8cd6")

@export_group("Vitals")
@export var health_col: Color = Color("a83232")
@export var resource_col: Color = Color("3a6fb2")
@export var spirit_col: Color = Color("b9c0d6")
@export var stamina_col: Color = Color("4f9a4a")
@export var rt_col: Color = Color("c9772e")
@export var cast_col: Color = Color("8a5cc9")
@export var resource_label: String = "Mana"      # OOB key stays "mana"
@export var spirit_label: String = "Spirit"      # OOB key stays "spirit"
