extends Control
## JSON-driven VN runtime — plays res://vn/story.vn.json exported from the Studio
## VN Maker. Honors the Immersion Engine P2 additions: each line's expression
## drives an emotion portrait swap (VnRuntime.resolve_sprite) and the per-line
## voice delivery (VnRuntime.voice_instruction) is resolved from the character's
## voice binding — ready for a TTS drop-in (see _speak).
##
## The UI is built in code so the scene file stays a bare Control + script (no
## fragile hand-authored .tscn). Backgrounds/portraits load when the exported
## path is a resource/file Godot can read; Studio web paths fall back to a tint.

const STORY_PATH := "res://vn/story.vn.json"

var _chars := {}       # id -> character dict
var _bgs := {}         # id -> background dict
var _scenes := {}      # id -> scene dict
var _order := []       # scene ids in author order (for last-scene detection)
var _scene_id := ""
var _line_idx := 0
var _flags := {}
var _vars := {}  # numeric stats/meters (Immersion P4)

# Cutscene playback (VN Maker E1) — a scene's opening cutscene is an ordered list of
# panels (static screens and/or Daz clips + captions), played one at a time before the
# dialogue. Played once per scene (re-entry doesn't replay).
var _cutscene_panels := []
var _panel_idx := 0
var _in_cutscene := false
var _cut_done := {}     # scene ids whose cutscene has already played

var _bg_color: ColorRect
var _bg: TextureRect
var _portrait: TextureRect
var _portrait_tint: ColorRect
var _name: Label
var _text: Label
var _emotion: Label
var _hint: Label
var _choices: VBoxContainer

# Cutscene overlay (built on top of everything, hidden until a cutscene plays)
var _cut_layer: Control
var _cut_media: TextureRect
var _cut_video: VideoStreamPlayer
var _cut_caption: Label
var _cut_hint: Label
var _cut_timer: Timer


func _ready() -> void:
	_build_ui()
	if not FileAccess.file_exists(STORY_PATH):
		_text.text = "No exported VN found.\nExport from the Studio VN Maker to res://vn/story.vn.json."
		return
	var f := FileAccess.open(STORY_PATH, FileAccess.READ)
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_text.text = "story.vn.json is not valid VN JSON."
		return
	for c in parsed.get("characters", []):
		_chars[str(c.get("id", ""))] = c
	for b in parsed.get("backgrounds", []):
		_bgs[str(b.get("id", ""))] = b
	for s in parsed.get("scenes", []):
		var sid := str(s.get("id", ""))
		_scenes[sid] = s
		_order.append(sid)
	_scene_id = str(parsed.get("start", ""))
	if not _scenes.has(_scene_id) and not _order.is_empty():
		_scene_id = _order[0]
	_enter_scene(_scene_id)


## Enter a scene: if it opens with an unplayed cutscene, play that first; otherwise
## render the dialogue. The only place a cutscene is (re)started, so line-advance
## inside a scene never restarts it.
func _enter_scene(id: String) -> void:
	_scene_id = id
	_line_idx = 0
	var sc := _cur_scene()
	var cut = sc.get("cutscene", null)
	if typeof(cut) == TYPE_DICTIONARY and not bool(_cut_done.get(id, false)):
		var panels: Array = cut.get("panels", [])
		if not panels.is_empty():
			_cutscene_panels = panels
			_panel_idx = 0
			_in_cutscene = true
			_cut_layer.visible = true
			_render_panel()
			return
	_in_cutscene = false
	_cut_layer.visible = false
	_render()


