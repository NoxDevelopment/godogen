extends Node
## res://scripts/ai_dm.gd
## The AI DUNGEON MASTER seam (autoload "AiDm") — SHIPPED INERT, DISABLED BY
## DEFAULT. This is the single, documented place a future AI layer (gamebook
## engine spec P4) plugs into a game that is otherwise 100% computed. With
## `enabled == false` (the shipped default) every method returns a pass-through /
## empty value, PlaySession never uses AI output, the play scene requests no
## narration, and play is byte-for-byte the pure computed core — the headless boot
## probe plays the whole sample adventure to an ending with this autoload doing
## nothing.
##
## SLICE 2 (this file) — ASYNC, ADDITIVE, DISPLAY-ONLY narration.
## ---------------------------------------------------------------------------
## The computed engine (nox_if_engine) stays the WHOLE game. AI is an ENHANCEMENT
## over the Runner/State, never a dependency of it, and never bypasses the rule
## engine. Slice 2 fills in ONE real capability — local-LLM flavour PROSE that is
## DISPLAYED ALONGSIDE (never instead of) a passage's computed text — and it does
## so WITHOUT ever touching a mechanic. The wrinkle "the hooks are synchronous but
## an LLM call is async" is resolved by NOT blocking the turn:
##
##   * The turn ALREADY resolved through the computed engine (PlaySession.choose).
##     choose()/conditions/effects/dice/available_choices/ending are NEVER routed
##     through the LLM. play_session.gd is untouched.
##   * After a passage is shown, IF `enabled`, the play scene calls
##     `request_narration(passage, state)`. That fires a NON-BLOCKING HTTPRequest
##     to a local Ollama endpoint (owned child HTTPRequest node — this autoload is
##     a Node, so it can add_child one) with a HARD timeout, and emits
##     `narration_ready(passage_id, text)` when the prose arrives "later".
##   * The play scene appends that prose in a SEPARATE label under the computed
##     passage text (clearly the AI flavour). The mechanics never wait for it.
##   * On ANY failure (disabled / unreachable / timeout / non-2xx / garbage) the
##     signal fires with `""` — inert. No crash, no hang, nothing is displayed.
##     This mirrors the euro engine-builder `llm_seat.gd` fail-then-fallback
##     discipline: the game can never stall on the AI.
##
## `enabled` STAYS FALSE in the shipped template. With it false, behaviour is
## byte-identical to before slice 2 and every existing probe passes unchanged.
##
## The OLD synchronous hooks (`narrate_passage` / `gloss_roll` / `review_choices`
## / `dm_intervene`) STAY as inert pass-throughs so their guarded call sites in
## play_session.gd keep working. The real narration path is the async signal.

## Emitted when an async narration request finishes. `text` is the AI-authored
## flavour prose to DISPLAY ALONGSIDE the computed passage, or "" on ANY failure
## (the inert result). `passage_id` lets a listener match the prose to the passage
## it was requested for and discard stale arrivals after the player moved on.
signal narration_ready(passage_id: String, text: String)

## Master switch. FALSE in the shipped template — the computed core plays fully
## without any AI. Flip to true (in code / an author build) to opt into the async
## LLM narration below; the computed mechanics are unaffected either way.
var enabled: bool = false


# =====================================================================
#  Provider configuration — [ai_dm] project settings (with code defaults)
# =====================================================================
## Read through ProjectSettings with a literal default (same pattern as the euro
## engine-builder llm_seat), so the seam works even if the [ai_dm] section is
## absent from project.godot, and the host/model are editable without touching
## code. Default host is the local Ollama single-shot generate endpoint.
const DEF_HOST := "http://localhost:11434"       ## Ollama default host.
const DEF_ENDPOINT_PATH := "/api/generate"       ## Ollama single-shot generate.
const DEF_MODEL := "llama3.2"                     ## any local model the user pulled.
const DEF_TIMEOUT := 8.0                          ## hard per-request HTTP cap (seconds).

static func host() -> String:
	return String(ProjectSettings.get_setting("ai_dm/host", DEF_HOST))

static func endpoint_path() -> String:
	return String(ProjectSettings.get_setting("ai_dm/endpoint_path", DEF_ENDPOINT_PATH))

static func model() -> String:
	return String(ProjectSettings.get_setting("ai_dm/model", DEF_MODEL))

static func timeout_seconds() -> float:
	return float(ProjectSettings.get_setting("ai_dm/timeout_seconds", DEF_TIMEOUT))

static func endpoint_url() -> String:
	var h := host()
	var pth := endpoint_path()
	if h.ends_with("/") and pth.begins_with("/"):
		h = h.substr(0, h.length() - 1)
	elif not h.ends_with("/") and not pth.begins_with("/"):
		h += "/"
	return h + pth


