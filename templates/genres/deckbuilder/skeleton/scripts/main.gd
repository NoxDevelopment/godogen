extends Control
## res://scripts/main.gd
## Deckbuilder combat controller: builds the starting deck from JSON card
## definitions, runs the draw/play/discard loop (energy, block, hand refill,
## discard-reshuffle), resolves card effects, and runs a minimal enemy that
## attacks every turn. Win by emptying the enemy's HP, lose at 0 HP.

const STARTING_DECK: Array[String] = [
	"strike", "strike", "strike",
	"defend", "defend", "defend",
	"cleave", "insight", "insight", "surge",
]
const HAND_SIZE := 5
const MAX_ENERGY := 3
const ENEMY_NAME := "Cog-Golem"
const ENEMY_MAX_HP := 30
const ENEMY_ATTACK := 8
const PLAYER_MAX_HP := 40

var turn := 0
var energy := 0
var block := 0
var player_hp := PLAYER_MAX_HP
var enemy_hp := ENEMY_MAX_HP
var combat_over := false

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
	turn = 0
	player_hp = PLAYER_MAX_HP
	enemy_hp = ENEMY_MAX_HP
	block = 0
	combat_over = false
	_banner_box.visible = false

	_hand.clear_cards()
	_discard.clear_cards()
	_deck.clear_cards()
	var order := STARTING_DECK.duplicate()
	order.shuffle()
	for card_name in order:
		_factory.create_card(card_name, _deck)

	start_turn()

	if not _probe_emitted:
		_probe_emitted = true
		_emit_boot_probe.call_deferred()


func start_turn() -> void:
	turn += 1
	energy = MAX_ENERGY
	block = 0
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
	player_hp -= maxi(ENEMY_ATTACK - block, 0)
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
		_finish_combat("VICTORY")


func _finish_combat(verdict: String) -> void:
	combat_over = true
	_banner_label.text = verdict
	_banner_box.visible = true
	if verdict == "VICTORY":
		GameManager.set_flag("battles_won", int(GameManager.get_flag("battles_won", 0)) + 1)


func _refresh_hud() -> void:
	_turn_label.text = "Turn %d" % turn
	_energy_label.text = "Energy %d/%d" % [energy, MAX_ENERGY]
	_block_label.text = "Block %d" % block
	_player_hp_label.text = "HP %d/%d" % [player_hp, PLAYER_MAX_HP]
	_deck_label.text = "Deck: %d" % _deck.get_card_count()
	_discard_label.text = "Discard: %d" % _discard.get_card_count()
	_enemy_hp_label.text = "%s  %d/%d" % [ENEMY_NAME, enemy_hp, ENEMY_MAX_HP]
	_intent_label.text = "Intent: Attack %d" % ENEMY_ATTACK


func _emit_boot_probe() -> void:
	print("DEBUG: deckbuilder core loop ready — deck=%d hand=%d discard=%d energy=%d/%d enemy_hp=%d turn=%d" % [
		_deck.get_card_count(), _hand.get_card_count(), _discard.get_card_count(),
		energy, MAX_ENERGY, enemy_hp, turn,
	])
