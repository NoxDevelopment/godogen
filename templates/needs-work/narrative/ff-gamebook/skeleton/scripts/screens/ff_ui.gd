class_name FFUI
extends RefCounted
## res://scripts/screens/ff_ui.gd
## Shared look-and-feel toolkit for every Phase-2 screen — the one place the
## STYLE_GUIDE.md "veritas-gamebook" palette, the reused fantasy fonts, and the
## reusable widget builders live, so a stat panel in Combat, the Adventure Sheet,
## and the Inventory grid all read as ONE book (STYLE_GUIDE 1.1 "one book").
##
## Nothing here rolls dice or mutates state. Colours are the named STYLE_GUIDE §1.3
## set; art (fonts / frames / icons / portraits / plates) is pulled through the
## Studio-bound AssetBinder by STABLE ID (GDD §10a) — never a hardcoded path — so
## Jesus can hot-swap any asset from the Studio with no code edits.

# --- STYLE_GUIDE §1.3 palette (named, restricted) ---------------------------
const PARCHMENT   := Color("e7dcc2")   # Tallow Parchment — aged-paper ground
const PARCHMENT_2 := Color("d8c9a6")   # a shade deeper for panels
const VELLUM      := Color("171a18")   # Drowned Vellum — dark ground
const INK         := Color("14110d")   # Bog Ink — near-black warm line/text
const UMBER       := Color("4a3f2e")   # Peat Umber — shadow wash
const FEN         := Color("7c8683")   # Fen Grey — fog/stone/dead sky
const SLATE       := Color("3a464a")   # Slate Drown — deep water / dark interior
const VERDIGRIS   := Color("6e8f7a")   # Ledger Verdigris — THE signature accent
const VERDIGRIS_2 := Color("9aa69b")   # verdigris ash
const FLAME       := Color("c88a3e")   # Tallow Flame — rare warmth (lantern/victory)
const ARREARS     := Color("8a2e24")   # Old Arrears Red — wounds / blood / danger
# Prose ink is a hair warmer/softer than pure Bog Ink — printed book ink is never
# jet-black on paper; this reads as pressed-in ink rather than a screen label.
const PROSE_INK   := Color("241c12")   # warm reading ink for body prose
const GILT_EDGE   := Color("3a2c17")   # dark umber edge for the illuminated initial

# --- reused fantasy assets (CC0/OFL) — see credits + asset manifest ----------
const FONT_DISPLAY := "res://assets/reused/fonts/Cinzel.ttf"          # titles / §N
const FONT_BODY    := "res://assets/reused/fonts/MedievalSharp.ttf"   # prose / choices
const FONT_RUNIC   := "res://assets/reused/fonts/UncialAntiqua.ttf"   # drop-cap / banners
const FRAME_TEX    := "res://assets/reused/ui/frame.png"              # 96x96 9-slice
const FRAME_DARK   := "res://assets/reused/ui/frame_dark.png"
const DIVIDER_TEX  := "res://assets/reused/ui/divider.png"

static var _cache: Dictionary = {}


static func _res(path: String) -> Resource:
	if _cache.has(path):
		return _cache[path]
	var r: Resource = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = r
	return r


static func font_display() -> FontFile: return _res(FONT_DISPLAY) as FontFile
static func font_body() -> FontFile:    return _res(FONT_BODY) as FontFile
static func font_runic() -> FontFile:   return _res(FONT_RUNIC) as FontFile


## The engraved display face with letter-spacing added — tracked caps read as
## "illuminated / inscribed" rather than a tight default label. Cached per spacing.
static func font_display_tracked(glyph_spacing: int = 2) -> FontVariation:
	var key := "fv_display_%d" % glyph_spacing
	if _cache.has(key):
		return _cache[key]
	var fv := FontVariation.new()
	fv.base_font = font_display()
	fv.spacing_glyph = glyph_spacing
	_cache[key] = fv
	return fv


