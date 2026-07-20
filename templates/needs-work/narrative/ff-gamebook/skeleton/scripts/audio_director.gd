extends Node
## res://scripts/audio_director.gd
## AudioDirector (autoload "AudioDirector") — the game's whole soundscape, Phase 6.
##
## Two responsibilities, both routed through the standard NoxDev bus layout
## (default_bus_layout.tres → Master / Music / SFX) so NoxSettings' volume sliders
## govern everything (STYLE_GUIDE §2.4 "volume-respecting"):
##
##   * MUSIC — one looping bed per game STATE (menu / explore / tension / combat /
##     boss / death / victory) on the **Music** bus, with a simple equal-time
##     CROSSFADE on every state change (STYLE_GUIDE §2.2). Two players ping-pong so
##     the outgoing bed fades out while the incoming fades in.
##   * SFX — a pooled set of one-shots on the **SFX** bus: the sacred dice, combat
##     hit/wound/parry, page-turn, UI click, potion, provision, coin, item pickup
##     (STYLE_GUIDE §2.3). Music ducks briefly under the dice + combat resolution
##     (STYLE_GUIDE §2.4 "the roll is the moment").
##
## Every clip is resolved by STABLE SLOT ID through the AssetBinder, exactly like
## the art (assets.manifest.json). Scene code never hardcodes an audio path — it
## asks the director by logical name, so Jesus can hot-swap a track from the Studio
## with no code edits. UI-click is auto-wired to every Button in the tree so the
## generic nox_ui shell needs no per-template edits.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const CROSSFADE := 1.1          # seconds, equal-power-ish linear on dB
const SILENT_DB := -60.0
const SFX_POOL := 8
const DUCK_DB := -8.0           # music dip under dice/combat resolution
const DUCK_HOLD := 0.30

## state -> music slot id (assets.manifest.json)
const MUSIC_SLOTS := {
	"menu": "audio/music/menu",
	"explore": "audio/music/explore",
	"tension": "audio/music/tension",
	"combat": "audio/music/combat",
	"boss": "audio/music/boss",
	"death": "audio/music/death",
	"victory": "audio/music/victory",
}

## logical sfx name -> slot id(s). A list picks a random variant per play.
const SFX_SLOTS := {
	"ui_click": "audio/sfx/ui_click",
	"page_turn": ["audio/sfx/page_turn_1", "audio/sfx/page_turn_2"],
	"dice_shake": "audio/sfx/dice_shake",
	"dice_land": "audio/sfx/dice_land",
	"hit": "audio/sfx/hit",
	"wound": "audio/sfx/wound",
	"parry": "audio/sfx/parry",
	"potion": "audio/sfx/potion",
	"eat": "audio/sfx/eat",
	"coin": "audio/sfx/coin",
	"pickup": "audio/sfx/pickup",
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active: AudioStreamPlayer     # currently-audible music player
var _current_state := ""
var _fade: Tween
var _duck: Tween
var _sfx: Array[AudioStreamPlayer] = []
var _wired: Dictionary = {}        # button instance_id -> true (avoid double-connect)


func _ready() -> void:
	# keep music/SFX alive while the tree is paused (pause menu, overlays)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_active = _music_a
	for _i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx.append(p)
	# auto-wire UI-click onto every Button, present and future, so the generic
	# nox_ui shell + all game screens get feedback with zero per-scene edits.
	get_tree().node_added.connect(_on_node_added)
	_wire_existing_buttons(get_tree().root)


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = MUSIC_BUS
	p.volume_db = SILENT_DB
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


# --- music -------------------------------------------------------------------


## Crossfade to the bed for `state` (menu/explore/tension/combat/boss/death/
## victory). No-op if already on that state. Missing clips fade the current bed
## out rather than cutting to silence.
func play_music(state: String) -> void:
	if state == _current_state:
		return
	_current_state = state
	var stream := _resolve(MUSIC_SLOTS.get(state, ""))
	if stream == null:
		stop_music()
		return
	_set_loop(stream, true)
	var incoming := _music_b if _active == _music_a else _music_a
	var outgoing := _active
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_active = incoming
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(incoming, "volume_db", 0.0, CROSSFADE)
	if outgoing.playing:
		_fade.tween_property(outgoing, "volume_db", SILENT_DB, CROSSFADE)
		_fade.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	_current_state = ""
	if _active != null and _active.playing:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_fade = create_tween()
		var a := _active
		_fade.tween_property(a, "volume_db", SILENT_DB, CROSSFADE)
		_fade.tween_callback(a.stop)


## Briefly dip the music so a key SFX (the dice, a wound) reads cleanly, then
## recover (STYLE_GUIDE §2.4). Ducks the audible player, not the bus, so it never
## fights NoxSettings' Music volume.
func duck_music(amount: float = DUCK_DB, hold: float = DUCK_HOLD) -> void:
	if _active == null or not _active.playing:
		return
	if _fade != null and _fade.is_valid():
		return   # don't duck mid-crossfade
	if _duck != null and _duck.is_valid():
		_duck.kill()
	_duck = create_tween()
	_duck.tween_property(_active, "volume_db", amount, 0.08)
	_duck.tween_interval(hold)
	_duck.tween_property(_active, "volume_db", 0.0, 0.45)


# --- sfx ---------------------------------------------------------------------


## Play a one-shot by logical name (see SFX_SLOTS). `duck` dips the music under it.
func play_sfx(name: String, duck: bool = false) -> void:
	var slot: Variant = SFX_SLOTS.get(name, "")
	var slot_id := ""
	if slot is Array and not (slot as Array).is_empty():
		slot_id = str((slot as Array).pick_random())
	else:
		slot_id = str(slot)
	var stream := _resolve(slot_id)
	if stream == null:
		return
	_set_loop(stream, false)
	var p := _free_sfx_player()
	p.stream = stream
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()
	if duck:
		duck_music()


func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx:
		if not p.playing:
			return p
	return _sfx[0]   # all busy — steal the oldest


# --- UI-click auto-wiring ----------------------------------------------------


func _on_node_added(n: Node) -> void:
	if n is Button:
		_wire_button(n)


func _wire_existing_buttons(root: Node) -> void:
	if root is Button:
		_wire_button(root)
	for c in root.get_children():
		_wire_existing_buttons(c)


func _wire_button(b: Button) -> void:
	var key := b.get_instance_id()
	if _wired.has(key):
		return
	_wired[key] = true
	b.pressed.connect(func() -> void: play_sfx("ui_click"))
	b.tree_exited.connect(func() -> void: _wired.erase(key))


# --- helpers -----------------------------------------------------------------


func _resolve(slot_id: String) -> AudioStream:
	if slot_id == "":
		return null
	var binder := get_node_or_null("/root/AssetBinder")
	if binder != null and binder.has_slot(slot_id):
		return binder.get_stream(slot_id)
	return null


func _set_loop(s: AudioStream, on: bool) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = on
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = on
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
