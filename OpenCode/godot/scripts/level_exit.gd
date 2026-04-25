extends Area2D
class_name LevelExit

signal exit_entered

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _unlocked := false
var _locked_text := "Locked"
var _ready_text := "Exit Ready"


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	set_unlocked(false)


func configure(config: Dictionary) -> void:
	var position_data: Array = config.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	_locked_text = String(config.get("locked_text", _locked_text))
	_ready_text = String(config.get("ready_text", _ready_text))
	set_unlocked(_unlocked)


func set_unlocked(value: bool) -> void:
	_unlocked = value
	if _unlocked:
		visual.color = Color(0.45, 0.8, 0.55, 1)
		label.text = _ready_text
	else:
		visual.color = Color(0.32, 0.34, 0.4, 1)
		label.text = _locked_text


func _on_body_entered(body: Node) -> void:
	if not _unlocked:
		return
	if body is PlayerController:
		exit_entered.emit()
