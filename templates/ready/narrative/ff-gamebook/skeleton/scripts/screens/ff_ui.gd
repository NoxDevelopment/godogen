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
# The desk the book lies on (FFC/Veritas study-desk framing) — near-black, warm,
# so the paper page reads as a lit physical object, never a flat app background.
const DESK        := Color("0f0c09")

# --- The player's OWN ink (hand-entered values, never the printed form) -----
# These separate "the pen the player wrote with" from the printed black form so the
# Adventure Sheet reads as a real filled-in paper sheet (ADVENTURE_SHEET_SPEC §3):
# scores/name go down in biro-blue, encounter-box scratchings in pencil graphite.
const INK_PEN     := Color("2a3550")   # dark biro blue — scores, hero name, kit
const GRAPHITE    := Color("2e2b26")   # pencil — encounter-box fill + scratch-downs

# --- reused fantasy assets (CC0/OFL) — see credits + asset manifest ----------
const FONT_DISPLAY := "res://assets/reused/fonts/Cinzel.ttf"          # titles / §N
const FONT_BODY    := "res://assets/reused/fonts/MedievalSharp.ttf"   # prose / choices
const FONT_RUNIC   := "res://assets/reused/fonts/UncialAntiqua.ttf"   # drop-cap / banners
# The player's handwriting (OFL, see credits): Caveat is legible even at the tiny
# encounter-box sizes; Reenie Beanie is looser/thinner, for large annotations only.
const FONT_HAND    := "res://assets/reused/fonts/Caveat.ttf"          # hand-entered values
const FONT_HAND_LOOSE := "res://assets/reused/fonts/ReenieBeanie.ttf" # large scrawl (name/notes)
const FRAME_TEX    := "res://assets/reused/ui/frame.png"              # 96x96 9-slice
const FRAME_DARK   := "res://assets/reused/ui/frame_dark.png"
const DIVIDER_TEX  := "res://assets/reused/ui/divider.png"
# The REAL paper (LOOKFEEL_PASS_2026-07): an aged-parchment page texture — fibre
# grain, foxing, toasted ragged edges — bound Studio-side as slot "ui/paper_page".
const PAPER_TEX    := "res://assets/ui/paper_page.png"

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
## The player's handwriting face — used for EVERY value the player/engine "wrote"
## onto the sheet (scores, name, gold, kit, encounter stats). Falls back to the body
## face if the OFL font isn't imported yet so a fresh clone never renders blank.
static func font_hand() -> FontFile:
	var f := _res(FONT_HAND) as FontFile
	return f if f != null else font_body()
## A looser, larger scrawl for big annotations only (hero name, long notes).
static func font_hand_loose() -> FontFile:
	var f := _res(FONT_HAND_LOOSE) as FontFile
	return f if f != null else font_hand()


