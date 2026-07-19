extends CanvasLayer
## Live combat HUD: current wave, score, run timer, enemies remaining.

@onready var _wave: Label = $Root/Margin/VBox/Wave
@onready var _score: Label = $Root/Margin/VBox/Score
@onready var _time: Label = $Root/Margin/VBox/Time
@onready var _enemies: Label = $Root/Margin/VBox/Enemies
@onready var _hint: Label = $Root/HintMargin/Hint

func _process(_delta: float) -> void:
	_wave.text = "WAVE  %d / %d" % [GameFlow.current, GameFlow.TOTAL_LEVELS]
	_score.text = "SCORE  %d" % GameFlow.score()
	_time.text = "TIME  " + GameFlow.format_time(GameFlow.run_time)
	_enemies.text = "ENEMIES  %d" % GameFlow.enemies_left
	if GameFlow.enemies_left == 0:
		_hint.text = "AREA CLEAR — reach the golden exit"
		_hint.visible = true
	else:
		_hint.visible = false
