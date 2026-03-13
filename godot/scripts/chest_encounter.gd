extends Area2D
class_name ChestEncounter

signal chest_started(chest: ChestEncounter, payload: Dictionary)
signal chest_opened(chest: ChestEncounter, reward_text: String)

@export var level_theme: String = "variables"
@export var reward_text: String = "Recovered a syntax shard."

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _opened := false
var _triggered := false
var _base_color := Color(0.847059, 0.666667, 0.27451, 1)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_visual_state()


func configure(config: Dictionary) -> void:
	level_theme = String(config.get("level_theme", level_theme))
	reward_text = String(config.get("reward_text", reward_text))
	var position_data: Array = config.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	_apply_visual_state()


func _on_body_entered(body: Node) -> void:
	if _opened or _triggered:
		return
	if body is PlayerController:
		_triggered = true
		chest_started.emit(
			self,
			{
				"interaction_type": "chest",
				"level_theme": level_theme,
				"title": "Hack Terminal",
				"status_text": "Solve the chest script to unlock the reward.",
				"success_text": "Chest unlocked.",
				"failure_text": "Chest remains sealed.",
				"time_limit": 0,
				"timer_enabled": false,
			}
		)


func mark_opened() -> void:
	if _opened:
		return
	_opened = true
	_triggered = true
	_apply_visual_state()
	chest_opened.emit(self, reward_text)


func reset_interaction() -> void:
	if _opened:
		return
	_triggered = false


func is_opened() -> bool:
	return _opened


func _apply_visual_state() -> void:
	if _opened:
		visual.color = Color(0.470588, 0.776471, 0.501961, 1)
		label.text = "OPEN"
	else:
		visual.color = _base_color
		label.text = "CHEST"