## A hand-written value Label with per-glyph "life" (ADVENTURE_SHEET_SPEC §3): the
## handwriting face in the player's ink, with a small DETERMINISTIC jitter in
## rotation / size / baseline / colour-value seeded from `seed_key` (a hash of the
## field key + value) so the same sheet state always looks identical — MP-safe and
## screenshot-stable for visual-judge. Jitter is baked once, never animated per frame.
static func handwritten(text: String, size: int = 22, color: Color = INK_PEN, seed_key: String = "", loose: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", font_hand_loose() if loose else font_hand())
	l.add_theme_font_size_override(&"font_size", size)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key if seed_key != "" else text)
	# ±1px size, ±3% colour value, ±1.5° tilt, ±2px baseline — believable pen wobble.
	l.add_theme_font_size_override(&"font_size", maxi(size + rng.randi_range(-1, 1), 8))
	var vj := 1.0 + rng.randf_range(-0.03, 0.03)
	l.add_theme_color_override(&"font_color", Color(color.r * vj, color.g * vj, color.b * vj, color.a))
	l.rotation_degrees = rng.randf_range(-1.5, 1.5)
	l.set_meta(&"jitter_off", Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# rotate about the glyph's own centre (containers drive the rect; pivot follows size)
	l.resized.connect(func() -> void: l.pivot_offset = l.size * 0.5)
	l.add_to_group(&"scalable_text")
	return l


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


## The paper texture, Studio-swappable by stable ID first (LOOKFEEL_PASS_2026-07).
static func paper_texture() -> Texture2D:
	var t := AssetBinder.get_texture("ui/paper_page")
	if t != null:
		return t
	return _res(PAPER_TEX) as Texture2D


## THE page ground (every book screen): a real aged-paper sheet lying on a
## near-black desk — page shadow, a stacked page-edge at right/bottom so it reads
## as an open book, the parchment texture across the sheet (FFC's book-on-a-desk
## framing). `mode` mirrors FFSettings.ReadingTheme: 0 Parchment · 1 Sepia (warmer
## wash) · 2 Dark (the same page read by lantern-light — the paper darkens, the
## ink on it is flipped to parchment by the caller). Falls back to a flat
## Tallow/Vellum fill only if the texture asset is missing.
static func paper_ground(mode: int = 0) -> Control:
	var g := PaperGround.new()
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_mode(mode)
	return g


## Back-compat alias (screens that only ever wanted "a parchment page").
static func page_background(dark: bool = false) -> Control:
	return paper_ground(2 if dark else 0)


## The physical page on the desk. The paper itself is a TextureRect CHILD (the
## proven render path — plates use it), while the desk, cast shadow and stacked
## page-edge are cheap parent draws underneath. Deterministic — screenshot-stable
## for visual-judge.
class PaperGround extends Control:
	var mode: int = 0
	var _paper: TextureRect
	## Desk border around the sheet (the page never bleeds to the screen edge).
	const M_X := 26.0
	const M_TOP := 16.0
	const M_BOT := 20.0

	func _init() -> void:
		_paper = TextureRect.new()
		_paper.texture = FFUI.paper_texture()
		_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paper.stretch_mode = TextureRect.STRETCH_SCALE
		_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_paper.offset_left = M_X
		_paper.offset_right = -M_X
		_paper.offset_top = M_TOP
		_paper.offset_bottom = -M_BOT
		add_child(_paper)

	func set_mode(m: int) -> void:
		mode = m
		if _paper != null:
			match mode:
				1:  _paper.self_modulate = Color(1.0, 0.90, 0.72)     # sepia — warmer wash
				2:  _paper.self_modulate = Color(0.34, 0.335, 0.30)   # dark — lantern-lit page
				_:  _paper.self_modulate = Color.WHITE
		queue_redraw()

	## The rect the page sheet occupies (children/callers may align columns to it).
	func page_rect() -> Rect2:
		return Rect2(Vector2(M_X, M_TOP), size - Vector2(M_X * 2.0, M_TOP + M_BOT))

	func _draw() -> void:
		# the desk
		draw_rect(Rect2(Vector2.ZERO, size), FFUI.DESK, true)
		var r := page_rect()
		# soft cast shadow under the sheet (three widening translucent skirts)
		for i in 3:
			var grow := 3.0 + 4.0 * float(i)
			draw_rect(r.grow(grow), Color(0, 0, 0, 0.16 - 0.045 * float(i)), true)
		# the stacked page-edge: thin cream leaves peeking at right + bottom (a book,
		# not a lone sheet)
		var leaf := Color(FFUI.PARCHMENT.r * 0.86, FFUI.PARCHMENT.g * 0.84, FFUI.PARCHMENT.b * 0.78)
		for i in 3:
			var off := 2.0 + 2.0 * float(i)
			var lr := Rect2(r.position + Vector2(off, off), r.size)
			draw_rect(lr, leaf.darkened(0.10 * float(i)), true)
		# flat parchment under the TextureRect child (covers a missing texture)
		draw_rect(r, FFUI.VELLUM if mode == 2 else FFUI.PARCHMENT, true)


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


## An OPAQUE engraved parchment card — the LOOKFEEL panel treatment shared by the
## Dice overlay, Options, Map, popups and the combat chrome: a paper-textured fill,
## a thin double rule (accent outer, umber hairline inner), corner ticks, and
## pinned brass tacks (the FFC "card pinned to the page" read). `dark` keeps the
## old vellum variant for night surfaces.
static func framed_panel(border: Color = VERDIGRIS, dark: bool = false) -> PanelContainer:
	var p := EngravedCard.new()
	p.accent = border
	p.dark = dark
	# the card IS paper: the page texture as the panel stylebox (StyleBoxTexture is
	# the reliable canvas texture path), tinted toward vellum for dark cards
	var tex := paper_texture()
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.modulate_color = Color(0.16, 0.155, 0.14) if dark else Color.WHITE
		sb.content_margin_left = 26
		sb.content_margin_right = 26
		sb.content_margin_top = 22
		sb.content_margin_bottom = 22
		p.add_theme_stylebox_override(&"panel", sb)
	else:
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color("241f19") if dark else PARCHMENT_2
		fb.set_corner_radius_all(2)
		fb.content_margin_left = 26
		fb.content_margin_right = 26
		fb.content_margin_top = 22
		fb.content_margin_bottom = 22
		p.add_theme_stylebox_override(&"panel", fb)
	return p


## The engraved card body: paper texture + double rule + corner ticks + pin tacks.
class EngravedCard extends PanelContainer:
	var accent: Color = FFUI.VERDIGRIS
	var dark := false
	var pins := true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# cast-shadow halo just outside the card (StyleBoxTexture has no shadow)
		for i in 3:
			draw_rect(r.grow(1.0 + 2.5 * float(i)), Color(0, 0, 0, 0.22 - 0.06 * float(i)), false, 2.5)
		# double rule: accent outer + umber hairline inner
		var o := r.grow(-7.0)
		draw_rect(o, accent, false, 2.0)
		var inner := o.grow(-4.0)
		var hair := Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.55)
		if dark:
			hair = Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.25)
		draw_rect(inner, hair, false, 1.0)
		# corner ticks on the outer rule
		var t := 7.0
		for c in [o.position, Vector2(o.end.x, o.position.y), Vector2(o.position.x, o.end.y), o.end]:
			draw_rect(Rect2(c - Vector2(t * 0.5, t * 0.5), Vector2(t, t)),
				Color(accent.r, accent.g, accent.b, 0.30), true)
		if pins:
			# brass pin tacks (FFC) just inside each corner
			var brass := Color("8a6f3c")
			var lit := Color("c9ad6e")
			for c in [o.position + Vector2(10, 10), Vector2(o.end.x - 10, o.position.y + 10),
					Vector2(o.position.x + 10, o.end.y - 10), o.end - Vector2(10, 10)]:
				draw_circle(c + Vector2(1, 1.5), 3.4, Color(0, 0, 0, 0.35))
				draw_circle(c, 3.2, brass)
				draw_circle(c - Vector2(0.9, 0.9), 1.1, lit)