## Draw the current cutscene panel — a Daz clip if the file is a playable VideoStream,
## else a static image, plus the caption card and a progress/click hint.
func _render_panel() -> void:
	var p: Dictionary = _cutscene_panels[clampi(_panel_idx, 0, _cutscene_panels.size() - 1)]
	var img := str(p.get("image", ""))
	var clip := str(p.get("clip", ""))
	var cap := str(p.get("caption", ""))
	_cut_timer.stop()
	_cut_video.stop()
	_cut_video.visible = false
	_cut_media.texture = null
	_cut_media.visible = false
	# Prefer the clip when it's a stream Godot can play (e.g. .ogv); Daz .mp4 needs
	# converting to .ogv/.webm — a static image or the caption card covers the rest.
	if clip != "" and ResourceLoader.exists(clip):
		var vs = load(clip)
		if vs is VideoStream:
			_cut_video.stream = vs
			_cut_video.visible = true
			_cut_video.play()
	if not _cut_video.visible and img != "":
		_set_texture(_cut_media, img)
		_cut_media.visible = _cut_media.texture != null
	_cut_caption.text = cap
	_cut_caption.visible = cap != ""
	var n := _cutscene_panels.size()
	var is_last := _panel_idx + 1 >= n
	var prefix := ("%d/%d · " % [_panel_idx + 1, n]) if n > 1 else ""
	_cut_hint.text = "%s▸ click to %s" % [prefix, ("continue" if is_last else "advance")]
	var dur := int(p.get("durationMs", 0))
	if dur > 0:
		_cut_timer.wait_time = float(dur) / 1000.0
		_cut_timer.start()


## Advance to the next cutscene panel, or end the cutscene and start the dialogue.
func _advance_panel() -> void:
	if not _in_cutscene:
		return
	_cut_timer.stop()
	if _panel_idx + 1 >= _cutscene_panels.size():
		_in_cutscene = false
		_cut_done[_scene_id] = true
		_cut_video.stop()
		_cut_layer.visible = false
		_render()
	else:
		_panel_idx += 1
		_render_panel()


func _cur_scene() -> Dictionary:
	return _scenes.get(_scene_id, {})


func _cur_line() -> Dictionary:
	var lines: Array = _cur_scene().get("lines", [])
	if lines.is_empty():
		return {}
	return lines[clampi(_line_idx, 0, lines.size() - 1)]


func _render() -> void:
	var sc := _cur_scene()
	var bg: Dictionary = _bgs.get(str(sc.get("background", "")), {})
	_set_texture(_bg, str(bg.get("image", "")))

	var ln := _cur_line()
	var speaker_id := str(ln.get("speaker", ""))
	var expr := str(ln.get("expression", ""))

	if speaker_id != "" and _chars.has(speaker_id):
		var ch: Dictionary = _chars[speaker_id]
		var col := _color(str(ch.get("color", "#cccccc")))
		_name.text = str(ch.get("name", ""))
		_name.add_theme_color_override("font_color", col)
		var emo := VnRuntime.canonical_emotion(expr)
		_emotion.text = emo.to_upper() if emo != "neutral" else ""
		var sprite := VnRuntime.resolve_sprite(ch.get("sprites", {}), expr)
		_set_texture(_portrait, sprite)
		_portrait_tint.color = Color(col.r, col.g, col.b, 0.35) if sprite == "" else Color.TRANSPARENT
		_portrait.visible = true
		_portrait_tint.visible = true
		_speak(ch, expr)
	else:
		_name.text = ""
		_emotion.text = ""
		_portrait.visible = false
		_portrait_tint.visible = false

	_text.text = str(ln.get("text", ""))
	_render_choices(sc)


## Resolve the per-line voice and hand it off. The template ships no bundled TTS,
## so this logs the resolved provider/voice/instruction (proving the P2 fields
## are consumed); a game can override _speak to synthesize or play a clip.
func _speak(character: Dictionary, expression: String) -> void:
	var provider := str(character.get("voiceProvider", "kokoro"))
	var voice := str(character.get("voice", ""))
	var instruction := VnRuntime.voice_instruction(character, expression)
	print("[VN voice] %s | %s/%s | %s" % [
		str(character.get("name", "")), provider, voice, instruction,
	])


func _render_choices(sc: Dictionary) -> void:
	# remove_child detaches immediately (queue_free alone is deferred, so a
	# same-frame re-render would briefly stack stale buttons).
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	var lines: Array = sc.get("lines", [])
	var at_last := _line_idx >= lines.size() - 1
	var visible := []
	for ch in sc.get("choices", []):
		var ok := true
		for r in ch.get("requires", []):
			if not _flags.get(str(r), false):
				ok = false
				break
		if ok and not VnRuntime.var_conditions_met(_vars, ch.get("requireVars", [])):
			ok = false
		if ok:
			visible.append(ch)
	if at_last and not visible.is_empty():
		_hint.text = ""
		for ch in visible:
			var b := Button.new()
			b.text = str(ch.get("text", "(continue)"))
			b.pressed.connect(_on_choice.bind(ch))
			_choices.add_child(b)
	else:
		var ended := at_last and visible.is_empty() and str(sc.get("next", "")) == ""
		_hint.text = "— The End —" if ended else "▸ click / Enter to continue"


