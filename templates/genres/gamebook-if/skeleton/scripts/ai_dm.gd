extends Node
## res://scripts/ai_dm.gd
## The AI DUNGEON MASTER seam (autoload "AiDm") — SHIPPED INERT, DISABLED BY
## DEFAULT. This is the single, documented place a future AI layer (gamebook
## engine spec P4) plugs into a game that is otherwise 100% computed. With
## `enabled == false` (the shipped default) every method returns a pass-through /
## empty value, PlaySession never uses AI output, and play is byte-for-byte the
## pure computed core — the headless boot probe plays the whole sample adventure
## to an ending with this autoload doing nothing.
##
## THERE IS NO LLM AND NO NETWORKING HERE. That is deliberate: the computed
## engine (nox_if_engine) is the whole game; AI is an ENHANCEMENT over the
## Runner/State, never a dependency of it, and never bypasses the rule engine.
## The hooks below are the *contract* the P4 layer will implement — not a stub of
## one. A real implementation would, when `enabled`, call out to a model to
## author flavour prose or gloss a roll, but it would STILL route every mechanic
## (choices, conditions, effects, dice) through the computed engine unchanged.
## We do not ship a fake or placeholder model call; we ship the seam, off.
##
## How PlaySession consumes it (see play_session.gd): every call site is guarded
## by `if AiDm.enabled`, so an inert AiDm cannot alter the computed result. To
## experiment, an author could set `AiDm.enabled = true` and fill these in — but
## with the bodies as shipped, enabling it changes nothing (they are inert), so
## the game keeps playing exactly the same. That is the point: the AI is optional.

## Master switch. FALSE in the shipped template — the computed core plays fully
## without any AI. The future P4 layer flips this and implements the hooks.
var enabled: bool = false


## Optional AI-authored narration to DISPLAY ALONGSIDE (never instead of) a
## passage's computed text. Inert default: "" — the play scene shows only the
## authored passage text. A P4 implementation returns extra prose; the computed
## `passage.text` is always rendered regardless.
func narrate_passage(_passage: Dictionary, _state: IFState) -> String:
	return ""


## Optional AI-authored gloss on a resolved dice check (for the dice tray).
## Inert default: "" — the tray shows the computed band/verdict only. A P4
## implementation returns colour text; it can NEVER change the `result` (the
## engine already resolved it deterministically).
func gloss_roll(_result: Dictionary) -> String:
	return ""


## Optional AI DM intervention on the offered choices. Inert default: returns the
## SAME array unchanged — the player sees exactly the engine-gated choices. This
## is a pass-through filter, not a gate: a P4 DM could reorder or annotate, but
## the authoritative gating (conditions) already happened in the engine.
func review_choices(choices: Array, _state: IFState) -> Array:
	return choices


## Reserved P4 entry point: a human/AI DM "push" to a passage or a roll override.
## Inert no-op in the computed core (returns false = "not handled"), mirroring the
## ff-gamebook SessionState DM-seat hooks. The engine's IFState is the single seam
## such a layer would intercept.
func dm_intervene(_kind: String, _payload: Dictionary) -> bool:
	return false
