extends RefCounted
class_name BrawlerEngine
## res://scripts/brawler_engine.gd
## The PURE, seedable, headless-testable engine for a JADE-EMPIRE-lineage 2D
## BEAT-'EM-UP MARTIAL-ARTS RPG: you learn MARTIAL-ARTS STYLES from different
## cultures, SWITCH STYLES mid-fight to exploit a rock-paper-scissors matchup
## triangle, and grow a martial-artist through a bounded CAMPAIGN of encounters.
## There is NO Godot-node dependency and NO CharacterBody2D / RigidBody2D in here:
## the whole beat-'em-up combat is our OWN fixed-timestep 1-D stage sim, so a fight
## replays BYTE-IDENTICALLY from a seed + an input/AI script and drives headlessly
## with no UI at all.
##
## WHY CUSTOM COMBAT (the key design decision — same lineage as the
## spinning-top-battler + ragdoll-locomotion templates):
##   Godot's physics + the frame-scheduler are NOT guaranteed bit-identical across
##   runs / builds / platforms, which would break byte-identical replays and the
##   determinism probe. So each fighter is a POINT on a horizontal stage (x
##   position, x velocity, facing) with HP, CHI (stamina), a current STYLE and an
##   ACTION STATE, advanced at a FIXED dt (1/60 s). Every step is a deterministic
##   float computation: resolve each side's INPUT -> possibly start an ACTION with
##   real startup/active/recovery FRAME DATA; during ACTIVE frames the move
##   projects a HITBOX interval in front of the fighter (a melee reach OR a
##   travelling chi projectile); a hitbox that overlaps the foe's HURTBOX applies
##   damage (scaled by the move + the attacker's attributes + a STYLE MATCHUP
##   multiplier + technique upgrades), knockback and hitstun; blocking converts the
##   hit to chip + blockstun. The COMBAT itself has ZERO randomness. The ONLY RNG
##   is ONE seeded generator used for optional AI DECISION JITTER (config
##   "ai_jitter", default 0.0 -> perfectly canned) and it is part of save/load. A
##   MAX_STEPS cap bounds every fight -> a timeout, never an infinite spar.
##
## STYLES (the Jade-Empire heart): six martial-arts styles from distinct cultures /
##   archetypes — Drunken Fist (fast), Iron Ox (power), Willow Guard (defensive),
##   Ghost Palm (ranged chi projectile), Steel Crane (weapon reach) and Coiling
##   Serpent (grappling throws). Each style carries base stat modifiers and a MOVE
##   SET of three moves (light / heavy / special) with genuine frame data. A STYLE
##   MATCHUP table (a real advantage relation, NOT cosmetic: fast beats power,
##   power beats defensive, defensive beats fast, plus the ranged/weapon/grappling
##   spokes) gives the advantaged attacker a damage multiplier, so SWITCHING to the
##   right counter mid-fight measurably matters. Learning a style unlocks its moves;
##   spending TECHNIQUE POINTS on a style deepens it (more damage per move).
##
## RPG: three attributes (BODY / MIND / SPIRIT à la Jade Empire) scale HP, chi and
##   damage. Winning a fight grants XP -> LEVEL UP -> attribute + technique points,
##   and masters teach new styles on schedule through the campaign. The campaign is
##   a bounded ladder of encounters ending in a final duel: WIN = clear the final
##   duel; LOSE = exhaust your continues. BOTH are reachable by a deterministic
##   auto-play (run_campaign wins on the base difficulty and loses on a buffed one),
##   and the campaign always terminates (finite encounters * finite continues *
##   step-capped fights).

# =====================================================================
#  Fixed-timestep sim tuning (auditable constants — swap for your own game)
# =====================================================================

const DT: float = 1.0 / 60.0             ## fixed combat timestep (seconds).
const MAX_STEPS_DEFAULT: int = 3600      ## hard cap (60 s @60Hz) -> timeout, never infinite.

const STAGE_MIN: float = 40.0            ## left wall (px).
const STAGE_MAX: float = 1240.0          ## right wall (px).
const START_GAP: float = 260.0           ## fighters start this far apart, centred.

const HURT_HALF: float = 24.0            ## a fighter's hurtbox half-width (px).
const FRONT_OFFSET: float = 16.0         ## a hitbox starts this far in front of the fighter.
const PROJ_HALF: float = 16.0            ## a chi projectile's hitbox half-width (px).
const TOUCH_PAD: float = 6.0             ## bodies cannot overlap closer than 2*HURT_HALF - this.

const WALK_SPEED_BASE: float = 220.0     ## px/s ground walk speed (scaled by style speed_mod).
const MOVE_DRAG: float = 12.0            ## knockback velocity decay per second.
const KB_SCALE: float = 45.0             ## knockback units -> px/s impulse.

const CHI_MAX_BASE: float = 40.0
const CHI_PER_SPIRIT: float = 5.0
const CHI_REGEN_IDLE: float = 26.0       ## chi/second regained while idle.
const CHI_REGEN_BUSY: float = 9.0        ## chi/second regained otherwise.

const HP_BASE: float = 100.0
const HP_PER_BODY: float = 10.0

const BLOCK_CHIP: float = 0.12           ## fraction of damage that leaks through a block.
const BLOCK_CHI_CHIP: float = 0.9        ## chi drained per point of blocked (pre-chip) damage.
const BLOCKSTUN_FRAMES: int = 9          ## frames frozen after blocking a hit.
const BLOCK_KB_SCALE: float = 0.25       ## knockback retained when blocked.

const PHYS_DMG_PER_BODY: float = 0.02    ## body attribute -> physical damage scaling.
const SPIRIT_DMG_PER_SPIRIT: float = 0.02## spirit attribute -> chi/special damage scaling.
const MIND_GUARD_PER_MIND: float = 0.015 ## mind attribute -> incoming-damage reduction.
const UPGRADE_DMG_STEP: float = 0.10     ## each technique point on a style -> +10% that style's damage.

const MATCHUP_ADV: float = 1.40          ## damage multiplier when your style beats theirs.
const MATCHUP_DIS: float = 0.70          ## damage multiplier when your style loses (~1/ADV).
const MATCHUP_EVEN: float = 1.0

## FNV-1a folding constants (63-bit masked) for deterministic checksums.
const FNV_OFFSET: int = 1469598103934665603
const FNV_PRIME: int = 1099511628211
const MASK63: int = 0x7FFFFFFFFFFFFFFF

# =====================================================================
#  Action states
# =====================================================================

const ACT_IDLE: String = "idle"
const ACT_ATTACK: String = "attacking"
const ACT_BLOCK: String = "block"
const ACT_BLOCKSTUN: String = "blockstun"
const ACT_HITSTUN: String = "hitstun"

# =====================================================================
#  Style archetypes + the MATCHUP triangle (a genuine advantage relation)
# =====================================================================
#  The core rock-paper-scissors from the design brief holds exactly:
#    fast beats power, power beats defensive, defensive beats fast.
#  The three extra spokes (ranged / weapon / grappling) fold into a consistent
#  ring with NO mutual contradictions (verified: no pair beats each other).

const ARCH_FAST: String = "fast"
const ARCH_POWER: String = "power"
const ARCH_DEFENSIVE: String = "defensive"
const ARCH_RANGED: String = "ranged"
const ARCH_WEAPON: String = "weapon"
const ARCH_GRAPPLING: String = "grappling"

const ARCHETYPES: Array = [
	ARCH_FAST, ARCH_POWER, ARCH_DEFENSIVE, ARCH_RANGED, ARCH_WEAPON, ARCH_GRAPPLING,
]