func _on_choice(ch: Dictionary) -> void:
	for f in ch.get("sets", []):
		_flags[str(f)] = true
	_vars = VnRuntime.apply_var_ops(_vars, ch.get("setVars", []))
	var goto := str(ch.get("goto", ""))
	if goto != "" and _scenes.has(goto):
		_enter_scene(goto)


func _unhandled_input(e: InputEvent) -> void:
	var advance := false
	if e is InputEventMouseButton:
		advance = e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	elif e.is_action_pressed("ui_accept"):
		advance = true
	if not advance:
		return
	if _in_cutscene:
		_advance_panel()
		return
	if _choices.get_child_count() > 0:
		return # waiting on a choice
	var sc := _cur_scene()
	var lines: Array = sc.get("lines", [])
	var at_last := _line_idx >= lines.size() - 1
	if not at_last:
		_line_idx += 1
		_render()
	elif str(sc.get("next", "")) != "" and _scenes.has(str(sc.get("next", ""))):
		_enter_scene(str(sc.get("next", "")))


func _set_texture(node: TextureRect, path: String) -> void:
	if path.strip_edges() == "":
		node.texture = null
		return
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	node.texture = tex


func _color(hex: String) -> Color:
	if hex.begins_with("#"):
		return Color.html(hex)
	return Color.WHITE


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_bg_color = ColorRect.new()
	_bg_color.color = Color(0.07, 0.09, 0.11)
	_bg_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_color)

	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_portrait_tint = ColorRect.new()
	_portrait_tint.color = Color.TRANSPARENT
	_portrait_tint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_portrait_tint.custom_minimum_size = Vector2(300, 380)
	_portrait_tint.position = Vector2(490, 200)
	_portrait_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_tint)

	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_portrait.custom_minimum_size = Vector2(300, 380)
	_portrait.position = Vector2(490, 200)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -190.0
	box.offset_left = 24.0
	box.offset_right = -24.0
	box.offset_bottom = -20.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 18)
	header.add_child(_name)

	_emotion = Label.new()
	_emotion.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	_emotion.add_theme_font_size_override("font_size", 11)
	header.add_child(_emotion)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 60)
	_text.add_theme_font_size_override("font_size", 16)
	col.add_child(_text)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	_hint.add_theme_font_size_override("font_size", 11)
	col.add_child(_hint)

	_choices = VBoxContainer.new()
	_choices.set_anchors_preset(Control.PRESET_CENTER)
	_choices.position = Vector2(440, 360)
	_choices.custom_minimum_size = Vector2(400, 0)
	_choices.add_theme_constant_override("separation", 8)
	add_child(_choices)

	# --- Cutscene overlay (on top of everything; hidden until a cutscene plays) ---
	_cut_layer = Control.new()
	_cut_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cut_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.visible = false
	add_child(_cut_layer)

	var cut_bg := ColorRect.new()
	cut_bg.color = Color.BLACK
	cut_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cut_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.add_child(cut_bg)

	_cut_video = VideoStreamPlayer.new()
	_cut_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cut_video.expand = true
	_cut_video.visible = false
	_cut_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.add_child(_cut_video)

	_cut_media = TextureRect.new()
	_cut_media.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cut_media.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cut_media.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cut_media.visible = false
	_cut_media.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.add_child(_cut_media)

	_cut_caption = Label.new()
	_cut_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_cut_caption.offset_top = -140.0
	_cut_caption.offset_bottom = -70.0
	_cut_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cut_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cut_caption.add_theme_font_size_override("font_size", 22)
	_cut_caption.add_theme_color_override("font_color", Color.WHITE)
	_cut_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.add_child(_cut_caption)

	_cut_hint = Label.new()
	_cut_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cut_hint.offset_left = -260.0
	_cut_hint.offset_top = -34.0
	_cut_hint.offset_right = -12.0
	_cut_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cut_hint.add_theme_font_size_override("font_size", 12)
	_cut_hint.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_cut_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.add_child(_cut_hint)

	_cut_timer = Timer.new()
	_cut_timer.one_shot = true
	_cut_timer.timeout.connect(_advance_panel)
	add_child(_cut_timer)
