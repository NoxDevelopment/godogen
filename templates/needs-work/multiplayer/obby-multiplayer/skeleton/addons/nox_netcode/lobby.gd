extends Control
## res://addons/nox_netcode/lobby.gd
## Shared-core lobby screen (both profiles). A minimal, theme-able Host/Join
## surface that binds ONLY to the Net autoload's clean signals — it owns no
## network logic itself. Because its labels carry the `scalable_text` group and
## it uses standard Button/LineEdit widgets, the ui-theme / settings_system
## drop-ins re-skin it with no code change (NoxDev UI ABI).
##
## Host flow: enter a name → Host → (peers join) → Start.
## Join flow: enter a name + the host address/code → Join → wait for Start.
## authority-turn adds a "Take DM seat" control; realtime hides it.

## Optional: scene to switch to when the host starts the game. Leave empty to
## let the embedding game handle game_started itself.
@export_file("*.tscn") var game_scene: String = ""

@onready var _name_edit: LineEdit = $Center/Panel/Margin/Rows/NameRow/NameEdit
@onready var _address_edit: LineEdit = $Center/Panel/Margin/Rows/AddressRow/AddressEdit
@onready var _host_button: Button = $Center/Panel/Margin/Rows/ButtonsRow/HostButton
@onready var _join_button: Button = $Center/Panel/Margin/Rows/ButtonsRow/JoinButton
@onready var _peer_list: VBoxContainer = $Center/Panel/Margin/Rows/PeerList
@onready var _ready_toggle: CheckButton = $Center/Panel/Margin/Rows/ControlsRow/ReadyToggle
@onready var _dm_button: Button = $Center/Panel/Margin/Rows/ControlsRow/DMSeatButton
@onready var _start_button: Button = $Center/Panel/Margin/Rows/StartButton
@onready var _leave_button: Button = $Center/Panel/Margin/Rows/LeaveButton
@onready var _status: Label = $Center/Panel/Margin/Rows/StatusLabel


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_ready_toggle.toggled.connect(_on_ready_toggled)
	_dm_button.pressed.connect(_on_dm_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)

	Net.lobby_changed.connect(_refresh)
	Net.peer_joined.connect(func(_id, _info): _refresh())
	Net.peer_left.connect(func(_id): _refresh())
	Net.session_started.connect(_refresh)
	Net.session_ended.connect(_on_session_ended)
	Net.connection_error.connect(_on_connection_error)
	Net.game_started.connect(_on_game_started)

	# The DM seat control is only meaningful in the authority-turn profile.
	_dm_button.visible = Net.profile() == "authority-turn"
	_refresh()


# --- Button handlers ---------------------------------------------------------

func _on_host_pressed() -> void:
	var err := Net.host({"player_name": _display_name()})
	if err != OK:
		_status.text = "Host failed — see the log."
	else:
		_status.text = "Hosting on %s:%d (%s). Waiting for players…" % [
			"0.0.0.0", Net._port, Net.transport()]
	_refresh()


func _on_join_pressed() -> void:
	var addr := _address_edit.text.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	var err := Net.join({"player_name": _display_name(), "address": addr})
	if err != OK:
		_status.text = "Join failed — see the log."
	else:
		_status.text = "Connecting to %s…" % addr
	_refresh()


func _on_ready_toggled(pressed: bool) -> void:
	Net.set_ready(pressed)


func _on_dm_pressed() -> void:
	Net.take_dm_seat()


func _on_start_pressed() -> void:
	Net.start()


func _on_leave_pressed() -> void:
	Net.leave()


# --- Net signal reactions ----------------------------------------------------

func _on_session_ended(reason: String) -> void:
	_status.text = "Session ended (%s)." % reason
	_refresh()


func _on_connection_error(message: String) -> void:
	_status.text = "Error: " + message


func _on_game_started() -> void:
	if game_scene != "":
		get_tree().change_scene_to_file.call_deferred(game_scene)
	else:
		_status.text = "Game started."


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	var in_session := Net.active
	_host_button.disabled = in_session
	_join_button.disabled = in_session
	_address_edit.editable = not in_session
	_name_edit.editable = not in_session
	_ready_toggle.disabled = not in_session
	_leave_button.disabled = not in_session
	# Only the host gates Start, and only once everyone is ready.
	_start_button.visible = Net.is_host()
	_start_button.disabled = not (Net.is_host() and _all_ready())
	_dm_button.disabled = not in_session

	for child in _peer_list.get_children():
		child.queue_free()

	var ids := Net.peers.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Net.peers[id]
		var row := Label.new()
		row.add_to_group(&"scalable_text")
		var tags: Array[String] = []
		if bool(info.get("ready", false)):
			tags.append("ready")
		if str(info.get("seat", "")) == Net.SEAT_DM:
			tags.append("DM")
		if int(id) == Net.local_id():
			tags.append("you")
		var suffix := ""
		if not tags.is_empty():
			suffix = "  [%s]" % ", ".join(tags)
		row.text = "%s%s" % [str(info.get("name", "peer %d" % id)), suffix]
		_peer_list.add_child(row)


func _all_ready() -> bool:
	if Net.peers.is_empty():
		return false
	for id in Net.peers:
		if not bool(Net.peers[id].get("ready", false)):
			return false
	return true


func _display_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if not n.is_empty() else "Player"