# =====================================================================
#  The async narration request (the ONLY part that touches the network)
# =====================================================================
## DISPLAY-ONLY, NON-BLOCKING. When `enabled`, POST a compact flavour prompt to the
## local LLM via an owned child HTTPRequest with a HARD timeout, and emit
## `narration_ready(passage_id, prose)` when it arrives. On ANY failure — disabled,
## request-start error, transport failure, timeout, non-2xx, or an unparseable /
## empty body — emit `narration_ready(passage_id, "")` (inert). It NEVER pushes an
## error that breaks play, NEVER mutates state, and NEVER calls the rule engine.
## The hard `http.timeout` guarantees this resolves even against a black-holed host,
## so a headless run can never hang here.
func request_narration(passage: Dictionary, state: IFState) -> void:
	var passage_id := str(passage.get("id", ""))
	if not enabled:
		# Off by default: touch no network, emit nothing. play.gd guards the call
		# too, so this is belt-and-suspenders — enabling changes only the display.
		return

	var http := HTTPRequest.new()
	http.timeout = maxf(0.5, timeout_seconds())  # HARD cap -> guarantees progress.
	add_child(http)

	var prompt := build_prompt(passage, state)
	var payload := {"model": model(), "prompt": prompt, "stream": false}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(endpoint_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		narration_ready.emit(passage_id, "")
		return

	# HTTPRequest is async — await its completion signal. The hard `timeout` above
	# resolves this as RESULT_TIMEOUT even against an unresponsive host.
	var result_arr: Array = await http.request_completed
	http.queue_free()

	var result := int(result_arr[0])       # HTTPRequest.Result
	var code := int(result_arr[1])         # HTTP status
	var raw: PackedByteArray = result_arr[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		narration_ready.emit(passage_id, "")   # unreachable / timeout / cancelled.
		return
	if code < 200 or code >= 300:
		narration_ready.emit(passage_id, "")   # server refused / errored.
		return

	var text := extract_reply_text(raw.get_string_from_utf8())
	# `text` may legitimately be "" (empty/garbage body) — that is the inert result.
	narration_ready.emit(passage_id, text)


## Build the COMPACT flavour prompt. Pure function of (passage, state); no side
## effects. It grounds the model in the ALREADY-RESOLVED passage and instructs it
## to write only atmospheric prose that never decides outcomes or offers choices.
func build_prompt(passage: Dictionary, state: IFState) -> String:
	var lines: Array[String] = []
	lines.append("You are the atmospheric narrator ('DM voice') for a computed gamebook.")
	lines.append("The rules engine has ALREADY resolved this turn; you do NOT decide")
	lines.append("outcomes, offer choices, name new items, or change any stat. Write 1-2")
	lines.append("sentences of vivid, sensory flavour that sits ALONGSIDE the passage")
	lines.append("below and never contradicts it.")
	lines.append("")
	lines.append("Passage: %s" % str(passage.get("title", "")))
	lines.append(str(passage.get("text", "")))
	if state != null and state.current_passage != "":
		lines.append("")
		lines.append("(Continue the mood of '%s'; introduce no new events.)" % state.current_passage)
	lines.append("")
	lines.append("Reply with ONLY the flavour prose, no preamble.")
	return "\n".join(lines)


## Pull the model's prose out of the HTTP body. Ollama's /api/generate (stream
## false) returns {"response": "..."}; an OpenAI-compatible local server returns
## choices[0].message.content / .text; otherwise the raw body is used. Returns ""
## for a body that yields no usable text.
func extract_reply_text(body: String) -> String:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.has("response"):
			return String(d["response"]).strip_edges()
		if d.has("choices") and d["choices"] is Array and (d["choices"] as Array).size() > 0:
			var c0: Variant = (d["choices"] as Array)[0]
			if c0 is Dictionary:
				var cd: Dictionary = c0
				if cd.has("message") and cd["message"] is Dictionary and (cd["message"] as Dictionary).has("content"):
					return String((cd["message"] as Dictionary)["content"]).strip_edges()
				if cd.has("text"):
					return String(cd["text"]).strip_edges()
		# A recognised JSON envelope with no usable field -> no prose.
		return ""
	# Not JSON — some local servers return plain text.
	return body.strip_edges()


# =====================================================================
#  Legacy inert hooks — STILL guarded by `if AiDm.enabled` at every call site
#  in play_session.gd. Kept as pass-throughs so nothing that calls them breaks;
#  the real narration path is the async `request_narration` / `narration_ready`.
# =====================================================================

## Optional SYNCHRONOUS AI-authored narration to DISPLAY ALONGSIDE (never instead
## of) a passage's computed text. Inert default: "". The async `request_narration`
## is the live slice-2 path; this stays for the guarded PlaySession call site.
func narrate_passage(_passage: Dictionary, _state: IFState) -> String:
	return ""


## Optional AI-authored gloss on a resolved dice check (for the dice tray). Inert
## default: "" — the tray shows the computed band/verdict only. It can NEVER change
## the `result` (the engine already resolved it deterministically).
func gloss_roll(_result: Dictionary) -> String:
	return ""


## Optional AI DM intervention on the offered choices. Inert default: returns the
## SAME array unchanged — the player sees exactly the engine-gated choices. A
## pass-through filter, not a gate: the authoritative gating already happened.
func review_choices(choices: Array, _state: IFState) -> Array:
	return choices


## Reserved P4 entry point: a human/AI DM "push" to a passage or a roll override.
## Inert no-op in the computed core (returns false = "not handled").
func dm_intervene(_kind: String, _payload: Dictionary) -> bool:
	return false
