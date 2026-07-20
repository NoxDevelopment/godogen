extends Control
## loading_screen — visual for SceneLoader. Progress bar + rotating tip + backdrop.
## Reuse-first: assign a real backdrop to $Backdrop and fill TIPS from the library,
## not placeholder art. Typography-deferred: theme.tres supplies the fonts.

## Fill these from your game's help/lore strings (reuse-first, localizable).
const TIPS := [
	"Tip: Press Esc to pause at any time.",
	"Tip: Autosave keeps the last few minutes safe.",
]

@onready var _bar: ProgressBar = $VBox/Bar
@onready var _tip: Label = $VBox/Tip
var _tip_timer := 0.0

func _ready() -> void:
	if TIPS.size() > 0:
		_tip.text = TIPS[randi() % TIPS.size()]
	_bar.value = 0.0

func set_progress(p: float) -> void:
	_bar.value = clampf(p, 0.0, 1.0) * 100.0

func _process(delta: float) -> void:
	# Rotate the tip every few seconds during long loads.
	_tip_timer += delta
	if _tip_timer >= 4.0 and TIPS.size() > 1:
		_tip_timer = 0.0
		_tip.text = TIPS[randi() % TIPS.size()]
