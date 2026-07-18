class_name RPGTrading
extends RefCounted
## res://addons/nox_rpg/rpg_trading.gd
## Faction-priced buying/selling between a player and a merchant RPGInventory
## (Immersion-Engine RPG systems, spec P3). Gold is a special inventory item
## ("gold" — uncapped, weightless). Buy prices scale by the player's faction tier
## with the merchant (friendlier = cheaper); the merchant buys back at half base.
## Deterministic + atomic. Pure RefCounted.

const GOLD := "gold"

var _base: Dictionary = {} # item_id -> base price (int)
## faction tier -> buy-price multiplier (friendlier = cheaper)
var _buy_mult: Dictionary = {
	"hated": 2.0, "hostile": 1.5, "unfriendly": 1.25, "neutral": 1.0,
	"friendly": 0.9, "honored": 0.8, "revered": 0.7, "exalted": 0.6,
}


func _init(base_prices: Dictionary = {}) -> void:
	_base = base_prices.duplicate(true)


func base_price(item_id: String) -> int:
	return int(_base.get(item_id, 0))


func buy_price(item_id: String, tier: String = "neutral") -> int:
	var mult: float = float(_buy_mult.get(tier, 1.0))
	return int(ceil(float(base_price(item_id)) * mult))


func sell_price(item_id: String, _tier: String = "neutral") -> int:
	return int(floor(float(base_price(item_id)) * 0.5))


## Player buys qty of item from merchant. { ok, reason, spent }. Atomic.
func buy(player: RPGInventory, merchant: RPGInventory, item_id: String, qty: int, tier: String = "neutral") -> Dictionary:
	if qty <= 0:
		return { "ok": false, "reason": "qty must be > 0", "spent": 0 }
	if not merchant.has(item_id, qty):
		return { "ok": false, "reason": "merchant out of stock", "spent": 0 }
	var cost: int = buy_price(item_id, tier) * qty
	if not player.has(GOLD, cost):
		return { "ok": false, "reason": "not enough gold", "spent": 0 }
	if player.space_for(item_id) < qty:
		return { "ok": false, "reason": "no room for the goods", "spent": 0 }
	player.remove(GOLD, cost)
	merchant.remove(item_id, qty)
	player.add(item_id, qty)
	merchant.add(GOLD, cost)
	return { "ok": true, "reason": "", "spent": cost }


## Player sells qty of item to merchant. { ok, reason, earned }. Atomic.
func sell(player: RPGInventory, merchant: RPGInventory, item_id: String, qty: int, tier: String = "neutral") -> Dictionary:
	if qty <= 0:
		return { "ok": false, "reason": "qty must be > 0", "earned": 0 }
	if not player.has(item_id, qty):
		return { "ok": false, "reason": "you don't have that", "earned": 0 }
	var earn: int = sell_price(item_id, tier) * qty
	if not merchant.has(GOLD, earn):
		return { "ok": false, "reason": "merchant can't afford it", "earned": 0 }
	player.remove(item_id, qty)
	merchant.remove(GOLD, earn)
	player.add(GOLD, earn)
	merchant.add(item_id, qty)
	return { "ok": true, "reason": "", "earned": earn }
