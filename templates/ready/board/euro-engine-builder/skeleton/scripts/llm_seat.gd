extends RefCounted
class_name LlmSeat
## res://scripts/llm_seat.gd
## The AI_LLM seat provider hook — the ONE encapsulated seam that lets a local LLM
## drive a seat in the Euro engine-builder (play-mode matrix, STAGE 2). It is a
## pure, self-contained adapter around a local LLM HTTP endpoint (Ollama by
## default). It NEVER touches the rules: it only turns "this seat, these legal
## actions" into a CHOSEN legal action, and it ALWAYS returns something the engine
## will accept — because on ANY failure it falls back to the deterministic
## heuristic ai_choose(). An AI_LLM seat with no provider therefore plays EXACTLY
## like an AI_HEURISTIC seat; the game can never stall on it.
##
## The flow (choose_action_async):
##   1. options := engine.legal_actions(seat)           (the ONLY choosable set)
##   2. if the provider is disabled -> heuristic fallback (no network touched)
##   3. build a COMPACT prompt: the seat's resources / tableau / VP / the goal, and
##      the legal actions ENUMERATED as a numbered list; ask for just the number.
##   4. POST it to the configured endpoint via HTTPRequest with a HARD timeout.
##   5. on a 2xx JSON reply, parse the chosen number -> a 0-based index into
##      `options`, then RE-VALIDATE it with is_legal() before returning it.
##   6. on ANY failure (unreachable, timeout, non-2xx, unparseable, out-of-range,
##      or an index that does not re-validate as legal) -> ai_choose() fallback.
##
## Everything except the live model response is deterministic and unit-testable:
## build_prompt(), parse_index() and resolve() are pure and are exercised head-
## lessly by the probes (an injected-reply path), so no running Ollama is needed
## to prove the parse + validate + fallback contract.

# =====================================================================
#  Provider configuration — [euro_llm] project settings (with code defaults)
# =====================================================================
## These mirror the [euro_llm] section in project.godot. Reading through
## ProjectSettings (with a literal default) means the seam works even if the
## section is absent, and the host/model are editable without touching code.
const DEF_ENABLED := false                       ## default OFF — no network unless opted in.
const DEF_HOST := "http://localhost:11434"       ## Ollama default host.
const DEF_ENDPOINT_PATH := "/api/generate"       ## Ollama single-shot generate.
const DEF_MODEL := "llama3.2"                     ## any local model the user has pulled.
const DEF_TIMEOUT := 8.0                          ## hard per-turn HTTP cap (seconds).

static func provider_enabled() -> bool:
	return bool(ProjectSettings.get_setting("euro_llm/enabled", DEF_ENABLED))

static func host() -> String:
	return String(ProjectSettings.get_setting("euro_llm/host", DEF_HOST))

static func endpoint_path() -> String:
	return String(ProjectSettings.get_setting("euro_llm/endpoint_path", DEF_ENDPOINT_PATH))

static func model() -> String:
	return String(ProjectSettings.get_setting("euro_llm/model", DEF_MODEL))

static func timeout_seconds() -> float:
	return float(ProjectSettings.get_setting("euro_llm/timeout_seconds", DEF_TIMEOUT))

static func endpoint_url() -> String:
	var h := host()
	var pth := endpoint_path()
	if h.ends_with("/") and pth.begins_with("/"):
		h = h.substr(0, h.length() - 1)
	elif not h.ends_with("/") and not pth.begins_with("/"):
		h += "/"
	return h + pth


