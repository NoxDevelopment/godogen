extends PanelContainer
## res://scripts/illustration_plate.gd
## The illustration plate: the big picture at the top of every page. In this
## data-driven gamebook the passages come from ANY loaded scenario/module, so
## the plate is scenario-agnostic — it binds one manifest slot per passage
## ("illustration/<passage_id>"). If the Studio asset board has generated art for
## that slot it shows it; otherwise it shows a deterministic tinted placeholder
## captioned with the PASSAGE TITLE (no manifest entry required, no warnings) so
## an unillustrated adventure still reads cleanly. Fill a passage's slot later and
## the same bind call shows the real art with zero code changes.

## The manifest slot currently bound ("" before the first passage).
var bound_slot_id := ""
## True while the bound slot has no generated file yet.
var is_placeholder := true

@onready var _placeholder_rect: ColorRect = $PlaceholderRect
@onready var _texture_rect: TextureRect = $PlateTexture
@onready var _caption: Label = $CaptionLabel


## Bind the plate for a passage. `title` captions the placeholder when there is
## no generated art. Returns true when real art was bound.
func bind_passage(passage_id: String, title: String = "") -> bool:
	bound_slot_id = "illustration/" + passage_id
	var texture: Texture2D = AssetBinder.get_texture(bound_slot_id)
	if texture != null:
		is_placeholder = false
		_texture_rect.texture = texture
		_texture_rect.show()
		_placeholder_rect.hide()
		_caption.hide()
		return true
	is_placeholder = true
	_placeholder_rect.color = AssetBinder.placeholder_color(bound_slot_id)
	_placeholder_rect.show()
	_texture_rect.hide()
	var caption := title if not title.is_empty() else passage_id
	_caption.text = caption
	_caption.show()
	return false