## A thin double rule with a small centre diamond — the Brante-style section rule
## used beneath every engraved title.
static func diamond_rule(accent: Color = VERDIGRIS) -> Control:
	var c := DiamondRule.new()
	c.accent = accent
	c.custom_minimum_size = Vector2(0, 14)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


class DiamondRule extends Control:
	var accent: Color = FFUI.VERDIGRIS

	func _draw() -> void:
		var y := size.y * 0.5
		var ink := Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.85)
		var cx := size.x * 0.5
		var gap := 12.0
		draw_line(Vector2(0, y), Vector2(cx - gap, y), ink, 1.6)
		draw_line(Vector2(cx + gap, y), Vector2(size.x, y), ink, 1.6)
		draw_line(Vector2(0, y + 3), Vector2(cx - gap, y + 3),
			Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.45), 1.0)
		draw_line(Vector2(cx + gap, y + 3), Vector2(size.x, y + 3),
			Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.45), 1.0)
		var d := 5.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, y - d), Vector2(cx + d, y + 1.5), Vector2(cx, y + d + 3), Vector2(cx - d, y + 1.5)]),
			accent)


## An engraved screen/panel title: tracked small-caps over the diamond rule.
static func engraved_header(text: String, size: int = 26, color: Color = INK, accent: Color = VERDIGRIS) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	var t := title(text, size, color)
	v.add_child(t)
	v.add_child(diamond_rule(accent))
	return v


## The Veritas plate presentation: the illustration set in a thin double-rule
## frame on a paper mat with a soft shadow, caption in small-caps beneath.
## `content` is added inside the frame (usually a TextureRect).
static func plate_frame(content: Control, accent: Color = UMBER) -> Control:
	var f := PlateFrame.new()
	f.accent = accent
	f.add_theme_constant_override(&"margin_left", 14)
	f.add_theme_constant_override(&"margin_right", 14)
	f.add_theme_constant_override(&"margin_top", 12)
	f.add_theme_constant_override(&"margin_bottom", 12)
	f.add_child(content)
	return f


