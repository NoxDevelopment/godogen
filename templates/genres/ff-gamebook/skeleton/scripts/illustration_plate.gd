extends PanelContainer
## res://scripts/illustration_plate.gd
## The illustration plate: the big picture at the top of every page, bound to
## one manifest slot per passage (slotId "illustration/<passage_id>"). While
## the slot's `file` is null the plate shows a ColorRect placeholder (the
## slot's deterministic tint + a caption naming the slot) — the Studio asset
## board fills the slot later and the same bind call shows the real art.

## The manifest slot currently bound ("" before the first passage).
var bound_slot_id := ""
## True while the bound slot has no generated file yet.
var is_placeholder := true

@onready var _placeholder_rect: ColorRect = $PlaceholderRect
@onready var _texture_rect: TextureRect = $PlateTexture
@onready var _caption: Label = $CaptionLabel


## Bind the plate for a passage (the page calls this on
## SessionState.passage_changed).
func bind_passage(passage_id: String) -> bool:
	return bind_slot("illustration/" + passage_id)


## Bind any manifest slot. Returns true when the slot exists in the manifest
## (placeholder or real art); false for an unknown slot (neutral placeholder).
func bind_slot(slot_id: String) -> bool:
	bound_slot_id = slot_id
	var known := AssetBinder.has_slot(slot_id)
	if not known:
		push_warning("IllustrationPlate: no manifest slot '%s'" % slot_id)
	var texture: Texture2D = AssetBinder.get_texture(slot_id) if known else null
	if texture != null:
		is_placeholder = false
		_texture_rect.texture = texture
		_texture_rect.show()
		_placeholder_rect.hide()
		_caption.hide()
	else:
		is_placeholder = true
		_placeholder_rect.color = AssetBinder.placeholder_color(slot_id)
		_placeholder_rect.show()
		_texture_rect.hide()
		var pack := str(AssetBinder.get_slot(slot_id).get("stylePack", AssetBinder.style_pack))
		_caption.text = "[ %s — awaiting %s plate ]" % [slot_id, pack] if known \
				else "[ unbound slot: %s ]" % slot_id
		_caption.show()
	return known