# =====================================================================
#  The async provider call (the ONLY part that touches the network)
# =====================================================================
## Produce `seat`'s action. ALWAYS returns a dict:
##   { "action": <a legal action dict>, "source": "llm"|"fallback", "reason": String }
## The returned action is GUARANTEED legal (validated via is_legal / ai_choose), so
## the caller can apply_action() it unconditionally. `host_node` must be in the
## scene tree (HTTPRequest is a Node); GameManager passes itself.
func choose_action_async(engine, seat: int, host_node: Node) -> Dictionary:
	var options: Array = engine.legal_actions(seat)
	if options.is_empty():
		# Unreachable in normal play (PRODUCE is always legal) but never crash.
		return {"action": {"type": "PRODUCE"}, "source": "fallback", "reason": "no legal actions"}
	# Provider off (or no seat opted in): behave exactly like AI_HEURISTIC, no network.
	if not provider_enabled():
		return _fallback(engine, seat, "provider disabled")

	var http := HTTPRequest.new()
	http.timeout = maxf(0.5, timeout_seconds())  # HARD cap -> guarantees progress.
	host_node.add_child(http)

	var prompt := build_prompt(engine, seat, options)
	var payload := {"model": model(), "prompt": prompt, "stream": false}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(endpoint_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return _fallback(engine, seat, "request start failed (err %d)" % err)

	# HTTPRequest is async — await its completion signal. The hard `timeout` above
	# guarantees this resolves (RESULT_TIMEOUT) even against a black-holed host, so
	# a headless run can never hang here.
	var result_arr: Array = await http.request_completed
	http.queue_free()

	var result := int(result_arr[0])       # HTTPRequest.Result
	var code := int(result_arr[1])         # HTTP status
	var raw: PackedByteArray = result_arr[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fallback(engine, seat, "transport result %d" % result)
	if code < 200 or code >= 300:
		return _fallback(engine, seat, "http status %d" % code)

	var text := raw.get_string_from_utf8()
	var reply := _extract_reply_text(text)
	if reply == "":
		return _fallback(engine, seat, "empty/unparseable body")
	return resolve(engine, seat, reply, options)


## Pull the model's answer out of the HTTP body. Ollama's /api/generate (stream
## false) returns {"response": "..."}; if the body is not that shape we treat the
## whole body as the reply so an alternate local endpoint still works.
func _extract_reply_text(body: String) -> String:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.has("response"):
			return String(d["response"]).strip_edges()
		# OpenAI-compatible local servers: choices[0].message.content / .text
		if d.has("choices") and d["choices"] is Array and (d["choices"] as Array).size() > 0:
			var c0: Variant = (d["choices"] as Array)[0]
			if c0 is Dictionary:
				var cd: Dictionary = c0
				if cd.has("message") and cd["message"] is Dictionary and (cd["message"] as Dictionary).has("content"):
					return String((cd["message"] as Dictionary)["content"]).strip_edges()
				if cd.has("text"):
					return String(cd["text"]).strip_edges()
	# Not a recognised JSON envelope — use the raw text (some servers return plain).
	return body.strip_edges()


func _fallback(engine, seat: int, reason: String) -> Dictionary:
	return {"action": engine.ai_choose(seat), "source": "fallback", "reason": reason}


# =====================================================================
#  Pure, testable core — no network, exercised head-lessly by the probes
# =====================================================================

## Turn a parsed reply into a VALIDATED action. Parses the chosen number, maps it
## to `options` (the numbered legal-action list the prompt showed), and re-checks
## is_legal() before accepting it. Any miss -> heuristic fallback. The returned
## action is ALWAYS legal; an unvalidated/out-of-range/illegal choice is NEVER
## returned.
func resolve(engine, seat: int, reply: String, options: Array) -> Dictionary:
	var idx := parse_index(reply, options.size())
	if idx >= 0 and idx < options.size():
		var candidate: Dictionary = options[idx]
		# Defence in depth: re-validate against the live rules, not just the list —
		# a stale/tampered option or an out-of-turn seat is rejected here.
		if engine.is_legal(seat, candidate):
			return {"action": candidate, "source": "llm", "index": idx, "reason": _extract_reason(reply)}
		return _fallback(engine, seat, "chosen option %d re-validated as illegal" % (idx + 1))
	return _fallback(engine, seat, "no valid choice parsed from reply")


## Parse the FIRST integer in the reply and map it to a 0-based index into a list
## of `count` numbered options (the prompt numbers them 1..count). Returns the
## index, or -1 if there is no in-range number. Tolerates surrounding prose,
## fences, punctuation ("2", "I pick 2.", "```3```", "Action 4 — build").
static func parse_index(reply: String, count: int) -> int:
	if count <= 0:
		return -1
	var re := RegEx.new()
	# First run of digits anywhere in the reply.
	if re.compile("\\d+") != OK:
		return -1
	var m := re.search(reply)
	if m == null:
		return -1
	var n := m.get_string().to_int()  # 1-based as shown to the model.
	if n < 1 or n > count:
		return -1
	return n - 1


## Optional one-line reason (everything after the first number, trimmed/cut). Pure
## cosmetic — logged, never affects the chosen action.
static func _extract_reason(reply: String) -> String:
	var one := reply.strip_edges().replace("\n", " ").replace("\r", " ")
	if one.length() > 120:
		one = one.substr(0, 120)
	return one


## Build the COMPACT decision prompt: the seat's state, the win condition, and the
## legal actions as a numbered list — then ask for just the number. Pure function
## of (engine, seat, options); no side effects, safe to call in tests.
func build_prompt(engine, seat: int, options: Array) -> String:
	var p: Dictionary = engine.players[seat]
	var lines: Array[String] = []
	lines.append("You are an AI opponent in a competitive Euro engine-builder board game.")
	lines.append("Goal: score the most victory points (VP). Plant goal-stars via DEPLOY;")
	lines.append("first to %d stars ends the game, else it ends after %d rounds. VP come from" % [
		engine.GOAL_STARS, engine.MAX_ROUNDS])
	lines.append("built cards, stars (%d VP each), first-come objectives, and end-game majorities." % engine.STAR_VP)
	lines.append("")
	lines.append("YOUR SEAT (%s): VP %d, stars %d, cards built %d, round %d/%d." % [
		engine.seat_name(seat), engine.live_vp(seat), int(p["stars"]),
		(p["tableau"] as Array).size(), engine.round_index + 1, engine.MAX_ROUNDS])
	lines.append("Your resources: %s." % engine._fmt(p["resources"]))
	lines.append("Your production per PRODUCE: %s." % engine._fmt(engine.production_of(p)))
	var hand_names: Array[String] = []
	for cid in p["hand"]:
		hand_names.append(String(engine.CARD_DB[cid]["name"]))
	lines.append("Your hand: %s." % (", ".join(hand_names) if not hand_names.is_empty() else "empty"))
	lines.append("")
	lines.append("Choose ONE of these legal actions:")
	for i in options.size():
		lines.append("%d. %s" % [i + 1, describe_action(engine, options[i])])
	lines.append("")
	lines.append("Reply with ONLY the number of your chosen action (optionally one short reason).")
	return "\n".join(lines)


## A short human/LLM-readable description of a single legal action.
func describe_action(engine, action: Dictionary) -> String:
	match String(action.get("type", "")):
		"PRODUCE":
			return "PRODUCE — gain %s" % engine._fmt(engine.production_of(engine.players[engine.current]))
		"BUILD":
			var hi := int(action.get("hand_index", -1))
			var hand: Array = engine.players[engine.current]["hand"]
			if hi >= 0 and hi < hand.size():
				var card: Dictionary = engine.CARD_DB[hand[hi]]
				return "BUILD %s (cost %s -> produces %s, %d VP)" % [
					card["name"], engine._fmt(card["cost"]), engine._fmt(card["output"]), int(card["vp"])]
			return "BUILD (invalid card)"
		"TRADE":
			return "TRADE %d %s -> %d %s" % [
				engine.TRADE_IN, String(action.get("from", "?")),
				engine.TRADE_OUT, String(action.get("to", "?"))]
		"RESEARCH":
			return "RESEARCH — pay %s, draw %d cards" % [engine._fmt(engine.RESEARCH_COST), engine.RESEARCH_DRAW]
		"DEPLOY":
			return "DEPLOY — pay %s, plant a goal-star (+%d VP)" % [engine._fmt(engine.DEPLOY_COST), engine.STAR_VP]
		_:
			return "unknown action"