class PlateFrame extends MarginContainer:
	var accent: Color = FFUI.UMBER

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# shadow skirt + paper mat a touch lighter than the page
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.18), true)
		draw_rect(r, Color(FFUI.PARCHMENT.r * 1.02, FFUI.PARCHMENT.g * 1.02, FFUI.PARCHMENT.b * 1.0), true)
		# double rule around the plate opening
		var o := r.grow(-6.0)
		draw_rect(o, Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.9), false, 1.8)
		draw_rect(o.grow(-3.0), Color(accent.r, accent.g, accent.b, 0.55), false, 1.0)


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
	# Engraved book-entry treatment (LOOKFEEL): a quiet ruled line on the paper,
	# not a grey web button — thin ink underline, a left accent stem on hover, the
	# fill barely deeper than the page so the prose stays the loudest thing.
	b.add_theme_stylebox_override(&"normal", _entry_box(Color(0.13, 0.10, 0.06, 0.035), Color(INK.r, INK.g, INK.b, 0.55), 0))
	b.add_theme_stylebox_override(&"hover", _entry_box(Color(0.42, 0.55, 0.46, 0.12), VERDIGRIS, 3))
	b.add_theme_stylebox_override(&"pressed", _entry_box(Color(0.13, 0.10, 0.06, 0.16), Color(INK.r, INK.g, INK.b, 0.8), 3))
	b.add_theme_stylebox_override(&"focus", _entry_box(Color(0, 0, 0, 0), Color(ARREARS.r, ARREARS.g, ARREARS.b, 0.7), 3))
	b.add_theme_color_override(&"font_color", INK)
	b.add_theme_color_override(&"font_hover_color", INK)
	b.add_theme_color_override(&"font_focus_color", INK)
	b.add_theme_color_override(&"font_pressed_color", INK)
	if locked:
		b.disabled = true
		b.add_theme_stylebox_override(&"disabled", _entry_box(Color(0.3, 0.28, 0.22, 0.06), Color(FEN.r, FEN.g, FEN.b, 0.5), 0))
		b.add_theme_color_override(&"font_disabled_color", Color(UMBER.r, UMBER.g, UMBER.b, 0.72))
	b.add_to_group(&"scalable_text")
	return b


## A choice-entry stylebox: soft paper fill, an ink rule underneath, an optional
## left accent stem (`stem` px) — the whole "choices are lines in the book" idiom.
static func _entry_box(fill: Color, rule: Color, stem: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = rule
	s.border_width_bottom = 2
	s.border_width_left = stem
	s.set_corner_radius_all(1)
	s.content_margin_left = 16
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## A small labelled action chip ([Test your Luck] / [Eat] etc.).
static func chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_override(&"font", font_body())
	b.add_theme_font_size_override(&"font_size", 16)
	b.add_theme_stylebox_override(&"normal", panel_box(Color("e0d5b6"), Color(UMBER.r, UMBER.g, UMBER.b, 0.7), 1, 2))
	b.add_theme_stylebox_override(&"hover", panel_box(Color("e7ddc2"), VERDIGRIS, 1, 2))
	b.add_theme_stylebox_override(&"pressed", panel_box(Color("cfc4a2"), Color(INK.r, INK.g, INK.b, 0.8), 1, 2))
	b.add_theme_stylebox_override(&"focus", panel_box(Color(0, 0, 0, 0), Color(ARREARS.r, ARREARS.g, ARREARS.b, 0.6), 1, 2))
	b.add_theme_stylebox_override(&"disabled", panel_box(Color(0.85, 0.8, 0.68, 0.35), Color(FEN.r, FEN.g, FEN.b, 0.5), 1, 2))
	b.add_theme_color_override(&"font_color", INK)
	b.add_theme_color_override(&"font_disabled_color", Color(UMBER.r, UMBER.g, UMBER.b, 0.6))
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


## A compact "SKILL 9" stat pill for the HUD — printed caption, the value in the
## player's own hand (the sheet idiom carried into the page chrome).
static func stat_pill(name: String, value: String, accent: Color = INK) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.10, 0.06, 0.05)
	sb.border_color = Color(UMBER.r, UMBER.g, UMBER.b, 0.5)
	sb.border_width_bottom = 1
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override(&"panel", sb)
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	var n := label(name, 12, UMBER, false)
	n.add_theme_font_override(&"font", font_display_tracked(1))
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(n)
	var v := handwritten(value, 20, accent if accent != INK else INK_PEN, "pill_%s_%s" % [name, value])
	box.add_child(v)
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
