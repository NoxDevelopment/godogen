extends Control
## FF-gamebook main menu (vendored nox_ui). Reads title/subtitle/backdrop/credits from
## NoxShell (per-game NoxShellConfig). Phase-7 shell wiring layered on the generic
## shell without forking its behaviour:
##   * Continue  → NoxShell.resume_last() (resumes the newest save; visible only when a
##                 save exists — the #25 bug fix, shared with the nox_ui SOURCE).
##   * Load      → the loading-continue slot picker (load_screen, LOAD mode) over the
##                 FF SaveManager.
##   * Options   → the fully-fleshed tabbed Options overlay.
##   * Credits   → the credits skill's scrolling credits.tscn (asset-heavy mode),
##                 replacing the overflow-prone inline text panel.
## These per-template routes live in this vendored copy; the shared SOURCE stays
## generic (see the re-vendoring note in the skeleton's phase report).

const OPTIONS_VIEW := preload("res://scripts/screens/options_view.gd")
const LOAD_SCREEN := preload("res://addons/loading/load_screen.tscn")
const CREDITS_SCENE := "res://credits.tscn"

@onready var _title: Label = $CenterBox/VBox/Title
@onready var _subtitle: Label = $CenterBox/VBox/Subtitle
@onready var _continue: Button = $CenterBox/VBox/Continue
@onready var _backdrop: TextureRect = $Backdrop

func _ready() -> void:
	_title.text = NoxShell.title()
	_subtitle.text = NoxShell.subtitle()
	_subtitle.visible = _subtitle.text.strip_edges() != ""
	_continue.visible = NoxShell.has_resumable()
	var bp := NoxShell.backdrop_path()
	if bp != "" and ResourceLoader.exists(bp):
		_backdrop.texture = load(bp)
		_backdrop.visible = true
	else:
		_backdrop.visible = false
	_apply_book_dress()
	# Title / Main Menu bed — brooding invitation (STYLE_GUIDE §2.2). AudioDirector is a
	# project autoload; guard so the shell still runs where one isn't shipped. UI-click
	# SFX is auto-wired onto every Button.
	var _ad := get_node_or_null("/root/AudioDirector")
	if _ad != null:
		_ad.play_music("menu")
	_first_focus()

func _first_focus() -> void:
	$CenterBox/VBox/NewGame.grab_focus()


## FF-template dress (LOOKFEEL_PASS_2026-07 §menu): the generic web-shell chrome
## becomes a book cover — the amber accent bar goes, the title sets in the
## engraved tracked display face over a diamond rule, and the menu entries become
## engraved parchment plates over the darkened cover art. Per-template styling
## lives in this vendored copy; the shared nox_ui SOURCE stays generic.
func _apply_book_dress() -> void:
	var accent := get_node_or_null("Accent")
	if accent != null:
		accent.visible = false
	# deepen the cover art so the lockup carries
	_backdrop.self_modulate = Color(0.34, 0.33, 0.36)
	# engraved title lockup
	_title.add_theme_font_override(&"font", FFUI.font_display_tracked(4))
	_title.add_theme_font_size_override(&"font_size", 64)
	_title.add_theme_color_override(&"font_color", FFUI.PARCHMENT)
	_title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override(&"shadow_offset_x", 2)
	_title.add_theme_constant_override(&"shadow_offset_y", 3)
	_subtitle.add_theme_font_override(&"font", FFUI.font_body())
	_subtitle.add_theme_font_size_override(&"font_size", 17)
	_subtitle.add_theme_color_override(&"font_color", FFUI.VERDIGRIS_2)
	# a diamond rule between the lockup and the entries
	var vbox := $CenterBox/VBox
	var rule := FFUI.diamond_rule(FFUI.VERDIGRIS)
	rule.custom_minimum_size = Vector2(360, 14)
	vbox.add_child(rule)
	vbox.move_child(rule, _subtitle.get_index() + 1)
	# the entries: engraved parchment plates
	for b in [$CenterBox/VBox/NewGame, _continue, $CenterBox/VBox/Load,
			$CenterBox/VBox/Options, $CenterBox/VBox/Credits, $CenterBox/VBox/Quit]:
		if b == null:
			continue
		_dress_button(b)


func _dress_button(b: Button) -> void:
	b.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	b.add_theme_font_size_override(&"font_size", 19)
	b.add_theme_color_override(&"font_color", FFUI.INK)
	b.add_theme_color_override(&"font_hover_color", FFUI.INK)
	b.add_theme_color_override(&"font_pressed_color", FFUI.INK)
	b.add_theme_color_override(&"font_focus_color", FFUI.INK)
	b.add_theme_stylebox_override(&"normal", _plate_box(Color("e2d8bc"), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.9)))
	b.add_theme_stylebox_override(&"hover", _plate_box(Color("ece2c6"), FFUI.VERDIGRIS))
	b.add_theme_stylebox_override(&"pressed", _plate_box(Color("cfc4a2"), FFUI.INK))
	b.add_theme_stylebox_override(&"focus", _plate_box(Color(0, 0, 0, 0), Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.8)))


func _plate_box(fill: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_size = 6
	s.shadow_color = Color(0, 0, 0, 0.35)
	return s

func _on_new_game_pressed() -> void: NoxShell.new_game()
func _on_continue_pressed() -> void: NoxShell.resume_last()

func _on_load_pressed() -> void:
	var ls := LOAD_SCREEN.instantiate()
	ls.mode = 0   # load_screen.Mode.LOAD
	add_child(ls)

func _on_options_pressed() -> void:
	add_child(OPTIONS_VIEW.new())

func _on_credits_pressed() -> void:
	if ResourceLoader.exists(CREDITS_SCENE):
		get_tree().change_scene_to_file(CREDITS_SCENE)
	else:
		push_warning("main_menu: credits scene missing at %s" % CREDITS_SCENE)

func _on_quit_pressed() -> void: NoxShell.quit_game()