## An ORNAMENTED illuminated drop-cap as BBCode (STYLE_GUIDE §1 "the page is sacred";
## typography SKILL "drop-caps & illuminated initials"). The first letter becomes a
## large Uncial versal in Ledger Verdigris — the STYLE_GUIDE signature accent — inked
## with a dark umber outline and a soft cast shadow so it reads *pressed / gilded into
## the page*. The remainder of the opening word follows in tracked engraved small-caps
## (the classic manuscript "versal + spaced opening"), then the prose flows in the body
## face. Returns the whole passage as BBCode for a RichTextLabel built by `rich()`.
static func illuminated_cap(text: String) -> String:
	var body := text.strip_edges(true, false)
	if body == "":
		return text
	var initial := body.substr(0, 1)
	# extent of the first word (so its tail can render as small-caps opening)
	var i := 1
	while i < body.length() and not _is_space(body[i]):
		i += 1
	var opener := body.substr(1, i - 1)
	var tail := body.substr(i)
	# Balanced LIFO nesting (font > font_size > outline_size > outline_color > color);
	# the gilt umber outline gives the versal its raised edge, and the label-level ink
	# shadow set in rich() presses the whole glyph into the page.
	var cap := "[font=%s][font_size=58]" % FONT_RUNIC \
		+ "[outline_size=5][outline_color=#%s]" % GILT_EDGE.to_html(false) \
		+ "[color=#%s]%s[/color]" % [VERDIGRIS.to_html(false), initial] \
		+ "[/outline_color][/outline_size][/font_size][/font]"
	if opener == "":
		return cap + tail
	var versal := "[font=%s][font_size=22][color=#%s]%s[/color][/font_size][/font]" % [
		FONT_DISPLAY, UMBER.to_html(false), opener.to_upper()]
	return cap + versal + tail


static func _is_space(ch: String) -> bool:
	return ch == " " or ch == "\n" or ch == "\t" or ch == "\r"


# --- Art by STABLE ID through the Studio-bound AssetBinder (GDD §10a) --------


## An icon texture by short name — resolves manifest slot "icon/<name>".
static func icon(name: String) -> Texture2D:
	return AssetBinder.get_texture("icon/" + name)


## A portrait texture by short name — resolves manifest slot "portrait/<name>".
static func portrait(name: String) -> Texture2D:
	return AssetBinder.get_texture("portrait/" + name)


## A section plate texture by slot id (as authored in Section.illustration,
## e.g. "plate/s2"). Returns null until bound (caller shows a framed fallback).
static func plate(slot_id: String) -> Texture2D:
	return AssetBinder.get_texture(slot_id)


# --- Backgrounds ------------------------------------------------------------