## beats[a] = the archetypes `a` has the damage advantage over. Consistent (no A
## beats B while B beats A). The core triangle is the first entries.
const BEATS: Dictionary = {
	ARCH_FAST: [ARCH_POWER, ARCH_WEAPON],
	ARCH_POWER: [ARCH_DEFENSIVE, ARCH_GRAPPLING],
	ARCH_DEFENSIVE: [ARCH_FAST, ARCH_RANGED],
	ARCH_RANGED: [ARCH_WEAPON, ARCH_GRAPPLING],
	ARCH_WEAPON: [ARCH_DEFENSIVE, ARCH_POWER],
	ARCH_GRAPPLING: [ARCH_FAST, ARCH_WEAPON],
}

# =====================================================================
#  The six styles + their move sets (real frame data)
# =====================================================================
#  A move: {id,name,kind,startup,active,recovery,damage,reach,chi_cost,knockback,
#           hitstun,projectile,proj_speed,props:[...]}. kind is light|heavy|special.
#  A style: {id,name,culture,archetype,hp_mod,chi_mod,damage_mod,speed_mod,
#            defense_mod,moves:{light,heavy,special}}.
#  These are hardcoded reference constants (see repo RULE #1.5), never a DB.

const STYLES: Dictionary = {
	"drunken_fist": {
		"id": "drunken_fist", "name": "Drunken Fist", "culture": "Southern Chinese",
		"archetype": ARCH_FAST,
		"hp_mod": 0.95, "chi_mod": 1.05, "damage_mod": 1.00, "speed_mod": 1.28, "defense_mod": 0.90,
		"moves": {
			"light": {"id": "df_jab", "name": "Reeling Jab", "kind": "light",
				"startup": 4, "active": 3, "recovery": 8, "damage": 6.0, "reach": 58.0,
				"chi_cost": 0.0, "knockback": 5.0, "hitstun": 12, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"heavy": {"id": "df_combo", "name": "Sloshing Combo", "kind": "heavy",
				"startup": 8, "active": 4, "recovery": 15, "damage": 12.0, "reach": 62.0,
				"chi_cost": 4.0, "knockback": 9.0, "hitstun": 17, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"special": {"id": "df_sway", "name": "Sway Counter", "kind": "special",
				"startup": 6, "active": 6, "recovery": 13, "damage": 15.0, "reach": 60.0,
				"chi_cost": 10.0, "knockback": 13.0, "hitstun": 20, "projectile": false,
				"proj_speed": 0.0, "props": ["counter"]},
		},
	},
	"iron_ox": {
		"id": "iron_ox", "name": "Iron Ox", "culture": "Mongolian Steppe",
		"archetype": ARCH_POWER,
		"hp_mod": 1.10, "chi_mod": 0.90, "damage_mod": 1.16, "speed_mod": 0.82, "defense_mod": 1.05,
		"moves": {
			"light": {"id": "ox_hook", "name": "Ox Hook", "kind": "light",
				"startup": 6, "active": 3, "recovery": 12, "damage": 10.0, "reach": 52.0,
				"chi_cost": 0.0, "knockback": 12.0, "hitstun": 14, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"heavy": {"id": "ox_haymaker", "name": "Haymaker", "kind": "heavy",
				"startup": 13, "active": 5, "recovery": 22, "damage": 22.0, "reach": 58.0,
				"chi_cost": 6.0, "knockback": 22.0, "hitstun": 24, "projectile": false,
				"proj_speed": 0.0, "props": ["armor"]},
			"special": {"id": "ox_pound", "name": "Ground Pound", "kind": "special",
				"startup": 17, "active": 6, "recovery": 25, "damage": 27.0, "reach": 72.0,
				"chi_cost": 14.0, "knockback": 20.0, "hitstun": 28, "projectile": false,
				"proj_speed": 0.0, "props": ["armor", "launcher"]},
		},
	},
	"willow_guard": {
		"id": "willow_guard", "name": "Willow Guard", "culture": "Japanese Aiki",
		"archetype": ARCH_DEFENSIVE,
		"hp_mod": 1.05, "chi_mod": 1.10, "damage_mod": 0.95, "speed_mod": 0.98, "defense_mod": 1.30,
		"moves": {
			"light": {"id": "wg_palm", "name": "Guiding Palm", "kind": "light",
				"startup": 5, "active": 3, "recovery": 10, "damage": 7.0, "reach": 54.0,
				"chi_cost": 0.0, "knockback": 8.0, "hitstun": 12, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"heavy": {"id": "wg_redirect", "name": "Redirect Throw", "kind": "heavy",
				"startup": 9, "active": 4, "recovery": 16, "damage": 13.0, "reach": 56.0,
				"chi_cost": 5.0, "knockback": 16.0, "hitstun": 20, "projectile": false,
				"proj_speed": 0.0, "props": ["armor"]},
			"special": {"id": "wg_stillwater", "name": "Still-Water Counter", "kind": "special",
				"startup": 4, "active": 8, "recovery": 18, "damage": 18.0, "reach": 55.0,
				"chi_cost": 12.0, "knockback": 18.0, "hitstun": 26, "projectile": false,
				"proj_speed": 0.0, "props": ["counter"]},
		},
	},
	"ghost_palm": {
		"id": "ghost_palm", "name": "Ghost Palm", "culture": "Tibetan Highland",
		"archetype": ARCH_RANGED,
		"hp_mod": 0.90, "chi_mod": 1.30, "damage_mod": 1.00, "speed_mod": 0.96, "defense_mod": 0.88,
		"moves": {
			"light": {"id": "gp_bolt", "name": "Chi Bolt", "kind": "light",
				"startup": 7, "active": 26, "recovery": 12, "damage": 8.0, "reach": 20.0,
				"chi_cost": 6.0, "knockback": 6.0, "hitstun": 12, "projectile": true,
				"proj_speed": 13.0, "props": ["projectile"]},
			"heavy": {"id": "gp_twin", "name": "Twin Palms", "kind": "heavy",
				"startup": 10, "active": 30, "recovery": 18, "damage": 13.0, "reach": 20.0,
				"chi_cost": 10.0, "knockback": 10.0, "hitstun": 16, "projectile": true,
				"proj_speed": 13.0, "props": ["projectile"]},
			"special": {"id": "gp_lance", "name": "Spirit Lance", "kind": "special",
				"startup": 12, "active": 36, "recovery": 22, "damage": 21.0, "reach": 20.0,
				"chi_cost": 18.0, "knockback": 16.0, "hitstun": 22, "projectile": true,
				"proj_speed": 14.0, "props": ["projectile"]},
		},
	},
	"steel_crane": {
		"id": "steel_crane", "name": "Steel Crane", "culture": "Korean Staff",
		"archetype": ARCH_WEAPON,
		"hp_mod": 1.00, "chi_mod": 1.00, "damage_mod": 1.08, "speed_mod": 1.02, "defense_mod": 1.00,
		"moves": {
			"light": {"id": "sc_thrust", "name": "Crane Thrust", "kind": "light",
				"startup": 6, "active": 3, "recovery": 12, "damage": 9.0, "reach": 96.0,
				"chi_cost": 0.0, "knockback": 10.0, "hitstun": 14, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"heavy": {"id": "sc_sweep", "name": "Low Sweep", "kind": "heavy",
				"startup": 11, "active": 5, "recovery": 18, "damage": 15.0, "reach": 106.0,
				"chi_cost": 5.0, "knockback": 14.0, "hitstun": 20, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"special": {"id": "sc_whirl", "name": "Whirlwind Staff", "kind": "special",
				"startup": 10, "active": 9, "recovery": 22, "damage": 19.0, "reach": 112.0,
				"chi_cost": 12.0, "knockback": 18.0, "hitstun": 24, "projectile": false,
				"proj_speed": 0.0, "props": ["launcher"]},
		},
	},
	"coiling_serpent": {
		"id": "coiling_serpent", "name": "Coiling Serpent", "culture": "Thai Clinch",
		"archetype": ARCH_GRAPPLING,
		"hp_mod": 1.08, "chi_mod": 0.95, "damage_mod": 1.15, "speed_mod": 1.05, "defense_mod": 0.95,
		"moves": {
			"light": {"id": "cs_knee", "name": "Clinch Knee", "kind": "light",
				"startup": 6, "active": 3, "recovery": 12, "damage": 9.0, "reach": 44.0,
				"chi_cost": 0.0, "knockback": 4.0, "hitstun": 14, "projectile": false,
				"proj_speed": 0.0, "props": []},
			"heavy": {"id": "cs_toss", "name": "Shoulder Toss", "kind": "heavy",
				"startup": 10, "active": 4, "recovery": 20, "damage": 16.0, "reach": 42.0,
				"chi_cost": 6.0, "knockback": 26.0, "hitstun": 22, "projectile": false,
				"proj_speed": 0.0, "props": ["throw"]},
			"special": {"id": "cs_suplex", "name": "Dragon Suplex", "kind": "special",
				"startup": 12, "active": 5, "recovery": 26, "damage": 25.0, "reach": 40.0,
				"chi_cost": 14.0, "knockback": 30.0, "hitstun": 30, "projectile": false,
				"proj_speed": 0.0, "props": ["throw", "launcher"]},
		},
	},
}

const STYLE_ORDER: Array = [
	"drunken_fist", "iron_ox", "willow_guard", "ghost_palm", "steel_crane", "coiling_serpent",
]
const MOVE_KINDS: Array = ["light", "heavy", "special"]

# =====================================================================
#  Campaign definition (a bounded ladder ending in a final duel)
# =====================================================================
#  Each encounter: an opponent style + a level offset + an optional style REWARD
#  the player learns from the master when they win. Escalating, finite -> the
#  campaign always terminates. The player starts knowing two styles; each master
#  teaches one more, so by the final duel the full six-style toolkit is available.

## `hp_scale` + `dmg_scale` ramp the ladder: the opening bruiser is a weakling a
## fresh disciple can beat, and each rung is tougher up to the final duel. They
## stack ON TOP of the difficulty multipliers (so the "buffed" preset multiplies
## every rung into an unwinnable wall -> the reachable LOSS).
const CAMPAIGN: Array = [
	{"name": "Alley Bruiser", "style": "iron_ox", "level_offset": 0, "teaches": "willow_guard",
		"xp": 60, "master": "Old Reed, the Willow Sage", "hp_scale": 0.68, "dmg_scale": 0.66},
	{"name": "Temple Sentinel", "style": "drunken_fist", "level_offset": 0, "teaches": "ghost_palm",
		"xp": 90, "master": "Nun of the Silent Peak", "hp_scale": 0.76, "dmg_scale": 0.72},
	{"name": "Highland Adept", "style": "ghost_palm", "level_offset": 1, "teaches": "steel_crane",
		"xp": 120, "master": "Crane Marshal Ho", "hp_scale": 0.82, "dmg_scale": 0.78},
	{"name": "Staff Marshal", "style": "steel_crane", "level_offset": 1, "teaches": "coiling_serpent",
		"xp": 150, "master": "Serpent Matron", "hp_scale": 0.88, "dmg_scale": 0.83},
	{"name": "Serpent Champion", "style": "coiling_serpent", "level_offset": 2, "teaches": "",
		"xp": 190, "master": "", "hp_scale": 0.76, "dmg_scale": 0.78},
	{"name": "The Lotus Tyrant (Final Duel)", "style": "willow_guard", "level_offset": 2,
		"teaches": "", "xp": 240, "master": "", "hp_scale": 0.84, "dmg_scale": 0.84},
]

const START_STYLES: Array = ["drunken_fist", "iron_ox"]
const CONTINUES_DEFAULT: int = 2          ## losing a fight burns a continue; 0 left -> campaign LOSS.
const XP_PER_LEVEL: int = 100             ## XP threshold per level.

# =====================================================================
#  Live run state
# =====================================================================

## The player's persistent RPG record (survives across encounters).
var player: Dictionary = {}

## The two combatants of the CURRENT fight: [side0, side1]. side0 is the player.
var fighters: Array = []

## Campaign progress.
var encounter_index: int = 0
var continues_left: int = CONTINUES_DEFAULT
var campaign_over: bool = false
var campaign_result: String = "running"   ## running | won | lost.

## Current-fight state.
var step_count: int = 0
var fight_over: bool = false
var fight_outcome: String = "none"         ## none | side0 | side1 | timeout.
var illegal_attempts: int = 0
var event_log: Array = []                  ## recent human-readable combat lines.

## Config / difficulty (set in setup()).
var max_steps: int = MAX_STEPS_DEFAULT
var foe_hp_mult: float = 1.0
var foe_dmg_mult: float = 1.0
var player_dmg_mult: float = 1.0
var ai_jitter: float = 0.0                 ## seeded AI decision jitter (default 0 = canned).
var difficulty: String = "normal"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0

# =====================================================================
#  Setup
# =====================================================================

## Start a fresh campaign. seed_value == 0 -> random (still saved so it replays);
## any other value replays byte-identically. `config` overrides difficulty:
##   difficulty:String ("normal" | "buffed" | "easy"),
##   foe_hp_mult, foe_dmg_mult, player_dmg_mult, max_steps, ai_jitter,
##   start_styles:Array, continues:int.
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	difficulty = String(config.get("difficulty", "normal"))
	_apply_difficulty(difficulty)
	foe_hp_mult = float(config.get("foe_hp_mult", foe_hp_mult))
	foe_dmg_mult = float(config.get("foe_dmg_mult", foe_dmg_mult))
	player_dmg_mult = float(config.get("player_dmg_mult", player_dmg_mult))
	max_steps = int(config.get("max_steps", max_steps))
	ai_jitter = float(config.get("ai_jitter", 0.0))
	continues_left = int(config.get("continues", CONTINUES_DEFAULT))

	var start_styles: Array = config.get("start_styles", START_STYLES)
	player = _new_player(start_styles)

	encounter_index = 0
	campaign_over = false
	campaign_result = "running"
	fighters = []
	step_count = 0
	fight_over = false
	fight_outcome = "none"
	illegal_attempts = 0
	event_log = []


## Difficulty presets. normal: a fair ladder a skilled counter-policy clears.
## buffed: foes get big HP + damage multipliers so a base player is overwhelmed
## (the guaranteed-reachable LOSS). easy: extra continues + weaker foes.
func _apply_difficulty(name: String) -> void:
	match name:
		"buffed":
			foe_hp_mult = 2.2
			foe_dmg_mult = 2.05
			player_dmg_mult = 0.72
			max_steps = MAX_STEPS_DEFAULT
		"easy":
			foe_hp_mult = 0.82
			foe_dmg_mult = 0.85
			player_dmg_mult = 1.12
			max_steps = MAX_STEPS_DEFAULT
		_:  # normal
			foe_hp_mult = 1.0
			foe_dmg_mult = 1.0
			player_dmg_mult = 1.0
			max_steps = MAX_STEPS_DEFAULT


## Build the player's persistent RPG record. Two attributes start modest; body +
## spirit climb with levelling. known_styles seeds the starting kit; upgrades is a
## per-style technique-point tally that deepens each style's damage.
func _new_player(start_styles: Array) -> Dictionary:
	var known: Array = []
	for s in start_styles:
		if STYLES.has(String(s)) and not known.has(String(s)):
			known.append(String(s))
	if known.is_empty():
		known = [START_STYLES[0]]
	var upgrades: Dictionary = {}
	for sid in STYLE_ORDER:
		upgrades[sid] = 0
	return {
		"name": "Wandering Disciple",
		"body": 8, "mind": 6, "spirit": 7,
		"level": 1, "xp": 0,
		"technique_points": 0,
		"attribute_points": 0,
		"known_styles": known,
		"upgrades": upgrades,
		"active_style": String(known[0]),
	}

# =====================================================================
#  Fighter construction (a combat entity built from a profile)
# =====================================================================

## Build a combat entity. `profile` = {name, body, mind, spirit, known_styles,
## upgrades, active_style, policy, hp_mult, dmg_mult}. Positions + facing are set
## by begin_fight; here we derive HP/chi from the attributes + active style.
func _make_fighter(profile: Dictionary, side: int) -> Dictionary:
	var active_style: String = String(profile.get("active_style", ""))
	var known: Array = profile.get("known_styles", [])
	if not STYLES.has(active_style):
		active_style = String(known[0]) if known.size() > 0 else STYLE_ORDER[0]
	var body: int = int(profile.get("body", 6))
	var spirit: int = int(profile.get("spirit", 5))
	var style: Dictionary = STYLES[active_style]
	var max_hp: float = (HP_BASE + HP_PER_BODY * float(body)) * float(style["hp_mod"]) * float(profile.get("hp_mult", 1.0))
	var max_chi: float = (CHI_MAX_BASE + CHI_PER_SPIRIT * float(spirit)) * float(style["chi_mod"])
	return {
		"name": String(profile.get("name", "Fighter")),
		"side": side,
		"body": body, "mind": int(profile.get("mind", 5)), "spirit": spirit,
		"known_styles": (known as Array).duplicate(),
		"upgrades": (profile.get("upgrades", {}) as Dictionary).duplicate(),
		"active_style": active_style,
		"policy": String(profile.get("policy", "skilled_counter")),
		"dmg_mult": float(profile.get("dmg_mult", 1.0)),
		"x": 0.0, "vx": 0.0, "facing": 1,
		"hp": max_hp, "max_hp": max_hp,
		"chi": max_chi, "max_chi": max_chi,
		"action": ACT_IDLE,
		"move_kind": "",           # which move is executing (light/heavy/special).
		"action_frame": 0,
		"action_total": 0,
		"hit_done": false,         # a move lands at most once per activation.
		"pending": {},             # a human-queued action, consumed next step.
		"combo": 0,                # consecutive landed hits (for the HUD / XP flavour).
	}


## Turn the persistent player record into a combat profile.
func _player_profile(policy: String, dmg_mult: float) -> Dictionary:
	return {
		"name": String(player["name"]),
		"body": int(player["body"]), "mind": int(player["mind"]), "spirit": int(player["spirit"]),
		"known_styles": (player["known_styles"] as Array).duplicate(),
		"upgrades": (player["upgrades"] as Dictionary).duplicate(),
		"active_style": String(player["active_style"]),
		"policy": policy, "hp_mult": 1.0, "dmg_mult": dmg_mult,
	}


## Build the AI opponent profile for an encounter, scaled by the ladder + difficulty.
func _foe_profile(enc: Dictionary) -> Dictionary:
	var lvl_off: int = int(enc.get("level_offset", 0))
	var body: int = 6 + lvl_off * 2
	var spirit: int = 5 + lvl_off
	var style_id: String = String(enc["style"])
	return {
		"name": String(enc["name"]),
		"body": body, "mind": 5 + lvl_off, "spirit": spirit,
		"known_styles": [style_id],
		"upgrades": {style_id: lvl_off},
		"active_style": style_id,
		"policy": "boss" if lvl_off >= 3 else "foe_normal",
		"hp_mult": foe_hp_mult * float(enc.get("hp_scale", 1.0)),
		"dmg_mult": foe_dmg_mult * float(enc.get("dmg_scale", 1.0)),
	}


## Set up a fresh fight between two profiles. side0 (profile_a) faces side1 to the
## right; both start facing each other, centred and START_GAP apart.
func begin_fight(profile_a: Dictionary, profile_b: Dictionary) -> void:
	var a: Dictionary = _make_fighter(profile_a, 0)
	var b: Dictionary = _make_fighter(profile_b, 1)
	var mid: float = (STAGE_MIN + STAGE_MAX) * 0.5
	a["x"] = mid - START_GAP * 0.5
	b["x"] = mid + START_GAP * 0.5
	a["facing"] = 1
	b["facing"] = -1
	fighters = [a, b]
	step_count = 0
	fight_over = false
	fight_outcome = "none"


# =====================================================================
#  Style / move / matchup helpers
# =====================================================================

func style_archetype(style_id: String) -> String:
	if STYLES.has(style_id):
		return String(STYLES[style_id]["archetype"])
	return ARCH_FAST


## The matchup multiplier applied to attacker damage: ADV if attacker's archetype
## beats defender's, DIS if it loses, EVEN otherwise. This is the REAL advantage
## (it scales damage), not cosmetic.
func matchup_multiplier(attacker_style: String, defender_style: String) -> float:
	var aa: String = style_archetype(attacker_style)
	var da: String = style_archetype(defender_style)
	if aa == da:
		return MATCHUP_EVEN
	if (BEATS[aa] as Array).has(da):
		return MATCHUP_ADV
	if (BEATS[da] as Array).has(aa):
		return MATCHUP_DIS
	return MATCHUP_EVEN


## The style that best counters `foe_style` among `known_styles` (highest matchup
## multiplier; ties broken by STYLE_ORDER for determinism).
func best_counter_style(known_styles: Array, foe_style: String) -> String:
	var best: String = ""
	var best_mult: float = -1.0
	for sid in STYLE_ORDER:
		if not (known_styles as Array).has(sid):
			continue
		var m: float = matchup_multiplier(sid, foe_style)
		if m > best_mult:
			best_mult = m
			best = sid
	if best == "":
		best = String((known_styles as Array)[0]) if (known_styles as Array).size() > 0 else STYLE_ORDER[0]
	return best


func move_of(style_id: String, kind: String) -> Dictionary:
	return STYLES[style_id]["moves"][kind]


## The upgrade-scaled damage of a move for a given fighter (technique points on the
## style raise it). Attribute + matchup scaling is applied later in _apply_hit.
func _move_base_damage(f: Dictionary, style_id: String, kind: String) -> float:
	var mv: Dictionary = move_of(style_id, kind)
	var pts: int = int((f["upgrades"] as Dictionary).get(style_id, 0))
	return float(mv["damage"]) * (1.0 + UPGRADE_DMG_STEP * float(pts))

# =====================================================================
#  Legality — the rules probe checks these
# =====================================================================

## Is `action` legal for the fighter on `side` RIGHT NOW? Rejects: acting while
## busy (mid-attack / stunned), using a move from a style you have not learned,
## switching to an unlearned style, and specials you cannot afford. Illegal
## attempts are counted (not applied).
func is_legal(side: int, action: Dictionary) -> bool:
	if side < 0 or side >= fighters.size():
		return false
	var f: Dictionary = fighters[side]
	var t: String = String(action.get("type", ""))
	match t:
		"idle", "walk":
			return true
		"block":
			# can raise / hold a guard whenever not stunned or mid-attack.
			return f["action"] == ACT_IDLE or f["action"] == ACT_BLOCK
		"switch":
			if f["action"] != ACT_IDLE and f["action"] != ACT_BLOCK:
				return false
			var sid: String = String(action.get("style", ""))
			return (f["known_styles"] as Array).has(sid) and STYLES.has(sid)
		"attack":
			if f["action"] != ACT_IDLE and f["action"] != ACT_BLOCK:
				return false
			var kind: String = String(action.get("kind", ""))
			if not MOVE_KINDS.has(kind):
				return false
			var style_id: String = String(f["active_style"])
			if not (f["known_styles"] as Array).has(style_id):
				return false
			var mv: Dictionary = move_of(style_id, kind)
			return float(f["chi"]) >= float(mv["chi_cost"])
		_:
			return false


## Queue a human action for the given side (consumed on the next step). Rejects +
## counts illegal actions. Returns true if accepted.
func request_action(side: int, action: Dictionary) -> bool:
	if not is_legal(side, action):
		illegal_attempts += 1
		return false
	var f: Dictionary = fighters[side]
	f["pending"] = action.duplicate(true)
	return true


## Directly switch a fighter's active style (used by policies + the UI). Legal only
## when idle/blocking and the style is known. Counts illegal attempts.
func switch_style(side: int, style_id: String) -> bool:
	if not is_legal(side, {"type": "switch", "style": style_id}):
		illegal_attempts += 1
		return false
	var f: Dictionary = fighters[side]
	f["active_style"] = style_id
	# switching does NOT refill HP, but re-derives the chi ceiling from the new
	# style's chi_mod (chi is clamped to the new max).
	var style: Dictionary = STYLES[style_id]
	f["max_chi"] = (CHI_MAX_BASE + CHI_PER_SPIRIT * float(f["spirit"])) * float(style["chi_mod"])
	f["chi"] = minf(float(f["chi"]), float(f["max_chi"]))
	return true

# =====================================================================
#  The fixed-timestep step
# =====================================================================

## Advance the current fight by ONE fixed DT. Deterministic + bounded. Resolves
## each side's intent (human pending action or AI decision), starts/advances
## actions, projects active hitboxes + resolves hits, integrates movement, regens
## chi, then checks the KO / timeout end conditions. Returns true while the fight
## is still live.
func step() -> bool:
	if fight_over or fighters.size() < 2:
		return false

	# 1) resolve intent for both sides (deterministic order: side0 then side1).
	for side in 2:
		_resolve_intent(side)

	# 2) advance actions + resolve active-frame hits (attacker order side0, side1).
	_advance_and_hit(0, 1)
	_advance_and_hit(1, 0)

	# 3) integrate movement (knockback velocity + walk), keep bodies from overlapping.
	for side in 2:
		_integrate_motion(side)
	_separate_bodies()

	# 4) chi regen + face the foe when neutral.
	for side in 2:
		_regen_and_face(side)

	step_count += 1
	_check_fight_end()
	return not fight_over


## Decide + apply this side's action for the step. A human's queued `pending`
## action wins; otherwise the fighter's AI policy chooses. Only actionable states
## (idle / block) can start something new.
func _resolve_intent(side: int) -> void:
	var f: Dictionary = fighters[side]
	if f["action"] != ACT_IDLE and f["action"] != ACT_BLOCK:
		# busy (attacking / stunned) — clear any stale pending intent, keep going.
		f["pending"] = {}
		return
	var action: Dictionary = {}
	if not (f["pending"] as Dictionary).is_empty():
		action = f["pending"] as Dictionary
		f["pending"] = {}
	else:
		action = _ai_decide(side)
	_apply_action(side, action)


## Apply a resolved action to a fighter that is idle or blocking.
func _apply_action(side: int, action: Dictionary) -> void:
	var f: Dictionary = fighters[side]
	var t: String = String(action.get("type", "idle"))
	match t:
		"attack":
			if not is_legal(side, action):
				return
			_start_attack(side, String(action["kind"]))
		"switch":
			switch_style(side, String(action.get("style", "")))
			# hold guard after a switch so the fighter is not exposed.
			if f["action"] == ACT_IDLE:
				f["action"] = ACT_BLOCK
		"block":
			f["action"] = ACT_BLOCK
		"walk":
			# leave a raised guard to walk.
			f["action"] = ACT_IDLE
			var dir: int = int(action.get("dir", 0))
			f["vx"] = float(dir) * _walk_speed(f)
		"idle", _:
			if f["action"] == ACT_BLOCK:
				f["action"] = ACT_IDLE
			f["vx"] = 0.0


func _start_attack(side: int, kind: String) -> void:
	var f: Dictionary = fighters[side]
	var style_id: String = String(f["active_style"])
	var mv: Dictionary = move_of(style_id, kind)
	f["chi"] = maxf(0.0, float(f["chi"]) - float(mv["chi_cost"]))
	f["action"] = ACT_ATTACK
	f["move_kind"] = kind
	f["action_frame"] = 0
	f["action_total"] = int(mv["startup"]) + int(mv["active"]) + int(mv["recovery"])
	f["hit_done"] = false
	f["vx"] = 0.0


## Advance `attacker`'s action one frame; if it is in its ACTIVE window this frame,
## project the hitbox and resolve a hit on `defender`.
func _advance_and_hit(attacker: int, defender: int) -> void:
	var f: Dictionary = fighters[attacker]
	match String(f["action"]):
		ACT_ATTACK:
			var mv: Dictionary = move_of(String(f["active_style"]), String(f["move_kind"]))
			var frame: int = int(f["action_frame"])
			var startup: int = int(mv["startup"])
			var active: int = int(mv["active"])
			# resolve a hit on the frames that are ACTIVE (single hit per activation).
			if frame >= startup and frame < startup + active and not bool(f["hit_done"]):
				_try_hit(attacker, defender, mv)
			f["action_frame"] = frame + 1
			if int(f["action_frame"]) >= int(f["action_total"]):
				f["action"] = ACT_IDLE
				f["move_kind"] = ""
				f["action_frame"] = 0
		ACT_HITSTUN, ACT_BLOCKSTUN:
			f["action_frame"] = int(f["action_frame"]) + 1
			if int(f["action_frame"]) >= int(f["action_total"]):
				f["action"] = ACT_IDLE
				f["action_frame"] = 0
		_:
			pass


## Compute the attacker's active hitbox interval [lo, hi] this frame (a melee reach
## in front, or a travelling projectile), and if it overlaps the defender's
## hurtbox apply the hit.
func _try_hit(attacker: int, defender: int, mv: Dictionary) -> void:
	var fa: Dictionary = fighters[attacker]
	var fd: Dictionary = fighters[defender]
	var facing: int = int(fa["facing"])
	var front: float = float(fa["x"]) + float(facing) * FRONT_OFFSET
	var lo: float = 0.0
	var hi: float = 0.0
	if bool(mv["projectile"]):
		var into_active: int = int(fa["action_frame"]) - int(mv["startup"])
		var traveled: float = float(into_active) * float(mv["proj_speed"])
		var center: float = front + float(facing) * traveled
		lo = center - PROJ_HALF
		hi = center + PROJ_HALF
	else:
		var far: float = front + float(facing) * float(mv["reach"])
		lo = minf(front, far)
		hi = maxf(front, far)
	var d_lo: float = float(fd["x"]) - HURT_HALF
	var d_hi: float = float(fd["x"]) + HURT_HALF
	if hi >= d_lo and lo <= d_hi:
		_apply_hit(attacker, defender, mv)
		fa["hit_done"] = true


## Land a confirmed hit: compute matchup- + attribute- + upgrade-scaled damage,
## route it through the defender's block (chip + blockstun) or a clean hit
## (hitstun + knockback), and log it.
func _apply_hit(attacker: int, defender: int, mv: Dictionary) -> void:
	var fa: Dictionary = fighters[attacker]
	var fd: Dictionary = fighters[defender]
	var kind: String = String(mv["kind"])
	var style_id: String = String(fa["active_style"])

	# base move damage (with technique upgrades) -> attribute scaling -> style mod
	# -> difficulty mult -> matchup.
	var dmg: float = _move_base_damage(fa, style_id, kind)
	var is_chi: bool = bool(mv["projectile"]) or kind == "special"
	if is_chi:
		dmg *= 1.0 + SPIRIT_DMG_PER_SPIRIT * float(fa["spirit"])
	else:
		dmg *= 1.0 + PHYS_DMG_PER_BODY * float(fa["body"])
	dmg *= float(STYLES[style_id]["damage_mod"])
	dmg *= float(fa["dmg_mult"])
	dmg *= matchup_multiplier(style_id, String(fd["active_style"]))

	# the defender's MIND grants a small flat incoming-damage reduction + their
	# active style's defense_mod.
	var guard: float = 1.0 - MIND_GUARD_PER_MIND * float(fd["mind"])
	guard = clampf(guard, 0.35, 1.0)
	dmg *= guard
	dmg /= maxf(0.6, float(STYLES[String(fd["active_style"])]["defense_mod"]))

	var facing: int = int(fa["facing"])
	var blocking: bool = String(fd["action"]) == ACT_BLOCK and _is_facing_attacker(fd, fa)
	if blocking:
		var chip: float = dmg * BLOCK_CHIP
		fd["hp"] = maxf(0.0, float(fd["hp"]) - chip)
		fd["chi"] = maxf(0.0, float(fd["chi"]) - dmg * BLOCK_CHI_CHIP)
		fd["vx"] = float(fd["vx"]) + float(facing) * float(mv["knockback"]) * KB_SCALE * BLOCK_KB_SCALE
		fd["action"] = ACT_BLOCKSTUN
		fd["action_frame"] = 0
		fd["action_total"] = BLOCKSTUN_FRAMES
		fa["combo"] = 0
		_log("%s blocks %s (chip %.1f)" % [String(fd["name"]), String(mv["name"]), chip])
	else:
		fd["hp"] = maxf(0.0, float(fd["hp"]) - dmg)
		fd["vx"] = float(fd["vx"]) + float(facing) * float(mv["knockback"]) * KB_SCALE
		fd["action"] = ACT_HITSTUN
		fd["move_kind"] = ""
		fd["action_frame"] = 0
		fd["action_total"] = int(mv["hitstun"])
		fa["combo"] = int(fa["combo"]) + 1
		_log("%s lands %s for %.1f (%s)" % [
			String(fa["name"]), String(mv["name"]), dmg, String(fa["active_style"])])


func _is_facing_attacker(defender: Dictionary, attacker: Dictionary) -> bool:
	var to_atk: float = float(attacker["x"]) - float(defender["x"])
	return (to_atk >= 0.0 and int(defender["facing"]) > 0) or (to_atk < 0.0 and int(defender["facing"]) < 0)


## Integrate a fighter's horizontal motion: knockback velocity decays under drag;
## walking is a fixed velocity set by the action. Clamp to the stage walls.
func _integrate_motion(side: int) -> void:
	var f: Dictionary = fighters[side]
	f["x"] = float(f["x"]) + float(f["vx"]) * DT
	# drag only bleeds the residual knockback/walk velocity between steps.
	var drag: float = clampf(1.0 - MOVE_DRAG * DT, 0.0, 1.0)
	f["vx"] = float(f["vx"]) * drag
	if absf(float(f["vx"])) < 1.0:
		f["vx"] = 0.0
	f["x"] = clampf(float(f["x"]), STAGE_MIN, STAGE_MAX)


## Bodies cannot pass through each other: if the two fighters overlap closer than
## their combined hurt half-widths, push them apart symmetrically.
func _separate_bodies() -> void:
	var a: Dictionary = fighters[0]
	var b: Dictionary = fighters[1]
	var min_gap: float = 2.0 * HURT_HALF - TOUCH_PAD
	var gap: float = float(b["x"]) - float(a["x"])
	if absf(gap) < min_gap:
		var push: float = (min_gap - absf(gap)) * 0.5
		var dir: float = 1.0 if gap >= 0.0 else -1.0
		a["x"] = clampf(float(a["x"]) - dir * push, STAGE_MIN, STAGE_MAX)
		b["x"] = clampf(float(b["x"]) + dir * push, STAGE_MIN, STAGE_MAX)


## Regen chi (faster while idle) and turn to face the foe when in a neutral state
## (idle / blocking) — you cannot turn mid-attack or mid-stun.
func _regen_and_face(side: int) -> void:
	var f: Dictionary = fighters[side]
	var regen: float = CHI_REGEN_IDLE if String(f["action"]) == ACT_IDLE else CHI_REGEN_BUSY
	f["chi"] = minf(float(f["max_chi"]), float(f["chi"]) + regen * DT)
	if String(f["action"]) == ACT_IDLE or String(f["action"]) == ACT_BLOCK:
		var foe: Dictionary = fighters[1 - side]
		f["facing"] = 1 if float(foe["x"]) >= float(f["x"]) else -1


func _check_fight_end() -> void:
	var a: Dictionary = fighters[0]
	var b: Dictionary = fighters[1]
	if float(a["hp"]) <= 0.0 and float(b["hp"]) <= 0.0:
		# simultaneous KO -> the side with the higher (less negative) HP fraction; tie
		# goes to the defender side1. Deterministic.
		fight_over = true
		fight_outcome = "side1"
		return
	if float(b["hp"]) <= 0.0:
		fight_over = true
		fight_outcome = "side0"
		return
	if float(a["hp"]) <= 0.0:
		fight_over = true
		fight_outcome = "side1"
		return
	if step_count >= max_steps:
		fight_over = true
		# timeout: higher HP fraction wins; exact tie -> side1 (the defender).
		var fa: float = float(a["hp"]) / maxf(1.0, float(a["max_hp"]))
		var fb: float = float(b["hp"]) / maxf(1.0, float(b["max_hp"]))
		fight_outcome = "side0" if fa > fb else "side1"


func fight_winner() -> int:
	if fight_outcome == "side0":
		return 0
	if fight_outcome == "side1":
		return 1
	return -1

# =====================================================================
#  AI policies (deterministic — drive a whole fight headlessly)
# =====================================================================
#  A policy returns an action dict for a fighter given the current state. Combat
#  has ZERO randomness; the only stochastic element is an optional seeded jitter on
#  the AI's spacing thresholds (config "ai_jitter", default 0 -> canned).

## The AI decision for `side`. Dispatches on the fighter's policy name.
func _ai_decide(side: int) -> Dictionary:
	var f: Dictionary = fighters[side]
	var foe: Dictionary = fighters[1 - side]
	match String(f["policy"]):
		"skilled_counter":
			return _policy_skilled(side, f, foe, true, true)
		"boss":
			return _policy_skilled(side, f, foe, true, true)
		"foe_normal":
			return _policy_skilled(side, f, foe, false, true)
		"aggressive_weak":
			return _policy_skilled(side, f, foe, false, false)
		"turtle":
			return {"type": "block"}
		_:
			return {"type": "idle"}


## The workhorse policy. `use_counter` = switch to the style that best beats the
## foe when neutral; `guard` = block when the foe is threatening. Spacing: walk in
## until a move reaches, then throw the best AFFORDABLE move that reaches; retreat
## a step is never needed on a 1-D stage. A tiny seeded jitter can widen/narrow the
## engage range so two seeds diverge (the determinism probe relies on this).
func _policy_skilled(side: int, f: Dictionary, foe: Dictionary, use_counter: bool, guard: bool) -> Dictionary:
	var gap: float = absf(float(foe["x"]) - float(f["x"]))
	var jitter: float = 0.0
	if ai_jitter > 0.0:
		jitter = _rng.randf_range(-ai_jitter, ai_jitter)

	# 1) counter-switch when neutral and not already on the best counter.
	if use_counter:
		var counter: String = best_counter_style(f["known_styles"] as Array, String(foe["active_style"]))
		if counter != String(f["active_style"]) and (f["known_styles"] as Array).size() > 1:
			return {"type": "switch", "style": counter}

	# 2) defensive read: if the foe is winding up / active AND within its threat
	#    range, raise guard (only when we can afford to react).
	if guard and _foe_is_threatening(foe, gap):
		return {"type": "block"}

	# 3) offence: pick the best affordable move that reaches this gap.
	var kind: String = _best_reaching_move(f, gap + jitter)
	if kind != "":
		return {"type": "attack", "kind": kind}

	# 4) close the distance (or nudge to projectile range for a ranged style).
	var dir: int = 1 if float(foe["x"]) >= float(f["x"]) else -1
	return {"type": "walk", "dir": dir}


## Is the foe actively threatening us within its move's reach? True while it is in
## startup or active frames of an attack whose reach (or projectile travel) covers
## the current gap.
func _foe_is_threatening(foe: Dictionary, gap: float) -> bool:
	if String(foe["action"]) != ACT_ATTACK:
		return false
	var mv: Dictionary = move_of(String(foe["active_style"]), String(foe["move_kind"]))
	var reach: float = float(mv["reach"])
	if bool(mv["projectile"]):
		reach = float(mv["proj_speed"]) * float(mv["active"]) + FRONT_OFFSET
	# only worth blocking if the foe has not yet passed its active window.
	var frame: int = int(foe["action_frame"])
	var passed: bool = frame >= int(mv["startup"]) + int(mv["active"])
	return not passed and gap <= reach + HURT_HALF + FRONT_OFFSET + 12.0


## The strongest AFFORDABLE move in the active style whose effective reach covers
## `gap`. Prefers special > heavy > light when several reach + are affordable.
## Returns "" when nothing reaches (caller should close the distance).
func _best_reaching_move(f: Dictionary, gap: float) -> String:
	var style_id: String = String(f["active_style"])
	var order: Array = ["special", "heavy", "light"]
	for kind in order:
		var mv: Dictionary = move_of(style_id, kind)
		if float(f["chi"]) < float(mv["chi_cost"]):
			continue
		var eff: float = float(mv["reach"]) + FRONT_OFFSET + HURT_HALF
		if bool(mv["projectile"]):
			eff = float(mv["proj_speed"]) * float(mv["active"]) + FRONT_OFFSET + HURT_HALF
		if gap <= eff:
			return kind
	return ""


func _walk_speed(f: Dictionary) -> float:
	return WALK_SPEED_BASE * float(STYLES[String(f["active_style"])]["speed_mod"])

# =====================================================================
#  Fight drivers (run a whole fight under policies — for probes + campaign)
# =====================================================================

## Run the CURRENT fight to its end under each fighter's assigned policy. Bounded by
## max_steps. Returns the winning side (0/1). Pure w.r.t. combat; only touches the
## RNG for AI jitter (part of save/load).
func simulate_current_fight() -> int:
	while not fight_over:
		step()
	return fight_winner()


## Convenience: set up + run a one-off fight between two profiles to its end.
func simulate_fight(profile_a: Dictionary, profile_b: Dictionary) -> int:
	begin_fight(profile_a, profile_b)
	return simulate_current_fight()

# =====================================================================
#  RPG progression — XP / levels / learning / technique upgrades
# =====================================================================

## Grant XP and resolve any level-ups. Each level grants attribute + technique
## points; attribute points are auto-invested (body then spirit then mind) so the
## auto-play grows without UI, but the UI can also spend them explicitly.
func award_xp(amount: int) -> void:
	player["xp"] = int(player["xp"]) + maxi(0, amount)
	while int(player["xp"]) >= int(player["level"]) * XP_PER_LEVEL:
		player["xp"] = int(player["xp"]) - int(player["level"]) * XP_PER_LEVEL
		_level_up()


func _level_up() -> void:
	player["level"] = int(player["level"]) + 1
	player["attribute_points"] = int(player["attribute_points"]) + 3
	player["technique_points"] = int(player["technique_points"]) + 1
	# auto-invest for headless auto-play: cycle body -> spirit -> mind.
	var order: Array = ["body", "spirit", "body", "mind"]
	while int(player["attribute_points"]) > 0:
		var attr: String = String(order[int(player["level"]) % order.size()])
		if String(order[0]) == attr:
			pass
		# deterministic round-robin over the four picks by remaining points.
		var idx: int = (int(player["attribute_points"]) + int(player["level"])) % order.size()
		var pick: String = String(order[idx])
		player[pick] = int(player[pick]) + 1
		player["attribute_points"] = int(player["attribute_points"]) - 1


## Learn a new style (from a master / an encounter reward). Unlocks its moves.
## Returns false if already known or invalid.
func learn_style(style_id: String) -> bool:
	if not STYLES.has(style_id):
		return false
	if (player["known_styles"] as Array).has(style_id):
		return false
	(player["known_styles"] as Array).append(style_id)
	return true


## Has the player learned this style (its moves are usable)?
func knows_style(style_id: String) -> bool:
	return (player["known_styles"] as Array).has(style_id)


## Spend one technique point to deepen a KNOWN style (raises every move's damage by
## UPGRADE_DMG_STEP). Returns false if unknown or out of points.
func upgrade_technique(style_id: String) -> bool:
	if not knows_style(style_id):
		illegal_attempts += 1
		return false
	if int(player["technique_points"]) <= 0:
		return false
	player["technique_points"] = int(player["technique_points"]) - 1
	(player["upgrades"] as Dictionary)[style_id] = int((player["upgrades"] as Dictionary).get(style_id, 0)) + 1
	return true


## Set the player's active style (UI + policies). Legal only if learned.
func set_active_style(style_id: String) -> bool:
	if not knows_style(style_id):
		illegal_attempts += 1
		return false
	player["active_style"] = style_id
	return true

# =====================================================================
#  Campaign driver
# =====================================================================

## Start (or restart) the campaign at encounter 0 with the current player record.
func start_campaign() -> void:
	encounter_index = 0
	campaign_over = false
	campaign_result = "running"


## Prepare the fight for the current encounter: pick the player's counter style
## (auto-play convenience), then begin the fight. Returns the encounter dict.
func begin_current_encounter(player_policy: String = "skilled_counter") -> Dictionary:
	var enc: Dictionary = CAMPAIGN[encounter_index]
	# auto-select the best counter the player knows for this foe (the UI can still
	# switch mid-fight; this just seeds a sensible start).
	var counter: String = best_counter_style(player["known_styles"] as Array, String(enc["style"]))
	set_active_style(counter)
	var pprof: Dictionary = _player_profile(player_policy, player_dmg_mult)
	var fprof: Dictionary = _foe_profile(enc)
	begin_fight(pprof, fprof)
	return enc


## Resolve the OUTCOME of the just-finished current fight into campaign progress:
## a player win awards XP, learns the master's style + advances; a loss burns a
## continue (0 left -> campaign LOSS). Returns the campaign result string.
func resolve_encounter_outcome() -> String:
	var enc: Dictionary = CAMPAIGN[encounter_index]
	if fight_winner() == 0:
		award_xp(int(enc.get("xp", 40)))
		var teaches: String = String(enc.get("teaches", ""))
		if teaches != "":
			learn_style(teaches)
			# auto-invest a technique point into the freshly-taught style for auto-play.
			if int(player["technique_points"]) > 0:
				upgrade_technique(teaches)
		encounter_index += 1
		if encounter_index >= CAMPAIGN.size():
			campaign_over = true
			campaign_result = "won"
	else:
		continues_left -= 1
		if continues_left <= 0:
			campaign_over = true
			campaign_result = "lost"
	return campaign_result


## Fully auto-play the WHOLE campaign under a player policy, deterministically, to a
## terminal result ("won" | "lost"). Always terminates: finite encounters * finite
## continues, each fight step-capped. This is what the progression probe drives to
## prove BOTH a WIN (base difficulty) and a LOSS (buffed difficulty) are reachable.
func run_campaign(player_policy: String = "skilled_counter") -> String:
	start_campaign()
	var safety: int = 0
	var safety_cap: int = CAMPAIGN.size() * (CONTINUES_DEFAULT + 8) + 16
	while not campaign_over and safety < safety_cap:
		safety += 1
		begin_current_encounter(player_policy)
		simulate_current_fight()
		resolve_encounter_outcome()
	if not campaign_over:
		# the safety net should never trip (fights are step-capped); if it somehow
		# does, resolve as a loss so the driver still terminates cleanly.
		campaign_over = true
		campaign_result = "lost"
	return campaign_result


func is_campaign_won() -> bool:
	return campaign_over and campaign_result == "won"


func is_campaign_lost() -> bool:
	return campaign_over and campaign_result == "lost"

# =====================================================================
#  Queries for the view / probes
# =====================================================================

func fighter(side: int) -> Dictionary:
	if side < 0 or side >= fighters.size():
		return {}
	return fighters[side]


## The move set of a style as an ordered array of move dicts (light, heavy,
## special) — the UI move list + the styles probe read this.
func style_moves(style_id: String) -> Array:
	var out: Array = []
	if not STYLES.has(style_id):
		return out
	for kind in MOVE_KINDS:
		out.append((STYLES[style_id]["moves"][kind] as Dictionary).duplicate())
	return out


func current_encounter() -> Dictionary:
	if encounter_index < CAMPAIGN.size():
		return CAMPAIGN[encounter_index]
	return {}


func recent_log(n: int = 12) -> Array:
	var start: int = maxi(0, event_log.size() - n)
	return event_log.slice(start, event_log.size())


func _log(line: String) -> void:
	event_log.append(line)
	if event_log.size() > 200:
		event_log = event_log.slice(event_log.size() - 200, event_log.size())


func seed_value() -> int:
	return _seed

# =====================================================================
#  Determinism checksums
# =====================================================================

func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63


func _fold_f(h: int, v: float) -> int:
	return _fold(h, int(round(v * 1000.0)))


## FNV-1a over the QUANTISED fight state (both fighters' x/vx/hp/chi/action). Two
## engines with the same seed + config + input/AI script match iff this matches —
## the determinism probe folds this each step + at the end.
func fight_checksum() -> int:
	var h: int = FNV_OFFSET
	h = _fold(h, step_count)
	for side in fighters.size():
		var f: Dictionary = fighters[side]
		h = _fold_f(h, float(f["x"]))
		h = _fold_f(h, float(f["vx"]))
		h = _fold_f(h, float(f["hp"]))
		h = _fold_f(h, float(f["chi"]))
		h = _fold(h, int(f["facing"]))
		h = _fold(h, hash(String(f["action"])))
		h = _fold(h, hash(String(f["move_kind"])))
		h = _fold(h, int(f["action_frame"]))
		h = _fold(h, STYLE_ORDER.find(String(f["active_style"])))
		h = _fold(h, int(f["combo"]))
	return h


## Order-stable checksum of the WHOLE run (fight + campaign + player + RNG). Used by
## the save/load round-trip probe.
func run_checksum() -> int:
	var h: int = fight_checksum()
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, encounter_index)
	h = _fold(h, continues_left)
	h = _fold(h, 1 if campaign_over else 0)
	h = _fold(h, hash(campaign_result))
	h = _fold(h, 1 if fight_over else 0)
	h = _fold(h, hash(fight_outcome))
	h = _fold(h, illegal_attempts)
	h = _fold(h, int(player["level"]))
	h = _fold(h, int(player["xp"]))
	h = _fold(h, int(player["body"]))
	h = _fold(h, int(player["mind"]))
	h = _fold(h, int(player["spirit"]))
	h = _fold(h, int(player["technique_points"]))
	for sid in STYLE_ORDER:
		h = _fold(h, 1 if (player["known_styles"] as Array).has(sid) else 0)
		h = _fold(h, int((player["upgrades"] as Dictionary).get(sid, 0)))
	h = _fold(h, STYLE_ORDER.find(String(player["active_style"])))
	return h

# =====================================================================
#  Save / load — the WHOLE run round-trips (JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"rng_state": str(_rng.state),
		"difficulty": difficulty,
		"max_steps": max_steps,
		"foe_hp_mult": foe_hp_mult,
		"foe_dmg_mult": foe_dmg_mult,
		"player_dmg_mult": player_dmg_mult,
		"ai_jitter": ai_jitter,
		"encounter_index": encounter_index,
		"continues_left": continues_left,
		"campaign_over": campaign_over,
		"campaign_result": campaign_result,
		"step_count": step_count,
		"fight_over": fight_over,
		"fight_outcome": fight_outcome,
		"illegal_attempts": illegal_attempts,
		"player": _dup_player(player),
		"fighters": _dup_fighters(),
		"event_log": event_log.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	difficulty = String(data.get("difficulty", "normal"))
	max_steps = int(data.get("max_steps", MAX_STEPS_DEFAULT))
	foe_hp_mult = float(data.get("foe_hp_mult", 1.0))
	foe_dmg_mult = float(data.get("foe_dmg_mult", 1.0))
	player_dmg_mult = float(data.get("player_dmg_mult", 1.0))
	ai_jitter = float(data.get("ai_jitter", 0.0))
	encounter_index = int(data.get("encounter_index", 0))
	continues_left = int(data.get("continues_left", CONTINUES_DEFAULT))
	campaign_over = bool(data.get("campaign_over", false))
	campaign_result = String(data.get("campaign_result", "running"))
	step_count = int(data.get("step_count", 0))
	fight_over = bool(data.get("fight_over", false))
	fight_outcome = String(data.get("fight_outcome", "none"))
	illegal_attempts = int(data.get("illegal_attempts", 0))
	player = _coerce_player(data.get("player", {}))
	fighters = _coerce_fighters(data.get("fighters", []))
	event_log = (data.get("event_log", []) as Array).duplicate()


func _dup_player(p: Dictionary) -> Dictionary:
	var out: Dictionary = p.duplicate(true)
	return out


func _coerce_player(src: Dictionary) -> Dictionary:
	if src.is_empty():
		return _new_player(START_STYLES)
	var upg: Dictionary = {}
	for sid in STYLE_ORDER:
		upg[sid] = int((src.get("upgrades", {}) as Dictionary).get(sid, 0))
	var known: Array = []
	for s in (src.get("known_styles", START_STYLES) as Array):
		if STYLES.has(String(s)) and not known.has(String(s)):
			known.append(String(s))
	if known.is_empty():
		known = [START_STYLES[0]]
	return {
		"name": String(src.get("name", "Wandering Disciple")),
		"body": int(src.get("body", 6)),
		"mind": int(src.get("mind", 5)),
		"spirit": int(src.get("spirit", 5)),
		"level": int(src.get("level", 1)),
		"xp": int(src.get("xp", 0)),
		"technique_points": int(src.get("technique_points", 0)),
		"attribute_points": int(src.get("attribute_points", 0)),
		"known_styles": known,
		"upgrades": upg,
		"active_style": String(src.get("active_style", known[0])),
	}


func _dup_fighters() -> Array:
	var out: Array = []
	for f in fighters:
		out.append((f as Dictionary).duplicate(true))
	return out


func _coerce_fighters(src: Array) -> Array:
	var out: Array = []
	for item in src:
		var f: Dictionary = (item as Dictionary).duplicate(true)
		# ensure the transient keys exist after a load.
		if not f.has("pending"):
			f["pending"] = {}
		if not f.has("combo"):
			f["combo"] = 0
		out.append(f)
	return out
