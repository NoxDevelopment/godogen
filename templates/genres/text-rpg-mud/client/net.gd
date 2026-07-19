extends Node
## NoxMUD client networking — speaks Evennia's webclient websocket protocol.
##
## Evennia sends JSON arrays ["cmd", [args], {kwargs}] over ws://host:4002/.
## For cmd == "text", args[0] is HTML with <span class="color-NNN"> color spans +
## <br> line breaks + HTML entities. We convert that to Godot BBCode and emit it;
## the UI renders it in a RichTextLabel. Commands are sent back as ["text",[cmd],{}].

signal text_received(bbcode: String)
signal prompt_received(text: String)
signal connected()
signal disconnected()
signal oob_received(cmd: String, args: Array, kwargs: Dictionary)

@export var url: String = "ws://127.0.0.1:4002/"
@export var auto_login: String = ""  # e.g. "connect noxadmin NoxLoomDev2026"

var _sock := WebSocketPeer.new()
var _was_open := false
var _xterm: PackedColorArray

func _ready() -> void:
	_build_xterm_palette()
	_sock.connect_to_url(url)

func _process(_delta: float) -> void:
	_sock.poll()
	var state := _sock.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			connected.emit()
			if auto_login != "":
				send(auto_login)
		while _sock.get_available_packet_count() > 0:
			var raw := _sock.get_packet().get_string_from_utf8()
			_handle(raw)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _was_open:
			_was_open = false
			disconnected.emit()

func send(command: String) -> void:
	if _sock.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_sock.send_text(JSON.stringify(["text", [command], {}]))

func _handle(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY or parsed.is_empty():
		return
	var cmd := str(parsed[0])
	var args: Array = parsed[1] if parsed.size() > 1 and typeof(parsed[1]) == TYPE_ARRAY else []
	var kwargs: Dictionary = parsed[2] if parsed.size() > 2 and typeof(parsed[2]) == TYPE_DICTIONARY else {}
	match cmd:
		"text":
			if not args.is_empty():
				text_received.emit(_html_to_bbcode(str(args[0])))
		"prompt":
			if not args.is_empty():
				prompt_received.emit(_strip_tags(str(args[0])))
		_:
			# OOB (GMCP-style) — vitals/room/hands data plugs in here later.
			oob_received.emit(cmd, args, kwargs)

# --- HTML (Evennia webclient markup) -> Godot BBCode -----------------------

func _html_to_bbcode(html: String) -> String:
	var s := html
	s = s.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	# color spans -> [color=#hex]
	var re := RegEx.new()
	re.compile("<span class=\"([a-zA-Z0-9_\\- ]+)\">")
	var out := ""
	var pos := 0
	var m := re.search(s, pos)
	while m:
		out += s.substr(pos, m.get_start() - pos)
		out += _span_class_to_bbcode(m.get_string(1))
		pos = m.get_end()
		m = re.search(s, pos)
	out += s.substr(pos)
	out = out.replace("</span>", "[/color]")
	out = out.replace("<b>", "[b]").replace("</b>", "[/b]")
	out = _strip_tags(out)
	return _unescape(out)

func _span_class_to_bbcode(cls: String) -> String:
	# classes look like "color-012" (foreground) or "bgcolor-000"; take the first color-NNN
	for token in cls.split(" ", false):
		if token.begins_with("color-"):
			var idx := token.substr(6).to_int()
			if idx >= 0 and idx < _xterm.size():
				return "[color=#%s]" % _xterm[idx].to_html(false)
	return "[color=#d8d2c2]"  # default parchment text

func _strip_tags(s: String) -> String:
	var re := RegEx.new()
	re.compile("<[^>]+>")
	return re.sub(s, "", true)

func _unescape(s: String) -> String:
	return (s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
		.replace("&#39;", "'").replace("&nbsp;", " ").replace("&amp;", "&"))

# --- xterm-256 palette (Evennia color-NNN maps to this) --------------------

func _build_xterm_palette() -> void:
	_xterm = PackedColorArray()
	# 0-15: standard + bright ANSI
	var base := [
		"000000", "aa0000", "00aa00", "aa5500", "0000aa", "aa00aa", "00aaaa", "aaaaaa",
		"555555", "ff5555", "55ff55", "ffff55", "5555ff", "ff55ff", "55ffff", "ffffff",
	]
	for h in base:
		_xterm.append(Color.html(h))
	# 16-231: 6x6x6 color cube
	var steps := [0, 95, 135, 175, 215, 255]
	for r in range(6):
		for g in range(6):
			for b in range(6):
				_xterm.append(Color8(steps[r], steps[g], steps[b]))
	# 232-255: grayscale ramp
	for i in range(24):
		var v := 8 + i * 10
		_xterm.append(Color8(v, v, v))
