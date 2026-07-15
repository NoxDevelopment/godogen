class_name VnRuntime
extends RefCounted
## Pure helpers for the NoxDev VN JSON runtime — the Godot mirror of the Studio
## authoring model (apps/web/lib/actions/vnMaker.helpers.ts). Kept static + free
## of node state so the player script (and future tests) can reuse it.
##
## Consumes the engine-agnostic payload the Studio VN Maker exports to
## res://vn/story.vn.json (format "noxdev-vn"): characters (with expression
## sprites + voice binding), backgrounds, and scenes of dialogue lines + choices.

const EMOTIONS := [
	"neutral", "happy", "sad", "angry", "surprised",
	"scared", "shy", "smug", "tired", "excited",
]

## Emotion -> natural-language delivery style (Qwen3-TTS instruct). Mirrors
## EMOTION_STYLE in the Studio helpers so authored + exported delivery match.
const EMOTION_STYLE := {
	"neutral": "speak naturally",
	"happy": "speak cheerfully and warmly",
	"sad": "speak sadly and slowly",
	"angry": "speak angrily",
	"surprised": "speak with surprise",
	"scared": "speak fearfully, voice trembling",
	"shy": "speak shyly and softly",
	"smug": "speak smugly, teasing",
	"tired": "speak wearily, slightly tired",
	"excited": "speak excitedly and fast",
}

## Free-form expression names -> canonical emotion.
const SYNONYMS := {
	"normal": "neutral", "default": "neutral", "calm": "neutral", "idle": "neutral",
	"smile": "happy", "smiling": "happy", "joy": "happy", "joyful": "happy",
	"grin": "happy", "laugh": "happy", "laughing": "happy", "cheerful": "happy",
	"cry": "sad", "crying": "sad", "frown": "sad", "down": "sad", "upset": "sad",
	"mad": "angry", "furious": "angry", "rage": "angry", "annoyed": "angry",
	"shock": "surprised", "shocked": "surprised", "surprise": "surprised",
	"fear": "scared", "afraid": "scared", "worried": "scared", "nervous": "scared",
	"blush": "shy", "bashful": "shy", "embarrassed": "shy",
	"smirk": "smug", "teasing": "smug", "confident": "smug",
	"sleepy": "tired", "exhausted": "tired", "weary": "tired",
	"thrilled": "excited", "eager": "excited",
}


## Resolve any expression string to a canonical emotion.
static func canonical_emotion(expression: String) -> String:
	var key := expression.strip_edges().to_lower()
	if key == "":
		return "neutral"
	if EMOTIONS.has(key):
		return key
	return SYNONYMS.get(key, "neutral")


## Best sprite for a line's expression — the emotion portrait swap.
## Order: exact declared key -> canonical-emotion key -> neutral/default/normal
## -> first available. Returns "" when the character has no usable sprites.
static func resolve_sprite(sprites: Dictionary, expression: String) -> String:
	var by_key := {}
	var first := ""
	for k in sprites.keys():
		var url := str(sprites[k])
		if url.strip_edges() == "":
			continue
		var lk := str(k).strip_edges().to_lower()
		if not by_key.has(lk):
			by_key[lk] = url
		if first == "":
			first = url
	if by_key.is_empty():
		return ""
	var declared := expression.strip_edges().to_lower()
	if declared != "" and by_key.has(declared):
		return by_key[declared]
	var canon := canonical_emotion(expression)
	if by_key.has(canon):
		return by_key[canon]
	for fallback in ["neutral", "default", "normal"]:
		if by_key.has(fallback):
			return by_key[fallback]
	return first


## Natural-language delivery instruction for a character speaking an expression:
## the character's base voiceStyle + the emotion style (Qwen3-TTS consumes it).
static func voice_instruction(character: Dictionary, expression: String) -> String:
	var emo := canonical_emotion(expression)
	var base := str(character.get("voiceStyle", "")).strip_edges()
	var emo_style := str(EMOTION_STYLE.get(emo, "speak naturally"))
	if base != "" and emo != "neutral":
		return "%s, %s" % [base, emo_style]
	if base != "":
		return base
	return emo_style


## Apply a choice's numeric variable mutations (stats/meters; unset = 0). Mirrors
## applyVarOps in the Studio helpers.
static func apply_var_ops(vars: Dictionary, ops) -> Dictionary:
	if ops == null:
		return vars
	var next := vars.duplicate()
	for o in ops:
		var key := str(o.get("key", ""))
		if key == "":
			continue
		var cur := float(next.get(key, 0))
		var val := float(o.get("value", 0))
		next[key] = (cur + val) if str(o.get("op", "")) == "add" else val
	return next


## True when every numeric condition holds against the variables (unset = 0).
static func var_conditions_met(vars: Dictionary, conds) -> bool:
	if conds == null:
		return true
	for c in conds:
		var v := float(vars.get(str(c.get("key", "")), 0))
		var target := float(c.get("value", 0))
		match str(c.get("cmp", "")):
			">=":
				if not (v >= target):
					return false
			"<=":
				if not (v <= target):
					return false
			"==":
				if not (v == target):
					return false
			">":
				if not (v > target):
					return false
			"<":
				if not (v < target):
					return false
			"!=":
				if not (v != target):
					return false
	return true
