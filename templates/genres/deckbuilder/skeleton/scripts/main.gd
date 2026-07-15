extends Control
## res://scripts/main.gd
## Deckbuilder COMBAT controller. Builds the hand deck, runs the draw/play/
## discard loop (energy, block, hand refill, discard-reshuffle), resolves card
## effects, and runs a minimal enemy that attacks every turn. Win by emptying
## the enemy's HP, lose at 0 HP.
##
## When a ROGUELIKE RUN is active (GameManager.has_run), combat reads the run:
## your persisted HP, your grown deck, the encounter the current map node
## fields, and your relics (bonus energy / starting block / heal-on-kill). On
## win it reports the result back (HP + gold + relic persist), offers a card
## reward, and returns to the map; on loss it ends the run. With NO active run
## the scene still plays standalone against the default Cog-Golem — so the base
## template and its boot probe are unchanged.

const STARTING_DECK: Array[String] = [
	"strike", "strike", "strike",
	"defend", "defend", "defend",
	"cleave", "insight", "insight", "surge",
]
const HAND_SIZE := 5
const BASE_ENERGY := 3
const DEFAULT_ENEMY_NAME := "Cog-Golem"
const DEFAULT_ENEMY_HP := 30
const DEFAULT_ENEMY_ATTACK := 8
const DEFAULT_PLAYER_HP := 40

var turn := 0
var energy := 0
var block := 0
var player_hp := DEFAULT_PLAYER_HP
var player_max_hp := DEFAULT_PLAYER_HP
var enemy_hp := DEFAULT_ENEMY_HP
var combat_over := false

# run-driven combat parameters (snapshotted at new_combat)
var _run_active := false
var _max_energy := BASE_ENERGY
var _enemy_name := DEFAULT_ENEMY_NAME
var _enemy_max_hp := DEFAULT_ENEMY_HP
var _enemy_attack := DEFAULT_ENEMY_ATTACK
var _is_boss := false

var _probe_emitted := false

@onready var _factory: CardFactory = $CardManager/CardFactory
@onready var _deck: Pile = $Deck
@onready var _discard: Pile = $Discard
@onready var _hand: Hand = $Hand
@onready var _play_area: Pile = $PlayArea
@onready var _turn_label: Label = $HUD/Stats/TurnLabel
@onready var _energy_label: Label = $HUD/Stats/EnergyLabel
@onready var _block_label: Label = $HUD/Stats/BlockLabel
@onready var _player_hp_label: Label = $HUD/Stats/PlayerHPLabel
@onready var _deck_label: Label = $HUD/DeckLabel
@onready var _discard_label: Label = $HUD/DiscardLabel
@onready var _enemy_hp_label: Label = $EnemyPanel/Margin/Rows/EnemyHPLabel
@onready var _intent_label: Label = $EnemyPanel/Margin/Rows/IntentLabel
@onready var _end_turn_button: Button = $HUD/EndTurnButton
@onready var _banner_box: CenterContainer = $HUD/BannerBox
@onready var _banner_label: Label = $HUD/BannerBox/Rows/BannerLabel
@onready var _reset_button: Button = $HUD/BannerBox/Rows/ResetButton
@onready var _banner_rows: VBoxContainer = $HUD/BannerBox/Rows


func _ready() -> void:
	_play_area.can_play = _can_play_card
	_play_area.card_played.connect(_on_card_played)
	_end_turn_button.pressed.connect(end_turn)
	_reset_button.pressed.connect(new_combat)
	# CardManager (a sibling-ready child) has already preloaded the factory.
	new_combat.call_deferred()


func _process(_delta: float) -> void:
	_refresh_hud()


func new_combat() -> void:
	_run_active = GameManager.has_run and not GameManager.is_run_over()
	_clear_reward_buttons()

	if _run_active:
		player_max_hp = GameManager.max_hp
		player_hp = GameManager.hp
		_max_energy = BASE_ENERGY + GameManager.relic_bonus_energy()
		var enc: Dictionary = GameManager.current_encounter()
		_enemy_name = String(enc.get("name", DEFAULT_ENEMY_NAME))
		_enemy_max_hp = int(enc.get("max_hp", DEFAULT_ENEMY_HP))
		_enemy_attack = int(enc.get("attack", DEFAULT_ENEMY_ATTACK))
		_is_boss = String(enc.get("kind", "")) == "boss"
	else:
		player_max_hp = DEFAULT_PLAYER_HP
		player_hp = DEFAULT_PLAYER_HP
		_max_energy = BASE_ENERGY
		_enemy_name = DEFAULT_ENEMY_NAME
		_enemy_max_hp = DEFAULT_ENEMY_HP
		_enemy_attack = DEFAULT_ENEMY_ATTACK
		_is_boss = false

	turn = 0
	enemy_hp = _enemy_max_hp
	block = 0
	combat_over = false
	_banner_box.visible = false

	_hand.clear_cards()
	_discard.clear_cards()
	_deck.clear_cards()
	var order: Array[String] = (GameManager.deck.duplicate() if _run_active else STARTING_DECK.duplicate())
	order.shuffle()
	for card_name in order:
		_factory.create_card(card_name, _deck)

	start_turn()

	if not _probe_emitted:
		_probe_emitted = true
		_emit_boot_probe.call_deferred()


