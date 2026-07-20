class_name IFSection
extends RefCounted
## res://addons/nox_if_engine/if_section.gd
## A typed, read-only VIEW over one scenario passage dict — the GDD §5 `Section`
## data model made concrete:
##
##   Section = { id, title?, text?, illustration?,
##               onEnter: [effect]?,          # applied on entry
##               choices: [ { id/label, goto/target, conditions?, effects?, check? } ]?,
##               events:  [ event ]?,          # combat / luck / skill / item / forced
##               event?, enemy?,               # (P0 scaffold convenience shorthands)
##               ending?: { id, kind, label } }
##
## The engine (IFRunner/IFScenario) still operates on the raw passage dicts — this
## wrapper is a convenience for UI/tools so screen code and the validator read
## STRUCTURE, not ad-hoc `dict.get(...)` strings. `raw()` returns the underlying
## dict for anything the typed surface doesn't cover. Nothing here mutates state.

var _p: Dictionary = {}


func _init(passage: Dictionary = {}) -> void:
	_p = passage


static func of(passage: Dictionary) -> IFSection:
	return IFSection.new(passage)


func id() -> String:
	return str(_p.get("id", ""))


func title() -> String:
	return str(_p.get("title", ""))


func text() -> String:
	return str(_p.get("text", ""))


## The illustration slot id/path for this section (Phase 5 art binding), or "".
func illustration() -> String:
	return str(_p.get("illustration", ""))


func on_enter() -> Array:
	return _p.get("onEnter", [])


## The raw choice dicts as authored (the runner filters by condition; this returns
## all of them so tools/validator can inspect the full branch set).
func choices() -> Array:
	return _p.get("choices", [])


## Normalised events list. The §5 model is `events[]`; the P0 scaffold also allows a
## single `event` string (+ `enemy`/`unlucky_effect`) shorthand, which this folds
## into a one-element list so callers have ONE shape to read.
func events() -> Array:
	if _p.has("events"):
		return _p.get("events", [])
	var e := str(_p.get("event", ""))
	if e == "":
		return []
	var ev: Dictionary = {"kind": e}
	if _p.has("enemy"):
		ev["enemy"] = _p["enemy"]
	if _p.has("unlucky_effect"):
		ev["unlucky_effect"] = _p["unlucky_effect"]
	return [ev]


func has_event(kind: String) -> bool:
	for ev in events():
		if str((ev as Dictionary).get("kind", "")) == kind:
			return true
	return false


## The passage-level auto-resolution check node (routes by outcome band), or {}.
func check() -> Dictionary:
	return _p.get("check", {})


func is_ending() -> bool:
	return _p.has("ending")


func ending() -> Dictionary:
	return _p.get("ending", {})


func raw() -> Dictionary:
	return _p
