class_name IFCampaignStore
extends RefCounted
## res://addons/nox_if_engine/if_campaign_store.gd
## The LONG-TERM store (spec P1) — everything about a campaign that OUTLIVES a
## single play session: campaign progress, world/campaign-level variables & flags,
## and the roster of carried characters (each with its own persistent sheet +
## inventory + history). This is the half of persistence that is NOT the moment-
## to-moment scene; the short-term half is the live IFState the runner drives.
## Keeping these two in separate objects is the whole point of the P1 persistence
## contract: a save serialises long-term (this) and short-term (the session
## snapshot) into clearly-labelled sections, and short-term scene state can never
## silently leak into the durable record.
##
## Convention: campaign vars/flags are namespaced `world.*` (or any agreed
## prefix). During a module they are layered onto the session so conditions/
## effects can read and write them; at module end only the prefixed keys are
## captured back here — everything else in the session was scene-scoped.

const WORLD_PREFIX := "world."

## Progress.
var current_module: String = ""
var completed_modules: Array[String] = []
var module_history: Array = []       # [ { module, ending, kind } ]
var status: String = "active"        # "active" | "complete" | "failed"

## World/campaign long-term state (keys kept fully prefixed, e.g. "world.embers").
var campaign_vars: Dictionary = {}
var campaign_flags: Dictionary = {}

## Master seed for deriving per-module deterministic seeds.
var master_seed: int = 0

## slot id -> IFCharacter (carried, mutated across modules).
var roster: Dictionary = {}
var roster_order: Array[String] = []

var campaign_id: String = ""


## Initialise a fresh store from a campaign definition (its authored defaults).
func init_from_campaign(campaign: IFCampaign, seed_override: int = -1) -> void:
	campaign_id = campaign.id
	master_seed = campaign.seed if seed_override < 0 else seed_override
	current_module = campaign.start_module_id
	completed_modules.clear()
	module_history.clear()
	status = "active"
	campaign_vars = campaign.campaign_vars.duplicate(true)
	campaign_flags = campaign.campaign_flags.duplicate(true)
	roster.clear()
	roster_order.clear()
	for slot in campaign.roster_order:
		var src: IFCharacter = campaign.roster[slot]
		# Deep-copy the authored character so the campaign definition stays pristine.
		var c := IFCharacter.new(src.save_data())
		roster[slot] = c
		roster_order.append(slot)


func character_in(slot: String) -> IFCharacter:
	return roster.get(slot, null)


## A deterministic per-module dice seed derived from the master seed and the
## module's ordinal — so every module has its own reproducible stream and the
## whole campaign replays byte-for-byte.
func module_seed(module_ordinal: int) -> int:
	# A simple, stable mix (odd multiplier + offset); deterministic and spread.
	return int(master_seed * 2654435761 + module_ordinal * 40503 + 17) & 0x7fffffff


func mark_completed(module_id: String, ending: Dictionary) -> void:
	if not completed_modules.has(module_id):
		completed_modules.append(module_id)
	module_history.append({
		"module": module_id,
		"ending": str(ending.get("id", "")),
		"kind": str(ending.get("kind", "")),
	})


func world_var(key: String, default: float = 0.0) -> float:
	return float(campaign_vars.get(key, default))


# --- long-term save section (the `longTerm` block of a campaign save) ---------


func save_data() -> Dictionary:
	var roster_out: Array = []
	for slot in roster_order:
		roster_out.append({
			"slot": slot,
			"character": (roster[slot] as IFCharacter).save_data(),
		})
	return {
		"campaignId": campaign_id,
		"masterSeed": master_seed,
		"status": status,
		"progress": {
			"currentModule": current_module,
			"completedModules": completed_modules.duplicate(),
			"moduleHistory": module_history.duplicate(true),
		},
		"campaignVars": campaign_vars.duplicate(true),
		"campaignFlags": campaign_flags.duplicate(true),
		"roster": roster_out,
	}


func load_data(data: Dictionary) -> void:
	campaign_id = str(data.get("campaignId", ""))
	master_seed = int(data.get("masterSeed", 0))
	status = str(data.get("status", "active"))
	var progress: Dictionary = data.get("progress", {})
	current_module = str(progress.get("currentModule", ""))
	completed_modules.assign(progress.get("completedModules", []))
	module_history = (progress.get("moduleHistory", []) as Array).duplicate(true)
	campaign_vars = (data.get("campaignVars", {}) as Dictionary).duplicate(true)
	campaign_flags = (data.get("campaignFlags", {}) as Dictionary).duplicate(true)
	roster.clear()
	roster_order.clear()
	for entry in data.get("roster", []):
		var slot := str(entry.get("slot", ""))
		if slot == "":
			continue
		roster[slot] = IFCharacter.new(entry.get("character", {}))
		roster_order.append(slot)