func start_turn() -> void:
	turn += 1
	energy = _max_energy
	# a relic can plate you with block at the top of every turn.
	block = GameManager.relic_start_block() if _run_active else 0
	draw_cards(HAND_SIZE - _hand.get_card_count())


func draw_cards(count: int) -> void:
	for i in count:
		if _deck.get_card_count() == 0:
			_reshuffle_discard_into_deck()
			if _deck.get_card_count() == 0:
				return
		_hand.move_cards(_deck.get_top_cards(1), -1, false)


func _reshuffle_discard_into_deck() -> void:
	var cards := _discard.get_top_cards(_discard.get_card_count())
	if cards.is_empty():
		return
	_deck.move_cards(cards, -1, false)
	_deck.shuffle()


func end_turn() -> void:
	if combat_over:
		return
	while _hand.get_card_count() > 0:
		_discard.move_cards(_hand.get_random_cards(1), -1, false)
	# Enemy acts: block soaks its attack, the rest hits the player.
	player_hp -= maxi(_enemy_attack - block, 0)
	if player_hp <= 0:
		player_hp = 0
		_finish_combat("DEFEAT")
		return
	start_turn()


## Programmatic play (tests, tutorials, AI) — same path a drag-drop takes.
func play_card(card: Card) -> bool:
	if not _can_play_card(card):
		return false
	return _play_area.move_cards([card], -1, false)


func _can_play_card(card: Card) -> bool:
	if combat_over:
		return false
	return energy >= int(card.card_info.get("cost", 0))


func _on_card_played(card: Card) -> void:
	var info: Dictionary = card.card_info
	energy -= int(info.get("cost", 0))
	var amount := int(info.get("amount", 0))
	match String(info.get("type", "")):
		"attack":
			enemy_hp = maxi(enemy_hp - amount, 0)
		"block":
			block += amount
		"draw":
			draw_cards(amount)
		"energy":
			energy += amount
		_:
			push_warning("Unknown card type on '%s'" % card.card_name)
	_discard.move_cards([card], -1, false)
	GameManager.set_flag("cards_played", int(GameManager.get_flag("cards_played", 0)) + 1)
	if enemy_hp <= 0:
		if _run_active:
			player_hp = mini(player_max_hp, player_hp + GameManager.relic_heal_on_kill())
		_finish_combat("VICTORY")


func _finish_combat(verdict: String) -> void:
	combat_over = true
	_banner_label.text = verdict
	_banner_box.visible = true

	if not _run_active:
		# standalone: the classic reset-to-fight-again button (unchanged).
		if verdict == "VICTORY":
			GameManager.set_flag("battles_won", int(GameManager.get_flag("battles_won", 0)) + 1)
		_reset_button.visible = true
		return

	# roguelike: feed the result back into the run, then route the player.
	_reset_button.visible = false
	GameManager.resolve_combat(verdict == "VICTORY", player_hp)
	if verdict != "VICTORY":
		_banner_label.text = "DEFEAT — the run ends."
		_add_reward_button("Return to map", _return_to_map)
		return
	if _is_boss:
		_banner_label.text = "The Archivist falls — you win the run!"
		_add_reward_button("Return to map", _return_to_map)
		return
	# a normal/elite win: offer a card to add to the deck (or skip).
	_banner_label.text = "Victory! Add a card to your deck:"
	for card_id in GameManager.roll_rewards():
		var cid := card_id
		_add_reward_button(_reward_label(cid), func() -> void:
			GameManager.add_card(cid)
			_return_to_map())
	_add_reward_button("Skip", _return_to_map)


func _reward_label(card_id: String) -> String:
	return "Take: %s" % card_id.capitalize()


func _add_reward_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_to_group(&"scalable_text")
	b.add_to_group(&"reward_button")
	b.pressed.connect(cb)
	_banner_rows.add_child(b)


func _clear_reward_buttons() -> void:
	for b in get_tree().get_nodes_in_group(&"reward_button"):
		if is_instance_valid(b):
			b.queue_free()
	_reset_button.visible = true


func _return_to_map() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _refresh_hud() -> void:
	_turn_label.text = "Turn %d" % turn
	_energy_label.text = "Energy %d/%d" % [energy, _max_energy]
	_block_label.text = "Block %d" % block
	_player_hp_label.text = "HP %d/%d" % [player_hp, player_max_hp]
	_deck_label.text = "Deck: %d" % _deck.get_card_count()
	_discard_label.text = "Discard: %d" % _discard.get_card_count()
	_enemy_hp_label.text = "%s  %d/%d" % [_enemy_name, enemy_hp, _enemy_max_hp]
	_intent_label.text = "Intent: Attack %d" % _enemy_attack


func _emit_boot_probe() -> void:
	print("DEBUG: deckbuilder core loop ready — deck=%d hand=%d discard=%d energy=%d/%d enemy_hp=%d turn=%d run=%s" % [
		_deck.get_card_count(), _hand.get_card_count(), _discard.get_card_count(),
		energy, _max_energy, enemy_hp, turn, str(_run_active),
	])
