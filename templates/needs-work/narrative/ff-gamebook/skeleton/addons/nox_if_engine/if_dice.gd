class_name IFDice
extends RefCounted
## res://addons/nox_if_engine/if_dice.gd
## Seedable dice-expression roller — the deterministic randomness source for the
## whole computed engine. Parses the standard tabletop expression grammar
## `NdM`, `NdM+K`, `NdM-K` (e.g. `2d6`, `1d20`, `1d6+6`, `2d6+12`) and returns
## the individual die faces PLUS the summed total, because the resolution layer
## needs the faces to judge criticals (double-1s under FF, a natural-20 under
## d20 — see if_resolver.gd) and the total to compare.
##
## Every roll advances one owned RandomNumberGenerator, so a fixed seed replays a
## scenario byte-for-byte. This is the same contract the ff-gamebook `dice.gd`
## and the VN `skill_check.gd` expose (`set_seed`), lifted here to be system-
## agnostic: the roller knows nothing about SKILL, DC or bands — only faces.

var _rng := RandomNumberGenerator.new()

## Cache of parsed expressions so repeated rolls of the same string don't re-parse.
var _parse_cache: Dictionary = {}


func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


## Deterministic rolls for tests/replays. Mirrors dice.gd / skill_check.gd.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


## The current RNG state — lets a Runner snapshot/restore mid-scenario (save/load
## in P1) so a resumed session keeps rolling the same sequence.
func get_state() -> int:
	return _rng.state


func set_state(state: int) -> void:
	_rng.state = state


## Parse `NdM(+/-K)` into `{count, sides, modifier}`. Raises via push_error on a
## malformed expression and returns a safe 1d1 so a single bad datum can't crash
## a whole play — but the error is loud, never silent.
func parse(expr: String) -> Dictionary:
	var key := expr.strip_edges()
	if _parse_cache.has(key):
		return _parse_cache[key]
	var parsed := _parse(key)
	_parse_cache[key] = parsed
	return parsed


## Pure, side-effect-free validation of a dice expression for the ruleset
## validator/importer (P2) — mirrors `_parse` grammar but pushes NO errors and
## never returns a "safe default"; it reports precisely what is wrong. Accepts
## `NdM`, `NdM+K`, `NdM-K` and a bare integer constant `K` (a gen like "0").
## Returns { ok: bool, error: String }.
static func validate_expr(expr: String) -> Dictionary:
	var s := str(expr).strip_edges().to_lower().replace(" ", "")
	if s == "":
		return {"ok": false, "error": "empty dice expression"}
	var modifier_str := ""
	var body := s
	var plus := s.find("+")
	var minus := s.find("-")
	var sign_at := -1
	if plus >= 0:
		sign_at = plus
	if minus >= 0 and (sign_at < 0 or minus < sign_at):
		sign_at = minus
	if sign_at == 0:
		return {"ok": false, "error": "expression '%s' starts with a sign" % expr}
	if sign_at > 0:
		body = s.substr(0, sign_at)
		modifier_str = s.substr(sign_at)
		if not modifier_str.is_valid_int():
			return {"ok": false, "error": "bad modifier '%s' in '%s'" % [modifier_str, expr]}
	if not body.contains("d"):
		if body.is_valid_int():
			return {"ok": true, "error": ""}
		return {"ok": false, "error": "malformed expression '%s'" % expr}
	var halves := body.split("d")
	if halves.size() != 2:
		return {"ok": false, "error": "malformed dice body '%s'" % body}
	if halves[0] != "" and not halves[0].is_valid_int():
		return {"ok": false, "error": "bad dice count in '%s'" % expr}
	if not halves[1].is_valid_int():
		return {"ok": false, "error": "bad dice sides in '%s'" % expr}
	var count := 1 if halves[0] == "" else halves[0].to_int()
	var sides := halves[1].to_int()
	if count < 1:
		return {"ok": false, "error": "non-positive dice count in '%s'" % expr}
	if sides < 1:
		return {"ok": false, "error": "non-positive dice sides in '%s'" % expr}
	return {"ok": true, "error": ""}


func _parse(expr: String) -> Dictionary:
	var s := expr.strip_edges().to_lower().replace(" ", "")
	if s == "":
		push_error("IFDice: empty dice expression")
		return {"count": 1, "sides": 1, "modifier": 0, "expr": expr}
	# Split off a trailing +K / -K modifier.
	var modifier := 0
	var body := s
	var plus := s.find("+")
	var minus := s.find("-")
	var sign_at := -1
	if plus >= 0:
		sign_at = plus
	if minus >= 0 and (sign_at < 0 or minus < sign_at):
		sign_at = minus
	if sign_at >= 0:
		body = s.substr(0, sign_at)
		var mod_str := s.substr(sign_at)
		if not mod_str.is_valid_int():
			push_error("IFDice: bad modifier in '%s'" % expr)
		modifier = mod_str.to_int()
	# body is now "NdM" or a bare constant "K".
	if not body.contains("d"):
		if body.is_valid_int():
			return {"count": 0, "sides": 0, "modifier": body.to_int() + modifier, "expr": expr}
		push_error("IFDice: malformed expression '%s'" % expr)
		return {"count": 1, "sides": 1, "modifier": modifier, "expr": expr}
	var halves := body.split("d")
	if halves.size() != 2:
		push_error("IFDice: malformed dice body '%s'" % body)
		return {"count": 1, "sides": 1, "modifier": modifier, "expr": expr}
	var count := 1 if halves[0] == "" else halves[0].to_int()
	var sides := halves[1].to_int()
	if count < 1 or sides < 1:
		push_error("IFDice: non-positive dice in '%s'" % expr)
		count = maxi(count, 1)
		sides = maxi(sides, 1)
	return {"count": count, "sides": sides, "modifier": modifier, "expr": expr}


## Roll an expression. Returns:
##   { expr, count, sides, modifier, faces:[int...], sum:int, total:int }
## where `sum` is the raw dice sum and `total` = sum + modifier. `faces` is the
## ordered list of individual die results (criticals inspect it).
func roll(expr: String) -> Dictionary:
	var p := parse(expr)
	var faces: Array[int] = []
	var sum := 0
	for i in int(p.count):
		var face := _rng.randi_range(1, int(p.sides))
		faces.append(face)
		sum += face
	var total := sum + int(p.modifier)
	return {
		"expr": expr,
		"count": int(p.count),
		"sides": int(p.sides),
		"modifier": int(p.modifier),
		"faces": faces,
		"sum": sum,
		"total": total,
	}