## A full-rect parchment ground (the reading page). `dark` uses Drowned Vellum.
static func page_background(dark: bool = false) -> Control:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = VELLUM if dark else PARCHMENT
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## A subtle vertical wash rectangle (paper-grain stand-in) for depth.
static func wash(color: Color, alpha: float = 0.12) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.color = Color(color.r, color.g, color.b, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --- Panels (StyleBoxFlat, on-palette; hatched-ink border feel) -------------


static func panel_box(bg: Color = PARCHMENT_2, border: Color = UMBER, width: int = 2, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(width)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func panel(bg: Color = PARCHMENT_2, border: Color = UMBER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", panel_box(bg, border))
	return p


## An OPAQUE parchment (or vellum) overlay panel with a strong colour border and a
## doubled inner rule for a book-plate feel — used by the Dice overlay, Adventure
## Sheet, Inventory and Map so the panel never bleeds the busy page behind it.
static func framed_panel(border: Color = VERDIGRIS, dark: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var fill := Color("241f19") if dark else PARCHMENT_2
	var sb := panel_box(fill, border, 3, 5)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	sb.shadow_size = 6
	sb.shadow_color = Color(INK.r, INK.g, INK.b, 0.4)
	p.add_theme_stylebox_override(&"panel", sb)
	return p


## A panel bordered with the REUSED Kenney fantasy frame texture (9-slice). Meant to
## wrap an OPAQUE image (a plate or portrait) so the frame's transparent centre is
## covered by the content. Falls back to framed_panel if the texture is unavailable.
static func tex_framed(border: Color = VERDIGRIS) -> PanelContainer:
	var tex := AssetBinder.get_texture("ui/frame")
	if tex == null:
		tex = _res(FRAME_TEX) as Texture2D
	if tex == null:
		return framed_panel(border)
	var p := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	for side in ["left", "right", "top", "bottom"]:
		sb.set("texture_margin_" + side, 32)
		sb.set("content_margin_" + side, 14)
	sb.modulate_color = border
	p.add_theme_stylebox_override(&"panel", sb)
	return p


# --- Text -------------------------------------------------------------------


## An illuminated section heading: the engraved display face, letter-tracked, with a
## light parchment outline + soft umber cast shadow so the title reads as *inscribed
## into the page* (engraved/illuminated, typography SKILL) rather than a flat label.
static func title(text: String, size: int = 30, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", font_display_tracked(2))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	# emboss: a hairline parchment highlight edge + a warm umber drop = "pressed in"
	l.add_theme_constant_override(&"outline_size", 3)
	l.add_theme_color_override(&"font_outline_color", Color(PARCHMENT.r, PARCHMENT.g, PARCHMENT.b, 0.55))
	l.add_theme_color_override(&"font_shadow_color", Color(UMBER.r, UMBER.g, UMBER.b, 0.35))
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_to_group(&"scalable_text")
	return l


static func label(text: String, size: int = 18, color: Color = INK, body: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", font_body() if body else font_display())
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_to_group(&"scalable_text")
	return l


## The reading-prose label: warm readable body face on parchment ink, generous
## line-height, and a faint 1px ink-shadow so the text reads as *pressed into the
## page* (typography SKILL "subtle emboss/shadow"). Illuminated drop-caps and the
## engraved bold face are applied per-passage via BBCode (see `illuminated_cap`).
static func rich(size: int = 19, color: Color = PROSE_INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_font_override(&"normal_font", font_body())
	r.add_theme_font_override(&"bold_font", font_display_tracked(1))
	r.add_theme_font_size_override(&"normal_font_size", size)
	r.add_theme_color_override(&"default_color", color)
	# generous manuscript line-height — the page breathes (STYLE_GUIDE §1)
	r.add_theme_constant_override(&"line_separation", 7)
	# pressed-in ink: a 1px warm shadow under the body glyphs
	r.add_theme_color_override(&"font_shadow_color", Color(GILT_EDGE.r, GILT_EDGE.g, GILT_EDGE.b, 0.18))
	r.add_theme_constant_override(&"shadow_offset_x", 1)
	r.add_theme_constant_override(&"shadow_offset_y", 1)
	r.add_to_group(&"scalable_text")
	return r


static func divider_rule() -> Control:
	var tex := _res(DIVIDER_TEX) as Texture2D
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(0, 16)
		t.modulate = Color(UMBER.r, UMBER.g, UMBER.b, 0.8)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	var c := ColorRect.new()
	c.color = Color(UMBER.r, UMBER.g, UMBER.b, 0.5)
	c.custom_minimum_size = Vector2(0, 2)
	return c


# --- Buttons ----------------------------------------------------------------


## A full-width choice button (WIREFRAMES §2: >=56 dp tall). `locked` renders it
## greyed with a reason chip (conditional-choice locking, WIREFRAMES 5.2).
static func choice_button(text: String, locked: bool = false, reason: String = "") -> Button:
	var b := Button.new()
	b.text = ("  " + text + ("      [ " + reason + " ]" if reason != "" else "")) if locked else text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	b.add_theme_font_override(&"font", font_body())
	b.add_theme_font_size_override(&"font_size", 18)
	var normal := panel_box(PARCHMENT_2, UMBER, 2, 4)
	var hover := panel_box(Color("e2d4b2"), VERDIGRIS, 2, 4)
	var pressed := panel_box(Color("cbb98f"), UMBER, 2, 4)
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", pressed)
	b.add_theme_stylebox_override(&"focus", panel_box(Color(0,0,0,0), ARREARS, 2, 4))
	b.add_theme_color_override(&"font_color", INK)
	b.add_theme_color_override(&"font_hover_color", INK)
	if locked:
		b.disabled = true
		var dis := panel_box(Color(0.72, 0.66, 0.52, 0.5), FEN, 1, 4)
		b.add_theme_stylebox_override(&"disabled", dis)
		b.add_theme_color_override(&"font_disabled_color", Color(UMBER.r, UMBER.g, UMBER.b, 0.75))
	b.add_to_group(&"scalable_text")
	return b


## A small labelled action chip ([Test your Luck] / [Eat] etc.).
static func chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_override(&"font", font_body())
	b.add_theme_font_size_override(&"font_size", 16)
	b.add_theme_stylebox_override(&"normal", panel_box(Color("cfe0d4"), VERDIGRIS, 1, 12))
	b.add_theme_stylebox_override(&"hover", panel_box(Color("dbe9df"), VERDIGRIS, 2, 12))
	b.add_theme_stylebox_override(&"pressed", panel_box(Color("bcd0c2"), VERDIGRIS, 1, 12))
	b.add_theme_color_override(&"font_color", INK)
	b.add_to_group(&"scalable_text")
	return b


# --- Stat & bar widgets -----------------------------------------------------


## A "STAMINA ▓▓▓░░ 16/24" style bar row. `label_text` sits left, a value right.
static func stat_bar(label_text: String, cur: int, maximum: int, fill: Color) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	var head := HBoxContainer.new()
	var nm := label(label_text, 15, UMBER)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	head.add_child(label("%d/%d" % [cur, maximum], 15, INK))
	row.add_child(head)
	var bar := ProgressBar.new()
	bar.max_value = maxi(maximum, 1)
	bar.value = clampi(cur, 0, maxi(maximum, 1))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(UMBER.r, UMBER.g, UMBER.b, 0.35); bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new(); fg.bg_color = fill; fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"background", bg)
	bar.add_theme_stylebox_override(&"fill", fg)
	row.add_child(bar)
	return row


## A compact "SKILL 9" stat pill for the HUD.
static func stat_pill(name: String, value: String, accent: Color = INK) -> Control:
	var p := FFUI.panel(Color("ded0ac"), Color(UMBER.r, UMBER.g, UMBER.b, 0.6))
	p.add_theme_constant_override(&"separation", 0)
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	var n := label(name, 14, UMBER); box.add_child(n)
	var v := label(value, 17, accent); v.add_theme_font_override(&"font", font_display()); box.add_child(v)
	p.add_child(box)
	return p


## A portrait inside the reused verdigris frame. `size` is the square edge.
static func portrait_panel(tex: Texture2D, size: int = 128, tint: Color = VERDIGRIS) -> Control:
	var frame := tex_framed(tint)
	frame.custom_minimum_size = Vector2(size, size)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(size - 34, size - 34)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if tex != null:
		tr.texture = tex
	else:
		# labelled asset-slot fallback (never a bare ColorRect): a tinted plate
		var ph := ColorRect.new(); ph.color = SLATE
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.add_child(ph)
	frame.add_child(tr)
	return frame


# --- Roll-quality colour coding (WIREFRAMES 5.7) ----------------------------


## Colour + tag for a rolled attribute value, never punitive.
static func roll_quality(stat: String, value: int) -> Dictionary:
	# SKILL/LUCK: 7-12; STAMINA: 14-24.
	var lo := 7.0
	var hi := 12.0
	if stat == "stamina":
		lo = 14.0; hi = 24.0
	var t := clampf((float(value) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
	if t < 0.34:
		return {"tag": "rough", "color": ARREARS}
	elif t < 0.67:
		return {"tag": "average", "color": FLAME}
	return {"tag": "strong", "color": VERDIGRIS}
